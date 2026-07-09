extends Node
class_name NetAnimSync
# NetAnimSync — replicated animation + body-material state for a player. Lives as
# a child of the player. The owner mirrors the live AnimationTree into these vars
# each physics tick (player calls push_state); the sibling MultiplayerSynchronizer
# replicates them (its SceneReplicationConfig paths point here, e.g.
# NetAnimSync:net_transition); on proxies the setters feed the values back into
# the AnimationTree so remote critters animate without re-running the FSM.

@onready var _player: Node = get_parent()

var net_transition: String = "idle":
	set(value):
		net_transition = value
		if _is_proxy_ready():
			_player.animation_tree["parameters/Transition/transition_request"] = value
var net_walk_blend: Vector2 = Vector2.ZERO:
	set(value):
		net_walk_blend = value
		if _is_proxy_ready():
			_player.animation_tree["parameters/walk/blend_position"] = value
var net_run_blend: Vector2 = Vector2.ZERO:
	set(value):
		net_run_blend = value
		if _is_proxy_ready():
			_player.animation_tree["parameters/run/blend_position"] = value
var net_model_yaw: float = 0.0:
	set(value):
		net_model_yaw = value
		if _is_proxy_ready():
			_player.model.rotation.y = value
# The owner sets this from PlayerData; proxies apply whatever id arrives so every
# peer sees this critter's chosen look.
var net_material_id: String = PlayerData.DEFAULT_BODY_MATERIAL:
	set(value):
		net_material_id = value
		if _is_proxy_ready():
			_apply_body_material(value)

# True once we're a fully-ready proxy, i.e. replicated writes should be applied.
func _is_proxy_ready() -> bool:
	return _player != null and _player.is_node_ready() and not _player.is_authority

# Called by the player once authority is known (from its _ready). Applies the
# initial look/animation for both the owner and proxies.
func setup() -> void:
	if _player.is_authority:
		net_material_id = PlayerData.body_material_id
		_apply_body_material(PlayerData.body_material_id)
		return
	# Proxy: seed the AnimationTree + look from whatever state has arrived so far.
	_player.animation_tree["parameters/Transition/transition_request"] = net_transition
	_player.animation_tree["parameters/walk/blend_position"] = net_walk_blend
	_player.animation_tree["parameters/run/blend_position"] = net_run_blend
	_player.model.rotation.y = net_model_yaw
	_apply_body_material(net_material_id)

# Owner-only: snapshot the live animation state for replication to proxies.
func push_state() -> void:
	net_transition = _player.animation_tree["parameters/Transition/current_state"]
	net_walk_blend = _player.animation_tree["parameters/walk/blend_position"]
	net_run_blend = _player.animation_tree["parameters/run/blend_position"]
	net_model_yaw = _player.model.rotation.y

# Applies the body material for the given catalog id to the mesh's first surface.
func _apply_body_material(id: String) -> void:
	var body_mesh := _find_body_mesh()
	if body_mesh:
		body_mesh.set_surface_override_material(0, PlayerData.get_body_material(id))

func _find_body_mesh() -> MeshInstance3D:
	var skeleton := _player.get_node_or_null("Mouse/Armature/Skeleton3D")
	if skeleton:
		for child in skeleton.get_children():
			if child is MeshInstance3D:
				return child
	return null
