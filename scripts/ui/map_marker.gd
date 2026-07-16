extends Node
class_name MapMarker
# MapMarker — drop as a child of any Node3D to put it on the minimap. Joins
# the "map_markers" group so the Minimap can discover every point of interest
# without wiring. Callers (job stands) can flag their marker as the player's
# current objective; the minimap then draws it highlighted and edge-clamped.

@export var color: Color = Color.WHITE
@export var label: String = ""
# Optional glyph drawn instead of the plain dot. Single-color icons (the
# addons/at-icons set) work best: the minimap tints them with `color`.
@export var icon: Texture2D = null
# What this icon means, shown in the minimap's TAB legend (falls back to
# `label`). Markers sharing an icon should share a legend so they collapse
# into one legend row.
@export var legend: String = ""

func _ready() -> void:
	add_to_group("map_markers")

# World position shown on the map (the marker tags its parent).
func map_position() -> Vector3:
	var parent := get_parent() as Node3D
	return parent.global_position if parent != null else Vector3.ZERO

# Marks / unmarks this spot as the active objective ("map_objective" group).
func set_objective(value: bool) -> void:
	if value and not is_in_group("map_objective"):
		add_to_group("map_objective")
	elif not value and is_in_group("map_objective"):
		remove_from_group("map_objective")
