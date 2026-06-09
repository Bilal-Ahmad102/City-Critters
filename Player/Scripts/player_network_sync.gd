extends MultiplayerSynchronizer
# PlayerNetworkSync — syncs transform and animation state over the network.
# Attach to: scenes/player/player.tscn alongside MultiplayerSynchronizer node

# Synced properties are set in the inspector via the Replication tab.
# Sync: position, rotation, animation blend parameter.

func _ready() -> void:
	if not is_multiplayer_authority():
		set_physics_process(false)
