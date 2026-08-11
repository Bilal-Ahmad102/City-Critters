extends Control
## Loading screen shown while the world scene streams in on a background thread,
## then swaps to it. Used both when a single player enters the world and after a
## multiplayer lobby is hosted or joined. The world path and a status line come
## from the Multiplayer autoload so the same screen serves every entry point.

@onready var status_label: Label = %StatusLabel
@onready var progress_bar: ProgressBar = %ProgressBar

var _target: String = ""
var _done: bool = false

func _ready() -> void:
	_target = Multiplayer.WORLD_SCENE
	status_label.text = Multiplayer.loading_status if Multiplayer.loading_status != "" else "Loading..."
	progress_bar.value = 0.0
	var err: int = ResourceLoader.load_threaded_request(_target)
	if err != OK:
		status_label.text = "Failed to start loading (%s)" % err
		_done = true

func _process(_delta: float) -> void:
	if _done:
		return
	var progress: Array = []
	var st: int = ResourceLoader.load_threaded_get_status(_target, progress)
	match st:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not progress.is_empty():
				progress_bar.value = float(progress[0]) * 100.0
		ResourceLoader.THREAD_LOAD_LOADED:
			_done = true
			progress_bar.value = 100.0
			var packed: PackedScene = ResourceLoader.load_threaded_get(_target)
			get_tree().change_scene_to_packed(packed)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_done = true
			status_label.text = "Failed to load the world."
