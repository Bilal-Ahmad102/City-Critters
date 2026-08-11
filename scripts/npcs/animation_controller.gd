# animation_controller.gd
extends Node
class_name NPCAnimationController

# Owns the NPC's ACTIVITY animation: the three-phase enter -> loop -> exit sequence an NPC
# plays while performing a scheduled activity (sit down, hold the pose, stand up). Locomotion
# clips (idle/walk/run) are still driven by the LimboHSM states; this node only touches the
# AnimationTree for activity poses and coordinates the play-once phase timing.
#
# Phase advance is driven primarily by the AnimationTree's animation_finished signal: when the
# play-once ENTER clip ends we switch to the loop (loop_reached); when the EXIT clip ends we
# emit exit_finished. A clip-length fallback TIMER backs the signal up, because a clip played
# backward through a TimeScale node (e.g. enter_pray = End_Praying reversed) never emits
# animation_finished — the timer advances those. Whichever fires first wins; the second no-ops.

# The ENTER clip finished and we switched to the loop. NPCBase updates its stationary_anim so
# the idle HSM state holds the loop (not the enter) pose from here on.
signal loop_reached(loop_input: StringName)
# The play-once EXIT (stand-up) clip finished. NPCBase then walks to the next activity — this
# node knows nothing about locations or schedules.
signal exit_finished

# Phase of the activity animation. NONE = not performing (locomotion HSM owns the tree).
enum Phase { NONE, ENTER, LOOP, EXIT }

# Extra seconds the fallback timer waits past the clip length, so the animation_finished signal
# (which fires right at the clip end, after the transition crossfade) wins for forward clips.
const TIMER_MARGIN: float = 0.5

# AnimationTree Transition input name -> AnimationPlayer clip name. Mirrors the wiring in
# scenes/npcs/npc.tscn (the Transition inputs and their AnimationNodeAnimation sources).
const CLIP_FOR_INPUT: Dictionary = {
	&"idle": &"Idle", &"walk": &"walking", &"run": &"running",
	&"sit_park": &"Sitting_in_park", &"drink": &"Drinking",
	&"box_idle": &"Box Idle", &"looking": &"Looking Around",
	&"sleeping": &"Sleeping Idle",
	# enter_pray reuses End_Praying (no dedicated start-pray clip in the model; the
	# npc.tscn enter_pray blend node feeds that same clip, played backward via TimeScale).
	&"enter_pray": &"End_Praying", &"pray": &"Praying", &"end_pray": &"End_Praying",
}

var phase: int = Phase.NONE
var _loop_input: StringName = &"idle"   # input to switch to when the ENTER clip finishes
var _await_clip: StringName = &""       # AnimationPlayer clip whose finish advances the phase
var _timer: float = 0.0                 # fallback countdown for clips that never emit finished

# Set by NPCBase (mirrors its export) so debug lines carry the owning NPC's id.
var debug_anim: bool = false
var npc_id: StringName = &""

var _tree: AnimationTree = null
var _ap: AnimationPlayer = null


# Give the node its AnimationTree / AnimationPlayer (siblings under the NPC) and id.
func setup(tree: AnimationTree, ap: AnimationPlayer, id: StringName) -> void:
	_tree = tree
	_ap = ap
	npc_id = id
	_tree.animation_finished.connect(_on_animation_finished)

# Fallback: advance the phase if the clip's finish signal never came (reversed/TimeScale clips).
func _process(delta: float) -> void:
	if _timer <= 0.0:
		return
	if phase != Phase.ENTER and phase != Phase.EXIT:
		return
	_timer -= delta
	if _timer <= 0.0:
		_advance_phase(&"timer")

# A play-once clip in the tree finished. Advance only if it's the clip this phase awaits (ENTER
# and EXIT may share a clip, e.g. pray, so key the ACTION off phase, not the name).
func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == _await_clip and (phase == Phase.ENTER or phase == Phase.EXIT):
		_advance_phase(anim_name)

# Move ENTER -> LOOP or EXIT -> done. Idempotent for this phase: clears the wait state so the
# other trigger (signal vs timer) that arrives second finds nothing to do.
func _advance_phase(reason: StringName) -> void:
	_await_clip = &""
	_timer = 0.0
	if phase == Phase.ENTER:
		_dbg("ENTER done -> LOOP", _loop_input, reason)
		play(_loop_input)
		phase = Phase.LOOP
		loop_reached.emit(_loop_input)
	elif phase == Phase.EXIT:
		_dbg("EXIT done -> travel", &"", reason)
		phase = Phase.NONE
		exit_finished.emit()

# Request an AnimationTree Transition input (idle/walk/sit_park/pray/…).
func play(input_name: StringName) -> void:
	if debug_anim:
		_dbg("play", input_name)
	_tree["parameters/Transition/transition_request"] = String(input_name)

# Begin an activity on arrival: play the enter clip once (ENTER phase, switches to the loop when
# that clip finishes), or go straight to the loop if there's no usable enter clip.
func start(enter_input: StringName, loop_input: StringName) -> void:
	_loop_input = loop_input
	var enter_clip: StringName = CLIP_FOR_INPUT.get(enter_input, &"")
	if enter_input != &"" and enter_clip != &"":
		_await_clip = enter_clip
		_timer = _clip_length(enter_clip) + TIMER_MARGIN
		_dbg("arrived -> ENTER", enter_input)
		play(enter_input)
		phase = Phase.ENTER
	else:
		_await_clip = &""
		_timer = 0.0
		_dbg("arrived -> LOOP (no enter)", loop_input)
		play(loop_input)
		phase = Phase.LOOP

# Play the outgoing activity's stand-up clip in place; exit_finished fires when it ends.
func begin_exit(exit_input: StringName) -> void:
	var exit_clip: StringName = CLIP_FOR_INPUT.get(exit_input, &"")
	_await_clip = exit_clip
	_timer = _clip_length(exit_clip) + TIMER_MARGIN
	_dbg("leaving -> EXIT", exit_input)
	play(exit_input)
	phase = Phase.EXIT

# Leave the activity pose (walking / manual control takes over the tree).
func reset() -> void:
	phase = Phase.NONE
	_await_clip = &""
	_timer = 0.0

# Length of an AnimationPlayer clip in seconds, 0 if unknown.
func _clip_length(clip: StringName) -> float:
	if clip != &"" and _ap != null and _ap.has_animation(clip):
		return _ap.get_animation(clip).length
	return 0.0

# Print an activity-animation event when debug_anim is on. `clip` is the input name the event
# concerns (blank if none); `via` is the AnimationPlayer clip name or "timer" that advanced it.
func _dbg(event: String, clip: StringName, via: StringName = &"") -> void:
	if not debug_anim:
		return
	var mapped: StringName = CLIP_FOR_INPUT.get(clip, &"?") if clip != &"" else &"-"
	print("[anim %s] %s  input=%s clip=%s via=%s phase=%s" % [
			npc_id, event, clip, mapped, via, phase])
