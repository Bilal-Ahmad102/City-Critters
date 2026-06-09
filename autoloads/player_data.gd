extends Node
# PlayerData — stores local player state across scenes.

var player_name: String = "Player"
var species: String = "cat"
var body_color: Color = Color.WHITE
var currency: int = 0
var inventory: Array = []
var rapport: Dictionary = {}  # npc_id -> int

func add_currency(amount: int) -> void:
	currency += amount

func get_rapport(npc_id: String) -> int:
	return rapport.get(npc_id, 0)

func increase_rapport(npc_id: String, amount: int) -> void:
	rapport[npc_id] = get_rapport(npc_id) + amount
