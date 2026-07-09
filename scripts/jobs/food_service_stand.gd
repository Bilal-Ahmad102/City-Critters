extends Node3D
class_name FoodServiceStand
# FoodServiceStand — the physical (3D, walk-around) version of the Food Service
# job. No full-screen overlay: the player clocks in at the register, then works
# the shift dine-in style — carry items from the FoodSource spots to whichever
# ServeTable seats a matching order.
#
# Reuses the same logic node (FoodServiceJob): each order is seated at a free
# table, and the player must bring the right item to THAT table. Each ServeTable
# shows its own order ticket + countdown.

@onready var _job := $Job
@onready var _clock_area: InteractionArea = $ClockIn/InteractionArea
@onready var _status: Label3D = $ClockIn/Status
@onready var _tables_root: Node3D = $Tables

# table_id -> ServeTable, and order id -> the ServeTable it's seated at.
var _tables: Dictionary = {}
var _order_tables: Dictionary = {}
# Food sources + tables, armed only while a shift is running.
var _gated: Array = []
# The player who clocked in (to drop their items when the shift ends).
var _worker: Node3D = null

func _ready() -> void:
	_clock_area.prompt_text = "Press E to Clock In"
	_clock_area.interacted.connect(_on_clock_in)
	for table in _tables_root.get_children():
		if table is ServeTable:
			_tables[table.table_id] = table
			table.serve_requested.connect(_on_serve)
			_gated.append(table)
	for node in get_children():
		if node is FoodSource:
			_gated.append(node)
	_job.order_received.connect(_on_order_received)
	_job.order_fulfilled.connect(_on_order_fulfilled)
	_job.order_expired.connect(_on_order_expired)
	_job.job_started.connect(_on_job_started)
	_job.shift_ended.connect(_on_shift_ended)
	_status.text = "Food Service\nPress E to Clock In"
	# Off the clock: pickups and tables are dormant until you start a shift.
	_set_gated_active(false)

func _set_gated_active(value: bool) -> void:
	for node in _gated:
		node.set_active(value)

func _process(_delta: float) -> void:
	if not _job.is_active():
		return
	_status.text = "On shift  %02d s" % int(ceil(_job.time_left()))
	# Live countdown on each seated table.
	for order in _job.pending_orders():
		var table: ServeTable = _order_tables.get(order["id"], null)
		if table != null:
			table.set_time_left(maxf(0.0, order["time_limit"] - order["elapsed"]))

# ── Clock-in / serve ─────────────────────────────────────────────────────────

func _on_clock_in(by: Node3D) -> void:
	if _job.is_active():
		return
	_worker = by
	_job.start_job()

func _on_job_started() -> void:
	_set_gated_active(true)

# Fired by a ServeTable when the player interacts with it.
func _on_serve(table_id: int, by: Node3D) -> void:
	if not _job.is_active():
		return
	if not by.has_method("get_carry"):
		return
	var carry = by.get_carry()
	# Try each carried item against this table's order; consume the one that
	# matches (a table seats a single order, so at most one item can match).
	for item in carry.get_held_items():
		if _job.serve_table(table_id, item) >= 0:
			carry.drop_item(item)
			return

# ── Order tickets (one per table) ─────────────────────────────────────────────

func _on_order_received(order: Dictionary) -> void:
	var table: ServeTable = _tables.get(order["table"], null)
	if table == null:
		return
	_order_tables[order["id"]] = table
	table.show_order(order["item"])

func _on_order_fulfilled(order_id: int, _payout: int) -> void:
	_clear_order(order_id)

func _on_order_expired(order_id: int) -> void:
	_clear_order(order_id)

func _clear_order(order_id: int) -> void:
	var table: ServeTable = _order_tables.get(order_id, null)
	if table != null:
		table.clear_order()
		_order_tables.erase(order_id)

# ── Shift end ────────────────────────────────────────────────────────────────

func _on_shift_ended(summary: Dictionary) -> void:
	_set_gated_active(false)
	# Off the clock: whatever the worker was carrying is discarded.
	if _worker != null and _worker.has_method("get_carry"):
		_worker.get_carry().drop_all()
	_worker = null
	for table in _tables.values():
		table.clear_order()
	_order_tables.clear()
	_status.text = "Shift done!\nServed %d  Missed %d\nEarned $%d\n(E to clock in again)" % [
		summary.get("served", 0), summary.get("missed", 0), summary.get("earned", 0)
	]
