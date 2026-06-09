extends Node
# PlayerAppearance — applies species mesh and color customization.
# Attach to: scenes/player/player.tscn

@export var species_meshes: Dictionary = {}  # "cat" -> MeshInstance3D path

@onready var mesh_instance: MeshInstance3D = $"../MeshRoot/BodyMesh"

func apply_appearance(species: String, color: Color) -> void:
	_swap_mesh(species)
	_apply_color(color)

func _swap_mesh(species: String) -> void:
	# TODO: swap mesh based on species key once meshes are imported
	pass

func _apply_color(color: Color) -> void:
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, mat)
	mat.albedo_color = color
