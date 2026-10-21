class_name Ninja
extends CharacterBody3D
## The third-person ninja: walk, run, sprint, jump, fall, land (roll or hard landing), ground roll, slide,
## vault, climb and wall run. Movement is kinematic (velocity set per state, Jolt resolves collisions).
## One-shot moves (roll, slide, landings, vaults, wall flip) are driven by the clip's own root motion, stretched
## to fit the obstacle ("motion warping"), so the hands and feet land where they should.

signal state_changed(state: String)

enum State { GROUND, AIR, WALL_RUN, ACTION, HANG, WALL_UP, RAGDOLL }

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
## Lower = heavier: he takes longer to get up to speed and to stop, and turns wider the faster he goes.
@export var ground_accel := 9.0
@export var ground_decel := 11.0
@export var turn_speed := 10.0
## Running backwards (S on its own).
@export var backpedal_speed := 3.2
@export_group("Air")
@export var jump_height := 1.25
@export var fall_gravity_scale := 1.6
@export var air_control := 0.2
@export var coyote_time := 0.12
@export var jump_buffer := 0.15
## Press crouch this long (seconds) before landing to roll out of a fall.
@export var roll_window := 0.4
## Falls shorter than this (meters) just land. Longer ones need a roll, or you take a hard landing.
@export var safe_drop := 4.0
@export var hard_drop := 7.0
## Falls this long (meters) without a roll knock him down (ragdoll); this long even a roll can't save him.
@export var ragdoll_drop := 9.5
@export var ragdoll_drop_rolled := 18.0
## Second jump press within this long (seconds) of the jump: flip (forward, or a backflip holding back).
@export var flip_window := 0.6
@export var flip_up := 5.0
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
## Highest ledge he grabs by running up the wall at it (a run at a wall taller than this flips off it instead).
@export var climb_run_max := 4.0
## How high up the wall his feet get before a wall flip (meters).
@export var wall_flip_height := 1.8
## Sideways speed hanging from a ledge (meters per second).
@export var shimmy_speed := 0.6
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
## How far his body stays off the wall while wall running (meters, body center to wall), so he doesn't sink in.
@export var wall_run_gap := 0.55
@export_group("Wall run up")
## Sprinting (Shift) into a tall wall runs fast straight up it for this long (seconds), then he falls unless
## Space backflips him off first (or he reaches the top and grabs it).
@export var wall_up_time := 0.6
@export var wall_up_speed := 5.5
@export var wall_up_gap := 0.42
## Space (or back + Space) while running up a wall backflips off it: this hard away and this hard up.
@export var wall_backflip_push := 4.5
@export var wall_backflip_up := 5.5

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
## The ledge he hangs from in HANG: its top height and the wall's outward normal.
var _hang := {}
## The one-shot move playing in ACTION: its clip, how its root motion is stretched, and how it ends.
var _action := {}
var _stand_height := 1.8
var _jumped_at := -10.0
var _flipped := false
var _wall_up_timer := 0.0
var _last_vault := ""
## Velocity going into this frame's move, so a landing knows how hard it hit.
var _impact := Vector3.ZERO
var _ragdoll: PhysicalBoneSimulator3D
var _ragdoll_at := 0.0
var _skeleton: Skeleton3D
var _sfx: NinjaSfx

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
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_sfx = NinjaSfx.new()
	add_child(_sfx)
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
		State.HANG:
			_hang_step(delta)
		State.WALL_UP:
			_wall_up(delta)
		State.RAGDOLL:
			_ragdoll_step(delta)
	_sfx.footsteps(self)
	_impact = velocity
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
	# S on its own runs backwards, still facing where the camera looks
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var backing: bool = raw.y > 0.5 and absf(raw.x) < 0.5
	var target := input * (_target_speed() if not backing else backpedal_speed)
	var rate := ground_accel if target.length() > flat.length() else ground_decel
	flat = flat.move_toward(target, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = -0.5
	if backing:
		_face(-input, delta)
	elif input.length() > 0.05:
		# momentum: at a sprint he can't spin on the spot
		_face(input, delta, turn_speed * lerp(1.0, 0.45, clamp(flat.length() / sprint_speed, 0.0, 1.0)))

	if _buffer > 0.0:
		_buffer = 0.0
		var running := Vector2(velocity.x, velocity.z).length() > run_speed * 0.6
		if _try_vault() or _try_climb(climb_run_max if running else climb_max) or _try_wall_climb():
			return
		_jump()
		return
	if _try_wall_up():
		return
	if _t - _crouch_at < 0.05:
		_crouch_at = -10.0
		var speed := flat.length()
		if speed > (run_speed + sprint_speed) * 0.5:
			_start_action("slide", {"xz_scale": clamp(speed / 4.5, 0.8, 1.5), "low": true, "cancel_at": 0.8, "keep_speed": true})
			_sfx.play("whoosh", -6.0)
		else:
			_roll(max(speed, run_speed))
		return
	if backing and flat.length() > 0.15:
		# the run (or walk) played backwards
		var clip := "walk" if flat.length() < (walk_speed + backpedal_speed) * 0.5 else "run"
		if current_clip != clip + "_back":
			current_clip = clip + "_back"
			_anim.play(LIB_NAME + "/" + clip, 0.2, -1.0, true)
		_anim.speed_scale = clamp(flat.length() / CLIP_SPEED[clip], 0.6, 1.5)
		return
	_locomotion_anim(flat.length())


## The roll (C / Ctrl): always the sprinting forward roll, the way the stick points.
func _roll(speed: float) -> void:
	# roll the way the stick points, straight away
	if move_input().length() > 0.1:
		_face(move_input(), 1.0, 1000.0)
	# the clip covers 5.7 m at a sprint; from slower it goes less far
	_start_action("roll", {
		"warp_distance": clamp(speed * 0.9, 3.5, 5.7),
		"low": true,
		"cancel_at": 0.85,
		"keep_speed": true,
	})
	_sfx.play("whoosh", -4.0)


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
	_jumped_at = _t
	_flipped = false
	_set_state(State.AIR)
	var clip := "jump_up"
	if speed > run_speed * 0.7:
		clip = "jump_run" if randf() < 0.6 else "jump_long"
	_play(clip, 0.1, 1.0, true)


func _air(delta: float) -> void:
	_coyote = max(_coyote - delta, 0.0)
	if _coyote > 0.0 and _buffer > 0.0 and velocity.y <= 0.0:
		_buffer = 0.0
		_jump()
		return
	var g_scale := fall_gravity_scale if velocity.y < 0.0 else 1.0
	velocity.y -= _gravity * g_scale * delta
	_peak_y = max(_peak_y, global_position.y)
	var input := move_input()
	var flipping := current_clip.begins_with("flip_") and _anim.is_playing()
	if input.length() > 0.05:
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		var top: float = max(flat.length(), run_speed)
		flat = (flat + input * ground_accel * air_control * delta).limit_length(top)
		velocity.x = flat.x
		velocity.z = flat.z
		# a flip keeps the way it faces, or a backflip would turn round mid-air
		if not flipping:
			_face(input, delta, turn_speed * 0.3)
	if _buffer > 0.0 and _try_climb(climb_air_max):
		_buffer = 0.0
		return
	if _buffer > 0.0 and not _flipped and _t - _jumped_at < flip_window and _t - _jumped_at > 0.05:
		_buffer = 0.0
		_air_flip()
	# grab a ledge he's moving into without pressing anything, once it's above the knees
	if velocity.y < 3.0 and move_input().length() > 0.3 and _try_climb(climb_air_max, 0.9):
		return
	var kicking := current_clip.begins_with("wall_kick") and _anim.is_playing()
	if kicking:
		# turn from facing along the wall to facing where the kick sends him
		_face(Vector3(velocity.x, 0.0, velocity.z), delta, 6.0)
	if _try_wall_run():
		return
	if (velocity.y < -1.0 and not kicking and not flipping) or not _anim.is_playing():
		_play("fall", 0.3)
		_anim.speed_scale = 1.0


## Double-tap jump: a flip at the top of the jump. Forward it's one of the front flips at random; holding back
## it's a backflip that carries him back the way he came.
func _air_flip() -> void:
	_flipped = true
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var fwd := -global_basis.z
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var clip: String
	if raw.y > 0.5:
		clip = "flip_back"
		flat = -fwd * 3.0
	else:
		clip = ["flip_front", "flip_run", "flip_aerial"].pick_random()
		flat = fwd * max(flat.length() + 1.0, run_speed)
	velocity = Vector3(flat.x, max(velocity.y, flip_up), flat.z)
	# play it at the speed that has him round before he comes down
	var air: float = velocity.y / _gravity * (1.0 + 1.0 / sqrt(fall_gravity_scale))
	var anim := LIB.get_animation(clip)
	_play(clip, 0.1, clamp(anim.length / air, 0.8, 1.8), true)


func _land() -> void:
	last_drop = _peak_y - global_position.y
	var speed := Vector2(velocity.x, velocity.z).length()
	var rolled := _t - _crouch_at <= roll_window
	if last_drop >= ragdoll_drop_rolled or (last_drop >= ragdoll_drop and not rolled):
		_start_ragdoll(_impact)
	elif last_drop >= safe_drop:
		# medium and high falls roll out on their own, carrying the fall forward
		_sfx.play("land")
		_roll(max(speed, run_speed))
	else:
		_set_state(State.GROUND)
		_sfx.play("land", -6.0 if last_drop < 1.0 else 0.0)


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
	# a different vault each time for low obstacles: the one-hand side vault (either hand) or the speed vault
	var clip := "vault_high"
	if height <= vault_max:
		var pool := ["vault", "vault_mirror", "vault_speed"]
		pool.erase(_last_vault)
		clip = pool.pick_random()
	_last_vault = clip
	# each clip: a hand (or two) down on the top, the legs go over and he's down the far side at `landed` (clip
	# seconds), played at `play`. Warp it so he rises over the obstacle, goes across and lands well past it.
	var landed: float = {"vault": 1.1, "vault_mirror": 1.1, "vault_high": 1.25, "vault_speed": 1.0}[clip]
	var play: float = {"vault": 1.6, "vault_mirror": 1.6, "vault_high": 1.6, "vault_speed": 1.15}[clip]
	# keep the run's momentum: he carries on at most of the speed he came in at, well past the obstacle, at a
	# steady pace, and goes straight back into the run when he lands
	var speed: float = max(Vector2(velocity.x, velocity.z).length(), run_speed)
	var past: float = max(near + depth + 1.0, speed * landed / play)
	# high enough to clear the top from just before its near edge until just after its far edge
	var over_from: float = max(0.05, landed * (near - 0.2) / past)
	var over_to: float = max(over_from + 0.05, landed * (near + depth + 0.2) / past)
	rotation.y = atan2(-into.x, -into.z)
	_start_action(clip, {
		"keys_f": [[0.0, 0.0], [landed, past]],
		"linear_f": true,
		# the hand on the top is about 0.4 m below the hips, and the pose keeps the hips 0.93 m over the body's
		# origin: put the hand on the obstacle, not the feet (that had him vaulting a body length up in the air)
		"keys_y": [[0.0, 0.0], [over_from, max(height - 0.53, 0.0)], [over_to, max(height - 0.55, 0.0)], [landed, 0.0]],
		"end_at": landed + 0.1,
		"pass_through": true,
		"keep_speed": true,
		"speed": play,
	})
	_sfx.play("whoosh", -8.0)
	return true


## Space facing a ledge too tall or too deep to vault: climb onto it. Low ledges he pulls straight up onto; higher
## ones (up to `reach` above the feet) he jumps to, hangs from, then climbs.
func _try_climb(reach: float, low := -1.0) -> bool:
	var fwd := -global_basis.z
	var look := 1.3 if is_on_floor() else 0.9
	var hit := _ray(global_position + Vector3.UP * 0.6, fwd * look)
	if hit.is_empty():
		hit = _ray(global_position + Vector3.UP * 1.4, fwd * look)
	if hit.is_empty() or abs(hit.normal.y) > 0.3 or _no_parkour(hit.collider):
		return false
	var into := -Vector3(hit.normal.x, 0.0, hit.normal.z).normalized()
	if fwd.dot(into) < 0.4:
		return false
	var top := _ray(Vector3(hit.position.x, global_position.y + reach + 0.3, hit.position.z) + into * 0.3, Vector3.DOWN * (reach + 0.3))
	if top.is_empty() or top.normal.y < 0.7:
		return false
	var height: float = top.position.y - global_position.y
	if height < max(vault_min, low) or height > reach or top.position.y < hit.position.y:
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
	# higher ledges: grab it and hang (from the ground he jumps up to it first); then W climbs, S drops, A/D shimmy
	var hang_y: float = height - HANG_HANDS
	var hang_f: float = wall - HANG_GAP
	var info := {"top": top.position.y, "normal": hit.normal}
	if is_on_floor():
		_start_action("climb_jump", {
			"keys_f": [[0.0, 0.0], [0.45, hang_f], [1.5, hang_f]],
			"keys_y": [[0.0, 0.0], [0.45, hang_y], [1.5, hang_y]],
			"pass_through": true,
			"speed": 1.3,
			"end_at": 1.1,
			"hang": info,
		})
	else:
		_start_action("hang", {
			"keys_f": [[0.0, 0.0], [0.2, hang_f]],
			"keys_y": [[0.0, 0.0], [0.2, hang_y]],
			"pass_through": true,
			"end_at": 0.2,
			"blend": 0.1,
			"hang": info,
		})
	return true


# --- hanging from a ledge ---

## How far the hands are above the body's origin in the hang clips, and how far the body hangs off the wall.
const HANG_HANDS := 2.3
const HANG_GAP := 0.25


func _enter_hang(info: Dictionary) -> void:
	_hang = info
	collision_mask = 0
	velocity = Vector3.ZERO
	_set_state(State.HANG)
	_play("hang", 0.2)
	_anim.speed_scale = 1.0


func _hang_step(delta: float) -> void:
	velocity = Vector3.ZERO
	var n: Vector3 = _hang.normal
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _buffer > 0.0 or inp.y < -0.5:
		_buffer = 0.0
		_climb_from_hang()
		return
	if Input.is_action_just_pressed("crouch") or inp.y > 0.5:
		# let go and drop, pushed a little off the wall
		collision_mask = WORLD_MASK
		_hang = {}
		velocity = n * 1.5
		_peak_y = global_position.y
		_set_state(State.AIR)
		_play("fall", 0.3)
		return
	if abs(inp.x) > 0.3:
		var side: Vector3 = global_basis.x * signf(inp.x)
		var next: Vector3 = global_position + side * shimmy_speed * delta
		# only along as far as the ledge goes: there must still be wall in front and a top at the same height
		var wall := _ray(next + Vector3.UP * (HANG_HANDS - 0.4), -n * 0.8)
		var top := _ray(Vector3(next.x, _hang.top + 0.3, next.z) - n * (HANG_GAP + 0.3), Vector3.DOWN * 0.6)
		if not wall.is_empty() and not top.is_empty() and abs(top.position.y - _hang.top) < 0.2:
			global_position = next
			_play("shimmy_r" if inp.x > 0.0 else "shimmy_l", 0.15)
			_anim.speed_scale = 2.0
			return
	_play("hang", 0.25)
	_anim.speed_scale = 1.0


func _climb_from_hang() -> void:
	var up := LIB.get_animation("climb_up")
	var rise: float = _hang.top - global_position.y
	# room to stand up there, else stay hanging
	if not _ray(Vector3(global_position.x, _hang.top + 0.05, global_position.z) - _hang.normal * (HANG_GAP + 0.5), Vector3.UP * 1.8).is_empty():
		return
	var end_y: float = _clip_root(up, up.length).y
	_hang = {}
	_start_action("climb_up", {
		# the pull-up clip starts with bent arms, higher than the hang: ease up to it, then follow the clip
		"keys_f": [[0.0, 0.0], [2.0, 0.0], [up.length, HANG_GAP + 0.6]],
		"keys_y": [[0.0, 0.0], [1.0, rise - (end_y - _clip_root(up, 1.0).y)], [up.length, rise]],
		"pass_through": true,
		"cancel_at": 0.85,
		"speed": 1.4,
		"blend": 0.25,
	})


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
		# hold the body a set distance off the wall (it used to be pushed into it, which sank the arms and feet
		# into the wall)
		var gap: float = (global_position - check.position).dot(_wall_normal)
		var hold: float = clamp((wall_run_gap - gap) * 10.0, -3.0, 3.0)
		velocity.x = along.x + _wall_normal.x * hold
		velocity.z = along.z + _wall_normal.z * hold
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


## Sprinting (Shift) straight into a wall too tall to vault: run up it.
func _try_wall_up() -> bool:
	if not Input.is_action_pressed("sprint") or move_input().length() < 0.5:
		return false
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < run_speed * 0.9:
		return false
	var fwd := -global_basis.z
	var hit := _ray(global_position + Vector3.UP * 1.0, fwd * 0.8)
	if hit.is_empty() or abs(hit.normal.y) > 0.2 or fwd.dot(-hit.normal) < 0.8 or _no_parkour(hit.collider):
		return false
	if move_input().normalized().dot(-hit.normal) < 0.7:
		return false
	# too tall to vault, or it's a vault
	if _ray(global_position + Vector3.UP * (climb_over_max + 0.2), fwd * 1.0).is_empty():
		return false
	_wall_normal = hit.normal
	_wall_up_timer = 0.0
	rotation.y = atan2(hit.normal.x, hit.normal.z)
	velocity = Vector3(0.0, wall_up_speed, 0.0)
	_set_state(State.WALL_UP)
	var anim := LIB.get_animation("wall_up_run")
	_play("wall_up_run", 0.1, anim.length / wall_up_time, true)
	return true


func _wall_up(delta: float) -> void:
	_wall_up_timer += delta
	var n := _wall_normal
	var check := _ray(global_position + Vector3.UP * 1.0, -n * 1.0)
	if not check.is_empty() and abs(check.normal.y) < 0.2:
		_wall_normal = check.normal
		n = _wall_normal
	# keep close to the wall, facing it, feet on it
	var gap: float = (global_position - check.position).dot(n) if not check.is_empty() else wall_up_gap
	var hold: float = clamp((wall_up_gap - gap) * 10.0, -3.0, 3.0)
	velocity = n * hold
	# slows down over the last part of the run up
	velocity.y = wall_up_speed * (1.0 - smoothstep(wall_up_time * 0.6, wall_up_time, _wall_up_timer))
	rotation.y = lerp_angle(rotation.y, atan2(n.x, n.z), clamp(10.0 * delta, 0.0, 1.0))
	# Space, or back + Space: backflip off the wall
	if _buffer > 0.0:
		_buffer = 0.0
		velocity = n * wall_backflip_push + Vector3.UP * wall_backflip_up
		_leave_wall()
		_flipped = true
		var anim := LIB.get_animation("flip_back")
		var air: float = velocity.y / _gravity * (1.0 + 1.0 / sqrt(fall_gravity_scale))
		_play("flip_back", 0.1, clamp(anim.length / air, 0.8, 1.8), true)
		return
	# reached the top: grab it (and pull up while W is held)
	if _try_climb(HANG_HANDS + 0.3, 0.0):
		return
	var out_of_wall: bool = check.is_empty() or abs(check.normal.y) > 0.2
	if out_of_wall or not Input.is_action_pressed("sprint") or Input.is_action_just_pressed("crouch") \
			or _wall_up_timer > wall_up_time:
		velocity = n * 1.5 + Vector3.UP * min(velocity.y, 1.0)
		_leave_wall()
		_play("fall", 0.3)


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
	# face the wall (this used to add PI, which turned him round to face away from it before the flip)
	rotation.y = atan2(hit.normal.x, hit.normal.z)
	# the clip runs 1.8 m up to the wall, kicks off it at 0.56 s and flips 1.5 m back: stretch the run-in so his
	# feet plant on this wall, wherever he pressed jump
	var start := Vector3(global_position.x, 0.0, global_position.z)
	var wall: float = (-hit.normal).dot(Vector3(hit.position.x, 0.0, hit.position.z) - start)
	var anim := LIB.get_animation("wall_flip")
	var plant := 0.56
	var back: float = _clip_root(anim, anim.length).z - _clip_root(anim, plant).z
	_start_action("wall_flip", {
		"root_y": true,
		"keys_f": [[0.0, 0.0], [plant, wall - 0.3], [anim.length, wall - 0.3 + back]],
		# run two steps up the wall before flipping off it, not one hop
		"keys_y": [[0.0, 0.0], [0.84, wall_flip_height], [1.4, 0.0], [anim.length, 0.0]],
		"cancel_at": 0.8,
		"then_air": true,
	})
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
			p.z = _keyed(anim, -1 if _action.get("linear_f", false) else _action.track, pos, _action.keys_f, 2, _action.get("linear_f", false))
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
	if _action.has("end_at") and pos >= _action.end_at:
		u = 1.0
	# still under something low (a slide under a bar): keep sliding on until there's room to stand
	if _action.get("low", false) and (u >= 1.0 or cancel) and not _ray(global_position + Vector3.UP * 0.5, Vector3.UP * 1.4).is_empty():
		var on: Vector3 = -global_basis.z * 3.0
		velocity = Vector3(on.x, -1.0, on.z)
		return
	if u >= 1.0 and _action.has("hang"):
		var info: Dictionary = _action.hang
		_end_action(true)
		_enter_hang(info)
	elif u >= 1.0 and _action.has("then"):
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
func _keyed(anim: Animation, track: int, time: float, keys: Array, axis: int, linear := false) -> float:
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
		elif linear:
			w = inverse_lerp(k0[0], k1[0], time)
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
		# land running: carry straight on into the run clip
		if move_input().length() > 0.1:
			_play("sprint" if speed > run_speed else "run", 0.15)
	elif _action.track != -1:
		# keep a little of the move's momentum
		velocity.x *= 0.5
		velocity.z *= 0.5
	velocity.y = min(velocity.y, 0.0)
	var then_air: bool = _action.get("then_air", false)
	# a vault puts him back down exactly where he started, so he's on the ground even before the next slide
	var landed: bool = _action.has("keys_y") and _action.keys_y[-1][1] == 0.0
	_action = {}
	if landed:
		velocity.y = -2.0
	if then_air or not (is_on_floor() or landed):
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
	if _ragdoll != null:
		_stop_ragdoll()
	_hang = {}
	collision_mask = WORLD_MASK
	global_transform = to
	velocity = Vector3.ZERO
	_peak_y = to.origin.y
	_set_state(State.AIR)
	reset_physics_interpolation()


# --- ragdoll (a fall too high to land) ---

## Bone -> [child bone the capsule reaches to, capsule radius in meters]. Bones left out follow their parent.
const RAGDOLL_BONES := {
	"Hips": ["Spine", 0.13],
	"Spine": ["Spine2", 0.13],
	"Spine2": ["Neck", 0.14],
	"Head": ["HeadTop_End", 0.1],
	"LeftArm": ["LeftForeArm", 0.05],
	"LeftForeArm": ["LeftHand", 0.045],
	"RightArm": ["RightForeArm", 0.05],
	"RightForeArm": ["RightHand", 0.045],
	"LeftUpLeg": ["LeftLeg", 0.075],
	"LeftLeg": ["LeftFoot", 0.06],
	"RightUpLeg": ["RightLeg", 0.075],
	"RightLeg": ["RightFoot", 0.06],
}
const BONE_PREFIX := "mixamorig1_"


func _start_ragdoll(impact: Vector3) -> void:
	if not _action.is_empty():
		_end_action(true)
	_set_state(State.RAGDOLL)
	velocity = Vector3.ZERO
	_ragdoll_at = _t
	_anim.active = false
	_ragdoll = PhysicalBoneSimulator3D.new()
	_skeleton.add_child(_ragdoll)
	var scale_to_bone: float = 1.0 / _skeleton.global_basis.get_scale().x
	for short in RAGDOLL_BONES:
		var info: Array = RAGDOLL_BONES[short]
		var bone := _skeleton.find_bone(BONE_PREFIX + short)
		var child := _skeleton.find_bone(BONE_PREFIX + info[0])
		if bone == -1 or child == -1:
			continue
		var pose := _skeleton.get_bone_global_pose(bone)
		# the capsule runs from the bone toward its child, in the bone's own space
		var local_dir: Vector3 = pose.basis.inverse() * (_skeleton.get_bone_global_pose(child).origin - pose.origin)
		var length := local_dir.length()
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + short
		pb.bone_name = BONE_PREFIX + short
		pb.collision_layer = 16
		pb.collision_mask = WORLD_MASK
		pb.mass = 6.0 if short.begins_with("Spine") or short == "Hips" else 2.5
		pb.linear_damp = 0.3
		pb.angular_damp = 2.0
		pb.friction = 0.9
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		pb.set("joint_constraints/swing_span", 40.0)
		pb.set("joint_constraints/twist_span", 20.0)
		var up := Vector3.FORWARD if abs(local_dir.normalized().dot(Vector3.UP)) > 0.9 else Vector3.UP
		pb.body_offset = Transform3D(Basis.looking_at(local_dir.normalized(), up), local_dir * 0.5)
		pb.joint_offset = Transform3D(Basis(), Vector3(0, 0, length * 0.5))
		var cs := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		var radius: float = info[1] * scale_to_bone
		capsule.radius = radius
		capsule.height = max(length, radius * 2.0 + 0.01)
		cs.shape = capsule
		cs.rotation.x = PI * 0.5
		pb.add_child(cs)
		_ragdoll.add_child(pb)
	_ragdoll.physical_bones_start_simulation()
	_sfx.play("impact")
	# carry the fall into the bones, a little forward and down
	await get_tree().physics_frame
	if _ragdoll == null:
		return
	for pb in _ragdoll.get_children():
		if pb is PhysicalBone3D:
			(pb as PhysicalBone3D).apply_central_impulse(Vector3(impact.x, max(impact.y, -8.0), impact.z) * pb.mass * 0.3)


func _ragdoll_step(_delta: float) -> void:
	velocity = Vector3.ZERO
	# W (forward) gets him back up once he's down
	if _t - _ragdoll_at > 0.8 and Input.get_vector("move_left", "move_right", "move_forward", "move_back").y < -0.5:
		_get_up()


func _get_up() -> void:
	var hips := _skeleton.find_bone(BONE_PREFIX + "Hips")
	var head := _skeleton.find_bone(BONE_PREFIX + "Head")
	var hips_t: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(hips)
	var head_p: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(head).origin
	# chest facing the sky: on his back, kip up; otherwise roll over and stand
	var chest: Vector3 = hips_t.basis.z.normalized()
	var on_back := chest.y > 0.0
	var head_dir := Vector3(head_p.x - hips_t.origin.x, 0.0, head_p.z - hips_t.origin.z)
	_stop_ragdoll()
	# the body moves to where the ragdoll ended up; both get-up clips start with the head behind him
	var floor_hit := _ray(Vector3(hips_t.origin.x, hips_t.origin.y + 0.5, hips_t.origin.z), Vector3.DOWN * 3.0)
	var at := Vector3(hips_t.origin.x, floor_hit.position.y if not floor_hit.is_empty() else global_position.y, hips_t.origin.z)
	global_position = at
	if head_dir.length() > 0.05:
		_face(-head_dir, 1.0, 1000.0)
	reset_physics_interpolation()
	_start_action("kip_up" if on_back and randf() < 0.5 else "get_up", {"cancel_at": 0.8, "speed": 1.3, "blend": 0.3})


func _stop_ragdoll() -> void:
	if _ragdoll != null:
		_ragdoll.physical_bones_stop_simulation()
		_ragdoll.queue_free()
		_ragdoll = null
	_skeleton.reset_bone_poses()
	_anim.active = true
