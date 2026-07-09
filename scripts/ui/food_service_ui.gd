extends Control
# FoodServiceUI — screen overlay for the Food Service minigame. Builds the order
# tickets and the menu buttons, drives them from the FoodServiceJob logic node
# ($Job), and shows a payout summary when the shift ends.
#
# The visual tree is built in code so the .tscn stays trivial (root Control +
# a Job node). Emits `closed` once the player dismisses the summary, letting the
# caller (the job station) tear the overlay down and hand control back.

signal closed()

@onready var _job := $Job

var _tickets: Dictionary = {}        # order id -> {"root": Control, "bar": ProgressBar}
var _timer_label: Label
var _orders_row: HBoxContainer
var _menu_row: HBoxContainer
var _summary: Panel
var _summary_stats: Label

func _ready() -> void:
	_build_layout()
	_job.order_received.connect(_on_order_received)
	_job.order_fulfilled.connect(_on_order_fulfilled)
	_job.order_expired.connect(_on_order_expired)
	_job.shift_ended.connect(_on_shift_ended)
	_summary.hide()
	_job.start_job()

func _process(_delta: float) -> void:
	if not _job.is_active():
		return
	_timer_label.text = "Shift  %02d s" % int(ceil(_job.time_left()))
	# Refresh each countdown bar from live order state.
	for order in _job.pending_orders():
		var t: Dictionary = _tickets.get(order["id"], {})
		if t.is_empty():
			continue
		var frac: float = 1.0 - clampf(order["elapsed"] / order["time_limit"], 0.0, 1.0)
		t["bar"].value = frac * 100.0

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

	col.add_child(_heading("Orders"))
	_orders_row = HBoxContainer.new()
	_orders_row.add_theme_constant_override("separation", 12)
	_orders_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_orders_row)

	col.add_child(_heading("Menu — click to serve"))
	_menu_row = HBoxContainer.new()
	_menu_row.add_theme_constant_override("separation", 8)
	col.add_child(_menu_row)
	for item in _job.MENU:
		var btn := Button.new()
		btn.text = String(item).capitalize()
		btn.custom_minimum_size = Vector2(110, 48)
		btn.pressed.connect(_on_menu_pressed.bind(item))
		_menu_row.add_child(btn)

	_build_summary()

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

# ── Ticket handling ───────────────────────────────────────────────────────────

func _on_order_received(order: Dictionary) -> void:
	var ticket := VBoxContainer.new()
	ticket.custom_minimum_size = Vector2(96, 0)

	var name_label := Label.new()
	name_label.text = String(order["item"]).capitalize()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ticket.add_child(name_label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	ticket.add_child(bar)

	_orders_row.add_child(ticket)
	_tickets[order["id"]] = {"root": ticket, "bar": bar}

func _on_order_fulfilled(order_id: int, _payout: int) -> void:
	_remove_ticket(order_id)

func _on_order_expired(order_id: int) -> void:
	_remove_ticket(order_id)

func _remove_ticket(order_id: int) -> void:
	var t: Dictionary = _tickets.get(order_id, {})
	if t.is_empty():
		return
	t["root"].queue_free()
	_tickets.erase(order_id)

func _on_menu_pressed(item) -> void:
	_job.serve_item(item)  # false (no match) is a harmless whiff for the MVP

func _on_shift_ended(summary: Dictionary) -> void:
	_summary_stats.text = "Served: %d\nMissed: %d\nEarned: $%d" % [
		summary.get("served", 0), summary.get("missed", 0), summary.get("earned", 0)
	]
	_summary.show()
