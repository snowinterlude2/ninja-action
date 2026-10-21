extends Node3D
## Third-person orbit camera. The rig follows the ninja (top level, so it doesn't spin with him); the mouse turns
## the rig (yaw) and its Pitch child; a SpringArm3D pulls the camera in so it never goes through walls.
## Click to capture the mouse, Esc to free it.

@export var mouse_sensitivity := 0.0025
@export var follow_height := 1.55
## Higher is snappier. The camera lags a little behind fast moves so they read as fast.
@export var follow_sharpness := 14.0
@export var min_pitch := -70.0
@export var max_pitch := 45.0
@export var base_fov := 70.0
@export var sprint_fov := 78.0

@onready var _target: Node3D = get_parent()
@onready var _pitch: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var _camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	if _target is CollisionObject3D:
		_arm.add_excluded_object((_target as CollisionObject3D).get_rid())
	global_position = _target.global_position + Vector3.UP * follow_height
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		_pitch.rotation.x = clamp(_pitch.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var goal := _target.get_global_transform_interpolated().origin + Vector3.UP * follow_height
	global_position = global_position.lerp(goal, 1.0 - exp(-follow_sharpness * delta))
	var sprinting := Input.is_action_pressed("sprint") and _target is CharacterBody3D and Vector2((_target as CharacterBody3D).velocity.x, (_target as CharacterBody3D).velocity.z).length() > 5.0
	_camera.fov = lerp(_camera.fov, sprint_fov if sprinting else base_fov, 1.0 - exp(-4.0 * delta))
