extends Node3D

@export var mouse_sensitivity: float = 0.002 # rad pro Pixel (fein einstellbar)
@export var arm_yaw_offset_deg: float = 180.0  

@onready var spring_arm_3d: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $SpringArm3D/Camera3D

var yaw: float = 0.0    # Rotation um Y am Pivot (links/rechts)
var pitch: float = 0.0  # Rotation um X am SpringArm (hoch/runter)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Startwinkel aus aktueller Szene übernehmen (falls im Editor gedreht):
	# (get_euler() liefert XYZ in Radiant; wir brauchen Y (yaw) am Pivot, X (pitch) am Arm)
	yaw = transform.basis.get_euler().y
	pitch = spring_arm_3d.transform.basis.get_euler().x

	# Einmal sauber anwenden, damit die Basen exakt von Quaternions kommen:
	_apply_yaw_pitch()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Update Winkel (wrap/clamp verhindert Ausreißer bei schnellen Deltas)
		yaw   = wrapf(yaw   - event.relative.x * mouse_sensitivity, -PI, PI)
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-60.0), deg_to_rad(30.0))
		_apply_yaw_pitch()

	# ESC: Maus ein-/ausfangen (praktisch im Debug)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

func _apply_yaw_pitch() -> void:
	#if $"../Dialogue_UI".is_showing_choices: return
	# WICHTIG: Basis *vollständig* aus Quaternions setzen und Translation beibehalten.

	# Pivot/Yaw (nur Y-Achse)
	var t_pivot := transform
	t_pivot.basis = Basis(Quaternion(Vector3.UP, yaw))
	transform = t_pivot  # behält origin (Position)

	# SpringArm: fester 180°-Yaw-Offset (hinter den Character) + Pitch (X)
	var t_arm := spring_arm_3d.transform
	var yaw_off := deg_to_rad(arm_yaw_offset_deg)

	# Basis vollständig aus Quaternions aufbauen (kein Euler-Gemische)
	var q := Quaternion(Vector3.UP, yaw_off) * Quaternion(Vector3.RIGHT, pitch)
	t_arm.basis = Basis(q)
	spring_arm_3d.transform = t_arm
