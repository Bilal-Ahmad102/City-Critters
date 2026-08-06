@tool
extends BTAction
class_name BTBeginActivity

## Starts the "goal" activity when it differs from what the NPC is already doing.
## Idempotent: once goal == current_activity it just succeeds without restarting the
## walk. FAILURE if the goal's location isn't registered yet — the tree retries next
## tick (this is what lets the NPC wait for late-registering WorldLocations).

func _tick(_delta: float) -> Status:
	var npc: NPCBase = get_agent()
	if npc == null:
		return FAILURE
	var goal: ActivityResource = blackboard.get_var(&"goal", null)
	if goal == null:
		return FAILURE
	if goal == npc.current_activity:
		return SUCCESS
	return SUCCESS if npc.begin_activity(goal) else FAILURE
