@tool
extends BTCondition
class_name BTIsCommanded

## SUCCESS while a player command is overriding the NPC's schedule, else FAILURE.
## Guards the command branch of the NPC brain so the schedule branch only runs when
## no command is active.

func _tick(_delta: float) -> Status:
	var npc: NPCBase = get_agent()
	if npc != null and npc.is_command_active():
		return SUCCESS
	return FAILURE
