extends "res://scripts/jobs/job_base.gd"
# RetailJob — inventory-management minigame (GDD: buy stock, shelve, run the
# register). Two parallel streams over the shift:
#   1. Restocking — shelves run empty and request a specific item; the player
#      carries the matching stock crate item over before the request expires.
#   2. Register — customers arrive at the counter and wait to be checked out;
#      the player interacts with the register to serve them.
# Same order-matching skeleton as FoodServiceJob so stands stay interchangeable.

signal restock_requested(request: Dictionary)
signal shelf_restocked(request_id: int, payout: int)
signal restock_expired(request_id: int)
signal customer_arrived()
signal customer_served(payout: int)
signal customer_left()

# Stock the shop carries. Ids double as the crate/pickup item names.
const ITEMS: Array[String] = ["produce", "cans", "snacks", "toys"]

@export var restock_pay: int = 12          # base pay for a filled shelf
@export var max_tip: int = 8               # extra for a near-instant restock
@export var restock_time_limit: float = 20.0
@export var spawn_interval: float = 6.0    # seconds between shelves emptying
@export var max_concurrent: int = 3
# Number of shelves in the store. Match the count of StockShelf nodes.
@export var num_shelves: int = 4

@export var checkout_pay: int = 10         # pay per customer rung up
@export var customer_interval: float = 12.0  # seconds between customers
@export var checkout_wait: float = 12.0    # how long a customer waits

var _pending: Array = []                   # active restock requests (Dictionaries)
var _request_counter: int = 0
var _spawn_timer: float = 0.0
var _restocked: int = 0
var _missed_shelves: int = 0

# Register state: one customer at a time. < 0 means nobody is waiting and the
# value counts down to the next arrival; >= 0 is how long they've waited.
var _customer_waiting: bool = false
var _customer_timer: float = 0.0
var _customers_served: int = 0
var _customers_lost: int = 0

func _on_job_started() -> void:
	_pending.clear()
	_request_counter = 0
	_spawn_timer = 0.0
	_restocked = 0
	_missed_shelves = 0
	_customer_waiting = false
	_customer_timer = customer_interval * 0.5  # first customer arrives early
	_spawn_request()  # start with one empty shelf

func _on_job_tick(delta: float) -> void:
	# Age restock requests, expiring any that run out (iterate back-to-front so
	# removals don't skip entries).
	for i in range(_pending.size() - 1, -1, -1):
		var request: Dictionary = _pending[i]
		request["elapsed"] += delta
		if request["elapsed"] >= request["time_limit"]:
			_pending.remove_at(i)
			_missed_shelves += 1
			restock_expired.emit(request["id"])
	# New shelves empty on cadence, up to the concurrent cap.
	_spawn_timer += delta
	if _spawn_timer >= spawn_interval and _pending.size() < max_concurrent:
		_spawn_timer = 0.0
		_spawn_request()
	# Register: countdown either to the next arrival or to the customer leaving.
	_customer_timer -= delta
	if _customer_timer <= 0.0:
		if _customer_waiting:
			_customer_waiting = false
			_customers_lost += 1
			_customer_timer = customer_interval
			customer_left.emit()
		else:
			_customer_waiting = true
			_customer_timer = checkout_wait
			customer_arrived.emit()

func _spawn_request() -> void:
	# Empty a random stocked shelf; skip if every shelf already wants stock.
	var free := _free_shelves()
	if free.is_empty():
		return
	var request := {
		"id": _request_counter,
		"item": ITEMS[randi() % ITEMS.size()],
		"shelf": free[randi() % free.size()],
		"time_limit": restock_time_limit,
		"elapsed": 0.0,
	}
	_pending.append(request)
	_request_counter += 1
	restock_requested.emit(request)

# Shelves with no pending restock request right now.
func _free_shelves() -> Array:
	var occupied := {}
	for r in _pending:
		occupied[r["shelf"]] = true
	var free := []
	for s in num_shelves:
		if not occupied.has(s):
			free.append(s)
	return free

# Fill `shelf` with `item`. Pays only if that shelf wants exactly that item.
# Returns the payout, or -1 on a miss so the caller can play a whiff cue.
func restock_shelf(shelf: int, item: String) -> int:
	for i in _pending.size():
		var request: Dictionary = _pending[i]
		if request["shelf"] != shelf:
			continue
		if request["item"] != item:
			return -1
		var payout := _payout_for(request)
		_pending.remove_at(i)
		_restocked += 1
		_award(payout)
		shelf_restocked.emit(request["id"], payout)
		return payout
	return -1

# Ring up the waiting customer. Returns the payout, or -1 when nobody is there.
func checkout() -> int:
	if not _customer_waiting:
		return -1
	_customer_waiting = false
	_customer_timer = customer_interval
	_customers_served += 1
	_award(checkout_pay)
	customer_served.emit(checkout_pay)
	return checkout_pay

func customer_waiting() -> bool:
	return _customer_waiting

# Faster restocking (more time left) earns a larger tip on top of restock_pay.
func _payout_for(request: Dictionary) -> int:
	var frac: float = 1.0 - clampf(request["elapsed"] / request["time_limit"], 0.0, 1.0)
	return restock_pay + int(round(max_tip * frac))

func pending_requests() -> Array:
	return _pending

func _build_summary() -> Dictionary:
	return {
		"restocked": _restocked,
		"missed": _missed_shelves,
		"customers": _customers_served,
		"walkouts": _customers_lost,
		"earned": _earned,
	}
