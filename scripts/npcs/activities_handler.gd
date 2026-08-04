extends Node

@onready var npc: NPCBase = $".."
@onready var state_machine: LimboHSM = %state_machine


func drink():
	var vending_machine = get_tree().get_first_node_in_group("Vending_Machine")
	drink_from_vending_machine(vending_machine)

func drink_from_vending_machine(VM_position:Vector3):
	npc.look_at(VM_position)
