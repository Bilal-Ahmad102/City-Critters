extends Node
# PlayerSpawnManager — spawns the City-Critters player for every peer.
#
# Drives a sibling MultiplayerSpawner: the server spawns a player node per peer
# (named after the peer id, with that peer set as multiplayer authority) and the
# spawner replicates it to all clients. Works with either networking backend —
# the Steam SteamMultiplayerPeer or plain ENet — since it only uses Godot's
# high-level `multiplayer` API. Falls back to a single local player when run
# with no active peer, so the world is still playable solo for testing.

@export var player_scene: PackedScene
@export var spawn_root: NodePath = NodePath("../Players")

@onready var spawner: MultiplayerSpawner = $"../PlayerSpawner"
@onready var _root: Node3D = get_node(spawn_root)


func _ready() -> void:
	spawner.spawn_function = _spawn_player

	if multiplayer.multiplayer_peer == null:
		# Solo / offline: no replication, just drop one controllable player in.
		_root.add_child(player_scene.instantiate())
		return

	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		# Spawn the host and anyone who connected before the world loaded.
		spawner.spawn(multiplayer.get_unique_id())
		for peer_id in multiplayer.get_peers():
			spawner.spawn(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		spawner.spawn(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var node := _root.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


# Runs on every peer (server spawns, clients reconstruct the replicated spawn).
func _spawn_player(peer_id: int) -> Node:
	var player := player_scene.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	# Deterministic per-peer spawn offset so critters don't stack on the origin.
	var angle := float(peer_id % 8) * (TAU / 8.0)
	player.position = Vector3(cos(angle) * 2.0, 1.5, sin(angle) * 2.0)
	return player
