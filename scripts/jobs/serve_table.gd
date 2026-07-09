extends Node3D
class_name ServeTable
# ServeTable — one dine-in table the player brings food to. Shows the seated
# customer's order on a floating ticket and fires `serve_requested` when the
# player interacts. The FoodServiceStand owns the tables, drives their tickets
# from the job's orders, and does the actual serve on request.

signal serve_requested(table_id: int, by: Node3D)

@export var table_id: int = 0

@onready var _area: InteractionArea = $InteractionArea
@onready var _ticket: Label3D = $Ticket

var _item: String = ""

func _ready() -> void:
	_area.prompt_text = "Serve"
	_area.interacted.connect(_on_interacted)
	clear_order()

func _on_interacted(by: Node3D) -> void:
	serve_requested.emit(table_id, by)

# Arms / disarms serving (the stand disables it until the shift starts).
func set_active(value: bool) -> void:
	_area.set_active(value)

# Seats an order: shows the wanted item on the ticket.
func show_order(item: String) -> void:
	_item = item
	_ticket.text = item.capitalize()
	_ticket.visible = true

# Live countdown text while an order is seated.
func set_time_left(secs: float) -> void:
	if _ticket.visible:
		_ticket.text = "%s\n%ds" % [_item.capitalize(), int(ceil(secs))]

func clear_order() -> void:
	_item = ""
	_ticket.visible = false
	_ticket.text = ""
