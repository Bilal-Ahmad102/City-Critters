@tool
extends BTAction
class_name BTPickScheduleEntry

## Writes the activity the schedule wants right now into the "goal" blackboard var.
## FAILURE when the schedule is empty (nothing to do).

func _tick(_delta: float) -> Status:
	var npc: NPCBase = get_agent()
	if npc == null:
		return FAILURE
	var goal: ActivityResource = npc.scheduled_activity_now()
	if goal == null:
		return FAILURE
	blackboard.set_var(&"goal", goal)
	return SUCCESS
