extends CharacterBody3D
# NPCBase — base class for all NPCs. Handles schedule, patrol, and interaction.
# Extend this for each unique NPC.

@export var npc_data: Resource  # NPCData resource
@export var schedule: Array = []  # Array of {time: int, location: Vector3, action: String}

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var dialogue_trigger: Area3D = $DialogueTrigger

var _current_destination: Vector3 = Vector3.ZERO

func _ready() -> void:
	dialogue_trigger.body_entered.connect(_on_player_enter_range)
	_tick_schedule()

func _physics_process(delta: float) -> void:
	_move_to_destination(delta)

func _move_to_destination(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		return
	var next := nav_agent.get_next_path_position()
	var dir := (next - global_position).normalized()
	velocity = dir * 2.5
	move_and_slide()
	look_at(global_position + dir * Vector3(1, 0, 1), Vector3.UP)

func _tick_schedule() -> void:
	# TODO: pick destination based on current game hour
	pass

func _on_player_enter_range(body: Node3D) -> void:
	if body.is_in_group("player"):
		# TODO: trigger dialogue via DialogueSystem
		pass
