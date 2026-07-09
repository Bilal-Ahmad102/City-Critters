extends "res://scripts/jobs/job_base.gd"
# FoodServiceJob — single-stage order-matching minigame (Papa's-style MVP).
# Orders arrive over the shift; the player fulfills each by picking the matching
# menu item before its timer runs out. Faster service pays a bigger tip.

signal order_received(order: Dictionary)
signal order_fulfilled(order_id: int, payout: int)
signal order_expired(order_id: int)

# Menu the player picks from. Ids double as the UI button set.
const MENU: Array[String] = ["burger", "fries", "soda", "hotdog"]

@export var order_pay: int = 15           # base pay for a served order
@export var max_tip: int = 10             # extra for near-instant service
@export var order_time_limit: float = 15.0
@export var spawn_interval: float = 4.0   # seconds between new orders
@export var max_concurrent: int = 3
# Number of serve tables. Each order is seated at one free table; the player
# must bring the right item to that table. Match the count of ServeTable nodes.
@export var num_tables: int = 3

var _pending: Array = []                  # active orders (Dictionaries)
var _order_counter: int = 0
var _spawn_timer: float = 0.0
var _served: int = 0
var _missed: int = 0

func _on_job_started() -> void:
	_pending.clear()
	_order_counter = 0
	_spawn_timer = 0.0
	_served = 0
	_missed = 0
	_spawn_order()  # start with one already on the counter

func _on_job_tick(delta: float) -> void:
	# Age existing orders, expiring any that run out (iterate back-to-front so
	# removals don't skip entries).
	for i in range(_pending.size() - 1, -1, -1):
		var order: Dictionary = _pending[i]
		order["elapsed"] += delta
		if order["elapsed"] >= order["time_limit"]:
			_pending.remove_at(i)
			_missed += 1
			order_expired.emit(order["id"])
	# Spawn new orders on cadence, up to the concurrent cap.
	_spawn_timer += delta
	if _spawn_timer >= spawn_interval and _pending.size() < max_concurrent:
		_spawn_timer = 0.0
		_spawn_order()

func _spawn_order() -> void:
	# Seat the order at a random free table; skip if every table is occupied.
	var free := _free_tables()
	if free.is_empty():
		return
	var order := {
		"id": _order_counter,
		"item": MENU[randi() % MENU.size()],
		"table": free[randi() % free.size()],
		"time_limit": order_time_limit,
		"elapsed": 0.0,
	}
	_pending.append(order)
	_order_counter += 1
	order_received.emit(order)

# Tables with no pending order right now.
func _free_tables() -> Array:
	var occupied := {}
	for o in _pending:
		occupied[o["table"]] = true
	var free := []
	for t in num_tables:
		if not occupied.has(t):
			free.append(t)
	return free

# Dine-in serve: hand `item` to the customer at `table`. Fulfils that table's
# order only if the item matches. Returns the payout, or -1 on a miss (wrong
# item, or no order seated there) so the caller can play a whiff cue.
func serve_table(table: int, item: String) -> int:
	for i in _pending.size():
		var order: Dictionary = _pending[i]
		if order["table"] != table:
			continue
		if order["item"] != item:
			return -1
		var payout := _payout_for(order)
		_pending.remove_at(i)
		_served += 1
		_award(payout)
		order_fulfilled.emit(order["id"], payout)
		return payout
	return -1

# Called by the UI when the player picks a menu item. Fulfills the oldest
# pending order matching that item; picks with no match are ignored (return
# false) so the UI can play a whiff cue.
func serve_item(item: String) -> bool:
	for i in _pending.size():
		if _pending[i]["item"] == item:
			var order: Dictionary = _pending[i]
			var payout := _payout_for(order)
			_pending.remove_at(i)
			_served += 1
			_award(payout)
			order_fulfilled.emit(order["id"], payout)
			return true
	return false

# Faster service (more time left) earns a larger tip on top of order_pay.
func _payout_for(order: Dictionary) -> int:
	var frac: float = 1.0 - clampf(order["elapsed"] / order["time_limit"], 0.0, 1.0)
	return order_pay + int(round(max_tip * frac))

func pending_orders() -> Array:
	return _pending

func _build_summary() -> Dictionary:
	return {
		"served": _served,
		"missed": _missed,
		"earned": _earned,
	}
