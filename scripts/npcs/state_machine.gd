extends LimboHSM
# NPC locomotion state machine (LimboHSM), mirroring the player's setup. The
# agent is the NPCBase parent; states read its is_moving / is_running flags
# (driven by distance to the move_to target) and dispatch idle/walk/run.

@onready var idle: LimboState = $idle
@onready var walk: LimboState = $walk
@onready var run: LimboState = $run

func _ready() -> void:
	_init_state_machine()

func _init_state_machine() -> void:
	add_transition(ANYSTATE, idle, &"idle")
	add_transition(idle, walk, &"walk")
	add_transition(idle, run, &"run")
	add_transition(walk, run, &"run")
	add_transition(run, walk, &"walk")
	initial_state = idle
	initialize(get_parent())   # agent = the NPCBase
	set_active(true)

# --- transition inputs (states call the ones relevant to them) ---
func input_for_idle() -> void:
	if not agent.is_moving:
		dispatch(&"idle")

func input_for_walk() -> void:
	if agent.is_moving and not agent.is_running:
		dispatch(&"walk")

func input_for_run() -> void:
	if agent.is_running:
		dispatch(&"run")
