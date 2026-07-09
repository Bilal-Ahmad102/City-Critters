extends Node3D
class_name RetailStore
# RetailStore — the physical (3D, walk-around) Retail job. The player clocks in
# at the register, then works the shift: carry stock from the stockroom crates
# to whichever shelf requests it, and ring up customers who show up at the
# register. Mirror of FoodServiceStand around a RetailJob logic node.
#
# The register area is dual-purpose: off the clock it clocks the player in; on
# the clock it checks out the waiting customer.

@onready var _job := $Job
@onready var _register_area: InteractionArea = $Register/InteractionArea
@onready var _status: Label3D = $Register/Status
@onready var _customer_sign: Label3D = $Register/CustomerSign
@onready var _shelves_root: Node3D = $Shelves

# shelf_id -> StockShelf, and request id -> the StockShelf it points at.
var _shelves: Dictionary = {}
var _request_shelves: Dictionary = {}
# Stock crates + shelves, armed only while a shift is running.
var _gated: Array = []
# The player who clocked in (to drop their items when the shift ends).
var _worker: Node3D = null

func _ready() -> void:
	_register_area.prompt_text = "Press E to Clock In"
	_register_area.interacted.connect(_on_register)
	for shelf in _shelves_root.get_children():
		if shelf is StockShelf:
			_shelves[shelf.shelf_id] = shelf
			shelf.restock_requested.connect(_on_restock)
			_gated.append(shelf)
	for node in get_children():
		if node is FoodSource:  # stock crates reuse the generic pickup module
			_gated.append(node)
	_job.restock_requested.connect(_on_request_received)
	_job.shelf_restocked.connect(_on_request_done)
	_job.restock_expired.connect(_on_request_done)
	_job.customer_arrived.connect(_on_customer_changed)
	_job.customer_served.connect(func(_payout: int): _on_customer_changed())
	_job.customer_left.connect(_on_customer_changed)
	_job.job_started.connect(_on_job_started)
	_job.shift_ended.connect(_on_shift_ended)
	_status.text = "Retail\nPress E to Clock In"
	_customer_sign.visible = false
	# Off the clock: crates and shelves are dormant until you start a shift.
	_set_gated_active(false)

func _set_gated_active(value: bool) -> void:
	for node in _gated:
		node.set_active(value)

func _process(_delta: float) -> void:
	if not _job.is_active():
		return
	_status.text = "On shift  %02d s" % int(ceil(_job.time_left()))
	# Live countdown on each waiting shelf.
	for request in _job.pending_requests():
		var shelf: StockShelf = _request_shelves.get(request["id"], null)
		if shelf != null:
			shelf.set_time_left(maxf(0.0, request["time_limit"] - request["elapsed"]))

# ── Register (clock-in / checkout) ───────────────────────────────────────────

func _on_register(by: Node3D) -> void:
	if not _job.is_active():
		_worker = by
		_job.start_job()
		return
	_job.checkout()  # -1 when nobody is waiting is a harmless whiff

func _on_job_started() -> void:
	_set_gated_active(true)
	_on_customer_changed()

func _on_customer_changed() -> void:
	var waiting: bool = _job.customer_waiting()
	_customer_sign.visible = waiting
	_register_area.prompt_text = "Checkout" if waiting else "Register"

# ── Restocking ────────────────────────────────────────────────────────────────

# Fired by a StockShelf when the player interacts with it.
func _on_restock(shelf_id: int, by: Node3D) -> void:
	if not _job.is_active():
		return
	if not by.has_method("get_carry"):
		return
	var carry = by.get_carry()
	# Try each carried item against this shelf's request; consume the one that
	# matches (a shelf holds a single request, so at most one item can match).
	for item in carry.get_held_items():
		if _job.restock_shelf(shelf_id, item) >= 0:
			carry.drop_item(item)
			return

func _on_request_received(request: Dictionary) -> void:
	var shelf: StockShelf = _shelves.get(request["shelf"], null)
	if shelf == null:
		return
	_request_shelves[request["id"]] = shelf
	shelf.show_request(request["item"])

func _on_request_done(request_id: int, _payout: int = 0) -> void:
	var shelf: StockShelf = _request_shelves.get(request_id, null)
	if shelf != null:
		shelf.clear_request()
		_request_shelves.erase(request_id)

# ── Shift end ────────────────────────────────────────────────────────────────

func _on_shift_ended(summary: Dictionary) -> void:
	_set_gated_active(false)
	# Off the clock: whatever the worker was carrying is discarded.
	if _worker != null and _worker.has_method("get_carry"):
		_worker.get_carry().drop_all()
	_worker = null
	for shelf in _shelves.values():
		shelf.clear_request()
	_request_shelves.clear()
	_customer_sign.visible = false
	_register_area.prompt_text = "Press E to Clock In"
	_status.text = "Shift done!\nShelves %d  Customers %d\nEarned $%d\n(E to clock in again)" % [
		summary.get("restocked", 0), summary.get("customers", 0), summary.get("earned", 0)
	]
