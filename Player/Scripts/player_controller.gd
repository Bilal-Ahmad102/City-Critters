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

func _physics_process(delta: float) -> void:
	handle_gravity(delta)
	#handle_jump()
	handle_rotation(delta)
	apply_root_motion()
	move_and_slide()

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
