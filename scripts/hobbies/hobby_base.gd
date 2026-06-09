extends Node
# HobbyBase — base class for all hobby activities.
# Extend this for Fishing, Gardening, Music, etc.

signal hobby_started()
signal hobby_ended(reward: Dictionary)

@export var hobby_id: String = ""

func start() -> void:
	hobby_started.emit()
	_on_start()

func finish(reward: Dictionary) -> void:
	hobby_ended.emit(reward)

# Override in subclass
func _on_start() -> void:
	pass
