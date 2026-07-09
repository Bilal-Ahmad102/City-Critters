@tool
class_name CityStreet
extends Node3D

## Lays a straight road running along local Z, flanked by sidewalks, from
## the modular city kit. Road / sidewalk / prop are dropdowns auto-populated
## from the kit folder (see _SELECTORS + _validate_property). Road & sidewalk
## dimensions are MEASURED from the chosen model, so wider roads still get
## their sidewalks placed at the correct offset. Tiles are flat/decorative;
## put a ground collider under the town separately.

const KIT := "res://assets/Map/glTF (Godot)/"
const DEF_ROAD_LEN := 12.0
const DEF_ROAD_W := 6.0
const DEF_WALK := 3.0

const _SELECTORS := {
	"road_model": {"prefix": "Street_", "contains": "Lane", "exclude": "Curve"},
	"sidewalk_model": {"prefix": "Sidewalk_Straight"},
	"prop_model": {"prefix": "Prop_"},
}

@export var tiles: int = 5: set = _set_tiles
@export var sidewalks: bool = true: set = _set_walk
## Prop placed on the sidewalk every N tiles (0 = none).
@export var prop_every: int = 4: set = _set_propevery

@export_group("Models")
@export var road_model: String = "Street_2Lane": set = _set_road
@export var sidewalk_model: String = "Sidewalk_Straight_3m": set = _set_sidewalk
@export var prop_model: String = "Prop_Planter_Single": set = _set_prop

@export var rebuild: bool = false: set = _do_rebuild

var _root: Node3D

func _set_tiles(v: int) -> void: tiles = maxi(1, v); _rebuild()
func _set_walk(v: bool) -> void: sidewalks = v; _rebuild()
func _set_propevery(v: int) -> void: prop_every = maxi(0, v); _rebuild()
func _set_road(v: String) -> void: road_model = v; _rebuild()
func _set_sidewalk(v: String) -> void: sidewalk_model = v; _rebuild()
func _set_prop(v: String) -> void: prop_model = v; _rebuild()
func _do_rebuild(_v: bool) -> void: rebuild = false; _rebuild()

func _ready() -> void:
	_build()

func _rebuild() -> void:
	if is_node_ready():
		_build()

func length() -> float:
	var road_len := DEF_ROAD_LEN
	if road_model != "":
		road_len = maxf(0.5, _model_size(_path(road_model)).z)
	return tiles * road_len

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
	for file in dir.get_files():
		if not file.ends_with(".gltf"):
			continue
		var n := file.get_basename()
		if not n.begins_with(f.prefix):
			continue
		if f.has("contains") and not (f.contains in n):
			continue
		if f.has("exclude") and (f.exclude in n):
			continue
		out.append(n)
	out.sort()
	return out

func _path(model: String) -> String:
	return KIT + model + ".gltf"

func _build() -> void:
	if _root and is_instance_valid(_root):
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "StreetPieces"
	add_child(_root)

	var road_sz := _model_size(_path(road_model))
	var road_len := maxf(0.5, road_sz.z)
	var road_w := maxf(0.5, road_sz.x)

	var half := (tiles * road_len) / 2.0
	for i in tiles:
		var z := -half + road_len / 2.0 + i * road_len
		_place(_path(road_model), Vector3(0, 0, z), 0.0)

	if not sidewalks:
		return

	var walk_sz := _model_size(_path(sidewalk_model))
	var walk_w := maxf(0.5, walk_sz.x)
	var walk_len := maxf(0.5, walk_sz.z)
	var walk_x := road_w / 2.0 + walk_w / 2.0
	var total := tiles * road_len
	var n_walk := int(total / walk_len)
	var wh := (n_walk * walk_len) / 2.0
	for i in n_walk:
		var z := -wh + walk_len / 2.0 + i * walk_len
		_place(_path(sidewalk_model), Vector3(walk_x, 0, z), 0.0)
		_place(_path(sidewalk_model), Vector3(-walk_x, 0, z), 180.0)
		if prop_every > 0 and prop_model != "" and i % prop_every == 1:
			_place(_path(prop_model), Vector3(walk_x, 0, z), 0.0)
			_place(_path(prop_model), Vector3(-walk_x, 0, z), 0.0)

func _place(path: String, pos: Vector3, deg: float) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		push_warning("CityStreet: missing %s" % path)
		return
	var inst := scene.instantiate()
	inst.position = pos
	inst.rotation.y = deg_to_rad(deg)
	_root.add_child(inst)

func _model_size(path: String) -> Vector3:
	var scene: PackedScene = load(path)
	if scene == null:
		return Vector3(DEF_ROAD_W, 0.15, DEF_ROAD_LEN)
	var inst: Node3D = scene.instantiate()
	var aabb := _mesh_aabb(inst)
	inst.free()
	if aabb.size == Vector3.ZERO:
		return Vector3(DEF_ROAD_W, 0.15, DEF_ROAD_LEN)
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
