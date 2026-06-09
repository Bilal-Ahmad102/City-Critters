extends Node
# GameManager — top-level autoload
# Handles global state: current scene, game phase, session info.
# Add to Project > Autoloads as "GameManager"

signal scene_changed(scene_name: String)

var current_scene: String = ""

func change_scene(path: String) -> void:
	current_scene = path
	get_tree().change_scene_to_file(path)
	scene_changed.emit(current_scene)
