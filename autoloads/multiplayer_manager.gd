extends Node
# MultiplayerManager — manages ENet peer hosting and joining.
# Add to Project > Autoloads as "MultiplayerManager"

const PORT = 7777
const MAX_PLAYERS = 16

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected()

func host_game() -> void:
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_PLAYERS)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func join_game(address: String) -> void:
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(address, PORT)
	multiplayer.multiplayer_peer = peer
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)

func _on_server_disconnected() -> void:
	server_disconnected.emit()
