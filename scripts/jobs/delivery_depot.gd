extends Node3D
class_name DeliveryDepot
# DeliveryDepot — the physical Delivery job. The player clocks in at the
# counter, takes a parcel from the pickup crate, and runs it to the
# DeliveryPoint it is addressed to, anywhere in the world. Points are found via
# the "delivery_points" group at clock-in, so worlds just scatter
# delivery_point.tscn instances and the depot wires itself up.

@onready var _job := $Job
@onready var _clock_area: InteractionArea = $ClockIn/InteractionArea
@onready var _status: Label3D = $ClockIn/Status
@onready var _pickup_area: InteractionArea = $Pickup/InteractionArea

# All discovered points, name -> DeliveryPoint. Armed only during a shift.
var _points: Dictionary = {}
# The player who clocked in (to drop their parcel when the shift ends).
var _worker: Node3D = null

func _ready() -> void:
	_clock_area.prompt_text = "Press E to Clock In"
	_clock_area.interacted.connect(_on_clock_in)
	_pickup_area.prompt_text = "Take Parcel"
	_pickup_area.interacted.connect(_on_take_parcel)
	_pickup_area.set_active(false)
	_job.parcel_ready.connect(func(_parcel: Dictionary): _refresh_status())
	_job.parcel_taken.connect(func(_parcel: Dictionary):
		_refresh_status()
		_refresh_objective())
	_job.parcel_delivered.connect(_on_delivered)
	_job.job_started.connect(_on_job_started)
	_job.shift_ended.connect(_on_shift_ended)
	_status.text = "Delivery Depot\nPress E to Clock In"

func _process(_delta: float) -> void:
	if _job.is_active():
		_refresh_status()

# ── Clock-in ─────────────────────────────────────────────────────────────────

func _on_clock_in(by: Node3D) -> void:
	if _job.is_active():
		return
	_discover_points()
	if _points.is_empty():
		_status.text = "Delivery Depot\nNo delivery points in this world!"
		return
	_worker = by
	_job.start_job()

# Finds every DeliveryPoint in the world and hands their straight-line
# distances to the job. Re-run each clock-in so late-loaded points count.
func _discover_points() -> void:
	var destinations := {}
	for node in get_tree().get_nodes_in_group("delivery_points"):
		if not (node is DeliveryPoint):
			continue
		destinations[node.point_name] = global_position.distance_to(node.global_position)
		if not _points.has(node.point_name):
			node.delivery_requested.connect(_on_delivery_requested)
		_points[node.point_name] = node
	_job.set_destinations(destinations)

func _on_job_started() -> void:
	_pickup_area.set_active(true)
	for point in _points.values():
		point.set_active(true)
	_refresh_status()
	_refresh_objective()

# ── Parcels ──────────────────────────────────────────────────────────────────

func _on_take_parcel(by: Node3D) -> void:
	if not _job.is_active() or not by.has_method("get_carry"):
		return
	var parcel: Dictionary = _job.take_parcel()
	if parcel.is_empty():
		return
	# Tint the carried box per destination so runs are visually distinct.
	by.get_carry().pick_up("parcel", _color_for(parcel["dest"]))

func _on_delivery_requested(point_name: String, by: Node3D) -> void:
	if not _job.is_active() or not by.has_method("get_carry"):
		return
	if _job.deliver(point_name) >= 0:
		by.get_carry().drop_item("parcel")

func _on_delivered(_parcel_id: int, _payout: int) -> void:
	_refresh_status()
	_refresh_objective()

# Minimap objective tracks the current leg: the addressed mailbox while a
# parcel is carried, the depot itself while empty-pawed (come get the next).
func _refresh_objective() -> void:
	var target: String = _job.carried_parcel().get("dest", "")
	for point_name in _points:
		var marker: MapMarker = _points[point_name].get_node_or_null("MapMarker")
		if marker != null:
			marker.set_objective(_job.is_active() and point_name == target)
	var own: MapMarker = get_node_or_null("MapMarker")
	if own != null:
		own.set_objective(_job.is_active() and target == "")

func _color_for(dest: String) -> Color:
	# Stable hue per destination name.
	return Color.from_hsv(float(dest.hash() % 360) / 360.0, 0.7, 0.9)

# ── Status board ─────────────────────────────────────────────────────────────

func _refresh_status() -> void:
	var carried: Dictionary = _job.carried_parcel()
	var line: String
	if not carried.is_empty():
		line = "Deliver to: %s" % carried["dest"]
	elif _job.waiting_count() > 0:
		line = "%d parcel(s) waiting" % _job.waiting_count()
	else:
		line = "Waiting for parcels..."
	_status.text = "On shift  %02d s\n%s" % [int(ceil(_job.time_left())), line]

# ── Shift end ────────────────────────────────────────────────────────────────

func _on_shift_ended(summary: Dictionary) -> void:
	_pickup_area.set_active(false)
	for point in _points.values():
		point.set_active(false)
	_refresh_objective()
	# Off the clock: an undelivered parcel goes back to the depot (discarded).
	if _worker != null and _worker.has_method("get_carry"):
		_worker.get_carry().drop_all()
	_worker = null
	_status.text = "Shift done!\nDelivered %d\nEarned $%d\n(E to clock in again)" % [
		summary.get("delivered", 0), summary.get("earned", 0)
	]
