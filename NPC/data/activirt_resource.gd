class_name ActivityResource extends Resource

@export var id: StringName
@export var location_tag: StringName          # "bakery", "own_home", "town_square"
@export var object_type: StringName           # "counter", "bed", "stool", "" for none
# Three-phase activity animation. On arrival the NPC plays enter_animation once (sit
# down / lie down), then holds the looping `animation` for the activity's duration, then
# plays exit_animation once (stand up) before walking to its next activity. enter/exit
# empty = skip that phase (just hold `animation`, the original single-clip behaviour).
# All three are AnimationTree Transition input names (see npc.tscn), not clip names.
@export var enter_animation: StringName = &""
@export var animation: StringName = &"idle"    # the looping "performing" clip
@export var exit_animation: StringName = &""
@export var min_duration_minutes: int = 15
@export var interruptible: bool = true
@export var wander_radius: float = 0.0        # 0 means stand still at the slot


func create_task(npc: NPCBase) -> ActivityTask:
	return ActivityTask.new(self, npc)
