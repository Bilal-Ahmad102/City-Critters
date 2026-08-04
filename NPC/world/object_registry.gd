# location_registry.gd (autoload)
extends Node

var _by_tag: Dictionary = {}      # StringName -> Array[WorldLocation]
var _objects: Dictionary = {}     # StringName -> Array[SmartObject]


# ------------------------------------------------------------------ locations

func register(loc: WorldLocation) -> void:
	if not _by_tag.has(loc.tag):
		_by_tag[loc.tag] = []
	_by_tag[loc.tag].append(loc)


func unregister(loc: WorldLocation) -> void:
	if _by_tag.has(loc.tag):
		_by_tag[loc.tag].erase(loc)


func get_location(tag: StringName, npc_id: StringName = &"") -> WorldLocation:
	var list: Array = _by_tag.get(tag, [])
	if list.is_empty():
		push_warning("No location registered for tag: %s" % tag)
		return null
	if npc_id != &"":
		for loc in list:
			if loc.owner_id == npc_id:
				return loc
	return list[0]


# --------------------------------------------------------------- smart objects

func register_object(obj: SmartObject) -> void:
	if not _objects.has(obj.location_tag):
		_objects[obj.location_tag] = []
	_objects[obj.location_tag].append(obj)


func unregister_object(obj: SmartObject) -> void:
	if _objects.has(obj.location_tag):
		_objects[obj.location_tag].erase(obj)


func find_object(location_tag: StringName, object_type: StringName,
		npc_id: StringName, near: Vector3 = Vector3.INF) -> SmartObject:
	var list: Array = _objects.get(location_tag, [])
	var best: SmartObject = null
	var best_dist: float = INF

	for obj in list:
		if obj.object_type != object_type:
			continue
		if obj.free_slot(npc_id) == -1:
			continue
		if near == Vector3.INF:
			return obj
		var d: float = obj.global_position.distance_squared_to(near)
		if d < best_dist:
			best_dist = d
			best = obj

	return best
