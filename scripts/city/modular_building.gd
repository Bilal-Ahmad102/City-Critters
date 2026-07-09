@tool
class_name ModularBuilding
extends Node3D

## Parametric building assembled from the Downtown City MegaKit
## (assets/Map/glTF (Godot)). Tiles facade panels around a rectangular
## footprint: an optional storefront ground floor, brick upper floors with
## windows, corner trims, a cornice crown, a flat roof, an optional front
## fire escape, and a solid box collider.
##
## Each swappable part is a dropdown (@export enum) auto-populated from the
## kit folder by filename filter (see _SELECTORS + _validate_property).
## Piece dims are MEASURED from the chosen model's AABB at build, so swapping
## to a different-sized model still tiles correctly.

const KIT := "res://assets/Map/glTF (Godot)/"
const DEF_SEG := 2.0
const DEF_STOREY := 3.0

enum GroundStyle { BRICK, STOREFRONT }

# exported model var -> filename filter {prefix?, contains? (String|Array), exclude?}
const _SELECTORS := {
	"wall_model": {"prefix": "Brick_Plain"},
	"window_model": {"prefix": "Brick_Inset_Window"},
	"door_frame_model": {"prefix": "DoorFrame"},
	"door_model": {"prefix": "Door_"},
	"roof_model": {"prefix": "Roof_"},
	"cornice_model": {"prefix": "Cornice_", "contains": "Center"},
	"corner_model": {"prefix": "Brick_Column"},
	"storefront_wall_model": {"contains": ["FirstFloor", "Wall"]},
	"storefront_window_model": {"contains": ["FirstFloor", "Window"]},
	"entrance_model": {"prefix": "Entrance"},
	"fire_escape_model": {"prefix": "Stairs_Rails"},
}

@export_group("Shape")
@export var width_segments: int = 4: set = _set_w   # footprint X = segments * panel width
@export var depth_segments: int = 3: set = _set_d   # footprint Z = segments * panel width
@export var floors: int = 3: set = _set_f
@export var front_door: bool = true: set = _set_door
## Windows appear every N panel slots per upper floor (0 = none).
@export var window_every: int = 2: set = _set_win
@export var ground_style: GroundStyle = GroundStyle.BRICK: set = _set_ground
## Zig-zag metal fire escape down the front (+Z) face.
@export var fire_escape: bool = false: set = _set_fire

@export_group("Models")
@export var wall_model: String = "Brick_Plain_3": set = _set_wall
@export var window_model: String = "Brick_Inset_Window": set = _set_window
@export var door_frame_model: String = "DoorFrame_Wooden": set = _set_doorframe
@export var door_model: String = "Door_1": set = _set_doormodel
@export var roof_model: String = "Roof_2x2": set = _set_roof
@export var cornice_model: String = "Cornice_Brick_Center": set = _set_cornice
@export var corner_model: String = "Brick_Column_Small": set = _set_corner
@export var storefront_wall_model: String = "Metal_FirstFloor_Wall": set = _set_sfwall
@export var storefront_window_model: String = "Metal_FirstFloor_Window": set = _set_sfwin
@export var entrance_model: String = "Entrance_Concrete_2x1": set = _set_entrance
@export var fire_escape_model: String = "Stairs_Rails_Metal": set = _set_fireesc

@export var rebuild: bool = false: set = _do_rebuild

var _pieces: Node3D
var _pw := DEF_SEG      # panel width
var _sh := DEF_STOREY   # storey height
var _w := 0.0
var _d := 0.0

func _set_w(v: int) -> void: width_segments = maxi(2, v); _rebuild()
func _set_d(v: int) -> void: depth_segments = maxi(2, v); _rebuild()
func _set_f(v: int) -> void: floors = maxi(1, v); _rebuild()
func _set_door(v: bool) -> void: front_door = v; _rebuild()
func _set_win(v: int) -> void: window_every = maxi(0, v); _rebuild()
func _set_ground(v: GroundStyle) -> void: ground_style = v; _rebuild()
func _set_fire(v: bool) -> void: fire_escape = v; _rebuild()
func _do_rebuild(_v: bool) -> void: rebuild = false; _rebuild()
func _set_wall(v: String) -> void: wall_model = v; _rebuild()
func _set_window(v: String) -> void: window_model = v; _rebuild()
func _set_doorframe(v: String) -> void: door_frame_model = v; _rebuild()
func _set_doormodel(v: String) -> void: door_model = v; _rebuild()
func _set_roof(v: String) -> void: roof_model = v; _rebuild()
func _set_cornice(v: String) -> void: cornice_model = v; _rebuild()
func _set_corner(v: String) -> void: corner_model = v; _rebuild()
func _set_sfwall(v: String) -> void: storefront_wall_model = v; _rebuild()
func _set_sfwin(v: String) -> void: storefront_window_model = v; _rebuild()
func _set_entrance(v: String) -> void: entrance_model = v; _rebuild()
func _set_fireesc(v: String) -> void: fire_escape_model = v; _rebuild()

func _ready() -> void:
	_build()

func _rebuild() -> void:
	if is_node_ready():
		_build()

func size_x() -> float: return _w
func size_z() -> float: return _d
func height() -> float: return floors * _sh

# --- dropdown population (editor) ---
func _validate_property(property: Dictionary) -> void:
	if _SELECTORS.has(property.name):
		var opts := _scan(_SELECTORS[property.name])
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(opts)

func _scan(f: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(KIT)
	if dir == null:
		return out
	var prefix: String = f.get("prefix", "")
	for file in dir.get_files():
		if not file.ends_with(".gltf"):
			continue
		var n := file.get_basename()
		if not n.begins_with(prefix):
			continue
		if not _contains_ok(n, f.get("contains", "")):
			continue
		if f.has("exclude") and (f.exclude in n):
			continue
		out.append(n)
	out.sort()
	return out

func _contains_ok(n: String, needle) -> bool:
	if needle is Array:
		for s in needle:
			if not (s in n):
				return false
		return true
	if typeof(needle) == TYPE_STRING and needle != "":
		return needle in n
	return true

# --- build ---
func _path(model: String) -> String:
	return KIT + model + ".gltf"

func _build() -> void:
	if _pieces and is_instance_valid(_pieces):
		_pieces.queue_free()
	_pieces = Node3D.new()
	_pieces.name = "Pieces"
	add_child(_pieces)

	var wall_sz := _model_size(_path(wall_model))
	_pw = maxf(0.5, wall_sz.x)
	_sh = maxf(0.5, wall_sz.y)
	_w = width_segments * _pw
	_d = depth_segments * _pw

	for f in floors:
		var y := f * _sh
		var ground := f == 0
		if ground and ground_style == GroundStyle.STOREFRONT:
			_storefront_side(Vector3(0, y, _d / 2.0), 0.0, width_segments, front_door)
			_storefront_side(Vector3(0, y, -_d / 2.0), 180.0, width_segments, false)
			_storefront_side(Vector3(_w / 2.0, y, 0), 90.0, depth_segments, false)
			_storefront_side(Vector3(-_w / 2.0, y, 0), -90.0, depth_segments, false)
		else:
			_wall_side(Vector3(0, y, _d / 2.0), 0.0, width_segments, ground and front_door)
			_wall_side(Vector3(0, y, -_d / 2.0), 180.0, width_segments, false)
			_wall_side(Vector3(_w / 2.0, y, 0), 90.0, depth_segments, false)
			_wall_side(Vector3(-_w / 2.0, y, 0), -90.0, depth_segments, false)
		_corners(y)

	_cornice(floors * _sh)
	_roof(floors * _sh)
	if fire_escape:
		_fire_escape()
	_collision()

func _wall_side(origin: Vector3, deg: float, n: int, with_door: bool) -> void:
	var rot := deg_to_rad(deg)
	var along := Vector3(cos(rot), 0, -sin(rot))
	var half := (n * _pw) / 2.0
	var win_slots := 1
	if window_model != "":
		win_slots = maxi(1, int(round(_model_size(_path(window_model)).x / _pw)))
	var i := 0
	while i < n:
		var slot_center := -half + _pw / 2.0 + i * _pw
		if with_door and i == n / 2:
			var pos := origin + along * slot_center
			_place(_path(door_frame_model), pos, deg)
			_place(_path(door_model), pos + Vector3(0, 0.01, 0), deg)
			i += 1
			continue
		if window_every > 0 and i % window_every == 0 and i + win_slots <= n and not with_door:
			var wc := -half + (win_slots * _pw) / 2.0 + i * _pw
			_place(_path(window_model), origin + along * wc, deg)
			i += win_slots
			continue
		_place(_path(wall_model), origin + along * slot_center, deg)
		i += 1

# Ground-floor commercial facade: window shopfronts, solid pillars at the
# ends, a door in the middle of the front, and a small stoop at the door.
func _storefront_side(origin: Vector3, deg: float, n: int, with_door: bool) -> void:
	var rot := deg_to_rad(deg)
	var along := Vector3(cos(rot), 0, -sin(rot))
	var outward := Vector3(sin(rot), 0, cos(rot))
	var half := (n * _pw) / 2.0
	for i in n:
		var slot_center := -half + _pw / 2.0 + i * _pw
		var pos := origin + along * slot_center
		if with_door and i == n / 2:
			_place(_path(door_frame_model), pos, deg)
			_place(_path(door_model), pos + Vector3(0, 0.01, 0), deg)
			_place(_path(entrance_model), pos + outward * (_model_size(_path(entrance_model)).z / 2.0), deg)
			continue
		if i == 0 or i == n - 1:
			_place(_path(storefront_wall_model), pos, deg)
		else:
			_place(_path(storefront_window_model), pos, deg)

func _corners(y: float) -> void:
	var hx := _w / 2.0
	var hz := _d / 2.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_place(_path(corner_model), Vector3(sx * hx, y, sz * hz), 0.0)

func _cornice(y: float) -> void:
	_cornice_side(Vector3(0, y, _d / 2.0), 0.0, width_segments)
	_cornice_side(Vector3(0, y, -_d / 2.0), 180.0, width_segments)
	_cornice_side(Vector3(_w / 2.0, y, 0), 90.0, depth_segments)
	_cornice_side(Vector3(-_w / 2.0, y, 0), -90.0, depth_segments)

func _cornice_side(origin: Vector3, deg: float, n: int) -> void:
	var rot := deg_to_rad(deg)
	var along := Vector3(cos(rot), 0, -sin(rot))
	var half := (n * _pw) / 2.0
	for i in n:
		var c := -half + _pw / 2.0 + i * _pw
		_place(_path(cornice_model), origin + along * c, deg)

func _roof(y: float) -> void:
	var rs := _model_size(_path(roof_model))
	var step_x := maxf(0.5, rs.x)
	var step_z := maxf(0.5, rs.z)
	var hx := _w / 2.0
	var hz := _d / 2.0
	var x := -hx + step_x / 2.0
	while x < hx:
		var z := -hz + step_z / 2.0
		while z < hz:
			_place(_path(roof_model), Vector3(x, y, z), 0.0)
			z += step_z
		x += step_x

# Zig-zag metal fire escape hung on the front (+Z) face, one landing per
# upper floor, alternating sides so the stairs read as switchbacks.
func _fire_escape() -> void:
	var fe_sz := _model_size(_path(fire_escape_model))
	var z := _d / 2.0 + fe_sz.z / 2.0
	var off := _pw * 0.5
	for f in range(1, floors):
		var side := off if f % 2 == 0 else -off
		_place(_path(fire_escape_model), Vector3(side, f * _sh, z), 0.0)

func _collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_w, height(), _d)
	cs.shape = box
	cs.position = Vector3(0, height() / 2.0, 0)
	body.add_child(cs)
	_pieces.add_child(body)

func _place(path: String, pos: Vector3, deg: float) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		push_warning("ModularBuilding: missing %s" % path)
		return
	var inst := scene.instantiate()
	inst.position = pos
	inst.rotation.y = deg_to_rad(deg)
	_pieces.add_child(inst)

func _model_size(path: String) -> Vector3:
	var scene: PackedScene = load(path)
	if scene == null:
		return Vector3(DEF_SEG, DEF_STOREY, DEF_SEG)
	var inst: Node3D = scene.instantiate()
	var aabb := _mesh_aabb(inst)
	inst.free()
	if aabb.size == Vector3.ZERO:
		return Vector3(DEF_SEG, DEF_STOREY, DEF_SEG)
	return aabb.size

func _mesh_aabb(node: Node) -> AABB:
	var acc := AABB()
	var has := false
	if node is MeshInstance3D and node.mesh != null:
		acc = (node as MeshInstance3D).get_aabb()
		has = true
	for c in node.get_children():
		var child := _mesh_aabb(c)
		if child.size == Vector3.ZERO:
			continue
		if node is Node3D and c is Node3D:
			child = (c as Node3D).transform * child
		if has:
			acc = acc.merge(child)
		else:
			acc = child
			has = true
	return acc
