extends Node3D

@onready var animation_tree: AnimationTree = $AnimationTree

var animations : Array = ["idle", "enter_pray", "pray", "end_pray"]
var index : int = 0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation_tree.animation_finished.connect(_on_animation_finished)



func _process(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		index += 1
		if index == len(animations):
			index = 0
		animation_tree["parameters/Transition/transition_request"] = animations[index]

func _on_animation_finished(anim_name:  StringName):
	print(anim_name)
	if anim_name == "End_Praying":
		index += 1
		if index == len(animations):
			index = 0

		animation_tree["parameters/Transition/transition_request"] = animations[index]

		
