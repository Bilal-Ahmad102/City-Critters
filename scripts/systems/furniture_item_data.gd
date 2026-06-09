extends Resource
# FurnitureItemData — data resource for a placeable furniture item.
class_name FurnitureItemData

@export var item_id: String = ""
@export var display_name: String = ""
@export var scene: PackedScene = null
@export var grid_size: Vector2i = Vector2i(1, 1)
@export var price: int = 100
@export var icon: Texture2D = null
