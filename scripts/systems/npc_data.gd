extends Resource
# NPCData — data resource for each NPC.
class_name NPCData

@export var npc_id: String = ""
@export var display_name: String = ""
@export var species: String = ""
@export var schedule: Array = []         # Array of {hour: int, location: Vector3, action: String}
@export var dialogue_lines: Array = []
@export var gift_preferences: Array = [] # item_ids this NPC likes
@export var unlock_item: String = ""     # exclusive item unlocked at max rapport
