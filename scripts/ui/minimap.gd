@tool
extends Control
class_name Minimap
# Minimap — square GTA-style HUD map (bottom-left), drawn in code (no
# textures). Centered on the local player and rotating with the camera:
# whatever direction the camera looks is up on the map (the "N" tick rides
# the border to show true north). Shows every MapMarker in the "map_markers"
# group as an icon (or colored dot), and the current objective (markers in
# "map_objective") as a pulsing gold glyph that clamps to the border so it
# stays followable when out of range. Icons are unlabeled; pressing the
# `map_legend` action (TAB) opens a legend explaining what each icon means.
# Drop the scene into any world; markers wire themselves via groups.
#
# Layout is driven by the exports below (the .tscn anchors are overwritten
# at runtime), so resize/restyle from the inspector on the world's instance.

@export_group("Layout")
# Pixel size of the map square.
@export var map_size: Vector2 = Vector2(200, 200):
	set(value):
		map_size = value
		_apply_layout()
# Gap between the map and the bottom-left screen corner.
@export var screen_margin: Vector2 = Vector2(16, 16):
	set(value):
		screen_margin = value
		_apply_layout()
# Meters from the player to the edge of the map.
@export var world_range: float = 70.0

@export_group("Style")
@export var background_color: Color = Color(0.08, 0.1, 0.12, 0.55)
@export var border_color: Color = Color(1, 1, 1, 0.7)
@export var border_width: float = 2.0
# Pixel size of marker glyphs (icon textures) on the map.
@export var icon_size: float = 12.0
# Radius of the plain dot drawn for markers without an icon.
@export var dot_radius: float = 4.0
# Objective glyph tint (also used for its legend row).
@export var objective_color: Color = Color(1, 0.85, 0.25)
@export var player_arrow_color: Color = Color.WHITE
# Camera-forward is up when true (GTA style); false keeps north up.
@export var rotate_with_camera: bool = true
@export var show_north_tick: bool = true

var _player: Node3D = null
var _legend: CanvasLayer = null
var _legend_rows: VBoxContainer = null

func _ready() -> void:
	# Never eat clicks meant for the game.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()

func _process(_delta: float) -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	if Input.is_action_just_pressed("map_legend"):
		_toggle_legend()

# Pins the map to the bottom-left corner at the exported size/margin.
func _apply_layout() -> void:
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = screen_margin.x
	offset_right = screen_margin.x + map_size.x
	offset_top = -(screen_margin.y + map_size.y)
	offset_bottom = -screen_margin.y
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN

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
	var center := size * 0.5
	# Half-extent markers may occupy (border margin keeps glyphs inside).
	var half := center - Vector2.ONE * (icon_size * 0.5 + 4.0)
	var scale_px := minf(half.x, half.y) / world_range
	# Backdrop + border.
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	if border_width > 0.0:
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), border_color, false, border_width)

	if Engine.is_editor_hint():
		return  # Backdrop preview only; markers/player need a running game.
	var player := _find_player()
	if player == null:
		return
	var ppos := player.global_position

	# The map turns with the camera: rotate world-space offsets so the camera's
	# horizontal forward lands on screen-up. No camera (headless) = north-up.
	var spin := 0.0
	var camera := get_viewport().get_camera_3d()
	if rotate_with_camera and camera != null:
		var f := -camera.global_basis.z
		var flat := Vector2(f.x, f.z)
		if flat.length_squared() > 0.0001:  # looking straight down: keep last-ish
			spin = -PI / 2.0 - flat.angle()

	var font := ThemeDB.fallback_font
	var icon_half := Vector2.ONE * (icon_size * 0.5)
	# Points of interest.
	for marker in get_tree().get_nodes_in_group("map_markers"):
		if not (marker is MapMarker) or not is_instance_valid(marker):
			continue
		var at := _to_map(marker.map_position(), ppos, scale_px, spin)
		at = at.clamp(-half, half)
		if marker.icon != null:
			# Backing disc keeps the tinted glyph readable over any terrain.
			draw_circle(center + at, icon_size * 0.5 + 2.0, Color(0.05, 0.07, 0.09, 0.7))
			draw_texture_rect(marker.icon, Rect2(center + at - icon_half, icon_half * 2.0),
				false, marker.color)
		else:
			draw_circle(center + at, dot_radius, marker.color)
			draw_arc(center + at, dot_radius, 0.0, TAU, 12, Color(0, 0, 0, 0.6), 1.0, true)

	# Objective: pulsing gold, always visible (edge-clamped when far).
	for marker in get_tree().get_nodes_in_group("map_objective"):
		if not (marker is MapMarker) or not is_instance_valid(marker):
			continue
		var at := _to_map(marker.map_position(), ppos, scale_px, spin)
		at = at.clamp(-half, half)
		var pulse := (icon_size * 0.5) * (1.0 + 0.33 * sin(Time.get_ticks_msec() / 180.0))
		var p := center + at
		if marker.icon != null:
			# Same glyph as the regular marker, gold + pulsing so it reads as
			# "go here" while staying recognizable.
			draw_circle(p, pulse + 3.0, Color(0.15, 0.11, 0, 0.75))
			draw_texture_rect(marker.icon, Rect2(p - Vector2(pulse, pulse), Vector2(pulse, pulse) * 2.0),
				false, objective_color)
		else:
			var diamond := PackedVector2Array([
				p + Vector2(0, -pulse), p + Vector2(pulse, 0),
				p + Vector2(0, pulse), p + Vector2(-pulse, 0),
			])
			draw_colored_polygon(diamond, objective_color)
			draw_polyline(diamond + PackedVector2Array([diamond[0]]),
				Color(0.2, 0.15, 0, 0.8), 1.5, true)

	# Player arrow: pinned to the center, always pointing up — the map already
	# spins so that up IS the camera's facing direction.
	var arrow := PackedVector2Array([
		center + Vector2(0, -9.0),
		center + Vector2(5.0, 5.0),
		center + Vector2(-5.0, 5.0),
	])
	draw_colored_polygon(arrow, player_arrow_color)
	# North tick rides the border so you can still orient globally.
	if show_north_tick:
		var nd := Vector2(0, -1).rotated(spin)
		var edge := half - Vector2(4, 4)
		var reach := INF
		if absf(nd.x) > 0.001:
			reach = minf(reach, edge.x / absf(nd.x))
		if absf(nd.y) > 0.001:
			reach = minf(reach, edge.y / absf(nd.y))
		draw_string(font, center + nd * reach + Vector2(-4, 4), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))

# World offset from the player -> map pixels, spun so camera-forward is up.
func _to_map(world: Vector3, ppos: Vector3, scale_px: float, spin: float) -> Vector2:
	var rel := Vector2(world.x - ppos.x, world.z - ppos.z).rotated(spin)
	return rel * scale_px

# --- Legend (TAB) ------------------------------------------------------------
# Centered overlay listing every distinct icon currently on the map with what
# it means (MapMarker.legend, falling back to the marker's label). Rebuilt on
# every open so it always matches the world.

func _toggle_legend() -> void:
	if _legend == null:
		_build_legend()
	if _legend.visible:
		_legend.visible = false
	else:
		_fill_legend()
		_legend.visible = true

func _build_legend() -> void:
	_legend = CanvasLayer.new()
	_legend.layer = 20
	_legend.visible = false
	add_child(_legend)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	_legend_rows = VBoxContainer.new()
	_legend_rows.add_theme_constant_override("separation", 8)
	_legend_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_legend_rows)

func _fill_legend() -> void:
	var rows: VBoxContainer = _legend_rows
	for child in rows.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "MAP LEGEND"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)
	rows.add_child(HSeparator.new())
	# One row per distinct icon+meaning pair present in the world right now.
	var seen := {}
	for marker in get_tree().get_nodes_in_group("map_markers"):
		if not (marker is MapMarker) or not is_instance_valid(marker):
			continue
		var text: String = marker.legend if marker.legend != "" else marker.label
		if text == "":
			text = "Point of interest"
		var key: String = (marker.icon.resource_path if marker.icon != null else "dot") + "|" + text
		if seen.has(key):
			continue
		seen[key] = true
		rows.add_child(_legend_row(marker.icon, marker.color, text))
	rows.add_child(HSeparator.new())
	# Fixed map furniture.
	rows.add_child(_legend_row(null, objective_color, "Current objective (pulsing)"))
	rows.add_child(_legend_row(null, player_arrow_color, "You"))
	var hint := Label.new()
	hint.text = "TAB to close"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(hint)

func _legend_row(icon: Texture2D, color: Color, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != null:
		var tex := TextureRect.new()
		tex.texture = icon
		tex.custom_minimum_size = Vector2(20, 20)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.modulate = color
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)
	else:
		var dot := Label.new()
		dot.text = "●"
		dot.custom_minimum_size = Vector2(20, 0)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.add_theme_color_override("font_color", color)
		row.add_child(dot)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	return row
