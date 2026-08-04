extends Node3D

# Sandbox for the NPC schedule/movement system. Rosa runs the schedule on her node.
# 08:00 sleep -> own_home ("sleeping"); 10:10 wait -> Waiting_Area, where the ParkBench
# SmartObject sits her: she walks to an Approach (Slot) marker, then settles onto the
# reserved Seat marker on the bench and freezes there until the schedule moves her.

func _ready() -> void:
	GameClock.set_time(10.0 + 9.0 / 60.0)   # 10:09 — watch her walk to the bench and sit
