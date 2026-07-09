extends Control
class_name Minimap
# Minimap — circular HUD map, drawn in code (no textures). Centered on the
# local player and rotating with the camera: whatever direction the camera
# looks is up on the map (the "N" tick rides the rim to show true north).
# Shows every MapMarker in the "map_markers" group as a colored dot with its
# label, and the current objective (markers in "map_objective") as a pulsing
# diamond that clamps to the rim so it stays followable when out of range.
# Drop the scene into any world; markers wire themselves via groups.

# Meters from the player to the rim of the map.
@export var world_range: float = 70.0
# Draw labels next to marker dots (turn off for crowded worlds).
@export var show_labels: bool = true

var _player: Node3D = null

func _ready() -> void:
	# Never eat clicks meant for the game.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

# The local player's avatar (cached; re-found if it despawns).
func _find_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = null
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node3D and node.is_multiplayer_authority():
			_player = node
			break
	return _player

func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var center := size * 0.5
	# Backdrop + rim.
	draw_circle(center, radius, Color(0.08, 0.1, 0.12, 0.55))
	draw_arc(center, radius - 1.0, 0.0, TAU, 64, Color(1, 1, 1, 0.7), 2.0, true)

	var player := _find_player()
	if player == null:
		return
	var ppos := player.global_position

	# The map turns with the camera: rotate world-space offsets so the camera's
	# horizontal forward lands on screen-up. No camera (headless) = north-up.
	var spin := 0.0
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var f := -camera.global_basis.z
		var flat := Vector2(f.x, f.z)
		if flat.length_squared() > 0.0001:  # looking straight down: keep last-ish
			spin = -PI / 2.0 - flat.angle()

	var font := ThemeDB.fallback_font
	# Points of interest.
	for marker in get_tree().get_nodes_in_group("map_markers"):
		if not (marker is MapMarker) or not is_instance_valid(marker):
			continue
		var at := _to_map(marker.map_position(), ppos, radius, spin)
		var clamped := at.length() > radius - 8.0
		if clamped:
			at = at.normalized() * (radius - 8.0)
		draw_circle(center + at, 4.0, marker.color)
		draw_arc(center + at, 4.0, 0.0, TAU, 12, Color(0, 0, 0, 0.6), 1.0, true)
		if show_labels and not clamped and marker.label != "":
			draw_string(font, center + at + Vector2(6, 3), marker.label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.85))

	# Objective: pulsing diamond, always visible (edge-clamped when far).
	for marker in get_tree().get_nodes_in_group("map_objective"):
		if not (marker is MapMarker) or not is_instance_valid(marker):
			continue
		var at := _to_map(marker.map_position(), ppos, radius, spin)
		if at.length() > radius - 10.0:
			at = at.normalized() * (radius - 10.0)
		var pulse := 6.0 + 2.0 * sin(Time.get_ticks_msec() / 180.0)
		var p := center + at
		var diamond := PackedVector2Array([
			p + Vector2(0, -pulse), p + Vector2(pulse, 0),
			p + Vector2(0, pulse), p + Vector2(-pulse, 0),
		])
		draw_colored_polygon(diamond, Color(1, 0.85, 0.25))
		draw_polyline(diamond + PackedVector2Array([diamond[0]]),
			Color(0.2, 0.15, 0, 0.8), 1.5, true)

	# Player arrow: pinned to the center, always pointing up — the map already
	# spins so that up IS the camera's facing direction.
	var arrow := PackedVector2Array([
		center + Vector2(0, -9.0),
		center + Vector2(5.0, 5.0),
		center + Vector2(-5.0, 5.0),
	])
	draw_colored_polygon(arrow, Color(1, 1, 1))
	# North tick rides the rim so you can still orient globally.
	var north := Vector2(0, -1).rotated(spin) * (radius - 12.0)
	draw_string(font, center + north + Vector2(-4, 4), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))

# World offset from the player -> map pixels, spun so camera-forward is up.
func _to_map(world: Vector3, ppos: Vector3, radius: float, spin: float) -> Vector2:
	var rel := Vector2(world.x - ppos.x, world.z - ppos.z).rotated(spin)
	return rel * (radius / world_range)
