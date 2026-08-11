extends Control
## Main menu: enter Multiplayer, then host a new lobby or join an existing one.

## Drives the `Multiplayer` autoload (Steam_Multiplayer/network_manager.gd),
## which owns the Steam lobby lifecycle and loads the world scene itself once a
## session is established — so this menu only issues requests and reports status.

@onready var main_panel: VBoxContainer = %MainPanel
@onready var multiplayer_panel: VBoxContainer = %MultiplayerPanel
@onready var create_panel: VBoxContainer = %CreatePanel
@onready var customization_panel: VBoxContainer = %Customization_Panel
@onready var lobby_list: VBoxContainer = %LobbyList
@onready var material_list: VBoxContainer = %MaterialList
@onready var status_label: Label = %StatusLabel
@onready var name_edit: LineEdit = %NameEdit
@onready var max_players_spin: SpinBox = %MaxPlayersSpin
const WORLD_SCENE := "res://scenes/city/town.tscn"



func _ready() -> void:
	_show_main()
	%SinglePlayer.pressed.connect(_on_single_player_pressed)
	%MultiplayerButton.pressed.connect(_on_multiplayer_pressed)
	%Customization.pressed.connect(_show_customization)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%HostButton.pressed.connect(_on_host_pressed)
	%RefreshButton.pressed.connect(_on_refresh_pressed)
	%BackButton.pressed.connect(_show_main)
	%ConfirmCreateButton.pressed.connect(_on_confirm_create_pressed)
	%CreateBackButton.pressed.connect(_show_multiplayer)
	%back.pressed.connect(_show_main)

	_build_material_buttons()
	_apply_preview_material(PlayerData.body_material_id)

	Multiplayer.lobbies_refreshed.connect(_on_lobbies_refreshed)
	Multiplayer.session_failed.connect(_on_session_failed)


# ── Navigation ────────────────────────────────────────────────────────────────
func _hide_all_panels() -> void:
	main_panel.hide()
	multiplayer_panel.hide()
	create_panel.hide()
	customization_panel.hide()


func _show_main() -> void:
	_hide_all_panels()
	main_panel.show()


func _show_multiplayer() -> void:
	_hide_all_panels()
	multiplayer_panel.show()


func _show_customization() -> void:
	_hide_all_panels()
	customization_panel.show()


func _on_multiplayer_pressed() -> void:
	_show_multiplayer()
	_on_refresh_pressed()

func _on_single_player_pressed() -> void:
	# Solo: no lobby, just stream the world in through the loading screen.
	Multiplayer.loading_status = "Loading town..."
	get_tree().change_scene_to_file(Multiplayer.LOADING_SCENE)


# ── Customization ─────────────────────────────────────────────────────────────
func _build_material_buttons() -> void:
	for child in material_list.get_children():
		child.queue_free()
	for material_id in PlayerData.BODY_MATERIAL_ORDER:
		var button := Button.new()
		button.text = PlayerData.BODY_MATERIALS[material_id]["label"]
		button.custom_minimum_size = Vector2(260, 40)
		button.pressed.connect(_on_material_selected.bind(material_id))
		button.set_meta("material_id", material_id)
		material_list.add_child(button)
	_update_material_button_states()


func _on_material_selected(material_id: String) -> void:
	# Persist the choice for this session and show it live on the preview model.
	PlayerData.body_material_id = material_id
	_apply_preview_material(material_id)
	_update_material_button_states()


func _update_material_button_states() -> void:
	# Disable the active look's button so the current selection is obvious.
	for button in material_list.get_children():
		button.disabled = button.get_meta("material_id") == PlayerData.body_material_id


func _apply_preview_material(material_id: String) -> void:
	var preview_mesh := _find_preview_mesh()
	if preview_mesh:
		preview_mesh.set_surface_override_material(0, PlayerData.get_body_material(material_id))


func _find_preview_mesh() -> MeshInstance3D:
	var skeleton := get_node_or_null("Customization/Mouse/Armature/Skeleton3D")
	if skeleton:
		for child in skeleton.get_children():
			if child is MeshInstance3D:
				return child
	return null

func _on_quit_pressed() -> void:
	get_tree().quit()


# ── Hosting ───────────────────────────────────────────────────────────────────
func _on_host_pressed() -> void:
	# Show the create form so the player can name the lobby and pick a size.
	main_panel.hide()
	multiplayer_panel.hide()
	create_panel.show()
	name_edit.text = ""
	max_players_spin.value = 4


func _on_confirm_create_pressed() -> void:
	# A blank name falls back to a random one inside Multiplayer.host_game().
	_set_status("Creating lobby...")
	Multiplayer.host_game(name_edit.text, int(max_players_spin.value))


# ── Joining / browsing ────────────────────────────────────────────────────────
func _on_refresh_pressed() -> void:
	_set_status("Searching for lobbies...")
	_clear_lobby_list()
	Multiplayer.open_lobby_list()


func _on_lobbies_refreshed(lobbies: Array) -> void:
	_clear_lobby_list()
	if lobbies.is_empty():
		_set_status("No lobbies found. Host one to get started.")
		return

	_set_status("%d lobby(s) found." % lobbies.size())
	for this_lobby_id in lobbies:
		_add_lobby_entry(int(this_lobby_id))


func _add_lobby_entry(this_lobby_id: int) -> void:
	var lobby_name := ""
	var member_count := 0
	if Engine.has_singleton("Steam"):
		lobby_name = Steam.getLobbyData(this_lobby_id, "name")
		member_count = Steam.getNumLobbyMembers(this_lobby_id)
	if lobby_name.is_empty():
		lobby_name = "Lobby %s" % this_lobby_id

	var button := Button.new()
	button.text = "%s  (%d/%d)" % [lobby_name, member_count, Multiplayer.lobby_members_max]
	button.pressed.connect(_on_join_pressed.bind(this_lobby_id))
	lobby_list.add_child(button)


func _on_join_pressed(this_lobby_id: int) -> void:
	_set_status("Joining lobby %s..." % this_lobby_id)
	Multiplayer.join_lobby(this_lobby_id)


# ── Helpers ───────────────────────────────────────────────────────────────────
func _clear_lobby_list() -> void:
	for child in lobby_list.get_children():
		child.queue_free()


func _set_status(text: String) -> void:
	status_label.text = text


func _on_session_failed(reason: String) -> void:
	_set_status("Error: %s" % reason)
