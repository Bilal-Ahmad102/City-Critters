extends Node
# PlayerData — stores local player state across scenes. Currency (and the
# cosmetic picks worth keeping) persist to user://; saving is skipped when
# headless so smoke tests don't touch the real save.

const SAVE_PATH := "user://player.cfg"

# Body material catalog. Each entry maps a stable id (replicated over the
# network) to a label shown in the customization menu and the material resource
# applied to the player mesh. Add a new look by adding one entry here.
const BODY_MATERIALS := {
	"default": {
		"label": "Default",
		"path": "res://assets/Player/models/materials/default.tres",
	},
	"artic_blue": {
		"label": "Artic Blue",
		"path": "res://assets/Player/models/materials/artic_blue.tres",

	},
	"charcoal_grey": {
		"label": "Charcoal Grey",
		"path": "res://assets/Player/models/materials/Charcoal_Grey.tres",

	},
}
# Stable display order for the menu (dictionaries preserve insertion order, but
# this makes the intended ordering explicit).
const BODY_MATERIAL_ORDER: Array = ["default", "artic_blue","charcoal_grey"]
const DEFAULT_BODY_MATERIAL := "default"

var player_name: String = "Player"
var species: String = "cat"
var body_color: Color = Color.WHITE
# Currently selected body material id (key into BODY_MATERIALS).
var body_material_id: String = DEFAULT_BODY_MATERIAL
var currency: int = 0
var inventory: Array = []
var rapport: Dictionary = {}  # npc_id -> int

func _ready() -> void:
	load_saved()


# Returns the StandardMaterial3D for the given id (or the current selection when
# id is omitted), falling back to the default look for an unknown id.
func get_body_material(id: String = "") -> Material:
	var key := id if id != "" else body_material_id
	if not BODY_MATERIALS.has(key):
		key = DEFAULT_BODY_MATERIAL
	return load(BODY_MATERIALS[key]["path"])

func add_currency(amount: int) -> void:
	currency += amount

func save() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("player", "currency", currency)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "body_material_id", body_material_id)
	cfg.save(SAVE_PATH)

func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	currency = int(cfg.get_value("player", "currency", currency))
	player_name = str(cfg.get_value("player", "name", player_name))
	body_material_id = str(cfg.get_value("player", "body_material_id", body_material_id))

func get_rapport(npc_id: String) -> int:
	return rapport.get(npc_id, 0)

func increase_rapport(npc_id: String, amount: int) -> void:
	rapport[npc_id] = get_rapport(npc_id) + amount
