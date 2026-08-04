class_name WorldLocation extends Node3D

@export var tag: StringName
@export var owner_id: StringName = &""        # set to an npc_id for "own_home"

func _ready() -> void:
	LocationRegistry.register(self)

func _exit_tree() -> void:
	LocationRegistry.unregister(self)
