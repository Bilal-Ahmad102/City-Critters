extends Node

var player_character_selections: Dictionary = {}  # {peer_id: character_num}
var selected_level : PackedScene 
var selected_player : int = 1
var selected_lobby 
var selected_player_num : int = 1 
var joined_lobby_id

# Character selection -> body tint. The City-Critters player uses a single
# rigged mesh (Mouse), so selection drives colour rather than a whole scene.
# Extend with per-species scenes here once more critter models are imported.
const PLAYER_SCENE := preload("res://Player/Scenes/player.tscn")

var character_colors: Dictionary = {
	1: Color("e8e8e8"),  # white
	2: Color("d96459"),  # red
	3: Color("6a8fd9"),  # blue
}

# player_id : [is_grounded, blend_amount]
var player_animations : Dictionary = {
}

func update_animations_data(id,is_grounded,blend_amount):
	player_animations[id] = [is_grounded,blend_amount]

func add_new_player_anim(player_id,is_grounded,blend_amount):
	player_animations[player_id] = [is_grounded,blend_amount]

func set_my_character_selection(character_num: int):
	var my_id = multiplayer.get_unique_id()
	selected_player_num = character_num  # Update your existing variable
	player_character_selections[my_id] = character_num
	
	print("I am player %s, I selected character %s" % [my_id, character_num])
	
	# Tell the server about my choice
	if multiplayer.get_unique_id() != 1:  # If not the host
		rpc_id(1, "register_character_selection", my_id, character_num)
	else:  # If host
		register_character_selection(my_id, character_num)

@rpc("any_peer")
func register_character_selection(peer_id: int, character_num: int):
	player_character_selections[peer_id] = character_num
	print("Server registered: Player %s selected character %s" % [peer_id, character_num])
