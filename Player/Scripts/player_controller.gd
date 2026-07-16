extends CharacterBody3D

@export var move_speed: float = 5.0
@export var run_speed: float = 9.0
@export var jump_velocity: float = 5.5
# Impulse strength when walking into RigidBody3D props (crates, balls, bags).
@export var push_force: float = 6.0
# Max ledge height the player walks straight up (stairs, curbs). 0 disables.
@export var step_height: float = 0.4
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
# Yaw offset (radians) from the camera's forward while moving in the forward
# fan (any input with a forward component). The model rotates by this offset
# and plays the forward clip, so W+A / W+D walk the diagonals instead of
# strafing. Side/backward-only input keeps the strafe blend space.
var fan_offset: float = 0.0

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
	# move_and_slide strips the into-wall velocity component; remember what we
	# WANTED to do so the step-up probe knows the real travel direction.
	var desired_velocity := velocity
	move_and_slide()
	try_step_up(delta, desired_velocity)
	push_rigid_bodies(delta)
	net_sync.push_state()

# CharacterBody3D doesn't impart forces on rigid bodies by itself: shove
# anything we slid into. Horizontal only, so props get pushed, not launched.
func push_rigid_bodies(delta: float) -> void:
	for i in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if body is RigidBody3D:
			var push_dir: Vector3 = -col.get_normal()
			push_dir.y = 0.0
			if push_dir.length_squared() < 0.001:
				continue
			var speed: float = maxf(velocity.length(), 1.0)
			body.apply_central_impulse(push_dir.normalized() * push_force * speed * delta)

# CharacterBody3D has no stair stepping: walking into a low ledge just slides.
# When the wall we hit is blocking our travel, probe up -> forward -> down with
# collision-test motions; if that path clears and lands higher than we stand,
# it's a step — teleport onto it and keep walking.
func try_step_up(_delta: float, desired_velocity: Vector3) -> void:
	if step_height <= 0.0 or not is_on_wall():
		return
	if not is_on_floor() and velocity.y > 0.0:
		return  # rising jump: don't ledge-snap
	var forward := Vector3(desired_velocity.x, 0.0, desired_velocity.z)
	if forward.length_squared() < 0.0001:
		return
	var dir := forward.normalized()
	# Only bother when the wall actually opposes our direction of travel.
	if get_wall_normal().dot(dir) > -0.3:
		return
	var from := global_transform
	var up := _test_motion_travel(from, Vector3.UP * step_height)
	if up.y < 0.01:
		return  # ceiling right above
	from.origin += up
	# Probe far enough to plant the whole capsule on the tread — a per-frame
	# motion step is millimetres and would leave us grinding the ledge edge.
	var ahead_len := 0.3
	var ahead := _test_motion_travel(from, dir * ahead_len)
	if ahead.length() < ahead_len * 0.5:
		return  # still blocked at raised height: a real wall, not a step
	from.origin += ahead
	var down := _test_motion_travel(from, Vector3.DOWN * (up.y + 0.05))
	if -down.y >= up.y - 0.005:
		return  # came all the way back down: nothing to stand on
	global_position = from.origin + down
	velocity.y = 0.0
	apply_floor_snap()

# How far this body travels along `motion` from `from` before hitting anything.
func _test_motion_travel(from: Transform3D, motion: Vector3) -> Vector3:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	var result := PhysicsTestMotionResult3D.new()
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return result.get_travel()
	return motion

func handle_locomotion(locomotion:String,delta: float) -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	is_moving = input_dir.length() > 0.1
	is_running = false if !is_moving else is_running
	if Input.is_action_just_pressed("run") and is_moving:
		is_running = !is_running

	# Forward fan: any input with a forward component (keyboard diagonals and
	# analog stick angles alike) steers the model instead of strafing.
	var in_fan := is_moving and input_dir.y > 0.1
	fan_offset = -atan2(input_dir.x, input_dir.y) if in_fan else 0.0

	if Input.is_action_just_pressed("jump") and is_running and in_fan:
		is_running_jump = true

	if !locomotion: return

	var anim_dir := input_dir
	if in_fan:
		# The model turns toward the input; the animation stays the forward clip.
		anim_dir = Vector2(0.0, input_dir.length())
	else:
		anim_dir = kill_diagonal_movement(anim_dir)
	# Smooth toward target, store the smoothed value so it actually trails
	var smoothed: Vector2 = prev_input_dir.lerp(anim_dir, ANIM_BLEND_SPEED * delta)
	prev_input_dir = smoothed
	animation_tree["parameters/"+locomotion+"/blend_position"] = smoothed
func animate_for_peers(b_val, anim_name):
	pass
func kill_diagonal_movement(dir: Vector2) -> Vector2:
	if abs(dir.x) > abs(dir.y):
		return Vector2(sign(dir.x), 0.0)
	elif dir.y != 0.0:
		return Vector2(0.0, sign(dir.y))
	return dir

func handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

func handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

func handle_rotation(delta: float) -> void:
	if !is_moving: return
	# Camera forward plus the fan offset: W faces the camera's way, W+A / W+D
	# (and analog diagonals) turn the model toward the actual travel direction.
	var target_angle := camera_pivot.rotation.y + fan_offset
	model.rotation.y = lerp_angle(model.rotation.y, target_angle, ROTATION_SPEED * delta)

func apply_root_motion() -> void:
	var root_motion: Vector3 = animation_tree.get_root_motion_position()
	var motion: Vector3 = model.global_transform.basis * root_motion
	velocity.x = motion.x / get_physics_process_delta_time()
	velocity.z = motion.z / get_physics_process_delta_time()
