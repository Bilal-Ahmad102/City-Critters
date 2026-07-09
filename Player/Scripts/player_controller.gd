extends CharacterBody3D

@export var move_speed: float = 5.0
@export var run_speed: float = 9.0
@export var jump_velocity: float = 5.5
@export var ROTATION_SPEED: float = 10.0
@export var ANIM_BLEND_SPEED: float = 8.0

@onready var camera_pivot: Node3D = $third_person_controller
@onready var model: Node3D = $soldier_girl
@onready var animation_tree: AnimationTree = %AnimationTree
@onready var cam_controller: Node3D = $third_person_controller
# Split-out behaviour: carrying is in CarryComponent, replicated animation +
# material state is in NetAnimSync. This script keeps movement / input.
@onready var carry: CarryComponent = $CarryComponent
@onready var net_sync: NetAnimSync = $NetAnimSync

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

func _ready() -> void:
	# Group used by NPCs and InteractionArea triggers to recognise a player body.
	add_to_group("player")
	is_authority = is_multiplayer_authority()
	# Let the network component apply the initial look / proxy animation state.
	net_sync.setup()
	if not is_authority:
		# Proxy player: movement + animation are driven by replicated state only.
		set_physics_process(false)

# Carry lives in a child component; jobs reach it through this accessor so they
# don't depend on the child node's name.
func get_carry() -> CarryComponent:
	return carry

# Freezes movement + camera and frees the cursor so the player can use a UI
# overlay (job shift, dialogue, shop). Call set_busy(false) to hand control back.
# Only meaningful on the local authority avatar.
func set_busy(busy: bool) -> void:
	set_physics_process(not busy)
	if cam_controller:
		cam_controller.set_process(not busy)
		cam_controller.set_process_input(not busy)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if busy else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	handle_gravity(delta)
	handle_rotation(delta)
	apply_root_motion()
	move_and_slide()
	net_sync.push_state()

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
	# Always face the camera's forward, model direction
	var target_angle := camera_pivot.rotation.y
	model.rotation.y = lerp_angle(model.rotation.y, target_angle, ROTATION_SPEED * delta)

func apply_root_motion() -> void:
	var root_motion: Vector3 = animation_tree.get_root_motion_position()
	var motion: Vector3 = model.global_transform.basis * root_motion
	velocity.x = motion.x / get_physics_process_delta_time()
	velocity.z = motion.z / get_physics_process_delta_time()
