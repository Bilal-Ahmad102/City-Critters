extends LimboState
# NPC idle: stand still. Leaves for walk once the NPC has somewhere to be.

@onready var animation_tree: AnimationTree = %AnimationTree

var _npc: CharacterBody3D

func _setup() -> void:
	_npc = agent

func _enter() -> void:
	animation_tree["parameters/Transition/transition_request"] = "drink"

@warning_ignore("unused_parameter")
func _update(delta: float) -> void:
	get_root().input_for_idle()
