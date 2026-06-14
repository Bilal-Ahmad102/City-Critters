## Walk.gd
extends LimboState
@onready var animation_tree: AnimationTree = %AnimationTree

var _player: CharacterBody3D
func _setup() -> void:
	_player = agent

func _enter() -> void:
	animation_tree["parameters/Transition/transition_request"] = "walk"

func _exit() -> void:
	get_root().previous_state = self


@warning_ignore("unused_parameter")
func _update(delta: float) -> void:
	_player.handle_locomotion("walk",delta)
	call_transition_inputs()


func call_transition_inputs():
	get_root().input_for_run()
	get_root().input_for_idle()
