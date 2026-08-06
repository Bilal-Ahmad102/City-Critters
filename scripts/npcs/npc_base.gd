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
const TURN_SPEED: float = 8.0
const GRAVITY: float = 9.8
const FLOOR_STICK: float = -0.5

# step 7: simulation LOD. An NPC far from every player runs cheap — physics locomotion,
# root-motion sampling and the AnimationTree are skipped, and a schedule/command move
# becomes an instant teleport to the destination instead of a navmesh walk. The BTPlayer
# keeps ticking, so an offscreen NPC still follows its schedule (it jumps between the
# scheduled locations at the right game time). A hysteresis band avoids flip-flop at the
# boundary; with no players in the scene there is nothing to observe, so we stay HIGH.
enum Lod { HIGH, LOW }
const LOD_HIGH_ENTER: float = 28.0   # become HIGH when a player is within this
const LOD_LOW_EXIT: float = 35.0     # become LOW when the nearest player is beyond this
const LOD_INTERVAL: float = 0.5      # seconds between LOD re-evaluations

@onready var _model: Node3D = $Model
@onready var _tree: AnimationTree = $AnimationTree
@onready var _agent: NavigationAgent3D = $NavigationAgent3D

var is_moving: bool = false
var is_running: bool = false

# Shared runtime scratch for the Brain / behaviour tree (goal, slot, timer).
var blackboard: Blackboard = Blackboard.new()

var _has_target: bool = false
var _face_override: bool = false
var _face_yaw: float = 0.0
var _nav_ready: bool = false
var _unreachable_time: float = 0.0

var _lod: int = Lod.HIGH
var _lod_accum: float = 0.0
var _move_target: Vector3 = Vector3.ZERO   # last move_to destination (for LOD teleport)

@export var npc_id: StringName
@export var schedule: NPCSchedule
## Archetype deciding how this NPC answers player commands (accept / delay / refuse).
@export var personality: NPCPersonality
## When true a child BTPlayer (LimboAI behaviour tree) owns goal selection instead of
## the built-in GameClock.minute_changed runner. The BT polls scheduled_activity_now()
## / is_command_active() every tick and calls begin_activity()/end_command(); the
## locomotion HSM and movement below are unchanged either way.
@export var use_behavior_tree: bool = false

signal command_answered(reaction: int)   # NPCPersonality.Reaction

var current_activity: ActivityResource

# step 5: a player command currently overriding the schedule. While active the schedule
# is suppressed; when it ends (min_duration reached or cancelled) the schedule resumes.
var _command_active: bool = false

# The clip the idle state plays when the NPC is standing still. move_to resets it to
# "idle"; on arrival it becomes the current activity's animation (sleeping/sit_park/…).
var stationary_anim: StringName = &"idle"
var _activity_start_minute: int = -1

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
var _settle_from_yaw: float = 0.0


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

	# Spread the LOD checks across frames so N NPCs don't all scan on the same one.
	_lod_accum = randf() * LOD_INTERVAL

# --------------------------------------------------------------------- step 7: LOD

func _process(delta: float) -> void:
	_lod_accum += delta
	if _lod_accum < LOD_INTERVAL:
		return
	_lod_accum = 0.0
	_update_lod()

func _update_lod() -> void:
	var d2: float = _nearest_player_dist_sq()
	if d2 == INF:
		_set_lod(Lod.HIGH)   # nobody to observe — run normally
		return
	if _lod == Lod.HIGH:
		if d2 > LOD_LOW_EXIT * LOD_LOW_EXIT:
			_set_lod(Lod.LOW)
	elif d2 < LOD_HIGH_ENTER * LOD_HIGH_ENTER:
		_set_lod(Lod.HIGH)

func _nearest_player_dist_sq() -> float:
	var best: float = INF
	for p in get_tree().get_nodes_in_group("player"):
		var n3: Node3D = p as Node3D
		if n3 == null:
			continue
		var dd: float = global_position.distance_squared_to(n3.global_position)
		if dd < best:
			best = dd
	return best

func _set_lod(new_lod: int) -> void:
	if new_lod == _lod:
		return
	_lod = new_lod
	if _lod == Lod.LOW:
		# Finish any in-progress trip instantly, then stop simulating physics/animation.
		if _has_target:
			_teleport_to(_move_target)
		if _settling:
			# was mid-slide into a seat; the settle lerp won't run offscreen, so snap.
			global_position = _seat_xform.origin
			rotation.y = _seat_xform.basis.get_euler().y
			_settling = false
			_seated = true
		_tree.active = false
	else:
		_tree.active = true

# Whether this NPC is currently cheap-simulated (for the debug panel / tests).
func lod_string() -> String:
	return "HIGH" if _lod == Lod.HIGH else "LOW"

# Snap straight to a destination (LOD teleport). Behaves like an instant arrival so the
# schedule/BT and slot settling proceed exactly as after a walk.
func _teleport_to(target: Vector3) -> void:
	global_position = target
	_has_target = false
	is_moving = false
	is_running = false
	velocity = Vector3.ZERO
	arrived.emit()

func _physics_process(delta: float) -> void:
	if _lod == Lod.LOW:
		return                       # cheap-simulated: no locomotion/root motion offscreen
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

# Slide + turn from the approach spot into the seat pose over SETTLE_TIME, then hold.
func _settle(delta: float) -> void:
	_settle_t = minf(_settle_t + delta / SETTLE_TIME, 1.0)
	var e: float = smoothstep(0.0, 1.0, _settle_t)
	global_position = _settle_from_pos.lerp(_seat_xform.origin, e)
	rotation.y = lerp_angle(_settle_from_yaw, _seat_xform.basis.get_euler().y, e)
	if _settle_t >= 1.0:
		global_position = _seat_xform.origin
		_settling = false
		_seated = true

# Get off the seat and back onto the navmesh (the approach marker) before walking away.
func _stand_up() -> void:
	if _object != null and _slot >= 0 and (_seated or _settling):
		global_position = _object.slot_transform(_slot).origin
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
	var loc: WorldLocation = LocationRegistry.get_location(act.location_tag, npc_id)
	if loc == null:
		return false
	current_activity = act
	_stand_up()                     # get off any seat, back onto the navmesh
	_release_slot()                 # let go of the previous activity's slot
	_go_to_activity(act, loc)
	return true

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
	if current_activity != null and current_activity.animation != &"":
		stationary_anim = current_activity.animation
	else:
		stationary_anim = &"idle"
	_tree["parameters/Transition/transition_request"] = String(stationary_anim)

	# step 3: settle onto the reserved slot.
	if _object != null and _slot >= 0:
		if _object.has_seat(_slot):
			_seat_xform = _object.seat_transform(_slot)
			if _lod == Lod.LOW:
				# offscreen: snap straight into the seat pose, no settle animation
				# (the per-frame _settle runs in _physics_process, which LOW skips).
				global_position = _seat_xform.origin
				rotation.y = _seat_xform.basis.get_euler().y
				velocity = Vector3.ZERO
				_seated = true
			else:
				# physically sit on the object: slide/turn from here into the seat pose.
				_settle_from_pos = global_position
				_settle_from_yaw = rotation.y
				_settle_t = 0.0
				_settling = true
				velocity = Vector3.ZERO
		elif _lod == Lod.LOW:
			rotation.y = _object.slot_transform(_slot).basis.get_euler().y
		else:
			# no seat: just face the way the slot points (counter, stand spot).
			align_to(_object.slot_transform(_slot).basis)

# How many game-minutes the NPC has been performing the current activity.
func performed_minutes() -> int:
	if _activity_start_minute < 0:
		return 0
	return GameClock.total_minutes - _activity_start_minute

# -------------------------------- public API

func move_to(target: Vector3) -> void:
	_face_override = false
	_move_target = target
	# LOD: offscreen NPCs teleport to the destination instead of walking there.
	if _lod == Lod.LOW:
		_teleport_to(target)
		return
	_agent.target_position = target
	_has_target = true
	_unreachable_time = 0.0
	# Walking overrides any activity pose; default the stationary clip back to idle
	# until the NPC arrives and _on_arrived assigns the destination activity's clip.
	stationary_anim = &"idle"

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
		_has_target = false
		is_moving = false
		is_running = false
		arrived.emit()
		return

	is_moving = true
	is_running = dist > RUN_DIST

func _face(delta: float) -> void:
	var wanted_yaw: float
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
