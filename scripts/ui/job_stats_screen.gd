extends Control
class_name JobStatsScreen
# JobStatsScreen — lifetime job record overlay, toggled with the "job_stats"
# action (J / gamepad Back). Pure display: rebuilt from the JobStats autoload
# every time it opens, no game state touched. UI is built in code like the
# other job overlays so the .tscn stays trivial.

var _panel: PanelContainer
var _rows: VBoxContainer
var _totals: Label

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	# Containers resize to fit content; grow both ways so it stays centered.
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(460, 0)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "JOB RECORD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)

	box.add_child(HSeparator.new())

	_totals = Label.new()
	_totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_totals)

	var hint := Label.new()
	hint.text = "[J] close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.55)
	box.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("job_stats"):
		visible = not visible
		if visible:
			_rebuild()

func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var types := JobStats.job_types()
	if types.is_empty():
		var empty := Label.new()
		empty.text = "No shifts worked yet. Go clock in!"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate = Color(1, 1, 1, 0.7)
		_rows.add_child(empty)
	for job_type in types:
		_rows.add_child(_make_row(job_type))
	_totals.text = "Total: %d shifts   $%d earned   Wallet: $%d" % [
		JobStats.total_shifts(), JobStats.total_earned(), PlayerData.currency]

func _make_row(job_type: String) -> Control:
	var entry: Dictionary = JobStats.get_job(job_type)
	var row := VBoxContainer.new()

	var head := Label.new()
	head.text = "%s — %d shifts   $%d   best $%d   rating %d%%" % [
		job_type, int(entry.get("shifts", 0)), int(entry.get("earned", 0)),
		int(entry.get("best_shift", 0)),
		int(round(JobStats.performance(job_type) * 100.0))]
	row.add_child(head)

	var totals: Dictionary = entry.get("totals", {})
	if not totals.is_empty():
		var parts: Array[String] = []
		var keys := totals.keys()
		keys.sort()
		for key in keys:
			parts.append("%s %d" % [key, int(totals[key])])
		var detail := Label.new()
		detail.text = "   " + ", ".join(parts)
		detail.add_theme_font_size_override("font_size", 11)
		detail.modulate = Color(1, 1, 1, 0.6)
		row.add_child(detail)
	return row
