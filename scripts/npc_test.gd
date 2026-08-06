extends Node3D

# Sandbox for the NPC schedule/movement system. Rosa runs the schedule on her node.
# 08:00 sleep -> own_home; 10:10 wait -> Waiting_Area bench (reserves a slot, sits).
# A LimboAI behaviour tree (child BTPlayer + NPC/data/bt/npc_brain.tres) is the decider:
# it polls the schedule and a player command each tick and calls begin_activity/end_command.
# Player commands: walk up to Rosa, press E for her command menu (Commands + InteractionArea).
# Simulation LOD: an NPC far from every player runs cheap (physics/animation skipped, moves
# by teleport); it drops back to full walking sim when a player comes within range.

func _ready() -> void:
	GameClock.set_time(10.0 + 9.0 / 60.0)
