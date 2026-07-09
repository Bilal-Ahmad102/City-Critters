extends Node3D
class_name JobStation
# JobStation — a world spot the player walks up to and works a job shift. Its
# child InteractionArea fires `interacted`; that opens the assigned job's
# minigame overlay on a CanvasLayer and puts the player in the busy state.
# Dismissing the overlay (its `closed` signal) tears it down and returns control.

@export var job_scene: PackedScene           # e.g. scenes/jobs/food_service.tscn
@onready var _area: InteractionArea = $InteractionArea

var _player: Node3D = null
var _overlay: CanvasLayer = null

func _ready() -> void:
	_area.interacted.connect(_on_interacted)

func _on_interacted(by: Node3D) -> void:
	# Ignore re-triggers while a shift is already open.
	if _overlay != null or job_scene == null:
		return
	_player = by
	if _player.has_method("set_busy"):
		_player.set_busy(true)
	var ui := job_scene.instantiate()
	ui.closed.connect(_on_closed)
	_overlay = CanvasLayer.new()
	_overlay.add_child(ui)
	add_child(_overlay)

func _on_closed() -> void:
	if _player != null and _player.has_method("set_busy"):
		_player.set_busy(false)
	_player = null
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
