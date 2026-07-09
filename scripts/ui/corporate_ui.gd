extends Control
# CorporateUI — screen overlay for the Corporate Office minigame. Shows the
# current expense-report row from the CorporateJob logic node ($Job) with
# Approve / Reject buttons and a per-row countdown, then a payout summary when
# the shift ends. Same shape as FoodServiceUI: the tree is built in code so the
# .tscn stays trivial, and `closed` tells the job station to tear us down.

signal closed()

@onready var _job := $Job

var _timer_label: Label
var _score_label: Label
var _task_label: Label
var _task_bar: ProgressBar
var _feedback: Label
var _buttons: HBoxContainer
var _summary: Panel
var _summary_stats: Label
# Running tallies for the score line (mirrors the job's summary).
var _audited: int = 0
var _earned: int = 0

func _ready() -> void:
	_build_layout()
	_job.task_presented.connect(_on_task_presented)
	_job.task_answered.connect(_on_task_answered)
	_job.task_missed.connect(_on_task_missed)
	_job.shift_ended.connect(_on_shift_ended)
	_summary.hide()
	_job.start_job()

func _process(_delta: float) -> void:
	if not _job.is_active():
		return
	_timer_label.text = "Shift  %02d s" % int(ceil(_job.time_left()))
	var task: Dictionary = _job.current_task()
	if not task.is_empty():
		var frac: float = 1.0 - clampf(task["elapsed"] / task["time_limit"], 0.0, 1.0)
		_task_bar.value = frac * 100.0

# ── Layout ────────────────────────────────────────────────────────────────────

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 28)
	col.add_child(_timer_label)

	_score_label = Label.new()
	_score_label.text = "Audited: 0    Earned: $0"
	col.add_child(_score_label)

	col.add_child(_heading("Expense Report — approve or reject each row"))

	# The spreadsheet row under audit, centred and big.
	var row_box := VBoxContainer.new()
	row_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row_box)

	_task_label = Label.new()
	_task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_task_label.add_theme_font_size_override("font_size", 36)
	row_box.add_child(_task_label)

	_task_bar = ProgressBar.new()
	_task_bar.min_value = 0.0
	_task_bar.max_value = 100.0
	_task_bar.value = 100.0
	_task_bar.show_percentage = false
	_task_bar.custom_minimum_size = Vector2(340, 14)
	_task_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row_box.add_child(_task_bar)

	_feedback = Label.new()
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_font_size_override("font_size", 20)
	row_box.add_child(_feedback)

	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 16)
	col.add_child(_buttons)
	_add_button("Approve", true)
	_add_button("Reject", false)

	_build_summary()

func _add_button(text: String, approve: bool) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 52)
	btn.pressed.connect(func(): _job.answer(approve))
	_buttons.add_child(btn)

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l

func _build_summary() -> void:
	_summary = Panel.new()
	_summary.set_anchors_preset(Control.PRESET_CENTER)
	_summary.custom_minimum_size = Vector2(320, 200)
	# Keep it centred on its own size.
	_summary.pivot_offset = Vector2(160, 100)
	add_child(_summary)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for side in ["left", "top", "right", "bottom"]:
		box.add_theme_constant_override("margin_" + side, 16)
	_summary.add_child(box)

	var title := Label.new()
	title.text = "Shift Complete"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	_summary_stats = Label.new()
	_summary_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_summary_stats)

	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func(): closed.emit())
	box.add_child(leave)

# ── Task handling ─────────────────────────────────────────────────────────────

func _on_task_presented(task: Dictionary) -> void:
	_task_label.text = task["text"]
	_task_bar.value = 100.0

func _on_task_answered(_task_id: int, correct: bool, payout: int) -> void:
	if correct:
		_feedback.text = "Nice catch! +$%d" % payout
		_feedback.modulate = Color(0.5, 1.0, 0.5)
		_earned += payout
	else:
		_feedback.text = "Wrong call!"
		_feedback.modulate = Color(1.0, 0.55, 0.5)
	_audited += 1
	_refresh_score()

func _on_task_missed(_task_id: int) -> void:
	_feedback.text = "Row skipped — too slow!"
	_feedback.modulate = Color(1.0, 0.8, 0.4)
	_audited += 1
	_refresh_score()

func _refresh_score() -> void:
	_score_label.text = "Audited: %d    Earned: $%d" % [_audited, _earned]

func _on_shift_ended(summary: Dictionary) -> void:
	_summary_stats.text = "Correct: %d\nWrong: %d\nMissed: %d\nEarned: $%d" % [
		summary.get("correct", 0), summary.get("wrong", 0),
		summary.get("missed", 0), summary.get("earned", 0)
	]
	_summary.show()
