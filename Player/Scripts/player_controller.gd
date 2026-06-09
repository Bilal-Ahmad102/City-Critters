extends CharacterBody3D

@export var move_speed: float = 5.0
@export var run_speed: float = 9.0
@export var jump_velocity: float = 5.5
@export var rotation_speed: float = 10.5

@onready var camera_pivot: Node3D = $third_person_controller
@onready var mouse: Node3D = $Mouse


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_movement(delta)
	
	move_and_slide()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity()

func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_right", "move_left", "move_backward" , "move_forward",)

	# Vector2(x,y)
	# Vector3(x,y,z)

	var cam_basis := camera_pivot.global_transform.basis
	var direction := (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	print(direction)
	direction.y = 0.0
	var speed :=  move_speed
#
	if direction.length() > 0.1:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		var target_angle := atan2(direction.x, direction.z)
		mouse.rotation.y = lerp_angle(mouse.rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
