extends Node3D
# GridPlacementSystem — manages grid-based furniture placement in a room.
# Attach to the apartment root scene.

@export var grid_size: int = 1          # world units per cell
@export var grid_width: int = 10
@export var grid_height: int = 10

var _grid: Dictionary = {}  # Vector2i -> item_id

func place_item(grid_pos: Vector2i, item_id: String) -> bool:
	if _grid.has(grid_pos):
		return false
	_grid[grid_pos] = item_id
	return true

func remove_item(grid_pos: Vector2i) -> void:
	_grid.erase(grid_pos)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(world_pos.x / grid_size), int(world_pos.z / grid_size))

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(grid_pos.x * grid_size, 0.0, grid_pos.y * grid_size)
