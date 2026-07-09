extends Node
# Multiplayer — Steam lobby + peer network manager (autoload "Multiplayer").
#
# Owns the Steam lobby lifecycle (host / join / browse) and the
# SteamMultiplayerPeer used by Godot's high-level multiplayer. Once a session
# is established it loads the gameplay world, whose PlayerSpawner spawns the
# City-Critters player (Player/Scenes/player.tscn) for every peer.
#
# Requires the GodotSteam GDExtension (provides the `Steam` singleton and
# SteamMultiplayerPeer). Steam itself is initialized by the SteamManager
# autoload (Steam_Multiplayer/steam.gd).

signal lobbies_refreshed(lobbies: Array)
signal lobby_created_signal(lobby_id: int)
signal lobby_joined_signal(lobby_id: int)
signal player_count_changed(count: int)
signal session_failed(reason: String)

const WORLD_SCENE := "res://scenes/city/town.tscn"

var lobby_id: int = 0
var lobby_members: Array = []
var lobby_members_max: int = 8
var pending_lobby_name: String = ""
var steam_id: int = 0
var steam_username: String = ""
var is_host: bool = false
var use_gamepad: bool = false


func _ready() -> void:
	# Defer one frame so the SteamManager autoload has run steamInitEx().
	await get_tree().process_frame

	if not _steam_ready():
		return

	steam_id = Steam.getSteamID()
	steam_username = Steam.getPersonaName()
	print("Multiplayer: Steam ready - ID %s, Name %s" % [steam_id, steam_username])

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_match_list.connect(_on_lobby_match_list)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(_delta: float) -> void:
	# GodotSteam requires callbacks to be pumped every frame.
	if Engine.has_singleton("Steam"):
		Steam.run_callbacks()


func _steam_ready() -> bool:
	if not Engine.has_singleton("Steam"):
		push_warning("Multiplayer: GodotSteam not installed - networking disabled.")
		return false
	if not Steam.isSteamRunning():
		push_warning("Multiplayer: Steam is not running.")
		return false
	return true


# ── Hosting ────────────────────────────────────────────────────────────────
func host_game(lobby_name: String = "", max_players: int = 4) -> void:
	if not _steam_ready():
		session_failed.emit("Steam not available")
		return
	if lobby_id != 0:
		print("Multiplayer: already in lobby %s" % lobby_id)
		return
	is_host = true
	lobby_members_max = clampi(max_players, 2, 8)
	pending_lobby_name = lobby_name.strip_edges()
	if pending_lobby_name.is_empty():
		pending_lobby_name = _random_lobby_name()
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, lobby_members_max)


func _random_lobby_name() -> String:
	var adjectives := ["Cozy", "Sunny", "Rowdy", "Sleepy", "Hidden", "Busy", "Lucky", "Cheeky"]
	var nouns := ["Burrow", "Alley", "Rooftop", "Park", "Sewer", "Market", "Den", "Plaza"]
	var a: String = adjectives[randi() % adjectives.size()]
	var n: String = nouns[randi() % nouns.size()]
	return "%s %s #%d" % [a, n, randi() % 1000]


func _on_lobby_created(connect_result: int, this_lobby_id: int) -> void:
	if connect_result != 1:
		is_host = false
		session_failed.emit("Failed to create lobby (%s)" % connect_result)
		return

	lobby_id = this_lobby_id
	Steam.setLobbyJoinable(lobby_id, true)
	Steam.setLobbyData(lobby_id, "name", pending_lobby_name)
	Steam.setLobbyData(lobby_id, "mode", "city-critters")

	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_host(0)
	if err != OK:
		session_failed.emit("Failed to create host peer (%s)" % err)
		return
	multiplayer.multiplayer_peer = peer
	Steam.allowP2PPacketRelay(true)

	_refresh_members()
	lobby_created_signal.emit(lobby_id)
	print("Multiplayer: hosting lobby %s as peer %s" % [lobby_id, multiplayer.get_unique_id()])
	_start_session()


# ── Joining ────────────────────────────────────────────────────────────────
func join_lobby(this_lobby_id: int) -> void:
	if not _steam_ready():
		session_failed.emit("Steam not available")
		return
	is_host = false
	lobby_members.clear()
	Steam.joinLobby(this_lobby_id)


func _on_lobby_joined(this_lobby_id: int, _perm: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		session_failed.emit("Could not join lobby (%s)" % response)
		open_lobby_list()
		return

	lobby_id = this_lobby_id
	_refresh_members()

	if is_host:
		return  # host already created its peer in _on_lobby_created

	if lobby_members.is_empty():
		session_failed.emit("Lobby has no host")
		return

	var host_steam_id: int = lobby_members[0]["steam_id"]
	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_client(host_steam_id, 0)
	if err != OK:
		session_failed.emit("Failed to create client peer (%s)" % err)
		return
	multiplayer.multiplayer_peer = peer

	lobby_joined_signal.emit(lobby_id)
	print("Multiplayer: joined lobby %s as peer %s" % [lobby_id, multiplayer.get_unique_id()])
	_start_session()


# ── Lobby browsing ───────────────────────────────────────────────────────────
func open_lobby_list() -> void:
	if not _steam_ready():
		return
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()


func _on_lobby_match_list(these_lobbies: Array) -> void:
	lobbies_refreshed.emit(these_lobbies)


# ── Members / session ────────────────────────────────────────────────────────
func _refresh_members() -> void:
	lobby_members.clear()
	var count := Steam.getNumLobbyMembers(lobby_id)
	for i in range(count):
		var member_id: int = Steam.getLobbyMemberByIndex(lobby_id, i)
		lobby_members.append({
			"steam_id": member_id,
			"steam_name": Steam.getFriendPersonaName(member_id),
		})
	player_count_changed.emit(get_current_player_count())


func get_current_player_count() -> int:
	if lobby_id == 0:
		return 0
	return Steam.getNumLobbyMembers(lobby_id)


func _start_session() -> void:
	# Both host and clients load the same world; the world's PlayerSpawner
	# (driven by the host) replicates a player node for every peer.
	get_tree().change_scene_to_file(WORLD_SCENE)


func leave_lobby() -> void:
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	lobby_id = 0
	is_host = false
	lobby_members.clear()


# ── Signal relays ─────────────────────────────────────────────────────────────
func _on_lobby_chat_update(_lobby: int, _changed: int, _maker: int, _state: int) -> void:
	_refresh_members()


func _on_peer_connected(id: int) -> void:
	print("Multiplayer: peer connected %s" % id)


func _on_peer_disconnected(id: int) -> void:
	print("Multiplayer: peer disconnected %s" % id)
