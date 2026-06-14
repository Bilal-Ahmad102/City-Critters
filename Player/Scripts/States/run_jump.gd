extends LimboState

var _player: CharacterBody3D
@onready var animation_tree: AnimationTree = %AnimationTree

func _setup() -> void:
	_player = agent

func _enter() -> void:
	
	animation_tree["parameters/Transition/transition_request"] = "run_jump"
	if !animation_tree.animation_finished.is_connected(_on_animation_finished):
		animation_tree.animation_finished.connect(_on_animation_finished)

func _on_animation_finished(anin_name: StringName):
	get_root().dispatch(&"run")
	
func _update(delta: float) -> void:
	_player.handle_locomotion("",delta)
	
func _exit() -> void:
	if animation_tree.animation_finished.is_connected(_on_animation_finished):
		animation_tree.animation_finished.disconnect(_on_animation_finished)

	_player.is_running_jump = false
	get_root().previous_state = self
