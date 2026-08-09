class_name HouseProperty extends Node3D
# HouseProperty — makes a house buyable and shows who owns it.
#
# Attach to a house scene root. The house's id is its node name (House_1, ...),
# so the same instance name in town.tscn ties the world house to the persisted
# ownership record in PropertyManager.
#
# Built at runtime (no scene wiring needed):
#   • a floating "FOR SALE" / owner nameplate (Label3D),
#   • an InteractionArea over the footprint ("press E"),
#   • a MapMarker that appears on the owner's minimap only.
#
# Interaction rules: anyone may buy an unowned house; the owner may toggle
# public/private; non-owners can't interact with an owned house at all.

@export var price: int = 500
# Height of the nameplate above the house footprint.
@export var sign_lift: float = 2.0

var _house_id: String = ""
var _sign: Label3D
var _area: InteractionArea
var _marker: MapMarker
var _footprint: AABB


func _ready() -> void:
	_house_id = String(name)
	_footprint = _compute_footprint()
	_build_sign()
	_build_interaction()
	_build_marker()
	PropertyManager.ownership_changed.connect(_on_ownership_changed)
	_refresh()


func _on_ownership_changed(house_id: String) -> void:
	if house_id == _house_id:
		_refresh()


func _on_interacted(_by: Node3D) -> void:
	if not PropertyManager.is_owned(_house_id):
		PropertyManager.request_buy(_house_id, price)
	elif PropertyManager.is_local_owner(_house_id):
		PropertyManager.toggle_access(_house_id)


# ── State ────────────────────────────────────────────────────────────────────
func _refresh() -> void:
	var owned: bool = PropertyManager.is_owned(_house_id)
	var mine: bool = PropertyManager.is_local_owner(_house_id)

	# Nameplate.
	if not owned:
		_sign.text = "FOR SALE\n$%d  [E]" % price
		_sign.modulate = Color(0.5, 1.0, 0.5)
	elif mine:
		var access: String = "Public" if PropertyManager.is_public(_house_id) else "Private"
		_sign.text = "Your House (%s)\n[E] toggle" % access
		_sign.modulate = Color(1.0, 0.9, 0.4)
	else:
		var access2: String = "Public" if PropertyManager.is_public(_house_id) else "Private"
		_sign.text = "%s's House\n(%s)" % [PropertyManager.get_owner_name(_house_id), access2]
		_sign.modulate = Color(0.85, 0.85, 0.85)

	# Only the buyer and the owner may interact; others get nothing on an
	# owned house.
	_area.set_active(not owned or mine)

	# The owner sees their home on the minimap; nobody else does.
	if mine:
		if not _marker.is_in_group("map_markers"):
			_marker.add_to_group("map_markers")
	else:
		if _marker.is_in_group("map_markers"):
			_marker.remove_from_group("map_markers")


# ── Construction ─────────────────────────────────────────────────────────────
func _build_sign() -> void:
	_sign = Label3D.new()
	_sign.name = "PropertySign"
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.no_depth_test = false
	_sign.fixed_size = false
	_sign.pixel_size = 0.02
	_sign.font_size = 96
	_sign.outline_size = 24
	_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sign)
	var top: float = _footprint.position.y + _footprint.size.y + sign_lift
	_sign.position = Vector3(_footprint.get_center().x, top, _footprint.get_center().z)

func _build_interaction() -> void:
	_area = InteractionArea.new()
	_area.name = "BuyArea"
	_area.prompt_text = "Buy house"
	_area.collision_mask = 0xFFFFFFFF
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var size: Vector3 = _footprint.size
	box.size = Vector3(maxf(size.x, 2.0) + 2.0, maxf(size.y, 3.0), maxf(size.z, 2.0) + 2.0)
	shape.shape = box
	_area.add_child(shape)
	add_child(_area)
	_area.position = Vector3(_footprint.get_center().x,
		_footprint.position.y + box.size.y * 0.5, _footprint.get_center().z)
	_area.interacted.connect(_on_interacted)

func _build_marker() -> void:
	_marker = MapMarker.new()
	_marker.name = "HomeMarker"
	_marker.color = Color(1.0, 0.85, 0.3)
	_marker.label = "Home"
	_marker.legend = "Your House"
	add_child(_marker)
	# Starts out of the minimap group; _refresh() adds it back for the owner.
	_marker.remove_from_group("map_markers")


# Combined AABB of the house's meshes, in this node's local space.
func _compute_footprint() -> AABB:
	var box := AABB()
	var has: bool = false
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var xform: Transform3D = global_transform.affine_inverse() * mi.global_transform
				var a: AABB = xform * mi.mesh.get_aabb()
				if not has:
					box = a
					has = true
				else:
					box = box.merge(a)
		for c in n.get_children():
			stack.append(c)
	if not has:
		box = AABB(Vector3(-3, 0, -3), Vector3(6, 4, 6))
	return box
