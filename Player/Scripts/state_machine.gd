extends LimboHSM

'''================= States ======================='''

@onready var idle: LimboState = $idle
@onready var run: LimboState = $run
@onready var walk: LimboState = $walk
@onready var run_jump: LimboState = $run_jump

#@onready var land: LimboState = $land
#@onready var fall: LimboState = $fall
#@onready var idle_jump: LimboState = $idle_jump
'''================= States ======================='''

@onready var debug_label: Label = %debug_label


var previous_state : LimboState 
var movement_states : Array[LimboState]

var shield_hold_time := 0.0
const SHIELD_HOLD_THRESHOLD := 0.2 # seconds

var state_to_states_transition : Dictionary 


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	fill_state_to_states_dictionary()
	_init_state_machine_()
	movement_states = [idle,walk,run]


func _update(delta: float) -> void:
	debug_label.text = get_active_state().name
func fill_state_to_states_dictionary() -> void:
	state_to_states_transition = {
		idle:             [walk],
		walk:             [run,idle],
		run:              [walk,idle,run_jump],
		run_jump:         [run]
	}

func _init_state_machine_():
	initial_state = idle
	previous_state = idle
	_init_transitions()
	initialize(get_parent())
	set_active(true)
	
func _init_transitions() -> void:
	add_transition(ANYSTATE, idle, &"idle")
	for from_state in state_to_states_transition:
		for to_state in state_to_states_transition[from_state]:
			add_transition(from_state, to_state, _get_event(to_state))

func _get_event(to_state: LimboState) -> StringName:
	if to_state == idle:             return &"idle"
	if to_state == walk:             return &"walk"
	if to_state == run:              return &"run"
	if to_state == run_jump:              return &"run_jump"
	push_error("No event found for state: " + to_state.name)
	return &""



#region Inputs 
func input_for_run():
	if agent.is_running:
		print("done")
		dispatch(&"run")

func input_for_idle():
	if !agent.is_moving:
		dispatch(&"idle")

func input_for_walk():
	if agent.is_moving and !agent.is_running:
		dispatch(&"walk")
		return true
	else: return false

func input_for_jump():
	if agent.is_running_jump:
		dispatch(&"run_jump")
#endregion Inputs 
