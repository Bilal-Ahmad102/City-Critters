# npc_personality.gd — read-only archetype shared across NPCs. One .tres per type
# (guard.tres, shopkeeper.tres). Decides how the NPC answers a player command.
class_name NPCPersonality extends Resource

enum Reaction { ACCEPT, DELAY, REFUSE }

## Flat refusal, whatever the situation.
@export var takes_orders: bool = true
## Activity ids this NPC will never do on command.
@export var refuses: Array[StringName] = []
## Chance of going along with a command that is otherwise acceptable.
@export_range(0.0, 1.0) var compliance: float = 0.7
## Will they drop a non-interruptible task if the player insists.
@export var stubborn: bool = true

@export_group("Lines")
@export var refusal_line: String = "I'll not be doing that."
@export var delay_line: String = "In a moment, I'm busy."


func evaluate(cmd: ActivityResource, current: ActivityTask) -> Reaction:
	if not takes_orders:
		return Reaction.REFUSE
	if cmd.id in refuses:
		return Reaction.REFUSE
	if stubborn and current != null and not current.resource.interruptible:
		return Reaction.DELAY
	if randf() > compliance:
		return Reaction.DELAY
	return Reaction.ACCEPT
