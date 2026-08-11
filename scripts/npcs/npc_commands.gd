# npc_commands.gd
extends Node
class_name NPCCommands

# Player-facing command layer for an NPCBase. Sits as a child of the NPC next to an
# InteractionArea ("press E"). When the local player interacts, it opens a small
# code-built menu of commands; picking one calls npc.receive_command(activity) (the
# personality decides accept / delay / refuse) or npc.cancel_command() to hand control
# back to the schedule. The player is frozen (set_busy) while the menu is open.

# Activities the player may order this NPC to do. Assign in the scene; each needs a
# location the LocationRegistry can resolve, or the NPC accepts but has nowhere to go.
@export var commands: Array[ActivityResource] = []
# Optional button captions parallel to `commands`. Blank/short falls back to the
# activity id (e.g. "sleep" -> "Sleep").
@export var labels: PackedStringArray = []
# NodePath to the sibling InteractionArea. Defaults to a child named "InteractionArea".
@export var interaction_area: NodePath = ^"../InteractionArea"

var _npc: NPCBase = null
var _area: InteractionArea = null
var _player: Node3D = null

var _layer: CanvasLayer = null
var _status: Label = null

func _ready() -> void:
	_npc = get_parent() as NPCBase
	_area = get_node_or_null(interaction_area) as InteractionArea
	if _npc == null or _area == null:
		push_warning("NPCCommands needs an NPCBase parent and an InteractionArea sibling")
		return
	_area.interacted.connect(_on_interacted)

func _on_interacted(by: Node3D) -> void:
	if _layer != null:
		return                       # already open
	_player = by
	_npc.begin_interaction(by)        # stop + face the player for the interaction
	if _player.has_method("set_busy"):
		_player.set_busy(true)
	_build_menu()

func _build_menu() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	# Centred code-built PanelContainers hang bottom-right of the anchor without this.
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = "Ask %s to…" % String(_npc.npc_id).capitalize()
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	for i in commands.size():
		var cmd: ActivityResource = commands[i]
		if cmd == null:
			continue
		var btn: Button = Button.new()
		btn.text = _label_for(i)
		btn.pressed.connect(_on_command.bind(cmd))
		box.add_child(btn)

	var resume: Button = Button.new()
	resume.text = "Resume schedule"
	resume.pressed.connect(_on_resume)
	box.add_child(resume)

	var close: Button = Button.new()
	close.text = "Never mind"
	close.pressed.connect(_close)
	box.add_child(close)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(220, 0)
	box.add_child(_status)

func _label_for(i: int) -> String:
	if i < labels.size() and not labels[i].is_empty():
		return labels[i]
	return String(commands[i].id).capitalize()

func _on_command(cmd: ActivityResource) -> void:
	# Release the attend/face hold first so the command can move the NPC (a refused or
	# delayed command falls back to the resuming schedule), then close the menu.
	_npc.end_interaction()
	_npc.receive_command(cmd)
	_close()

func _on_resume() -> void:
	_npc.cancel_command()
	_close()

func _reaction_text(reaction: int) -> String:
	match reaction:
		NPCPersonality.Reaction.ACCEPT:
			return "On my way."
		NPCPersonality.Reaction.DELAY:
			return _line_or(_npc.personality, "delay_line", "In a moment.")
		NPCPersonality.Reaction.REFUSE:
			return _line_or(_npc.personality, "refusal_line", "No.")
	return ""

func _line_or(p: NPCPersonality, field: String, fallback: String) -> String:
	if p != null and not String(p.get(field)).is_empty():
		return String(p.get(field))
	return fallback

func _close() -> void:
	if _npc != null:
		_npc.end_interaction()       # drop the attend/face hold, resume the schedule
	if _layer != null:
		_layer.queue_free()
		_layer = null
		_status = null
	if _player != null and _player.has_method("set_busy"):
		_player.set_busy(false)
	_player = null

# Esc closes the menu too, matching the other overlay UIs.
func _unhandled_input(event: InputEvent) -> void:
	if _layer != null and event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
