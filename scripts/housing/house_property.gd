class_name HouseProperty extends Node3D
# HouseProperty — makes a house buyable and shows who owns it.
#
# Attach to a house scene root. The house's id is its node name (House_1, ...),
# so the same instance name in the world ties the world house to the persisted
# ownership record in PropertyManager.
#
# Flow the player sees:
#   1. Walk up to the FOR SALE sign already placed in the house scene; a "Buy
#      house [E]" prompt appears.
#   2. Press E → a panel pops up with the house details and a field to name it.
#   3. Confirm → the house is bought, the FOR SALE sign is hidden, and a
#      nameplate with the chosen name appears. The owner can reopen the panel to
#      rename it or toggle public/private access.
#
# Non-owners can't interact with an owned house.

@export var price: int = 500
# Height above the sign that the dynamic nameplate/price label floats at.
@export var label_height: float = 2.2
# Radius of the "press E" trigger around the sign.
@export var interact_radius: float = 2.5

var _house_id: String = ""
var _sign_prop: Node3D = null      # the FOR SALE prop in the scene (hidden once sold)
var _label: Label3D = null         # dynamic price / nameplate text above the sign
var _area: InteractionArea = null
var _marker: MapMarker = null
var _footprint: AABB

# Buy / manage panel (built on interact, freed on close).
var _ui: CanvasLayer = null
var _ui_player: Node3D = null
var _name_edit: LineEdit = null
var _status: Label = null


func _ready() -> void:
	_house_id = String(name)
	_footprint = _compute_footprint()
	_sign_prop = _find_sign_node()
	_build_label()
	_build_interaction()
	_build_marker()
	PropertyManager.ownership_changed.connect(_on_ownership_changed)
	_refresh()


func _on_ownership_changed(house_id: String) -> void:
	if house_id == _house_id:
		_refresh()
		if _ui != null:
			# Rebuild the open panel so it reflects the new state (e.g. after buy).
			_rebuild_ui()


# ── State ────────────────────────────────────────────────────────────────────
func _refresh() -> void:
	var owned: bool = PropertyManager.is_owned(_house_id)
	var mine: bool = PropertyManager.is_local_owner(_house_id)

	# The FOR SALE prop only makes sense while the house is unsold.
	if _sign_prop != null:
		_sign_prop.visible = not owned

	# Floating text: price while for sale, the house name once sold.
	if _label != null:
		if not owned:
			_label.text = "FOR SALE\n$%d" % price
			_label.modulate = Color(0.15, 0.7, 0.2)
		else:
			var access: String = "Public" if PropertyManager.is_public(_house_id) else "Private"
			_label.text = "%s\n%s · %s" % [
				PropertyManager.get_house_name(_house_id),
				PropertyManager.get_owner_name(_house_id), access]
			_label.modulate = Color(0.95, 0.8, 0.35) if mine else Color(0.85, 0.85, 0.9)

	# Only the buyer (unsold) and the owner may interact.
	_area.set_active(not owned or mine)
	_area.prompt_text = "Manage house" if mine else "Buy house"

	# The owner sees their home on the minimap; nobody else does.
	if mine:
		if not _marker.is_in_group("map_markers"):
			_marker.add_to_group("map_markers")
	else:
		if _marker.is_in_group("map_markers"):
			_marker.remove_from_group("map_markers")


func _on_interacted(by: Node3D) -> void:
	if _ui != null:
		return
	_ui_player = by
	if _ui_player != null and _ui_player.has_method("set_busy"):
		_ui_player.set_busy(true)
	_build_ui()


# ── Buy / manage UI ──────────────────────────────────────────────────────────
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	_rebuild_ui()
	set_process_unhandled_input(true)


func _rebuild_ui() -> void:
	if _ui == null:
		return
	for c in _ui.get_children():
		c.queue_free()

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	# Centred code-built PanelContainers hang bottom-right of the anchor without this.
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(360, 0)
	_ui.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var mine: bool = PropertyManager.is_local_owner(_house_id)
	var owned: bool = PropertyManager.is_owned(_house_id)

	if not owned:
		_build_buy_panel(box)
	elif mine:
		_build_manage_panel(box)
	else:
		_build_other_panel(box)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.modulate = Color(1, 1, 1, 0.85)
	box.add_child(_status)


func _build_buy_panel(box: VBoxContainer) -> void:
	box.add_child(_title("House for sale"))
	box.add_child(_detail("Address", _house_id))
	box.add_child(_detail("Price", "$%d" % price))
	box.add_child(_detail("Size", "%.0f x %.0f m" % [_footprint.size.x, _footprint.size.z]))
	box.add_child(_detail("Your balance", "$%d" % PlayerData.currency))
	box.add_child(HSeparator.new())

	var name_row := Label.new()
	name_row.text = "Name your house:"
	box.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Cozy Cottage"
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(0, 34)
	box.add_child(_name_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)

	var buy := Button.new()
	var afford: bool = PropertyManager.can_afford(price)
	buy.text = "Buy  ($%d)" % price if afford else "Can't afford"
	buy.disabled = not afford
	buy.custom_minimum_size = Vector2(0, 38)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.pressed.connect(_on_buy_pressed)
	buttons.add_child(buy)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 38)
	cancel.pressed.connect(_close_ui)
	buttons.add_child(cancel)


func _build_manage_panel(box: VBoxContainer) -> void:
	box.add_child(_title(PropertyManager.get_house_name(_house_id)))
	box.add_child(_detail("Address", _house_id))
	box.add_child(_detail("Owner", "You"))
	box.add_child(_detail("Access", "Public" if PropertyManager.is_public(_house_id) else "Private"))
	box.add_child(HSeparator.new())

	var name_row := Label.new()
	name_row.text = "Rename:"
	box.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.text = PropertyManager.get_house_name(_house_id)
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(0, 34)
	box.add_child(_name_edit)

	var rename_btn := Button.new()
	rename_btn.text = "Save name"
	rename_btn.custom_minimum_size = Vector2(0, 36)
	rename_btn.pressed.connect(_on_rename_pressed)
	box.add_child(rename_btn)

	var access_btn := Button.new()
	access_btn.text = "Make Private" if PropertyManager.is_public(_house_id) else "Make Public"
	access_btn.custom_minimum_size = Vector2(0, 36)
	access_btn.pressed.connect(_on_access_pressed)
	box.add_child(access_btn)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 36)
	close.pressed.connect(_close_ui)
	box.add_child(close)


func _build_other_panel(box: VBoxContainer) -> void:
	box.add_child(_title(PropertyManager.get_house_name(_house_id)))
	box.add_child(_detail("Owner", PropertyManager.get_owner_name(_house_id)))
	box.add_child(_detail("Access", "Public" if PropertyManager.is_public(_house_id) else "Private"))
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 36)
	close.pressed.connect(_close_ui)
	box.add_child(close)


func _on_buy_pressed() -> void:
	var chosen: String = _name_edit.text if _name_edit != null else ""
	PropertyManager.request_buy(_house_id, price, chosen)
	# ownership_changed rebuilds the panel into manage mode on success; if the buy
	# failed (e.g. sold to someone else first) reflect that.
	if not PropertyManager.is_owned(_house_id) and _status != null:
		_status.text = "Purchase failed."


func _on_rename_pressed() -> void:
	if _name_edit != null:
		PropertyManager.rename(_house_id, _name_edit.text)
	if _status != null:
		_status.text = "Saved."


func _on_access_pressed() -> void:
	PropertyManager.toggle_access(_house_id)


func _unhandled_input(event: InputEvent) -> void:
	if _ui != null and event.is_action_pressed("ui_cancel"):
		_close_ui()
		get_viewport().set_input_as_handled()


func _close_ui() -> void:
	if _ui != null:
		_ui.queue_free()
		_ui = null
	set_process_unhandled_input(false)
	if _ui_player != null and _ui_player.has_method("set_busy"):
		_ui_player.set_busy(false)
	_ui_player = null
	_name_edit = null
	_status = null


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	return l


func _detail(key: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var k := Label.new()
	k.text = key
	k.modulate = Color(1, 1, 1, 0.7)
	k.custom_minimum_size = Vector2(120, 0)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	row.add_child(v)
	return row


# ── Construction ─────────────────────────────────────────────────────────────
# Anchor a floating Label3D just above the FOR SALE sign (or, if the scene has no
# sign, above the front of the house).
func _build_label() -> void:
	var anchor: Vector3 = _sign_local_pos()
	_label = Label3D.new()
	_label.name = "HouseLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.01
	_label.font_size = 64
	_label.outline_size = 12
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = anchor + Vector3(0, label_height, 0)
	add_child(_label)


func _build_interaction() -> void:
	_area = InteractionArea.new()
	_area.name = "BuyArea"
	_area.prompt_text = "Buy house"
	_area.collision_mask = 0xFFFFFFFF
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interact_radius
	shape.shape = sphere
	_area.add_child(shape)
	# A prompt that shows when the player is in range.
	var prompt := Label3D.new()
	prompt.name = "Prompt"
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.pixel_size = 0.008
	prompt.font_size = 48
	prompt.outline_size = 10
	prompt.outline_modulate = Color(0, 0, 0, 0.8)
	prompt.position = Vector3(0, 1.4, 0)
	prompt.visible = false
	_area.add_child(prompt)
	add_child(_area)
	# Sit the trigger at the sign, near the ground so the player walks into it.
	var at: Vector3 = _sign_local_pos()
	_area.position = Vector3(at.x, _footprint.position.y + 1.0, at.z)
	_area.interacted.connect(_on_interacted)


func _build_marker() -> void:
	_marker = MapMarker.new()
	_marker.name = "HomeMarker"
	_marker.color = Color(1.0, 0.85, 0.3)
	_marker.label = "Home"
	_marker.legend = "Your House"
	add_child(_marker)
	_marker.remove_from_group("map_markers")


# Local-space position of the FOR SALE sign (or the front of the house as a
# fallback), used to anchor the label and the interaction trigger.
func _sign_local_pos() -> Vector3:
	if _sign_prop != null:
		return global_transform.affine_inverse() * _sign_prop.global_position
	var region: AABB = _main_mesh_aabb()
	return Vector3(region.get_center().x, region.position.y, region.position.z)


# The FOR SALE prop placed in the house scene: a descendant whose name mentions
# "ForSale" (preferred) or just "Sign".
func _find_sign_node() -> Node3D:
	var by_forsale: Node3D = _find_node_matching(["forsale", "for_sale"])
	if by_forsale != null:
		return by_forsale
	return _find_node_matching(["sign"])


func _find_node_matching(needles: Array) -> Node3D:
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var nm: String = String(n.name).to_lower()
		if n != self and n is Node3D:
			for needle in needles:
				if needle in nm:
					return n as Node3D
		for c in n.get_children():
			stack.append(c)
	return null


# AABB of the single largest mesh (the main building body), in local space.
func _main_mesh_aabb() -> AABB:
	var best := AABB()
	var best_vol: float = -1.0
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var xform: Transform3D = global_transform.affine_inverse() * mi.global_transform
				var a: AABB = xform * mi.mesh.get_aabb()
				var vol: float = a.size.x * a.size.y * a.size.z
				if vol > best_vol:
					best_vol = vol
					best = a
		for c in n.get_children():
			stack.append(c)
	if best_vol < 0.0:
		return _footprint
	return best


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
