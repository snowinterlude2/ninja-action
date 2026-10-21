extends SceneTree
## Renders a baked clip as a strip of frames seen from the side (and from behind), with its root motion applied,
## to check how a move really looks without playing. Needs a display (or xvfb-run) and a renderer:
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/filmstrip.gd -- <out dir> <clip> [clip...]
## Each clip is saved as <out dir>/<clip>.png: 8 frames across, side view on top, back view below.
## Add a box with --box=<height>,<depth>,<distance> to see a move against an obstacle.

const LIB := preload("res://assets/animations/ninja_locomotion.res")
const MODEL := preload("res://assets/characters/ninja/Ch45_nonPBR.fbx")
const FRAMES := 8
const SIZE := Vector2i(320, 360)

var _box := Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = SIZE
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.75, 0.8, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(-30), 0)
	world.add_child(sun)
	var floor := CSGBox3D.new()
	floor.size = Vector3(40, 0.1, 40)
	floor.position.y = -0.05
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 0.5, 0.52)
	floor.material = fm
	world.add_child(floor)
	var model: Node3D = MODEL.instantiate()
	world.add_child(model)
	# the game turns the model to face -Z
	model.rotation.y = PI
	var anim: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	anim.add_animation_library("n", LIB)
	var cam := Camera3D.new()
	cam.fov = 55
	world.add_child(cam)
	var obstacle: CSGBox3D
	for a in args.slice(1):
		if a.begins_with("--box="):
			var v := a.trim_prefix("--box=").split(",")
			if obstacle:
				obstacle.queue_free()
			obstacle = CSGBox3D.new()
			obstacle.size = Vector3(3, float(v[0]), float(v[1]))
			obstacle.position = Vector3(0, float(v[0]) * 0.5, -float(v[2]) - float(v[1]) * 0.5)
			var om := StandardMaterial3D.new()
			om.albedo_color = Color(0.9, 0.55, 0.2)
			om.albedo_color.a = 0.6
			om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			obstacle.material = om
			world.add_child(obstacle)
			continue
		var clip := a
		var full := "n/" + clip
		if not anim.has_animation(full):
			print("no clip ", clip)
			continue
		var a_res := anim.get_animation(full)
		var track := a_res.find_track(NodePath("RootMotion"), Animation.TYPE_POSITION_3D)
		var images: Array[Image] = []
		# a fixed camera that frames the whole path, so the travel shows
		var lo := Vector3(0, 0, 0)
		var hi := Vector3(0, 1.8, 0)
		for i in 21:
			var p := a_res.position_track_interpolate(track, a_res.length * i / 20.0) if track != -1 else Vector3.ZERO
			p = Vector3(-p.x, p.y, -p.z)
			lo = lo.min(p)
			hi = hi.max(p + Vector3.UP * 1.8)
		var centre := (lo + hi) * 0.5
		var reach: float = max(3.2, (hi - lo).length() * 1.1)
		for view in 2:
			for i in FRAMES:
				var t := a_res.length * i / float(FRAMES - 1)
				anim.play(full, 0.0)
				anim.seek(t, true)
				anim.pause()
				var rm := a_res.position_track_interpolate(track, t) if track != -1 else Vector3.ZERO
				# the model faces -Z, so the clip's forward (+Z) is world -Z
				model.position = Vector3(-rm.x, rm.y, -rm.z)
				cam.position = centre + (Vector3(reach, 0.3, 0) if view == 0 else Vector3(0, 0.6, reach + (hi.z - lo.z) * 0.5))
				cam.look_at(centre)
				for f in 3:
					await process_frame
				var img := root.get_viewport().get_texture().get_image()
				images.append(img)
		var sheet := Image.create(SIZE.x * FRAMES, SIZE.y * 2, false, images[0].get_format())
		for i in images.size():
			sheet.blit_rect(images[i], Rect2i(Vector2i.ZERO, SIZE), Vector2i((i % FRAMES) * SIZE.x, (i / FRAMES) * SIZE.y))
		sheet.save_png(out.path_join(clip + ".png"))
		print("saved ", clip)
	quit()
