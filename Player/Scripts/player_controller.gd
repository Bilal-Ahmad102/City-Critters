extends CharacterBody3D

@export var move_speed: float = 5.0
@export var run_speed: float = 9.0
@export var jump_velocity: float = 5.5
@export var ROTATION_SPEED: float = 10.0
@export var ANIM_BLEND_SPEED: float = 8.0

@onready var camera_pivot: Node3D = $third_person_controller
@onready var mouse: Node3D = $Mouse
@onready var animation_tree: AnimationTree = %AnimationTree
@onready var cam_controller: Node3D = $third_person_controller

var is_moving: bool = false
var is_running: bool = false
var is_running_jump: bool = false

var input_dir: Vector2 = Vector2.ZERO
var prev_input_dir: Vector2 = Vector2.ZERO

# ── Networking ───────────────────────────────────────────────────────────────
# True on the peer that owns (has authority over) this player. The owner reads
# input, runs the state machine + physics, and pushes anim state; everyone else
# is a proxy whose transform/animation come from the MultiplayerSynchronizer.
var is_authority: bool = true

# Replicated animation state. The owner mirrors the live AnimationTree values
# into these vars each physics tick; on proxies the setters feed them back into
# the AnimationTree so remote critters animate without re-running the FSM.
var net_transition: String = "idle":
	set(value):
		net_transition = value
		if not is_authority and is_node_ready():
			animation_tree["parameters/Transition/transition_request"] = value
var net_walk_blend: Vector2 = Vector2.ZERO:
	set(value):
		net_walk_blend = value
		if not is_authority and is_node_ready():
			animation_tree["parameters/walk/blend_position"] = value
var net_run_blend: Vector2 = Vector2.ZERO:
	set(value):
		net_run_blend = value
		if not is_authority and is_node_ready():
			animation_tree["parameters/run/blend_position"] = value
var net_mouse_yaw: float = 0.0:
	set(value):
		net_mouse_yaw = value
		if not is_authority and is_node_ready():
			mouse.rotation.y = value
# Replicated body-material choice. The owner sets it from PlayerData; proxies
# apply whatever id arrives so every peer sees this critter's chosen look.
var net_material_id: String = PlayerData.DEFAULT_BODY_MATERIAL:
	set(value):
		net_material_id = value
		if not is_authority and is_node_ready():
			_apply_body_material(value)

func _ready() -> void:
	is_authority = is_multiplayer_authority()
	if is_authority:
		# Apply this peer's chosen look and replicate the id to everyone else.
		net_material_id = PlayerData.body_material_id
		_apply_body_material(PlayerData.body_material_id)
		return
	# Proxy player: movement + animation are driven by replicated state only.
	set_physics_process(false)
	animation_tree["parameters/Transition/transition_request"] = net_transition
	animation_tree["parameters/walk/blend_position"] = net_walk_blend
	animation_tree["parameters/run/blend_position"] = net_run_blend
	mouse.rotation.y = net_mouse_yaw
	_apply_body_material(net_material_id)

# Applies the body material for the given catalog id to the mesh's first surface.
func _apply_body_material(id: String) -> void:
	var body_mesh := _find_body_mesh()
	if body_mesh:
		body_mesh.set_surface_override_material(0, PlayerData.get_body_material(id))

func _find_body_mesh() -> MeshInstance3D:
	var skeleton := get_node_or_null("Mouse/Armature/Skeleton3D")
	if skeleton:
		for child in skeleton.get_children():
			if child is MeshInstance3D:
				return child
	return null

func _physics_process(delta: float) -> void:
	handle_gravity(delta)
	handle_rotation(delta)
	apply_root_motion()
	move_and_slide()
	_push_net_state()

func _push_net_state() -> void:
	# Owner-only: snapshot the live animation state for replication to proxies.
	net_transition = animation_tree["parameters/Transition/current_state"]
	net_walk_blend = animation_tree["parameters/walk/blend_position"]
	net_run_blend = animation_tree["parameters/run/blend_position"]
	net_mouse_yaw = mouse.rotation.y

func handle_locomotion(locomotion:String,delta: float) -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	is_moving = input_dir.length() > 0.1
	is_running = false if !is_moving else is_running
	if Input.is_action_just_pressed("run") and is_moving:
		is_running = !is_running
	
	if Input.is_action_just_pressed("jump") and is_running and input_dir.distance_to(Vector2(0,1)) <= .3:
		is_running_jump = true

	if !locomotion: return

	kill_diagonal_movement()
	# Smooth toward target, store the smoothed value so it actually trails
	var smoothed: Vector2 = prev_input_dir.lerp(input_dir, ANIM_BLEND_SPEED * delta)
	prev_input_dir = smoothed
	animation_tree["parameters/"+locomotion+"/blend_position"] = smoothed
func animate_for_peers(b_val, anim_name):
	pass
func kill_diagonal_movement() -> void:
	if abs(input_dir.x) > abs(input_dir.y):
		input_dir = Vector2(sign(input_dir.x), 0.0)
	elif input_dir.y != 0.0:
		input_dir = Vector2(0.0, sign(input_dir.y))

func handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

func handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

func handle_rotation(delta: float) -> void:
	if !is_moving: return
	# Always face the camera's forward, mouse direction
	var target_angle := camera_pivot.rotation.y
	mouse.rotation.y = lerp_angle(mouse.rotation.y, target_angle, ROTATION_SPEED * delta)

func apply_root_motion() -> void:
	var root_motion: Vector3 = animation_tree.get_root_motion_position()
	var motion: Vector3 = mouse.global_transform.basis * root_motion
	velocity.x = motion.x / get_physics_process_delta_time()
	velocity.z = motion.z / get_physics_process_delta_time()
