extends CanvasLayer
# DialogueUI — displays NPC dialogue with typewriter effect.
# Attach to scenes/ui/menus/dialogue/dialogue_ui.tscn

@onready var name_label: Label = $Panel/NameLabel
@onready var text_label: RichTextLabel = $Panel/TextLabel
@onready var next_button: Button = $Panel/NextButton

var _lines: Array = []
var _index: int = 0

func open_dialogue(npc_name: String, lines: Array) -> void:
	_lines = lines
	_index = 0
	name_label.text = npc_name
	show()
	_show_line()

func _show_line() -> void:
	if _index >= _lines.size():
		hide()
		return
	text_label.text = ""
	var line: String = _lines[_index]
	for ch in line:
		text_label.text += ch
		await get_tree().create_timer(0.03).timeout

func _on_next_pressed() -> void:
	_index += 1
	_show_line()

func _ready() -> void:
	next_button.pressed.connect(_on_next_pressed)
	hide()
