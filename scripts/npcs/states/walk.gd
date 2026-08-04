extends LimboState
# NPC walk: root-motion stroll toward the target.

@onready var animation_tree: AnimationTree = %AnimationTree

var _npc: CharacterBody3D

func _setup() -> void:
	_npc = agent

func _enter() -> void:
	animation_tree["parameters/Transition/transition_request"] = "walk"

@warning_ignore("unused_parameter")
func _update(delta: float) -> void:
	get_root().input_for_run()
	get_root().input_for_idle()
