extends LimboState
# NPC run: root-motion jog for long hauls.

@onready var animation_tree: AnimationTree = %AnimationTree

var _npc: CharacterBody3D

func _setup() -> void:
	_npc = agent

func _enter() -> void:
	animation_tree["parameters/Transition/transition_request"] = "run"

@warning_ignore("unused_parameter")
func _update(delta: float) -> void:
	get_root().input_for_walk()
	get_root().input_for_idle()
