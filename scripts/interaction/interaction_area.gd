extends Area3D
class_name InteractionArea
# Reusable "walk up and press E" trigger. Drop one on any interactable — a job
# station, an NPC, a hobby spot. It detects the LOCAL player's avatar entering
# range, shows an optional prompt, and emits `interacted` when the player presses
# the interact action. Only the local authority player arms it, so remote proxies
# never fire it in multiplayer.
#
# Optional child named "Prompt" (a Label3D or any Node3D) is toggled with range;
# a Label3D also has its text set from `prompt_text`.

signal interacted(by: Node3D)
signal player_entered(by: Node3D)
signal player_exited(by: Node3D)

@export var prompt_text: String = "Interact"
@export var interact_action: StringName = &"interact"

# When false the trigger is dormant: no prompt, no interaction — even with the
# player standing in range. Callers toggle this (e.g. a job station disables its
# food/serve spots until the shift starts).
var active: bool = true
# The local player currently in range, or null when none.
var _player: Node3D = null
@onready var _prompt: Node3D = get_node_or_null("Prompt")

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_process_unhandled_input(false)
	_refresh()

# Arms / disarms the trigger. While disarmed the prompt hides and interacts are
# ignored; re-arming with the player still in range shows the prompt again.
func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	_refresh()

func _on_body_entered(body: Node3D) -> void:
	# Only the local player's own avatar arms the prompt; ignore anyone already
	# tracked and every non-local body (proxies, NPCs, props).
	if _player != null or not _is_local_player(body):
		return
	_player = body
	_refresh()
	player_entered.emit(body)

func _on_body_exited(body: Node3D) -> void:
	if body != _player:
		return
	_player = null
	_refresh()
	player_exited.emit(body)

func _unhandled_input(event: InputEvent) -> void:
	if not active or _player == null:
		return
	if event.is_action_pressed(interact_action):
		interacted.emit(_player)
		get_viewport().set_input_as_handled()

# Shows the prompt + listens for input only when armed and the player is here.
func _refresh() -> void:
	var show := active and _player != null
	_set_prompt_visible(show)
	set_process_unhandled_input(show)

func _is_local_player(body: Node) -> bool:
	return body.is_in_group("player") and body.is_multiplayer_authority()

func _set_prompt_visible(value: bool) -> void:
	if _prompt == null:
		return
	if _prompt is Label3D:
		_prompt.text = prompt_text
	_prompt.visible = value
