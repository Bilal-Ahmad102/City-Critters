extends CanvasLayer
class_name DialogueUI
# DialogueUI — bottom-center dialogue box with a typewriter reveal. The UI tree
# is built in code (dialogue_ui.tscn stays trivial, same pattern as the job
# overlay UIs). One box serves the whole world; NPCBase lazily spawns one under
# the scene root when none exists yet.
#
# While open the player is set busy and the interact action is consumed here:
# first press reveals the rest of the line, next press advances, and past the
# last line the box closes and control returns to the player.

signal closed

const CHARS_PER_SECOND := 45.0

var _lines: Array = []
var _index: int = 0
var _player: Node = null
var _reveal: float = 0.0

var _panel: PanelContainer
var _name_label: Label
var _text_label: RichTextLabel

func _ready() -> void:
	layer = 25
	add_to_group("dialogue_ui")
	_build_ui()
	_panel.hide()
	set_process(false)
	set_process_input(false)

func is_open() -> bool:
	return _panel.visible

func open_dialogue(npc_name: String, lines: Array, player: Node = null) -> void:
	if lines.is_empty() or is_open():
		return
	_lines = lines
	_index = 0
	_player = player
	if _player != null and _player.has_method("set_busy"):
		_player.set_busy(true)
	_name_label.text = npc_name
	_panel.show()
	set_process(true)
	set_process_input(true)
	_show_line()

# One interact press: reveal the rest of the line if it is still typing,
# otherwise move to the next line (closing past the last). Public so tests and
# other systems can drive the box without synthesizing input events.
func advance() -> void:
	if not is_open():
		return
	var total := _text_label.get_total_character_count()
	if _text_label.visible_characters >= 0 and _text_label.visible_characters < total:
		_text_label.visible_characters = -1
		return
	_index += 1
	if _index >= _lines.size():
		close()
	else:
		_show_line()

func close() -> void:
	if not is_open():
		return
	_panel.hide()
	set_process(false)
	set_process_input(false)
	if _player != null and _player.has_method("set_busy"):
		_player.set_busy(false)
	_player = null
	closed.emit()

func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# -1 means "show everything" (player skipped the typewriter).
	if _text_label.visible_characters < 0:
		return
	_reveal += delta * CHARS_PER_SECOND
	var total := _text_label.get_total_character_count()
	if int(_reveal) > _text_label.visible_characters:
		_text_label.visible_characters = mini(int(_reveal), total)

func _show_line() -> void:
	_text_label.text = str(_lines[_index])
	_text_label.visible_characters = 0
	_reveal = 0.0

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -48.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(_name_label)

	_text_label = RichTextLabel.new()
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.custom_minimum_size = Vector2(560.0, 54.0)
	_text_label.add_theme_font_size_override("normal_font_size", 17)
	vbox.add_child(_text_label)

	var hint := Label.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.text = "E — continue"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1.0, 1.0, 1.0, 0.55)
	vbox.add_child(hint)
