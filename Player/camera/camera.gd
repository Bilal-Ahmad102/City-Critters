extends Node3D

@export var mouse_sensitivity: float = 0.002    # rad pro Pixel
@export var gamepad_sensitivity: float = 2.5     # rad pro Sekunde bei vollem Ausschlag
@export var gamepad_deadzone: float = 0.15
@export var gamepad_invert_y: bool = false
@export var arm_yaw_offset_deg: float = 180.0

@onready var spring_arm_3d: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $SpringArm3D/Camera3D

var yaw: float = 0.0
var pitch: float = 0.0
var use_gamepad: bool = false
var active_device: int = 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	yaw = transform.basis.get_euler().y
	pitch = spring_arm_3d.transform.basis.get_euler().x
	_apply_yaw_pitch()

	_refresh_pad()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_pad()

func _refresh_pad() -> void:
	var pads := Input.get_connected_joypads()
	use_gamepad = pads.size() > 0
	if use_gamepad:
		active_device = pads[0]
		# Optional: Maus sichtbar machen, wenn am Pad gespielt wird
		# Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	# Maus nur, wenn KEIN Pad aktiv ist
	if not use_gamepad and event is InputEventMouseMotion:
		yaw   = wrapf(yaw   - event.relative.x * mouse_sensitivity, -PI, PI)
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-60.0), deg_to_rad(30.0))
		_apply_yaw_pitch()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

func _process(delta: float) -> void:
	if not use_gamepad:
		return

	# Rechter Stick: X = links/rechts, Y = hoch/runter
	var look := Vector2(
		Input.get_joy_axis(active_device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(active_device, JOY_AXIS_RIGHT_Y)
	)

	# Radiale Deadzone mit Rescale, damit es um die Mitte nicht zuckt
	var mag := look.length()
	if mag < gamepad_deadzone:
		return
	look = look.normalized() * ((mag - gamepad_deadzone) / (1.0 - gamepad_deadzone))

	if gamepad_invert_y:
		look.y = -look.y

	yaw   = wrapf(yaw   - look.x * gamepad_sensitivity * delta, -PI, PI)
	pitch = clampf(pitch - look.y * gamepad_sensitivity * delta, deg_to_rad(-60.0), deg_to_rad(30.0))
	_apply_yaw_pitch()

func _apply_yaw_pitch() -> void:
	var t_pivot := transform
	t_pivot.basis = Basis(Quaternion(Vector3.UP, yaw))
	transform = t_pivot

	var t_arm := spring_arm_3d.transform
	var yaw_off := deg_to_rad(arm_yaw_offset_deg)
	var q := Quaternion(Vector3.UP, yaw_off) * Quaternion(Vector3.RIGHT, pitch)
	t_arm.basis = Basis(q)
	spring_arm_3d.transform = t_arm
