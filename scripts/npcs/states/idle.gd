extends LimboState
# NPC idle: stand still. Leaves for walk once the NPC has somewhere to be.

@onready var animation_tree: AnimationTree = %AnimationTree

var _npc: CharacterBody3D

func _setup() -> void:
	_npc = agent

func _enter() -> void:
	# The stationary clip is "idle" by default, or the current activity's animation
	# once the NPC has arrived somewhere (sleeping/sit_park/looking/box_idle).
	animation_tree["parameters/Transition/transition_request"] = String(_npc.stationary_anim)

@warning_ignore("unused_parameter")
func _update(delta: float) -> void:
	# intent (is_moving/is_running) is computed in NPCBase._physics_process; here
	# we only react to it by requesting transitions.
	get_root().input_for_walk()
	get_root().input_for_run()
