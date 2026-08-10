# npc_base.gd
extends CharacterBody3D
class_name NPCBase

# Contract for everything above this node:
#   move_to(pos)              walk there, emits arrived
#   align_to(basis)           turn in place, for settling into a slot
#   stop()                    cancel
#   is_moving / is_running    READ ONLY, the FSM or BT picks animation from these
#
# The state machine never writes is_moving or is_running. It reads them.

signal arrived
signal path_failed

const ARRIVE_DIST: float = 0.4
# The baked navmesh sits ~0.5 above the floor the NPC stands on. NavigationAgent3D
# measures waypoint arrival in full 3D, so the desired distances must clear that
# vertical gap or the agent never advances past the first path point.
const PATH_DESIRED: float = 1.0
const TARGET_DESIRED: float = 1.2
const RUN_DIST: float = 25.0
# Time to slide+turn from the approach point into a seat pose once arrived.
const SETTLE_TIME: float = 0.3
# How long the target may stay unreachable before we give up. The nav map takes a
# few frames (a big navmesh can take ~200) to compute a path after move_to(), during
# which is_target_reachable() reads false; a one-frame abort would kill every route.
const UNREACHABLE_TIMEOUT: float = 3.0
# move_to snaps its goal onto the navmesh so a target placed slightly off it (a location centre
# that sits inside a building, a seat slot on grass) is still reachable. A snap farther than
# this is treated as "no good navmesh nearby" and the raw target is kept (don't yank the goal
# across the map to a far island or to the origin when the mesh isn't ready).
const NAV_SNAP_MAX: float = 5.0
const TURN_SPEED: float = 8.0
const GRAVITY: float = 9.8
const FLOOR_STICK: float = -0.5

# The activity-animation (enter/loop/exit) system lives in a dedicated child node; this node
# only orchestrates it. See animation_controller.gd.

@onready var _model: Node3D = $Model
@onready var _tree: AnimationTree = $AnimationTree
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _anim: NPCAnimationController = $AnimationController

var is_moving: bool = false
var is_running: bool = false

# Shared runtime scratch for the Brain / behaviour tree (goal, slot, timer).
var blackboard: Blackboard = Blackboard.new()

var _has_target: bool = false
var _face_override: bool = false
var _face_yaw: float = 0.0
var _nav_ready: bool = false
var _unreachable_time: float = 0.0

# The player currently interacting (pressed E). While set, the NPC halts its
# schedule/BT trip and turns to face them; clearing it resumes the interrupted walk.
var _attending_player: Node3D = null
var _attend_resume: bool = false   # true if a trip was interrupted to attend
var _area: InteractionArea = null  # this NPC's "press E" area (disabled while sleeping)

var _move_target: Vector3 = Vector3.ZERO   # last move_to destination (for LOD teleport)

# Hybrid waypoint routing: move_to() asks the WaypointNetwork for a high-level
# path (a list of waypoint positions), then walks each hop with the navmesh. The
# public `arrived` signal fires only when the FINAL target is reached.
var _route: Array[Vector3] = []            # remaining waypoint sub-goals
var _final_target: Vector3 = Vector3.ZERO  # the real destination (last leg)
var _leg_final: bool = true                # current leg heads straight to _final_target

@export var npc_id: StringName
@export var schedule: NPCSchedule
## Archetype deciding how this NPC answers player commands (accept / delay / refuse).
@export var personality: NPCPersonality
## When true a child BTPlayer (LimboAI behaviour tree) owns goal selection instead of
## the built-in GameClock.minute_changed runner. The BT polls scheduled_activity_now()
## / is_command_active() every tick and calls begin_activity()/end_command(); the
## locomotion HSM and movement below are unchanged either way.
@export var use_behavior_tree: bool = false
## Print every activity animation event (enter/loop/exit phase changes, clip requests) to
## the output, prefixed with this NPC's id. Leave off in normal play.
@export var debug_anim: bool = false

signal command_answered(reaction: int)   # NPCPersonality.Reaction

var current_activity: ActivityResource

# step 5: a player command currently overriding the schedule. While active the schedule
# is suppressed; when it ends (min_duration reached or cancelled) the schedule resumes.
var _command_active: bool = false

# The clip the idle state plays when the NPC is standing still. move_to resets it to
# "idle"; on arrival it becomes the current activity's animation (sleeping/sit_park/…).
var stationary_anim: StringName = &"idle"
var _activity_start_minute: int = -1

# The activity queued to travel to once the EXIT (stand-up) animation finishes.
var _pending_after_exit: ActivityResource = null

# step 3: the SmartObject slot this NPC has reserved for the current activity (a chair,
# a counter stool, a bed). -1 / null means the activity just uses the location centre.
var _object: SmartObject = null
var _slot: int = -1

# Seat settling / seated state (physically on a bench). While seated, physics is
# frozen so gravity doesn't drop her off the object.
var _settling: bool = false
var _seated: bool = false
var _settle_t: float = 0.0
var _seat_xform: Transform3D = Transform3D.IDENTITY
var _settle_from_pos: Vector3 = Vector3.ZERO
var _settle_from_basis: Basis = Basis.IDENTITY


func _ready() -> void:
	add_to_group("npc")

	# Mixamo clips import with loop_mode=0 (play-once). A root-motion locomotion clip
	# would play once then hold its end pose (zero motion delta) and freeze the NPC
	# mid-walk; a sustained activity clip (sleeping/sitting) would snap back to frame 0
	# after one cycle. Force the looping ones to loop.
	var ap: AnimationPlayer = $Model/AnimationPlayer
	for clip in ["walking", "running", "Idle",
			"Sleeping Idle", "Sitting_in_park", "Looking Around", "Box Idle"]:
		if ap.has_animation(clip):
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR

	arrived.connect(_on_arrived)

	# Activity animation lives in the AnimationController child: give it the tree/player and
	# let it tell us (exit_finished) when a stand-up clip is done so we can walk on.
	_anim.setup(_tree, ap, npc_id)
	_anim.debug_anim = debug_anim
	_anim.exit_finished.connect(_finish_exit)
	# When the enter clip finishes the anim node switches to the loop; hold that pose in idle.
	_anim.loop_reached.connect(func(loop_input: StringName) -> void: stationary_anim = loop_input)

	# The command layer calls begin_interaction() when the player presses E; the NPC
	# then stops and faces them. player_exited ends it if they walk out of range.
	# Optional — some NPC scenes may have no InteractionArea.
	_area = get_node_or_null("InteractionArea") as InteractionArea
	if _area != null:
		_area.player_exited.connect(_on_player_exited)

	# In BT mode the child BTPlayer polls the schedule every tick, so the built-in
	# minute-driven runner is left disconnected (having both would double-decide).
	if not use_behavior_tree:
		GameClock.minute_changed.connect(_on_minute_changed)
		# Apply the opening schedule entry deferred, not inline: WorldLocation nodes
		# register with LocationRegistry in their own _ready, which may run after this
		# NPC's. Querying now would miss them ("No location registered").
		call_deferred("_apply_current_schedule")

	_agent.path_desired_distance = PATH_DESIRED
	_agent.target_desired_distance = TARGET_DESIRED
	call_deferred("_wait_for_nav")

func _physics_process(delta: float) -> void:
	if _seated:
		return                       # frozen on the seat until the schedule moves her
	if _settling:
		_settle(delta)
		return

	_update_intent(delta)
	_face(delta)
	_apply_root_motion(delta)

	if !is_on_floor():
		velocity.y -= GRAVITY * delta

	move_and_slide()

# Slide + turn from the approach spot into the seat pose over SETTLE_TIME, then hold. Copies
# the seat marker's FULL orientation (not just yaw), so a tilted/angled seat tilts the NPC too.
func _settle(delta: float) -> void:
	_settle_t = minf(_settle_t + delta / SETTLE_TIME, 1.0)
	var e: float = smoothstep(0.0, 1.0, _settle_t)
	global_position = _settle_from_pos.lerp(_seat_xform.origin, e)
	var seat_basis: Basis = _seat_xform.basis.orthonormalized()
	var q: Quaternion = _settle_from_basis.get_rotation_quaternion().slerp(
			seat_basis.get_rotation_quaternion(), e)
	global_transform.basis = Basis(q)
	if _settle_t >= 1.0:
		global_position = _seat_xform.origin
		global_transform.basis = seat_basis
		_settling = false
		_seated = true

# Get off the seat and back onto the navmesh (the approach marker) before walking away.
func _stand_up() -> void:
	if _object != null and _slot >= 0 and (_seated or _settling):
		global_position = _object.slot_transform(_slot).origin
		# a tilted seat may have tilted the body; return upright (keep only yaw) for walking.
		global_transform.basis = Basis(Vector3.UP, global_transform.basis.get_euler().y)
	_settling = false
	_seated = false
func _wait_for_nav() -> void:
	# the navigation map needs one physics frame before the first query
	await get_tree().physics_frame
	_nav_ready = true

func _apply_current_schedule() -> void:
	_on_minute_changed(GameClock.total_minutes)

func _on_minute_changed(minutes: int) -> void:
	if schedule == null:
		return
	# step 5: a player command overrides the schedule. Hold it until it has run its
	# min_duration, then hand control back to the schedule.
	if _command_active:
		if current_activity != null \
				and performed_minutes() >= current_activity.min_duration_minutes:
			_end_command()
		return
	var entry: ScheduleEntry = schedule.entry_at(minutes)
	if entry == null or entry.activity == current_activity:
		return
	_begin_activity(entry.activity)

# Resolve an activity's location and start heading there (stand off any seat, drop the
# old slot first). No-op if the location isn't registered yet, so the next tick retries.
func _begin_activity(act: ActivityResource) -> bool:
	# While attending a player, hold position — don't let a schedule/BT boundary walk
	# the NPC off mid-interaction. The caller retries after the player leaves range.
	if _attending_player != null:
		return false
	var loc: WorldLocation = LocationRegistry.get_location(act.location_tag, npc_id)
	if loc == null:
		return false
	# If the NPC is currently performing an activity that has an exit clip (stand up),
	# play that first and defer the trip to the new activity until it finishes. Only when
	# actually performing (LOOP phase, not mid-walk).
	var outgoing: ActivityResource = current_activity
	var exit_anim: StringName = _exit_clip(outgoing)
	if exit_anim != &"" and _anim.phase == NPCAnimationController.Phase.LOOP \
			and not _has_target:
		current_activity = act          # claim the goal so the BT won't re-trigger this
		_pending_after_exit = act
		_begin_exit(exit_anim)
		return true
	current_activity = act
	_set_interactable(true)         # interactable while travelling; re-checked on arrival
	_stand_up()                     # get off any seat, back onto the navmesh
	_release_slot()                 # let go of the previous activity's slot
	_go_to_activity(act, loc)
	return true

# The exit clip for leaving an activity: an explicit exit_animation, else empty (no exit
# phase).
func _exit_clip(act: ActivityResource) -> StringName:
	if act == null:
		return &""
	return act.exit_animation

# Play the outgoing activity's stand-up clip in place; the AnimationController's exit_finished
# signal resumes the trip (via _finish_exit) once it ends. Stand off any seat first.
func _begin_exit(exit_anim: StringName) -> void:
	_stand_up()
	stationary_anim = exit_anim   # hold the stand-up pose in idle while it plays
	_anim.begin_exit(exit_anim)

# The stand-up clip finished: drop the old slot and start travelling to the queued activity.
func _finish_exit() -> void:
	var act: ActivityResource = _pending_after_exit
	_pending_after_exit = null
	if act == null:
		return
	var loc: WorldLocation = LocationRegistry.get_location(act.location_tag, npc_id)
	if loc == null:
		return
	_set_interactable(true)
	_release_slot()
	_go_to_activity(act, loc)

# Arm/disarm the "press E" area. Non-interruptible activities (sleep) disarm it so the
# player can't talk to the NPC while it performs them.
func _set_interactable(value: bool) -> void:
	if _area != null:
		_area.set_active(value)

# --------------------------------------------------------------- player commands

# Player asks the NPC to perform an activity now. Personality decides; on ACCEPT the
# command overrides the schedule until its min_duration elapses or cancel_command().
# Returns the NPCPersonality.Reaction.
func receive_command(cmd: ActivityResource) -> int:
	var cur_task: ActivityTask = null
	if current_activity != null:
		cur_task = ActivityTask.new(current_activity, self)
	var reaction: int = NPCPersonality.Reaction.ACCEPT
	if personality != null:
		reaction = personality.evaluate(cmd, cur_task)

	match reaction:
		NPCPersonality.Reaction.REFUSE:
			say(personality.refusal_line if personality != null else "No.")
		NPCPersonality.Reaction.DELAY:
			say(personality.delay_line if personality != null else "In a moment.")
		NPCPersonality.Reaction.ACCEPT:
			if _begin_activity(cmd):
				_command_active = true
				# Count the command's duration from now, not the previous activity's
				# arrival — otherwise a stale start could read as already-expired on the
				# BT's very next tick. _on_arrived resets it to the real arrival time.
				_activity_start_minute = GameClock.total_minutes
	command_answered.emit(reaction)
	return reaction

# End the command early (player dismiss, or "stop"). Schedule resumes immediately.
func cancel_command() -> void:
	if _command_active:
		_end_command()

func _end_command() -> void:
	end_command()
	# Legacy runner needs a manual re-tick to pick the schedule back up; the BT does
	# that on its own next frame.
	if not use_behavior_tree:
		_on_minute_changed(GameClock.total_minutes)

# ---------------------------------------------- behaviour-tree decision surface
# Thin public API the LimboAI brain tasks call, so the BT never reaches into the
# runner's private state. Behaviour is identical to the minute-driven runner.

# True while a player command is overriding the schedule (BTIsCommanded).
func is_command_active() -> bool:
	return _command_active

# The active command has run at least its min_duration (BTRunCommand end test).
func command_expired() -> bool:
	return current_activity != null \
			and performed_minutes() >= current_activity.min_duration_minutes

# Clear the command override; the caller (BT or legacy) re-selects the schedule.
func end_command() -> void:
	_command_active = false
	current_activity = null

# The activity the schedule wants at the current game time, or null if none.
func scheduled_activity_now() -> ActivityResource:
	if schedule == null:
		return null
	var entry: ScheduleEntry = schedule.entry_at(GameClock.total_minutes)
	if entry == null:
		return null
	return entry.activity

# Public alias for the BT: start heading to an activity. Returns false if its location
# isn't registered yet (the tree retries next tick).
func begin_activity(act: ActivityResource) -> bool:
	return _begin_activity(act)

# Walk to the activity. If it names an object_type, reserve a free slot on a matching
# SmartObject near the location and head for that exact slot; otherwise the location
# centre (step 2 behaviour).
func _go_to_activity(act: ActivityResource, loc: WorldLocation) -> void:
	if act.object_type != &"":
		var obj: SmartObject = LocationRegistry.find_object(
				act.location_tag, act.object_type, npc_id, loc.global_position)
		if obj != null:
			var s: int = obj.free_slot(npc_id)
			if s != -1 and obj.reserve(s, npc_id):
				_object = obj
				_slot = s
				move_to(obj.slot_transform(s).origin)
				return
	move_to(loc.global_position)

func _release_slot() -> void:
	if _object != null:
		_object.release(npc_id)
	_object = null
	_slot = -1

func _exit_tree() -> void:
	_release_slot()

func _on_arrived() -> void:
	# step 4: settle into the activity — play its clip and remember when it began so
	# performed_minutes() / min_duration checks (used by interruption later) can read it.
	_activity_start_minute = GameClock.total_minutes
	# Non-interruptible activities (sleep) disable interaction once the NPC is performing.
	_set_interactable(current_activity == null or current_activity.interruptible)
	_start_activity_anim()

	# step 3: settle onto the reserved slot.
	if _object != null and _slot >= 0:
		if _object.has_seat(_slot):
			# physically sit on the object: slide/turn from here into the seat pose.
			_seat_xform = _object.seat_transform(_slot)
			_settle_from_pos = global_position
			_settle_from_basis = global_transform.basis
			_settle_t = 0.0
			_settling = true
			velocity = Vector3.ZERO
		else:
			# no seat: just face the way the slot points (counter, stand spot).
			align_to(_object.slot_transform(_slot).basis)

# Begin the activity's animation on arrival: the AnimationController plays the enter clip once
# then switches to the loop (or straight to the loop when there's no enter clip). We keep
# stationary_anim in sync so the idle HSM state holds the same pose.
func _start_activity_anim() -> void:
	var loop_anim: StringName = &"idle"
	if current_activity != null and current_activity.animation != &"":
		loop_anim = current_activity.animation
	var enter: StringName = &""
	if current_activity != null:
		enter = current_activity.enter_animation
	# Hold the ENTER clip in idle while it plays (else the idle state would stomp it with the
	# loop); loop_reached flips stationary_anim to the loop once the enter clip finishes.
	stationary_anim = enter if enter != &"" else loop_anim
	_anim.start(enter, loop_anim)

# How many game-minutes the NPC has been performing the current activity.
func performed_minutes() -> int:
	if _activity_start_minute < 0:
		return 0
	return GameClock.total_minutes - _activity_start_minute

# -------------------------------- attend player during interaction

# Player pressed E: stop the current trip and turn to face them. A seated or settling
# NPC is already stopped in its activity pose, so leave it be (menu still opens).
func begin_interaction(by: Node3D) -> void:
	if _seated or _settling:
		return
	_attending_player = by
	_attend_resume = _has_target   # remember whether we interrupted a walk
	_has_target = false            # stop locomotion; _face now turns toward the player
	is_moving = false
	is_running = false

# Player left range (walked off): end the attend hold and resume the schedule.
func _on_player_exited(_by: Node3D) -> void:
	end_interaction()

# End the attend/face hold, whether the player walked away or finished the command
# menu. If a player command took over, that command owns the destination; otherwise
# resume the interrupted schedule trip. Idempotent.
func end_interaction() -> void:
	if _attending_player == null and not _attend_resume:
		return
	_attending_player = null
	_face_override = false
	if _command_active:
		_attend_resume = false
		return
	if _attend_resume:
		_attend_resume = false
		move_to(_move_target)

# -------------------------------- public API

func move_to(target: Vector3) -> void:
	_face_override = false
	_anim.reset()                # leave any activity pose; walking clip takes over
	var dest: Vector3 = _snap_to_navmesh(target)
	_move_target = dest
	_final_target = dest
	# Ask the waypoint graph for a route (empty when no network / go-direct); then
	# walk it hop by hop with the navmesh.
	_route = _build_route(global_position, dest)
	# Walking overrides any activity pose; default the stationary clip back to idle
	# until the NPC arrives and _on_arrived assigns the destination activity's clip.
	stationary_anim = &"idle"
	_start_next_leg()

# Query the WaypointNetwork (if one is in the scene) for the ordered waypoint
# positions between here and the destination. Trims a leading/trailing waypoint
# that the NPC or the target is already sitting on top of, to avoid a backtrack.
func _build_route(from: Vector3, to: Vector3) -> Array[Vector3]:
	var net: Node = get_tree().get_first_node_in_group("waypoint_network")
	if net == null or not net.has_method("route"):
		return []
	var pts: PackedVector3Array = net.route(from, to)
	var out: Array[Vector3] = []
	for p in pts:
		out.append(p)
	if not out.is_empty() and out[0].distance_to(from) <= TARGET_DESIRED:
		out.remove_at(0)
	if not out.is_empty() and out[out.size() - 1].distance_to(to) <= TARGET_DESIRED:
		out.remove_at(out.size() - 1)
	return out

# Point the agent at the next hop (a waypoint) or, when the route is exhausted, at
# the final target. Legs are snapped onto the navmesh like the final target.
func _start_next_leg() -> void:
	var goal: Vector3
	if _route.is_empty():
		goal = _final_target
		_leg_final = true
	else:
		goal = _snap_to_navmesh(_route.pop_front())
		_leg_final = false
	_agent.target_position = goal
	_has_target = true
	_unreachable_time = 0.0

# Nearest point on the agent's navmesh to `target`, so a goal placed a little off the mesh is
# still reachable. Returns the raw target if the nav map isn't ready or the nearest point is
# farther than NAV_SNAP_MAX (empty/unbaked map, or a genuinely distant/disconnected goal).
func _snap_to_navmesh(target: Vector3) -> Vector3:
	var map: RID = _agent.get_navigation_map()
	if not map.is_valid():
		return target
	# A valid map may still be pre-synchronization for the first ~frames after load;
	# querying it then errors (iteration id 0). Keep the raw target until it syncs.
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return target
	var p: Vector3 = NavigationServer3D.map_get_closest_point(map, target)
	if p.distance_to(target) > NAV_SNAP_MAX:
		return target
	return p

func align_to(target_basis: Basis) -> void:
	# settling into a slot: stop walking, turn to face the slot direction
	_has_target = false
	_face_override = true
	_face_yaw = target_basis.get_euler().y

func stop() -> void:
	_has_target = false
	_face_override = false
	is_moving = false
	is_running = false
	velocity.x = 0.0
	velocity.z = 0.0

func say(line: String) -> void:
	# placeholder until dialogue UI; Brain / personality call this
	print("[%s] %s" % [npc_id, line])

func is_facing_target(tolerance_deg: float = 5.0) -> bool:
	if not _face_override:
		return true
	return absf(angle_difference(rotation.y, _face_yaw)) < deg_to_rad(tolerance_deg)

# ------------------------------------------------------------------ per tick



func _update_intent(delta: float) -> void:
	if not _has_target or not _nav_ready:
		is_moving = false
		is_running = false
		return

	# The nav map needs a few frames to build a path after move_to(); until it does,
	# is_target_reachable() reads false. Treat that as "wait", not "fail" — only give
	# up once it has stayed unreachable past UNREACHABLE_TIMEOUT.
	if not _agent.is_target_reachable():
		is_moving = false
		is_running = false
		_unreachable_time += delta
		if _unreachable_time > UNREACHABLE_TIMEOUT:
			_has_target = false
			path_failed.emit()
		return
	_unreachable_time = 0.0

	# is_navigation_finished() is ALSO true on the frames before the agent has
	# computed a path (empty path == "finished"), which would fire a bogus arrival
	# the instant move_to() is called. Only count it as arrival when we are actually
	# within reach of the target.
	var dist: float = _agent.distance_to_target()
	if _agent.is_navigation_finished() and dist <= TARGET_DESIRED + 0.1:
		if _leg_final:
			_has_target = false
			is_moving = false
			is_running = false
			arrived.emit()
		else:
			# Reached a waypoint; head for the next hop without emitting arrived.
			_start_next_leg()
		return

	is_moving = true
	is_running = dist > RUN_DIST

func _face(delta: float) -> void:
	var wanted_yaw: float
	# Attending a player overrides everything: keep turning to look at them as they move.
	if _attending_player != null:
		var to_p: Vector3 = _attending_player.global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.0001:
			var dir_p: Vector3 = to_p.normalized()
			wanted_yaw = atan2(dir_p.x, dir_p.z)
			rotation.y = lerp_angle(rotation.y, wanted_yaw, TURN_SPEED * delta)
		return
	if _face_override:
		wanted_yaw = _face_yaw
	elif is_moving:
		var to: Vector3 = _agent.get_next_path_position() - global_position
		to.y = 0.0
		if to.length_squared() < 0.0001:
			return
		# mesh fronts +Z, so atan2(x, z) aims +Z along dir
		var dir: Vector3 = to.normalized()
		wanted_yaw = atan2(dir.x, dir.z)
	else:
		return
	rotation.y = lerp_angle(rotation.y, wanted_yaw, TURN_SPEED * delta)

func _apply_root_motion(delta: float) -> void:
	if not is_moving or delta <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	# the active clip's root bone displacement, rotated into world space, is this
	# tick's horizontal velocity. Use the FULL model basis (with its 0.4 scale) like
	# the player does: the clip authors displacement in the model's local space, so
	# the body must travel displacement * model_scale to match the feet — stripping
	# the scale makes the body glide ~2.5x faster than the animation (foot sliding).
	var root_motion: Vector3 = _tree.get_root_motion_position()
	var motion: Vector3 = _model.global_transform.basis * root_motion
	velocity.x = motion.x / delta
	velocity.z = motion.z / delta
