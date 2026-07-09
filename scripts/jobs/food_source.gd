extends Node3D
class_name FoodSource
# FoodSource — a physical spot in the world that hands the player an item when
# they walk up and press E. Drop one per menu item (burger, fries, ...) near a
# FoodServiceStand; the player carries the item over to the serve counter.

@export var item: String = "burger"
@export var color: Color = Color.WHITE

@onready var _area: InteractionArea = $InteractionArea
@onready var _mesh: CSGBox3D = $Mesh

func _ready() -> void:
	_area.prompt_text = "Take " + item.capitalize()
	_area.interacted.connect(_on_interacted)
	# Tint the crate to match the item the player will carry away.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_mesh.material = mat

func _on_interacted(by: Node3D) -> void:
	if by.has_method("get_carry"):
		by.get_carry().pick_up(item, color)

# Arms / disarms pickup (the stand disables it until the shift starts).
func set_active(value: bool) -> void:
	_area.set_active(value)
