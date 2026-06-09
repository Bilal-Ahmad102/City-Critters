extends Node3D
# CameraController — spring arm third-person camera with mouse orbit.
# Attach to: scenes/camera/camera_rig.tscn

@export var sensitivity: float = 0.3
@export var min_pitch: float = -30.0
@export var max_pitch: float = 60.0
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 2.0
@export var max_zoom: float = 10.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var _yaw: float = 0.0
var _pitch: float = -20.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * sensitivity
		_pitch -= event.relative.y * sensitivity
		_pitch = clamp(_pitch, min_pitch, max_pitch)
		rotation_degrees.y = _yaw
		spring_arm.rotation_degrees.x = _pitch

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			spring_arm.spring_length = clamp(spring_arm.spring_length - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			spring_arm.spring_length = clamp(spring_arm.spring_length + zoom_speed, min_zoom, max_zoom)
