extends SceneTree
## Saves screenshots of the ninja posed in key clips around the test map, to check the model, the mirrored
## clips and the camera without playing. Needs a display (or xvfb-run) and a renderer:
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/screenshots.gd -- <out dir>

## [file name, ninja position, yaw, clip, fraction of the clip, camera yaw offset]
const SHOTS := [
	["01_overview_idle", Vector3(0, 0, 0), 0.0, "idle", 0.2, 0.6],
	["02_run", Vector3(-14, 0, -6), 0.0, "run", 0.3, 0.9],
	["03_vault", Vector3(-14, 0.2, -14.9), 0.0, "vault", 0.45, 1.4],
	["04_wall_run_left_wall", Vector3(1.7, 1.2, 14), PI, "wall_run", 0.35, -0.3],
	["05_wall_run_right_wall_mirror", Vector3(-1.7, 1.2, 14), PI, "wall_run_mirror", 0.35, 0.3],
	["06_land_roll", Vector3(22, 0, 22), PI, "land_roll", 0.4, 1.2],
	["07_slide", Vector3(6, 0, 6), 0.0, "slide", 0.4, 1.3],
]


func _initialize() -> void:
	var map: Node = load("res://scenes/test_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	_run.call_deferred(map.get_node("Ninja"))


func _run(ninja: Ninja) -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	ninja.set_physics_process(false)
	var anim: AnimationPlayer = ninja.get_node("Model/AnimationPlayer")
	var rig: Node3D = ninja.camera_rig
	for shot in SHOTS:
		ninja.global_transform = Transform3D(Basis(Vector3.UP, shot[2]), shot[1])
		rig.rotation.y = shot[2] + shot[5]
		rig.global_position = shot[1] + Vector3.UP * rig.follow_height
		var clip: String = Ninja.LIB_NAME + "/" + shot[3]
		anim.play(clip, 0.0)
		anim.seek(anim.get_animation(clip).length * shot[4], true)
		anim.pause()
		for i in 12:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out.path_join(shot[0] + ".png"))
		print("saved ", shot[0])
	quit()
