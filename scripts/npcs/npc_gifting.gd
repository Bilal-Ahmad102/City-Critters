extends Node
# NPCGifting — handles item gifting and rapport gain.
# Attach as child of any NPC scene.

@export var npc_id: String = ""
@export var rapport_per_gift: int = 10

func receive_gift(item_id: String) -> void:
	# TODO: check if NPC has a preference for this item_id from NPCData
	PlayerData.increase_rapport(npc_id, rapport_per_gift)
	print("%s received gift: %s. Rapport now: %d" % [npc_id, item_id, PlayerData.get_rapport(npc_id)])
