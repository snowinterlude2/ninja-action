extends SceneTree
## Plays the test map headless with scripted key presses and checks each move does what it should.
##   godot --headless --fixed-fps 60 --script res://tools/test_moves.gd
## Prints PASS or FAIL per move and exits with 1 if anything failed.
## To also save what the camera sees every few frames (for looking at the moves), run it with a renderer:
##   xvfb-run godot --rendering-driver opengl3 --fixed-fps 60 --script res://tools/test_moves.gd -- --record=<dir> [--only=<word>]

var ninja: Ninja
var failures := 0
var _seen := {}
var _record := ""
var _only := ""
var _label := ""
var _frame := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--record="):
			_record = a.trim_prefix("--record=")
			DirAccess.make_dir_recursive_absolute(_record)
		elif a.begins_with("--only="):
			_only = a.trim_prefix("--only=")
	var map: Node = load("res://scenes/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	ninja = map.get_node("Ninja")
	ninja.state_changed.connect(func(_s: String) -> void: pass)
	_run.call_deferred()


func _run() -> void:
	await _frames(10)
	await _test_run()
	await _test_vault("vault low (0.9 m)", Vector3(-14, 0.1, -12.5), -15.0, "vault", -15.6)
	await _test_vault("vault (1.0 m, 0.8 deep)", Vector3(-14, 0.1, -17.5), -20.0, "vault", -20.9)
	await _test_vault("climb over (1.5 m)", Vector3(-14, 0.1, -22.5), -25.0, "vault_high", -25.4)
	await _test_climb("climb onto the deep 1.1 m box", Vector3(-14, 0.1, -27.0), 0.0, 1.4, 1.1, ["climb_up"])
	await _test_climb("jump, hang and climb the 3 m pillar", Vector3(18, 0.1, 13.5), PI, 2.0, 3.0, ["climb_jump", "hang", "climb_up"])
	await _test_climb("grab the 3 m pillar's edge mid-jump", Vector3(18, 0.1, 13.0), PI, 1.6, 3.0, ["jump", "hang", "climb_up"])
	await _test_wall_run()
	await _test_drop("6 m drop rolls on its own", "Station4", false, "roll")
	await _test_slide()
	await _test_wall_flip()
	await _test_new_moves()
	print("\n%s: %d failed" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)


# --- tests ---

func _test_run() -> void:
	_place(Vector3(0, 0.1, 0), 0.0)
	await _frames(20)
	Input.action_press("move_forward")
	await _frames(60)
	var speed := _flat_speed()
	_check("run reaches run speed", abs(speed - ninja.run_speed) < 0.3 and ninja.current_clip == "run", "speed %.2f clip %s" % [speed, ninja.current_clip])
	Input.action_press("sprint")
	await _frames(40)
	speed = _flat_speed()
	_check("sprint reaches sprint speed", abs(speed - ninja.sprint_speed) < 0.3 and ninja.current_clip == "sprint", "speed %.2f clip %s" % [speed, ninja.current_clip])
	_release_all()
	await _frames(60)
	_check("stops and idles", _flat_speed() < 0.1 and ninja.current_clip == "idle", "speed %.2f clip %s" % [_flat_speed(), ninja.current_clip])


## Runs at the obstacle (whose near face is at z = `face_z`) along -Z and presses jump just in front of it.
func _test_vault(label: String, start: Vector3, face_z: float, clip: String, past_z: float) -> void:
	_place(start, 0.0)
	await _frames(20)
	_seen.clear()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var pressed := false
	for i in 300:
		await physics_frame
		_note()
		if not pressed and ninja.global_position.z < face_z + 1.3:
			Input.action_press("jump")
			pressed = true
		elif pressed:
			Input.action_release("jump")
		if pressed and ninja.state == Ninja.State.GROUND and ninja.global_position.z < past_z:
			break
	_release_all()
	var p := ninja.global_position
	_check(label, _saw(clip) and p.z < past_z and p.y < 0.3, "clips %s  end %s" % [_seen.keys(), _v(p)])


## Runs at a ledge and presses jump after `press_after` meters, about a meter before it; he has to end up
## standing on top.
func _test_climb(label: String, start: Vector3, yaw: float, press_after: float, top: float, clips: Array) -> void:
	_place(start, yaw)
	await _frames(20)
	_seen.clear()
	Input.action_press("move_forward")
	var pressed := false
	for i in 400:
		await physics_frame
		_note()
		if not pressed and Vector2(ninja.global_position.x - start.x, ninja.global_position.z - start.z).length() > press_after:
			Input.action_press("jump")
			pressed = true
		elif pressed:
			Input.action_release("jump")
			# keep holding W: from a hang that's what climbs up
			if ninja.state == Ninja.State.ACTION and ninja.current_clip == "climb_up" and _seen.has("hang") == false:
				Input.action_release("move_forward")
		if pressed and ninja.state == Ninja.State.GROUND and _seen.has(clips[-1]):
			break
	_release_all()
	await _frames(10)
	var p := ninja.global_position
	var ok: bool = abs(p.y - top) < 0.15 and ninja.state == Ninja.State.GROUND
	for c in clips:
		ok = ok and _saw(c)
	_check(label, ok, "clips %s  end %s" % [_seen.keys(), _v(p)])


func _test_wall_run() -> void:
	# sprint down the alley close to its right wall (x = 2.0 face), jump, wall run, kick to the other wall
	_place(Vector3(1.3, 0.1, 6.0), PI)
	await _frames(20)
	_seen.clear()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(40)
	_tap("jump")
	var ran_at := -1.0
	var kicked := false
	var second := false
	var max_y := 0.0
	for i in 240:
		await physics_frame
		_note()
		max_y = max(max_y, ninja.global_position.y)
		if OS.has_environment("TRACE") and i % 6 == 0:
			print("  ", i, " ", ninja.state_name(), " ", _v(ninja.global_position), " v ", _v(ninja.velocity))
		if ninja.state == Ninja.State.WALL_RUN and ran_at < 0.0:
			ran_at = ninja.global_position.x
		if ran_at > 0.0 and not kicked and ninja.state == Ninja.State.WALL_RUN and ninja.global_position.z > 16.0:
			Input.action_press("jump")
			kicked = true
		elif kicked:
			Input.action_release("jump")
		if kicked and ninja.state == Ninja.State.WALL_RUN and ninja.global_position.x < 0.0:
			second = true
			break
	_release_all()
	# facing +Z, the +X wall is on the ninja's left
	_check("wall run on the left wall", ran_at > 1.0 and _seen.has("wall_run"), "clips %s  max height %.1f" % [_seen.keys(), max_y])
	_check("kick off onto the right wall", second and _seen.has("wall_kick") and _seen.has("wall_run_mirror"), "clips %s  at %s" % [_seen.keys(), _v(ninja.global_position)])
	await _frames(90)


func _test_drop(label: String, station: String, roll: bool, clip: String) -> void:
	var m := current_scene.find_child(station, true, false) as Node3D
	_place(m.global_position, m.global_rotation.y)
	await _frames(30)
	_seen.clear()
	Input.action_press("move_forward")
	var crouched := false
	for i in 400:
		await physics_frame
		_note()
		if roll and not crouched and ninja.state == Ninja.State.AIR and ninja.global_position.y < 1.0:
			Input.action_press("crouch")
			crouched = true
		elif crouched:
			Input.action_release("crouch")
		if _seen.has(clip):
			break
	_release_all()
	_check(label, _seen.has(clip) and ninja.last_drop > 5.5, "clips %s  drop %.1f m" % [_seen.keys(), ninja.last_drop])
	await _frames(150)


func _test_slide() -> void:
	_place(Vector3(6, 0.1, 6), 0.0)
	await _frames(20)
	_seen.clear()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(60)
	_tap("crouch")
	for i in 90:
		await physics_frame
		_note()
	_release_all()
	_check("C at a sprint rolls", _seen.has("roll"), "clips %s" % [_seen.keys()])
	await _frames(60)


func _test_wall_flip() -> void:
	_place(Vector3(-20, 0.1, 18), PI * 0.5)
	await _frames(20)
	_seen.clear()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var pressed := false
	var max_y := 0.0
	for i in 300:
		await physics_frame
		_note()
		max_y = max(max_y, ninja.global_position.y)
		if not pressed and ninja.global_position.x < -25.5:
			Input.action_press("jump")
			pressed = true
		elif pressed:
			Input.action_release("jump")
		if pressed and ninja.state == Ninja.State.GROUND and i > 60 and not _seen.is_empty() and _seen.has("wall_flip"):
			break
	_release_all()
	_check("wall flip on the tall wall", _seen.has("wall_flip") and max_y > 0.5, "clips %s  max height %.1f" % [_seen.keys(), max_y])


func _test_new_moves() -> void:
	# double-tap jump flips
	_place(Vector3(6, 0.1, -2), 0.0)
	await _frames(20)
	_seen.clear()
	Input.action_press("move_forward")
	await _frames(30)
	_tap("jump")
	await _frames(12)
	_tap("jump")
	for i in 60:
		await physics_frame
		_note()
	_release_all()
	_check("double-tap jump flips", _saw("flip_"), "clips %s" % [_seen.keys()])
	await _frames(60)
	# sprint into the tall wall: run up it, Space backflips off
	_place(Vector3(-20, 0.1, 18), PI * 0.5)
	await _frames(20)
	_seen.clear()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var up_y := 0.0
	var flipped := false
	for i in 300:
		await physics_frame
		_note()
		if ninja.state == Ninja.State.WALL_UP:
			up_y = max(up_y, ninja.global_position.y)
			if up_y > 1.8 and not flipped:
				Input.action_press("move_back")
				_tap("jump")
				flipped = true
		if flipped and ninja.state == Ninja.State.GROUND:
			break
	_release_all()
	_check("run up the wall and backflip off", up_y > 1.8 and _seen.has("flip_back"), "clips %s  height %.1f" % [_seen.keys(), up_y])
	await _frames(60)
	# sprint at the 3 m pillar: run up and pull up onto it
	_place(Vector3(18, 0.1, 12.0), PI)
	await _frames(20)
	_seen.clear()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 400:
		await physics_frame
		_note()
		if ninja.global_position.y > 2.9 and ninja.state == Ninja.State.GROUND:
			break
	_release_all()
	_check("run up the pillar and climb onto it", ninja.global_position.y > 2.9 and _seen.has("wall_up_run"), "clips %s  at %s" % [_seen.keys(), _v(ninja.global_position)])
	await _frames(60)
	# slide under the long bar
	_place(Vector3(0, 0.1, -19), 0.0)
	await _frames(20)
	_seen.clear()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var slid := false
	for i in 260:
		await physics_frame
		_note()
		if not slid and ninja.global_position.z < -21.6:
			_tap("crouch")
			slid = true
		if ninja.global_position.z < -26.0:
			break
	_release_all()
	_check("roll under the long bar", ninja.global_position.z < -25.0 and ninja.global_position.y < 0.3, "clips %s  at %s" % [_seen.keys(), _v(ninja.global_position)])
	await _frames(30)
	# walk off the 16 m pillar: ragdoll, W gets up
	var m := current_scene.find_child("Station5", true, false) as Node3D
	_place(m.global_position, m.global_rotation.y)
	await _frames(30)
	_seen.clear()
	Input.action_press("move_forward")
	var downed := false
	for i in 500:
		await physics_frame
		_note()
		if ninja.state == Ninja.State.RAGDOLL:
			downed = true
		if downed and ninja.state == Ninja.State.GROUND:
			break
	_release_all()
	_check("big fall ragdolls, W gets up", downed and _saw("get_up") or _saw("kip_up"), "clips %s  state %s" % [_seen.keys(), ninja.state_name()])


# --- helpers ---

func _saw(prefix: String) -> bool:
	for k in _seen:
		if String(k).begins_with(prefix):
			return true
	return false


func _place(pos: Vector3, yaw: float) -> void:
	_release_all()
	ninja.teleport(Transform3D(Basis(Vector3.UP, yaw), pos))
	ninja.camera_rig.rotation.y = yaw


func _note() -> void:
	_seen[ninja.current_clip] = true
	if _record != "":
		_frame += 1
		if _frame % 4 == 0:
			var img := root.get_viewport().get_texture().get_image()
			img.resize(480, 270)
			img.save_png(_record.path_join("%04d.png" % (_frame / 4)))


func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "jump", "crouch"]:
		Input.action_release(a)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _flat_speed() -> float:
	return Vector2(ninja.velocity.x, ninja.velocity.z).length()


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s  (%s)" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		failures += 1


func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]
