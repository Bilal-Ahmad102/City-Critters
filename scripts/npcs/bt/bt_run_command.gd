@tool
extends BTAction
class_name BTRunCommand

## Holds the NPC on the active player command until its min_duration elapses.
##   RUNNING  = command still going — keep it, which suppresses the schedule branch.
##   FAILURE  = command finished (ended here); let the schedule take over this tick.

func _tick(_delta: float) -> Status:
	var npc: NPCBase = get_agent()
	if npc == null:
		return FAILURE
	# A Selector resumes this RUNNING task directly without re-checking IsCommanded, so
	# we must notice an externally cancelled command (cancel_command / menu) ourselves.
	if not npc.is_command_active():
		return FAILURE
	if npc.command_expired():
		npc.end_command()
		return FAILURE
	return RUNNING
