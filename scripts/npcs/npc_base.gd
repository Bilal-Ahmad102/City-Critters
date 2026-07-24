extends CharacterBody3D
class_name NPCBase
# NPCBase — a townsfolk critter. Stands at its post playing Idle and chats when
# the player presses E in range (InteractionArea child). Empty-handed = talk
# (small rapport bonus on the first chat each session); carrying food = gift it,
# and items in NPCData.gift_preferences pay extra rapport. Rapport lives in
# PlayerData.rapport and persists with the save.
# Schedules / navigation come later, once a game clock exists.

const DIALOGUE_UI_SCENE := preload("res://scenes/ui/menus/dialogue/dialogue_ui.tscn")

@export var npc_data: NPCData
# Optional recolor for the shared critter mesh (see PlayerData.BODY_MATERIALS).
@export var body_material: Material

@export var talk_rapport: int = 2         # first chat per session
@export var gift_rapport: int = 10        # any gift
@export var loved_gift_rapport: int = 25  # gift listed in gift_preferences

var _talked: bool = false

@onready var _interaction: InteractionArea = $InteractionArea
@onready var _name_tag: Label3D = $NameTag
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer

func _ready() -> void:
	add_to_group("npcs")
	_name_tag.text = display_name()
	var marker: Node = get_node_or_null("MapMarker")
	if marker != null:
		marker.label = display_name()
	if body_material != null:
		var mesh: MeshInstance3D = $Model/Armature/Skeleton3D/Ch14
		for i in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(i, body_material)
	if _anim.has_animation("Idle"):
		_anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		_anim.play("Idle")
	_interaction.interacted.connect(_on_interacted)

func display_name() -> String:
	if npc_data != null and npc_data.display_name != "":
		return npc_data.display_name
	return String(name)

func npc_id() -> String:
	if npc_data != null and npc_data.npc_id != "":
		return npc_data.npc_id
	return String(name).to_lower()

func _on_interacted(by: Node3D) -> void:
	_face(by)
	var lines: Array = []
	var carry: CarryComponent = null
	if by.has_method("get_carry"):
		carry = by.get_carry()
	if carry != null and carry.is_carrying():
		lines = _gift_lines(carry)
	else:
		lines = _talk_lines()
	var ui: DialogueUI = _get_dialogue_ui()
	# Dormant while chatting so the "Talk" prompt doesn't float over the box;
	# re-armed when the dialogue closes.
	_interaction.set_active(false)
	ui.closed.connect(func() -> void: _interaction.set_active(true), CONNECT_ONE_SHOT)
	ui.open_dialogue(display_name(), lines, by)

func _talk_lines() -> Array:
	var lines: Array = []
	if npc_data != null:
		lines = npc_data.dialogue_lines.duplicate()
	if lines.is_empty():
		lines = ["..."]
	if not _talked:
		_talked = true
		lines.append(_award_rapport(talk_rapport))
	return lines

func _gift_lines(carry: CarryComponent) -> Array:
	var item: String = carry.get_held_item()
	carry.drop_item(item)
	var loved: bool = npc_data != null and npc_data.gift_preferences.has(item)
	var lines: Array = []
	if loved:
		lines.append("%s?! My absolute favorite! You remembered!" % item.capitalize())
		lines.append(_award_rapport(loved_gift_rapport))
	else:
		lines.append("A %s, for me? That's so kind of you!" % item)
		lines.append(_award_rapport(gift_rapport))
	return lines

func _award_rapport(amount: int) -> String:
	PlayerData.increase_rapport(npc_id(), amount)
	var total: int = PlayerData.get_rapport(npc_id())
	return "[color=#ff9dbb]♥ +%d rapport (%d total)[/color]" % [amount, total]

# Turn to face whoever is talking to us (yaw only). The critter mesh fronts
# +Z (Mixamo), so aim look_at (which points -Z) the opposite way.
func _face(target: Node3D) -> void:
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.001:
		look_at(global_position - to, Vector3.UP)

func _get_dialogue_ui() -> DialogueUI:
	var existing: Node = get_tree().get_first_node_in_group("dialogue_ui")
	if existing is DialogueUI:
		return existing
	var ui: DialogueUI = DIALOGUE_UI_SCENE.instantiate()
	get_tree().root.add_child(ui)
	return ui
