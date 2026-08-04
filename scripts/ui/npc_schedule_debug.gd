# npc_schedule_debug.gd — step-1 gate overlay. Shows the game clock and, per NPC
# in the "npc" group, its current scheduled activity + location tag. F3 toggles,
# H advances the GameClock one hour so you can watch the teleport happen.
extends Control

var _label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			visible = not visible
		elif event.keycode == KEY_H:
			GameClock.set_time(GameClock.hour + 1.0)


func _process(_delta: float) -> void:
	if not visible:
		return
	var lines: Array[String] = []
	lines.append("time %s  (min %d)   [H]=+1h  [F3]=hide" % [GameClock.time_string(), GameClock.total_minutes])
	for n in get_tree().get_nodes_in_group("npc"):
		var npc: NPCBase = n
		var act: String = "-"
		var tag: String = "-"
		if npc.current_activity != null:
			act = String(npc.current_activity.id)
			tag = String(npc.current_activity.location_tag)
		lines.append("  %s: %s @ %s   pos=(%.0f, %.0f)" % [
			String(npc.npc_id), act, tag, npc.global_position.x, npc.global_position.z])
	_label.text = "\n".join(lines)
