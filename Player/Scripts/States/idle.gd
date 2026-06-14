extends LimboState

var _player: CharacterBody3D
@onready var animation_tree: AnimationTree = %AnimationTree

func _setup() -> void:
	_player = agent  # agent = the CharacterBody2D passed to hsm.initialize()

func _enter() -> void:
	animation_tree["parameters/Transition/transition_request"] = "idle"

func _exit() -> void:
	get_root().previous_state = self


@warning_ignore("unused_parameter")
func _update(delta: float) -> void:
	_player.handle_locomotion("",delta)

	# ── Transitions ──────────────────────────────────────────
	call_transition_inputs()
	
func call_transition_inputs():
	get_root().input_for_walk()
	#get_root().input_for_jump()
