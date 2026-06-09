extends Resource
# SpeciesData — data resource for each playable species.
# Create via right-click > New Resource > SpeciesData in FileSystem.

class_name SpeciesData

@export var species_id: String = ""
@export var display_name: String = ""
@export var mesh_scene: PackedScene = null
@export var unlock_npc_id: String = ""   # which NPC grants this species
@export var unlock_rapport: int = 100
@export var is_starter: bool = false
