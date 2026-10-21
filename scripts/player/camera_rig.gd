extends Node3D
## Third-person orbit camera. The rig follows the ninja (top level, so it doesn't spin with him); the mouse turns
## the rig (yaw) and its Pitch child; a SpringArm3D pulls the camera in so it never goes through walls.
## Click to capture the mouse, Esc to free it. V switches between the wide camera and an over-the-shoulder one.

@export var mouse_sensitivity := 0.0025
@export var follow_height := 1.55
## Higher is snappier. The camera lags a little behind fast moves so they read as fast.
@export var follow_sharpness := 14.0
@export var min_pitch := -70.0
@export var max_pitch := 45.0
@export var base_fov := 70.0
@export var sprint_fov := 78.0
@export_group("Over the shoulder")
@export var shoulder_distance := 1.7
@export var shoulder_offset := 0.6
@export var shoulder_height := 1.65
@export var shoulder_fov := 65.0
@export_group("Depth of field")
## Things farther than this (meters) start to blur, fully blurred over the transition.
@export var dof_far := 14.0
@export var dof_far_transition := 14.0
@export var dof_amount := 0.12
## The ninja's mesh hides when the camera is pushed in closer than this, so it never clips through him.
@export var hide_closer_than := 0.75

var shoulder := false
var _wide_length := 3.4
var _side := 0.0

@onready var _target: Node3D = get_parent()
@onready var _pitch: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var _camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	# the rig follows the ninja's interpolated position itself every frame, so it opts out of physics interpolation
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if _target is CollisionObject3D:
		_arm.add_excluded_object((_target as CollisionObject3D).get_rid())
	global_position = _target.global_position + Vector3.UP * follow_height
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_wide_length = _arm.spring_length
	_arm.margin = 0.2
	_camera.near = 0.05
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = dof_far
	attrs.dof_blur_far_transition = dof_far_transition
	attrs.dof_blur_amount = dof_amount
	_camera.attributes = attrs


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		_pitch.rotation.x = clamp(_pitch.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V:
		shoulder = not shoulder
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var ease := 1.0 - exp(-8.0 * delta)
	var height := shoulder_height if shoulder else follow_height
	var goal := _target.get_global_transform_interpolated().origin + Vector3.UP * height
	global_position = global_position.lerp(goal, 1.0 - exp(-follow_sharpness * delta))
	_arm.spring_length = lerp(_arm.spring_length, shoulder_distance if shoulder else _wide_length, ease)
	# the shoulder offset moves the arm's start to the right, but only as far as there's room (a ray), so the
	# camera never starts inside a wall
	var want := shoulder_offset if shoulder else 0.0
	if want > 0.0:
		var right := global_basis.x
		var q := PhysicsRayQueryParameters3D.create(global_position, global_position + right * (want + 0.25), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			want = max(0.0, global_position.distance_to(hit.position) - 0.25)
	_side = lerp(_side, want, ease)
	_arm.position.x = _side
	var sprinting := Input.is_action_pressed("sprint") and _target is CharacterBody3D and Vector2((_target as CharacterBody3D).velocity.x, (_target as CharacterBody3D).velocity.z).length() > 5.0
	var fov := shoulder_fov if shoulder else base_fov
	_camera.fov = lerp(_camera.fov, fov + (sprint_fov - base_fov if sprinting else 0.0), 1.0 - exp(-4.0 * delta))
	# pushed right up against him by a wall: hide the mesh rather than look through it
	var model := _target.get_node_or_null("Model") as Node3D
	if model:
		model.visible = _camera.global_position.distance_to(_target.global_position + Vector3.UP * 1.1) > hide_closer_than
