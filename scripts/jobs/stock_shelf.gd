extends Node3D
class_name StockShelf
# StockShelf — one store shelf the player refills. Shows what stock it wants on
# a floating ticket and fires `restock_requested` when the player interacts.
# The RetailStore owns the shelves, drives their tickets from the job's
# requests, and does the actual restock on request. Mirror of ServeTable.

signal restock_requested(shelf_id: int, by: Node3D)

@export var shelf_id: int = 0

@onready var _area: InteractionArea = $InteractionArea
@onready var _ticket: Label3D = $Ticket

var _item: String = ""

func _ready() -> void:
	_area.prompt_text = "Restock"
	_area.interacted.connect(_on_interacted)
	clear_request()

func _on_interacted(by: Node3D) -> void:
	restock_requested.emit(shelf_id, by)

# Arms / disarms restocking (the store disables it until the shift starts).
func set_active(value: bool) -> void:
	_area.set_active(value)

# Marks the shelf empty: shows the wanted item on the ticket.
func show_request(item: String) -> void:
	_item = item
	_ticket.text = "Restock\n" + item.capitalize()
	_ticket.visible = true

# Live countdown text while the shelf waits for stock.
func set_time_left(secs: float) -> void:
	if _ticket.visible:
		_ticket.text = "Restock %s\n%ds" % [_item.capitalize(), int(ceil(secs))]

func clear_request() -> void:
	_item = ""
	_ticket.visible = false
	_ticket.text = ""
