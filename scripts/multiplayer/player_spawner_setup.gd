extends Node
# PlayerSpawnerSetup — registers player scenes with MultiplayerSpawner.
# Attach to the world scene root alongside a MultiplayerSpawner node.

@export var player_scene: PackedScene = null
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

func _ready() -> void:
	spawner.spawn_function = _spawn_player
	MultiplayerManager.player_connected.connect(_on_player_connected)
	MultiplayerManager.player_disconnected.connect(_on_player_disconnected)

func _on_player_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		spawner.spawn(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	var node := get_node_or_null(str(peer_id))
	if node:
		node.queue_free()

func _spawn_player(peer_id: int) -> Node:
	var player: CharacterBody3D = player_scene.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	return player
