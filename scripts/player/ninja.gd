class_name Ninja
extends CharacterBody3D
## The third-person ninja: walk, run, sprint, jump, fall, land (roll or hard landing), ground roll, slide,
## vault, climb and wall run. Movement is kinematic (velocity set per state, Jolt resolves collisions).
## One-shot moves (roll, slide, landings, vaults, wall flip) are driven by the clip's own root motion, stretched
## to fit the obstacle ("motion warping"), so the hands and feet land where they should.

signal state_changed(state: String)

enum State { GROUND, AIR, WALL_RUN, ACTION }

const LIB := preload("res://assets/animations/ninja_locomotion.res")
const LIB_NAME := "ninja"
const ROOT_TRACK := NodePath("RootMotion")
## How fast each loop's feet travel when it plays at normal speed (meters per second), so the clip can be sped
## up or slowed down to match the body and the feet don't skate.
const CLIP_SPEED := {"walk": 1.65, "run": 4.7, "sprint": 6.1}
## Layer 1 is the world. The ninja's own capsule is on layer 2 so its rays never hit itself.
const WORLD_MASK := 1

@export_group("Ground")
@export var walk_speed := 1.65
@export var run_speed := 4.4
@export var sprint_speed := 6.6
@export var ground_accel := 14.0
@export var ground_decel := 18.0
@export var turn_speed := 12.0
@export_group("Air")
@export var jump_height := 1.25
@export var fall_gravity_scale := 1.6
@export var air_control := 0.35
@export var coyote_time := 0.12
@export var jump_buffer := 0.15
## Press crouch this long (seconds) before landing to roll out of a fall.
@export var roll_window := 0.4
## Falls shorter than this (meters) just land. Longer ones need a roll, or you take a hard landing.
@export var safe_drop := 4.0
@export var hard_drop := 7.0
@export_group("Vault")
@export var vault_reach := 1.4
@export var vault_min := 0.35
@export var vault_max := 1.15
@export var climb_over_max := 1.8
## Thicker than this (meters) and it's a platform to climb onto, not something to vault.
@export var vault_max_depth := 0.9
@export_group("Climb")
## Highest ledge (meters above the feet) he can climb onto from the ground: jump, grab it, pull up.
@export var climb_max := 3.1
## Highest ledge he climbs onto straight away; above it he jumps to hang first.
@export var climb_low_max := 1.7
## Highest ledge he can grab while already in the air (above the feet).
@export var climb_air_max := 2.3
@export_group("Wall run")
@export var wall_run_min_speed := 3.5
@export var wall_run_speed := 7.0
@export var wall_run_time := 1.5
@export var wall_run_up := 2.5
@export var wall_run_gravity := 0.3
## Space during a wall run kicks off the wall: this hard away from it, this hard up, and this much of the run kept.
@export var wall_jump_push := 6.5
@export var wall_jump_up := 5.5
@export var wall_jump_keep := 0.6
## The diagonal wall run clip was shot with the wall on the character's left; the right side uses its mirror.
@export var wall_run_clip_left := "wall_run"
@export var wall_run_clip_right := "wall_run_mirror"
@export var wall_kick_clip_left := "wall_kick"
@export var wall_kick_clip_right := "wall_kick_mirror"

var state := State.GROUND
## Where the last fall started and how far it went, for the debug HUD.
var last_drop := 0.0
var current_clip := ""

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _t := 0.0
var _coyote := 0.0
var _buffer := 0.0
var _crouch_at := -10.0
var _peak_y := 0.0
var _wall_normal := Vector3.ZERO
var _wall_on_left := true
var _wall_timer := 0.0
var _wall_cooldown := 0.0
var _last_wall_normal := Vector3.ZERO
var _left_wall_at := -10.0
## The one-shot move playing in ACTION: its clip, how its root motion is stretched, and how it ends.
var _action := {}
var _stand_height := 1.8

@onready var _model: Node3D = $Model
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer
@onready var _shape: CollisionShape3D = $Collision
@onready var camera_rig: Node3D = $CameraRig


func _ready() -> void:
	add_to_group("player")
	_anim.add_animation_library(LIB_NAME, LIB)
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_stand_height = (_shape.shape as CapsuleShape3D).height
	# own capsule shape per instance, so crouching one ninja doesn't shrink another
	_shape.shape = _shape.shape.duplicate()
	_play("idle")


func _physics_process(delta: float) -> void:
	_t += delta
	_buffer = max(_buffer - delta, 0.0)
	_wall_cooldown = max(_wall_cooldown - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer
	if Input.is_action_just_pressed("crouch"):
		_crouch_at = _t
	match state:
		State.GROUND:
			_ground(delta)
		State.AIR:
			_air(delta)
		State.WALL_RUN:
			_wall_run(delta)
		State.ACTION:
			_action_step(delta)
	var was_on_floor := is_on_floor()
	move_and_slide()
	if state == State.AIR and is_on_floor():
		_land()
	elif state == State.GROUND and not is_on_floor():
		if was_on_floor:
			_coyote = coyote_time
		_set_state(State.AIR)
		_peak_y = global_position.y


# --- input ---

## Movement input turned to face where the camera looks, flattened onto the ground. Length 0 to 1.
func move_input() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw: float = camera_rig.global_rotation.y if camera_rig else global_rotation.y
	return Basis(Vector3.UP, yaw) * Vector3(v.x, 0.0, v.y)


func _target_speed() -> float:
	if Input.is_action_pressed("walk"):
		return walk_speed
	if Input.is_action_pressed("sprint"):
		return sprint_speed
	return run_speed


# --- ground ---

func _ground(delta: float) -> void:
	_coyote = coyote_time
	var input := move_input()
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var target := input * _target_speed()
	var rate := ground_accel if target.length() > flat.length() else ground_decel
	flat = flat.move_toward(target, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = -0.5
	if input.length() > 0.05:
		_face(input, delta)

	if _buffer > 0.0:
		_buffer = 0.0
		if _try_vault() or _try_climb(climb_max) or _try_wall_climb():
			return
		_jump()
		return
	if _t - _crouch_at < 0.05:
		_crouch_at = -10.0
		var speed := flat.length()
		if speed > (run_speed + sprint_speed) * 0.5:
			_start_action("slide", {"xz_scale": clamp(speed / 4.5, 0.8, 1.5), "low": true, "cancel_at": 0.8, "keep_speed": true})
		else:
			_start_action("roll", {"xz_scale": clamp(max(speed, run_speed) / 4.4, 0.8, 1.3), "low": true, "cancel_at": 0.88, "keep_speed": true})
		return
	_locomotion_anim(flat.length())


func _locomotion_anim(speed: float) -> void:
	var clip := "idle"
	if speed > 0.15:
		if speed < (walk_speed + run_speed) * 0.5:
			clip = "walk"
		elif speed < (run_speed + sprint_speed) * 0.5:
			clip = "run"
		else:
			clip = "sprint"
	_play(clip, 0.2)
	_anim.speed_scale = clamp(speed / CLIP_SPEED[clip], 0.6, 1.5) if CLIP_SPEED.has(clip) else 1.0


func _face(dir: Vector3, delta: float, rate := turn_speed) -> void:
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clamp(rate * delta, 0.0, 1.0))


# --- air ---

func _jump() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	velocity.y = sqrt(2.0 * _gravity * jump_height)
	_coyote = 0.0
	_peak_y = global_position.y
	_set_state(State.AIR)
	_play("jump_run" if speed > run_speed * 0.7 else "jump_up", 0.1)


func _air(delta: float) -> void:
	_coyote = max(_coyote - delta, 0.0)
	if _coyote > 0.0 and _buffer > 0.0 and velocity.y <= 0.0:
		_buffer = 0.0
		_jump()
		return
	var scale := fall_gravity_scale if velocity.y < 0.0 else 1.0
	velocity.y -= _gravity * scale * delta
	_peak_y = max(_peak_y, global_position.y)
	var input := move_input()
	if input.length() > 0.05:
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		var top: float = max(flat.length(), run_speed)
		flat = (flat + input * ground_accel * air_control * delta).limit_length(top)
		velocity.x = flat.x
		velocity.z = flat.z
		_face(input, delta, turn_speed * 0.3)
	if _buffer > 0.0 and _try_climb(climb_air_max):
		_buffer = 0.0
		return
	var kicking := current_clip.begins_with("wall_kick") and _anim.is_playing()
	if kicking:
		# turn from facing along the wall to facing where the kick sends him
		_face(Vector3(velocity.x, 0.0, velocity.z), delta, 6.0)
	if _try_wall_run():
		return
	if (velocity.y < -1.0 and not kicking) or not _anim.is_playing():
		_play("fall", 0.3)
		_anim.speed_scale = 1.0


func _land() -> void:
	last_drop = _peak_y - global_position.y
	var speed := Vector2(velocity.x, velocity.z).length()
	if last_drop >= safe_drop and _t - _crouch_at <= roll_window:
		_start_action("land_roll", {"xz_scale": clamp(max(speed, 3.0) / 3.0, 0.8, 1.4), "low": true, "cancel_at": 0.8, "keep_speed": true})
	elif last_drop >= hard_drop:
		velocity = Vector3.ZERO
		_start_action("land_hard", {"cancel_at": 0.55})
	elif last_drop >= safe_drop:
		velocity.x *= 0.3
		velocity.z *= 0.3
		_start_action("land_hard", {"speed": 1.6, "cancel_at": 0.3})
	else:
		_set_state(State.GROUND)


# --- vault ---

## Space in front of a knee- to chest-high, thin obstacle: vault it (low) or climb over it (high).
func _try_vault() -> bool:
	var fwd := -global_basis.z
	var hit := _ray(global_position + Vector3.UP * 0.4, fwd * vault_reach)
	if hit.is_empty() or abs(hit.normal.y) > 0.3 or _no_parkour(hit.collider):
		return false
	var into := -Vector3(hit.normal.x, 0.0, hit.normal.z).normalized()
	var top := _ray(Vector3(hit.position.x, global_position.y + climb_over_max + 0.3, hit.position.z) + into * 0.15, Vector3.DOWN * (climb_over_max + 0.3))
	if top.is_empty():
		return false
	var height: float = top.position.y - global_position.y
	if height < vault_min or height > climb_over_max:
		return false
	# room for the body over the top
	if not _ray(top.position + Vector3.UP * 0.05, Vector3.UP * 1.0).is_empty():
		return false
	# walk across the top to find how thick it is
	var depth := 0.15
	while depth < vault_max_depth + 0.2:
		var p: Vector3 = top.position + into * (depth + 0.2 - 0.15)
		var down := _ray(p + Vector3.UP * 0.3, Vector3.DOWN * 0.6)
		if down.is_empty() or abs(down.position.y - top.position.y) > 0.15:
			break
		depth += 0.2
	if depth > vault_max_depth:
		return false
	var start := Vector3(global_position.x, 0.0, global_position.z)
	var near: float = into.dot(Vector3(hit.position.x, 0.0, hit.position.z) - start)
	var clip := "vault" if height <= vault_max else "vault_high"
	var anim := LIB.get_animation(clip)
	# the clip: crouched on top with a hand down (until `on_top`), then the legs swing over and he drops down
	# the far side (landed at `landed`). Warp it so he hops up onto the near edge, swings over and lands past it.
	var on_top := 0.35 if clip == "vault" else 0.5
	var landed := 1.1 if clip == "vault" else 1.25
	var past: float = near + depth + 0.5
	var end_f: float = past + _clip_root(anim, anim.length).z - _clip_root(anim, landed).z
	rotation.y = atan2(-into.x, -into.z)
	_start_action(clip, {
		"keys_f": [[0.0, 0.0], [on_top, near + 0.2], [landed, past], [anim.length, end_f]],
		"keys_y": [[0.0, 0.0], [on_top, height], [landed, 0.0], [anim.length, 0.0]],
		"pass_through": true,
		"cancel_at": 0.75,
		"keep_speed": true,
		"speed": 1.25,
	})
	return true


## Space facing a ledge too tall or too deep to vault: climb onto it. Low ledges he pulls straight up onto; higher
## ones (up to `reach` above the feet) he jumps to, hangs from, then climbs.
func _try_climb(reach: float) -> bool:
	var fwd := -global_basis.z
	var hit := _ray(global_position + Vector3.UP * 0.6, fwd * 1.0)
	if hit.is_empty():
		hit = _ray(global_position + Vector3.UP * 1.4, fwd * 1.0)
	if hit.is_empty() or abs(hit.normal.y) > 0.3 or _no_parkour(hit.collider):
		return false
	var into := -Vector3(hit.normal.x, 0.0, hit.normal.z).normalized()
	if fwd.dot(into) < 0.6:
		return false
	var top := _ray(Vector3(hit.position.x, global_position.y + reach + 0.3, hit.position.z) + into * 0.3, Vector3.DOWN * (reach + 0.3))
	if top.is_empty() or top.normal.y < 0.7:
		return false
	var height: float = top.position.y - global_position.y
	if height < vault_min or height > reach or top.position.y < hit.position.y:
		return false
	# room to stand on top
	if not _ray(top.position + Vector3.UP * 0.05, Vector3.UP * 1.8).is_empty():
		return false
	var start := Vector3(global_position.x, 0.0, global_position.z)
	var wall: float = into.dot(Vector3(hit.position.x, 0.0, hit.position.z) - start)
	rotation.y = atan2(-into.x, -into.z)
	velocity = Vector3.ZERO
	var up := LIB.get_animation("climb_up")
	# climb_up starts hanging with the feet just off the ground and ends standing 1.6 m up; start it late for a
	# lower ledge, so only the last `height` meters of the pull-up play
	var up_rise: float = _clip_root(up, up.length).y
	var against: float = wall - 0.3
	var onto: float = wall + 0.45
	if height <= climb_low_max:
		var from := 0.0
		while from < 1.4 and up_rise - _clip_root(up, from).y > height:
			from += 1.0 / 30.0
		_start_action("climb_up", {
			"from": from,
			"keys_f": [[from, 0.0], [from + 0.3, against], [2.0, against], [up.length, onto]],
			"keys_y": [[from, 0.0], [up.length, height]],
			"pass_through": true,
			"cancel_at": 0.85,
			"speed": 1.35,
		})
		return true
	var hang_y: float = height - 2.0
	_start_action("climb_jump", {
		"keys_f": [[0.0, 0.0], [0.45, against], [1.5, against]],
		"keys_y": [[0.0, 0.0], [0.45, hang_y], [1.5, hang_y]],
		"pass_through": true,
		"speed": 1.3,
		"then": ["climb_up", {
			"keys_f": [[0.0, against], [2.0, against], [up.length, onto]],
			"keys_y": [[0.0, hang_y], [1.0, height - up_rise + _clip_root(up, 1.0).y], [up.length, height]],
			"pass_through": true,
			"cancel_at": 0.85,
			"speed": 1.35,
		}],
	})
	return true


## Where a clip's root motion has the body at `time`: x to its left, y up, z forward (meters).
func _clip_root(anim: Animation, time: float) -> Vector3:
	var track := anim.find_track(ROOT_TRACK, Animation.TYPE_POSITION_3D)
	return anim.position_track_interpolate(track, time) if track != -1 else Vector3.ZERO


# --- wall run and wall climb ---

func _try_wall_run() -> bool:
	if _wall_cooldown > 0.0 or velocity.y < -6.0 or not Input.is_action_pressed("sprint"):
		return false
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < wall_run_min_speed:
		return false
	var right := global_basis.x
	for side in [-1.0, 1.0]:
		var hit := _ray(global_position + Vector3.UP * 1.0, right * side * 1.0)
		if hit.is_empty() or abs(hit.normal.y) > 0.2 or _no_parkour(hit.collider):
			continue
		var n: Vector3 = hit.normal
		# don't grab the wall we just kicked off
		if _last_wall_normal.dot(n) > 0.7 and _t - _left_wall_at < 0.8:
			continue
		var along := flat - n * flat.dot(n)
		if along.length() < flat.length() * 0.6:
			continue
		_wall_normal = n
		_wall_timer = 0.0
		velocity = along.normalized() * max(flat.length(), wall_run_speed)
		velocity.y = max(velocity.y, wall_run_up)
		_face(along, 1.0, 1000.0)
		_set_state(State.WALL_RUN)
		# wall on the left when the wall's normal points to our right
		_wall_on_left = n.dot(right) > 0.0
		var clip := wall_run_clip_left if _wall_on_left else wall_run_clip_right
		_play(clip, 0.15)
		_anim.speed_scale = 1.0
		return true
	return false


func _wall_run(delta: float) -> void:
	_wall_timer += delta
	velocity.y -= _gravity * wall_run_gravity * delta
	var check := _ray(global_position + Vector3.UP * 1.0, -_wall_normal * 0.9)
	var off_wall: bool = check.is_empty() or abs(check.normal.y) > 0.2
	if not off_wall:
		_wall_normal = check.normal
		# keep running along the wall's surface as it bends
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		var along := (flat - _wall_normal * flat.dot(_wall_normal)).normalized() * flat.length()
		velocity.x = along.x - _wall_normal.x * 0.5
		velocity.z = along.z - _wall_normal.z * 0.5
	if _buffer > 0.0:
		_buffer = 0.0
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		velocity = _wall_normal * wall_jump_push + flat * wall_jump_keep
		velocity.y = wall_jump_up
		_leave_wall()
		_play(wall_kick_clip_left if _wall_on_left else wall_kick_clip_right, 0.1, 1.0, true)
		return
	if off_wall or _wall_timer > wall_run_time or Input.is_action_just_pressed("crouch") or is_on_floor():
		velocity += _wall_normal * 1.0
		_leave_wall()


func _leave_wall() -> void:
	_last_wall_normal = _wall_normal
	_left_wall_at = _t
	_wall_cooldown = 0.25
	_peak_y = global_position.y
	_set_state(State.AIR)


## Space while running at a wall too tall to vault: run up it and flip off (the run wall flip clip).
func _try_wall_climb() -> bool:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < run_speed * 0.6:
		return false
	var fwd := -global_basis.z
	var hit := _ray(global_position + Vector3.UP * 1.0, fwd * 1.0)
	if hit.is_empty() or abs(hit.normal.y) > 0.2 or fwd.dot(-hit.normal) < 0.75 or _no_parkour(hit.collider):
		return false
	# it has to be too tall to vault
	if _ray(global_position + Vector3.UP * (climb_over_max + 0.2), fwd * 1.2).is_empty():
		return false
	rotation.y = atan2(hit.normal.x, hit.normal.z) + PI
	_start_action("wall_flip", {"root_y": true, "cancel_at": 0.85, "then_air": true})
	return true


# --- one-shot moves driven by root motion ---

## Plays a clip whose RootMotion track moves the body. Options:
##   speed           - playback speed
##   xz_scale        - stretches the clip's travel along the ground
##   warp_distance   - stretches the travel so it covers exactly this many meters forward (vaults)
##   clear_height    - lifts the arc so the hips clear this height above the start (vaults)
##   root_y          - the clip's rise and fall moves the body too (no gravity while it plays)
##   pass_through    - ignore collisions while it plays (vaulting through the obstacle's box)
##   low             - shrink the capsule (rolls, slides)
##   cancel_at       - fraction of the clip after which movement input ends it early
##   keep_speed      - leave at running speed in the facing direction
##   then_air        - always hand over to the air state when it ends
func _start_action(clip: String, opts := {}) -> void:
	var anim := LIB.get_animation(clip)
	var track := anim.find_track(ROOT_TRACK, Animation.TYPE_POSITION_3D)
	var end: Vector3 = anim.position_track_interpolate(track, anim.length) if track != -1 else Vector3.ZERO
	var xz_scale: float = opts.get("xz_scale", 1.0)
	if opts.has("warp_distance") and end.z > 0.1:
		xz_scale = opts.warp_distance / end.z
	var lift := 0.0
	if opts.has("clear_height") and track != -1:
		var peak := -INF
		for i in 31:
			peak = max(peak, anim.position_track_interpolate(track, anim.length * i / 30.0).y)
		# the hips sit about 1 m above the feet; lift the arc until they clear the obstacle
		lift = max(0.0, opts.clear_height - 1.0 - peak)
	_action = opts.duplicate()
	_action.clip = clip
	_action.anim = anim
	_action.track = track
	_action.xz_scale = xz_scale
	_action.lift = lift
	_action.basis = _model.global_basis
	_action.origin = global_position
	_action.root_y = opts.get("root_y", false) or opts.has("clear_height") or opts.has("keys_y")
	if opts.get("pass_through", false):
		# the greybox is CSG, which can't take collision exceptions, so the body ghosts through for the vault;
		# the warp keeps it on its path and never lets it dip below where it started
		collision_mask = 0
	if opts.get("low", false):
		_set_low(true)
	_set_state(State.ACTION)
	_anim.speed_scale = 1.0
	_play(clip, opts.get("blend", 0.15), opts.get("speed", 1.0), true)
	if opts.has("from"):
		_anim.seek(opts.from, true)


func _action_step(delta: float) -> void:
	var anim: Animation = _action.anim
	var pos := _anim.current_animation_position if _anim.current_animation == LIB_NAME + "/" + _action.clip else anim.length
	var u: float = clamp(pos / anim.length, 0.0, 1.0)
	if _action.track != -1 or _action.has("keys_f"):
		var p: Vector3 = anim.position_track_interpolate(_action.track, pos) if _action.track != -1 else Vector3.ZERO
		p.x *= _action.xz_scale
		p.z *= _action.xz_scale
		if _action.has("from") and _action.track != -1:
			var p0: Vector3 = anim.position_track_interpolate(_action.track, _action.from)
			p.x -= p0.x * _action.xz_scale
		if _action.has("keys_f"):
			p.z = _keyed(anim, _action.track, pos, _action.keys_f, 2)
		if _action.has("keys_y"):
			p.y = _keyed(anim, _action.track, pos, _action.keys_y, 1)
		var target: Vector3 = _action.origin + _action.basis * Vector3(p.x, 0.0, p.z)
		var want := (target - global_position) / delta
		velocity.x = want.x
		velocity.z = want.z
		if _action.root_y:
			var y: float = _action.origin.y + p.y
			if not _action.has("keys_y"):
				var rise: float = max(p.y, 0.0) if _action.get("pass_through", false) else p.y
				y = _action.origin.y + rise + _action.lift * sin(PI * clamp(u * 1.4, 0.0, 1.0))
			velocity.y = (y - global_position.y) / delta
		else:
			velocity.y -= _gravity * delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_decel * delta)
		velocity.y -= _gravity * delta
	var cancel: bool = u >= _action.get("cancel_at", 1.0) and (move_input().length() > 0.1 or _buffer > 0.0)
	if u >= 1.0 and _action.has("then"):
		# chain into the next move from where this one left the body
		var next: Array = _action.then
		var keep_origin: Vector3 = _action.origin
		var keep_basis: Basis = _action.basis
		_end_action(true)
		_start_action(next[0], next[1])
		_action.origin = keep_origin
		_action.basis = keep_basis
	elif u >= 1.0 or cancel:
		_end_action()


## Root motion along one axis (1 = up, 2 = forward) pinned to key values: `keys` is [[clip time, meters], ...].
## Between two keys the body follows the clip's own curve on that axis, stretched to go from one key's value to
## the next; where the clip barely moves on it, it eases across instead.
func _keyed(anim: Animation, track: int, time: float, keys: Array, axis: int) -> float:
	if time <= keys[0][0]:
		return keys[0][1]
	for i in keys.size() - 1:
		var k0: Array = keys[i]
		var k1: Array = keys[i + 1]
		if time > k1[0]:
			continue
		var c0: float = anim.position_track_interpolate(track, k0[0])[axis] if track != -1 else 0.0
		var c1: float = anim.position_track_interpolate(track, k1[0])[axis] if track != -1 else 0.0
		var w: float
		if track != -1 and abs(c1 - c0) > 0.1:
			w = clamp((anim.position_track_interpolate(track, time)[axis] - c0) / (c1 - c0), 0.0, 1.0)
		else:
			w = smoothstep(k0[0], k1[0], time)
		return lerp(float(k0[1]), float(k1[1]), w)
	return keys[-1][1]


func _end_action(chained := false) -> void:
	if _action.get("pass_through", false):
		collision_mask = WORLD_MASK
	if _action.get("low", false):
		_set_low(false)
	if chained:
		_action = {}
		return
	var fwd := -global_basis.z
	if _action.get("keep_speed", false):
		var speed := sprint_speed if Input.is_action_pressed("sprint") else run_speed
		velocity = fwd * speed * clamp(move_input().length() + 0.3, 0.0, 1.0)
	elif _action.track != -1:
		# keep a little of the move's momentum
		velocity.x *= 0.5
		velocity.z *= 0.5
	velocity.y = min(velocity.y, 0.0)
	var then_air: bool = _action.get("then_air", false)
	_action = {}
	if then_air or not is_on_floor():
		_peak_y = global_position.y
		_set_state(State.AIR)
	else:
		_set_state(State.GROUND)


func _set_low(low: bool) -> void:
	var capsule := _shape.shape as CapsuleShape3D
	capsule.height = _stand_height * (0.5 if low else 1.0)
	_shape.position.y = capsule.height * 0.5


# --- helpers ---

func _play(clip: String, blend := 0.2, speed := 1.0, restart := false) -> void:
	if clip == current_clip and not restart and _anim.is_playing():
		return
	current_clip = clip
	_anim.play(LIB_NAME + "/" + clip, blend, speed)
	if restart:
		_anim.seek(0.0, true)


func _ray(from: Vector3, motion: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + motion, WORLD_MASK, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)


func _no_parkour(body: Object) -> bool:
	return body is Node and (body as Node).is_in_group("no_parkour")


func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(State.keys()[s])


func state_name() -> String:
	return String(State.keys()[state]) + ("" if _action.is_empty() else " / " + String(_action.clip))


func teleport(to: Transform3D) -> void:
	if not _action.is_empty():
		_end_action()
	global_transform = to
	velocity = Vector3.ZERO
	_peak_y = to.origin.y
	_set_state(State.AIR)
	reset_physics_interpolation()
