extends Node
# PropertyManager — house ownership registry for the shared world.
#
# Host-authoritative: the server owns the truth, validates purchases (so two
# players can't buy the same house), broadcasts changes to every peer, serves
# the current ownership map to late joiners, and persists it to user:// so a
# property is still yours the next time you join that host's world.
#
# Identity is the Steam ID (0 when running solo without Steam). Currency is
# spent locally on the buyer's own wallet; only the ownership record is networked.
# Each record also carries the player-chosen house name (shown on the nameplate).

signal ownership_changed(house_id: String)

const SAVE_PATH := "user://houses.cfg"

# house_id -> { "steam_id": int, "name": String, "house_name": String, "public": bool }
#   name       = owner's player name
#   house_name = the name the buyer gave the house
var _owners: Dictionary = {}
# Optimistic purchases awaiting host confirmation: house_id -> price to refund.
var _pending: Dictionary = {}


func _ready() -> void:
	# Solo / host both start from the persisted file. A client wipes its copy
	# the moment it connects and takes the host's map as truth instead.
	_load()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)


# ── Queries ──────────────────────────────────────────────────────────────────
func is_owned(house_id: String) -> bool:
	return _owners.has(house_id)

func get_owner_id(house_id: String) -> int:
	return int(_owners[house_id]["steam_id"]) if is_owned(house_id) else 0

func get_owner_name(house_id: String) -> String:
	return str(_owners[house_id]["name"]) if is_owned(house_id) else ""

# The player-chosen house name (falls back to the house id when unset/unsold).
func get_house_name(house_id: String) -> String:
	if is_owned(house_id):
		var n: String = str(_owners[house_id].get("house_name", ""))
		if n != "":
			return n
	return house_id

func is_public(house_id: String) -> bool:
	return is_owned(house_id) and bool(_owners[house_id]["public"])

func is_local_owner(house_id: String) -> bool:
	return is_owned(house_id) and get_owner_id(house_id) == local_steam_id()

func local_steam_id() -> int:
	var mp: Node = get_node_or_null("/root/Multiplayer")
	return int(mp.steam_id) if mp != null and "steam_id" in mp else 0

func local_player_name() -> String:
	var mp: Node = get_node_or_null("/root/Multiplayer")
	if mp != null and "steam_username" in mp and str(mp.steam_username) != "":
		return str(mp.steam_username)
	return PlayerData.player_name

func can_afford(price: int) -> bool:
	return PlayerData.currency >= price


# ── Buying ───────────────────────────────────────────────────────────────────
# Called locally when a player confirms a purchase in the buy UI. `house_name`
# is the name the buyer typed (blank falls back to the house id).
func request_buy(house_id: String, price: int, house_name: String = "") -> void:
	if is_owned(house_id):
		_notify("Already owned")
		return
	if not CurrencySystem.spend(price):
		_notify("Not enough money")
		return
	var sid: int = local_steam_id()
	var pname: String = local_player_name()
	var hname: String = house_name.strip_edges()
	if hname == "":
		hname = house_id
	if _is_authority():
		_apply_owner(house_id, sid, pname, hname, false)
		_set_owner.rpc(house_id, sid, pname, hname, false)
		_save()
		_notify("You bought %s!" % hname)
	else:
		# Optimistic: spend now, ask the host to confirm. Refund on denial.
		_pending[house_id] = price
		_srv_buy.rpc_id(1, house_id, sid, pname, hname)


# Owner renames their house.
func rename(house_id: String, new_name: String) -> void:
	if not is_local_owner(house_id):
		return
	var hname: String = new_name.strip_edges()
	if hname == "":
		return
	var o: Dictionary = _owners[house_id]
	if _is_authority():
		_apply_owner(house_id, int(o["steam_id"]), str(o["name"]), hname, bool(o["public"]))
		_set_owner.rpc(house_id, int(o["steam_id"]), str(o["name"]), hname, bool(o["public"]))
		_save()
	else:
		_srv_rename.rpc_id(1, house_id, hname)
	_notify("House renamed to %s" % hname)


# Owner toggles public / private access.
func toggle_access(house_id: String) -> void:
	if not is_local_owner(house_id):
		return
	var new_public: bool = not is_public(house_id)
	var o: Dictionary = _owners[house_id]
	if _is_authority():
		_apply_owner(house_id, int(o["steam_id"]), str(o["name"]), str(o.get("house_name", "")), new_public)
		_set_owner.rpc(house_id, int(o["steam_id"]), str(o["name"]), str(o.get("house_name", "")), new_public)
		_save()
	else:
		_srv_set_access.rpc_id(1, house_id, new_public)
	_notify("House set to %s" % ("Public" if new_public else "Private"))


# ── Networking (host is peer 1) ──────────────────────────────────────────────
@rpc("any_peer", "reliable")
func _srv_buy(house_id: String, sid: int, pname: String, house_name: String) -> void:
	if not multiplayer.is_server():
		return
	var caller: int = multiplayer.get_remote_sender_id()
	if is_owned(house_id):
		_deny_buy.rpc_id(caller, house_id)
		return
	_apply_owner(house_id, sid, pname, house_name, false)
	_save()
	_set_owner.rpc(house_id, sid, pname, house_name, false)

@rpc("any_peer", "reliable")
func _srv_rename(house_id: String, new_name: String) -> void:
	if not multiplayer.is_server() or not is_owned(house_id):
		return
	var o: Dictionary = _owners[house_id]
	_apply_owner(house_id, int(o["steam_id"]), str(o["name"]), new_name, bool(o["public"]))
	_save()
	_set_owner.rpc(house_id, int(o["steam_id"]), str(o["name"]), new_name, bool(o["public"]))

@rpc("any_peer", "reliable")
func _srv_set_access(house_id: String, new_public: bool) -> void:
	if not multiplayer.is_server() or not is_owned(house_id):
		return
	var o: Dictionary = _owners[house_id]
	_apply_owner(house_id, int(o["steam_id"]), str(o["name"]), str(o.get("house_name", "")), new_public)
	_save()
	_set_owner.rpc(house_id, int(o["steam_id"]), str(o["name"]), str(o.get("house_name", "")), new_public)

# Server -> all peers: authoritative ownership record.
@rpc("authority", "reliable")
func _set_owner(house_id: String, sid: int, pname: String, house_name: String, public: bool) -> void:
	_pending.erase(house_id)
	_apply_owner(house_id, sid, pname, house_name, public)

# Server -> buyer: purchase rejected, refund the optimistic spend.
@rpc("authority", "reliable")
func _deny_buy(house_id: String) -> void:
	var price: int = int(_pending.get(house_id, 0))
	if price > 0:
		CurrencySystem.earn(price)
		_pending.erase(house_id)
	_notify("House already sold")


func _on_peer_connected(id: int) -> void:
	# Host brings a late joiner up to date with the full ownership map.
	if not multiplayer.is_server():
		return
	for hid: String in _owners:
		var o: Dictionary = _owners[hid]
		_set_owner.rpc_id(id, hid, int(o["steam_id"]), str(o["name"]),
			str(o.get("house_name", "")), bool(o["public"]))

func _on_connected_to_server() -> void:
	# A guest discards its local file; the host's map is the truth.
	_owners.clear()


# ── Internals ────────────────────────────────────────────────────────────────
func _is_authority() -> bool:
	# No peer = solo (we are our own authority); otherwise only the server.
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()

func _apply_owner(house_id: String, sid: int, pname: String, house_name: String, public: bool) -> void:
	_owners[house_id] = {"steam_id": sid, "name": pname, "house_name": house_name, "public": public}
	ownership_changed.emit(house_id)

func _notify(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_notification"):
		hud.show_notification(text)
	else:
		print("PropertyManager: ", text)

func _save() -> void:
	if not _is_authority() or DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	for hid: String in _owners:
		var o: Dictionary = _owners[hid]
		cfg.set_value(hid, "steam_id", int(o["steam_id"]))
		cfg.set_value(hid, "name", str(o["name"]))
		cfg.set_value(hid, "house_name", str(o.get("house_name", "")))
		cfg.set_value(hid, "public", bool(o["public"]))
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for hid: String in cfg.get_sections():
		_owners[hid] = {
			"steam_id": int(cfg.get_value(hid, "steam_id", 0)),
			"name": str(cfg.get_value(hid, "name", "")),
			"house_name": str(cfg.get_value(hid, "house_name", "")),
			"public": bool(cfg.get_value(hid, "public", false)),
		}
