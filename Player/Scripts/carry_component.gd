extends Node
class_name CarryComponent
# CarryComponent — holds and displays the items the player is physically
# carrying. Lives as a child of the player; jobs reach it via player.get_carry()
# (FoodSource, FoodServiceStand, and any future carry job). Client-local for now
# (not replicated), so remote peers won't see the carried meshes yet.

# How many items the player can hold at once. 1 = single-carry (picking a new
# item swaps the held one). Bump to 2+ for a stack the player carries together.
@export var carry_capacity: int = 1
# Where the first carried item mesh sits relative to the hand node.
@export var carry_offset: Vector3 = Vector3(0.0, 0.9, 0.45)
# Vertical gap between stacked items when carrying more than one.
@export var carry_stack_offset: Vector3 = Vector3(0.0, 0.35, 0.0)
# Node the item meshes are parented to (turns with the critter's facing).
@export var _hand: Node3D

var held_items: Array[String] = []
var _held_meshes: Array[MeshInstance3D] = []

@onready var _player: Node = get_parent()

func _physics_process(_delta: float) -> void:
	# Only the local owner reads input; carrying is local-only.
	if not _player.is_authority:
		return
	if Input.is_action_just_pressed("drop"):
		drop()

func is_carrying() -> bool:
	return not held_items.is_empty()

func is_full() -> bool:
	return held_items.size() >= carry_capacity

# The item picked up longest ago; "" when empty. Kept for callers that only
# reason about a single held item.
func get_held_item() -> String:
	return held_items[0] if is_carrying() else ""

# A copy of everything held (oldest first).
func get_held_items() -> Array[String]:
	return held_items.duplicate()

# Picks up an item. With capacity 1 a new pick swaps out the held item; with
# capacity 2+ it stacks until full, then returns false so the caller can cue a
# "hands full" whiff (the player must drop first).
func pick_up(item: String, color: Color = Color.WHITE) -> bool:
	if is_full():
		if carry_capacity <= 1:
			_remove_at(0)          # single-carry: swap
		else:
			return false           # multi-carry: hands full, drop first
	held_items.append(item)
	_spawn_held_mesh(color)
	_restack()
	return true

# Drops (discards) the most recently picked-up item. Returns false when empty.
func drop() -> bool:
	if not is_carrying():
		return false
	_remove_at(held_items.size() - 1)
	return true

# Drops one specific item by name (used when an order consumes it). Returns
# false if that item isn't held.
func drop_item(item: String) -> bool:
	var idx := held_items.find(item)
	if idx == -1:
		return false
	_remove_at(idx)
	return true

func drop_all() -> void:
	while is_carrying():
		_remove_at(held_items.size() - 1)

func _remove_at(idx: int) -> void:
	held_items.remove_at(idx)
	var mesh: MeshInstance3D = _held_meshes[idx]
	_held_meshes.remove_at(idx)
	if mesh:
		mesh.queue_free()
	_restack()

func _spawn_held_mesh(color: Color) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	_hand.add_child(mesh)
	_held_meshes.append(mesh)

# Positions held meshes as a vertical stack in the hands.
func _restack() -> void:
	for i in _held_meshes.size():
		_held_meshes[i].position = carry_offset + carry_stack_offset * float(i)
