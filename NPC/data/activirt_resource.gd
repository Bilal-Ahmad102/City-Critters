class_name ActivityResource extends Resource

@export var id: StringName
@export var location_tag: StringName          # "bakery", "own_home", "town_square"
@export var object_type: StringName           # "counter", "bed", "stool", "" for none
@export var animation: StringName = &"idle"
@export var min_duration_minutes: int = 15
@export var interruptible: bool = true
@export var wander_radius: float = 0.0        # 0 means stand still at the slot


func create_task(npc: NPCBase) -> ActivityTask:
	return ActivityTask.new(self, npc)
