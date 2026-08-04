class_name SmartObject extends Node3D

@export var object_type: StringName          # "counter", "bed", "stool"
@export var location_tag: StringName         # which WorldLocation it belongs to
@export var slots: Array[NodePath] = []      # APPROACH markers (on navmesh) the NPC walks to
@export var seats: Array[NodePath] = []      # SEAT markers (on the object), parallel to slots;
											 # empty entry / shorter array = no seat, stand at slot

var _reserved: Dictionary = {}               # slot index -> npc_id

func _ready() -> void:
	LocationRegistry.register_object(self)
func _process(delta: float) -> void:
	print(_reserved)
func free_slot(npc_id: StringName) -> int:
	for i in slots.size():
		if not _reserved.has(i):
			return i
		if _reserved[i] == npc_id:
			return i                          # already ours
	return -1

func reserve(index: int, npc_id: StringName) -> bool:
	if index < 0 or index >= slots.size():
		return false
	if _reserved.has(index) and _reserved[index] != npc_id:
		return false
	_reserved[index] = npc_id
	return true

func release(npc_id: StringName) -> void:
	for i in _reserved.keys():
		if _reserved[i] == npc_id:
			_reserved.erase(i)

func slot_transform(index: int) -> Transform3D:
	return (get_node(slots[index]) as Node3D).global_transform

# Does this slot have a physical seat pose (sit on the bench), or is it a stand spot?
func has_seat(index: int) -> bool:
	return index >= 0 and index < seats.size() and not seats[index].is_empty()

func seat_transform(index: int) -> Transform3D:
	return (get_node(seats[index]) as Node3D).global_transform
