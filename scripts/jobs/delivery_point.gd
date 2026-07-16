extends Node3D
class_name DeliveryPoint
# DeliveryPoint — a mailbox somewhere in the city that parcels get addressed
# to. Place freely around the world; it joins the "delivery_points" group so
# any DeliveryDepot can discover it at shift start. The always-visible sign
# doubles as the wayfinding aid, since parcels name their destination.

signal delivery_requested(point_name: String, by: Node3D)

# Address shown on parcels and on the sign. Must be unique per world.
@export var point_name: String = "Mailbox"

@onready var _area: InteractionArea = $InteractionArea
@onready var _sign: Label3D = $Sign

func _ready() -> void:
	add_to_group("delivery_points")
	_sign.text = point_name
	_area.prompt_text = "Deliver"
	_area.interacted.connect(_on_interacted)
	# Dormant until a depot arms it for a shift.
	_area.set_active(false)
	# The minimap dot inherits this point's address as its label.
	var marker: MapMarker = get_node_or_null("MapMarker")
	if marker != null:
		marker.label = point_name
		if marker.icon == null:
			marker.icon = preload("res://addons/at-icons/node/mailbox.svg")
		if marker.legend == "":
			marker.legend = "Delivery point (mailbox)"

func _on_interacted(by: Node3D) -> void:
	delivery_requested.emit(point_name, by)

# Arms / disarms delivering (the depot enables it only during a shift).
func set_active(value: bool) -> void:
	_area.set_active(value)
