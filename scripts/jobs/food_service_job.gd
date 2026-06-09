extends "res://scripts/jobs/job_base.gd"
# FoodServiceJob — Papa's Pizzeria-style food service minigame logic.

signal order_received(order: Dictionary)
signal order_fulfilled(order_id: int)

var _pending_orders: Array = []
var _order_counter: int = 0

func _on_job_started() -> void:
	_spawn_order()

func _spawn_order() -> void:
	var order = {
		"id": _order_counter,
		"item": "burger",
		"time_limit": 20.0,
		"elapsed": 0.0
	}
	_pending_orders.append(order)
	_order_counter += 1
	order_received.emit(order)

func fulfill_order(order_id: int) -> void:
	for i in _pending_orders.size():
		if _pending_orders[i]["id"] == order_id:
			_pending_orders.remove_at(i)
			order_fulfilled.emit(order_id)
			CurrencySystem.earn(15)
			return
