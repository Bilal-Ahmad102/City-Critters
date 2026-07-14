extends "res://scripts/jobs/job_base.gd"
# DeliveryJob — fetch-and-traversal minigame (GDD: pick up parcels and route
# them across the city). Parcels queue up at the depot, each addressed to one
# of the DeliveryPoints registered at shift start. The player takes one parcel
# at a time, runs it to the matching point, and returns for the next. Pay
# scales with the leg distance, with a tip for beating the par time.

func _init() -> void:
	job_type = "Delivery"

signal parcel_ready(parcel: Dictionary)      # a new parcel waits at the depot
signal parcel_taken(parcel: Dictionary)
signal parcel_delivered(parcel_id: int, payout: int)

@export var delivery_pay: int = 20           # flat pay per delivered parcel
@export var pay_per_meter: float = 0.5       # distance bonus (depot -> point)
@export var speed_tip: int = 10              # extra for beating the par time
@export var par_speed: float = 4.0           # m/s used to derive the par time
@export var spawn_interval: float = 8.0      # seconds between new parcels
@export var max_waiting: int = 3             # parcel backlog cap at the depot

# destination name -> straight-line distance from the depot. Filled by the
# depot before the shift starts (it knows the world layout, the job doesn't).
var _destinations: Dictionary = {}

var _waiting: Array = []                     # parcels at the depot (Dictionaries)
var _carried: Dictionary = {}                # the parcel in the player's paws
var _parcel_counter: int = 0
var _spawn_timer: float = 0.0
var _delivered: int = 0

# The depot calls this ahead of start_job with {name: distance_in_meters}.
func set_destinations(destinations: Dictionary) -> void:
	_destinations = destinations

func _on_job_started() -> void:
	_waiting.clear()
	_carried = {}
	_parcel_counter = 0
	_spawn_timer = 0.0
	_delivered = 0
	_spawn_parcel()  # start with one on the depot counter

func _on_job_tick(delta: float) -> void:
	if not _carried.is_empty():
		_carried["elapsed"] += delta
	_spawn_timer += delta
	if _spawn_timer >= spawn_interval and _waiting.size() < max_waiting:
		_spawn_timer = 0.0
		_spawn_parcel()

func _spawn_parcel() -> void:
	if _destinations.is_empty():
		return
	var names := _destinations.keys()
	var dest: String = names[randi() % names.size()]
	var parcel := {
		"id": _parcel_counter,
		"dest": dest,
		"distance": _destinations[dest],
		"elapsed": 0.0,
	}
	_waiting.append(parcel)
	_parcel_counter += 1
	parcel_ready.emit(parcel)

# Hands the oldest waiting parcel to the player. Returns {} when there is
# nothing to take or a parcel is already being carried (one at a time).
func take_parcel() -> Dictionary:
	if _waiting.is_empty() or not _carried.is_empty():
		return {}
	_carried = _waiting.pop_front()
	_carried["elapsed"] = 0.0
	parcel_taken.emit(_carried)
	return _carried

# Drop the carried parcel off at `dest`. Pays only when it matches the parcel's
# address. Returns the payout, or -1 on a miss (wrong door, or empty-pawed).
func deliver(dest: String) -> int:
	if _carried.is_empty() or _carried["dest"] != dest:
		return -1
	var payout := delivery_pay + int(round(_carried["distance"] * pay_per_meter))
	# Par time assumes a straight run there at par_speed, plus a little grace.
	var par: float = _carried["distance"] / par_speed + 3.0
	if _carried["elapsed"] <= par:
		payout += speed_tip
	var id: int = _carried["id"]
	_carried = {}
	_delivered += 1
	_award(payout)
	parcel_delivered.emit(id, payout)
	return payout

func carried_parcel() -> Dictionary:
	return _carried

func waiting_count() -> int:
	return _waiting.size()

func _build_summary() -> Dictionary:
	return {
		"delivered": _delivered,
		"earned": _earned,
	}
