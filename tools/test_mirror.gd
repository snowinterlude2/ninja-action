extends SceneTree
## Checks the mirror step: the flipped left strafe should match the real right strafe (same Mixamo pack).
## Prints the average and worst gap between matching bone positions, in meters.
##   godot --headless --script res://tools/test_mirror.gd

const Bake := preload("res://tools/bake_animations.gd")


func _init() -> void:
	var lib: AnimationLibrary = load(Bake.OUT)
	var scene: Node = load("res://assets/characters/ninja/Ch45_nonPBR.fbx").instantiate()
	var sk: Skeleton3D = scene.get_node(Bake.SKELETON)
	var baker = Bake.new()
	var mirrored: Animation = baker._mirror(lib.get_animation("strafe_run_l"), sk)
	var real := lib.get_animation("strafe_run_r")
	var src := lib.get_animation("strafe_run_l")
	# 1) by definition: each bone of the flip sits where its twin was, reflected across X
	var worst_def := 0.0
	for i in 10:
		var t := src.length * i / 10.0
		var a := _pose(mirrored, sk, t)
		var o := _pose(src, sk, t)
		for b in a.size():
			var tw := sk.find_bone(sk.get_bone_name(b).replace("Left", "@").replace("Right", "Left").replace("@", "Right"))
			tw = b if tw == -1 else tw
			worst_def = max(worst_def, a[b].distance_to(Vector3(-o[tw].x, o[tw].y, o[tw].z)))
	print("mirror check: worst gap to the reflected original %.4f m" % worst_def)
	# 2) against the real right strafe, at the best phase offset (the two clips may start on different feet)
	var best := INF
	var best_off := 0.0
	for j in 20:
		var off := real.length * j / 20.0
		var total := 0.0
		var n := 0
		for i in 10:
			var t := real.length * i / 10.0
			var a := _pose(mirrored, sk, fmod(t + off, real.length))
			var b := _pose(real, sk, t)
			for k in a.size():
				total += a[k].distance_to(b[k])
				n += 1
		if total / n < best:
			best = total / n
			best_off = off
	print("vs real right strafe: average gap %.3f m at offset %.2f s" % [best, best_off])
	scene.free()
	quit()


func _pose(anim: Animation, sk: Skeleton3D, time: float) -> PackedVector3Array:
	var global: Array[Transform3D] = []
	var out := PackedVector3Array()
	for b in sk.get_bone_count():
		var path := NodePath("Skeleton3D:" + sk.get_bone_name(b))
		var r := anim.find_track(path, Animation.TYPE_ROTATION_3D)
		var p := anim.find_track(path, Animation.TYPE_POSITION_3D)
		var local := sk.get_bone_rest(b)
		if r != -1:
			local.basis = Basis(anim.rotation_track_interpolate(r, time))
		if p != -1:
			local.origin = anim.position_track_interpolate(p, time)
		var parent := sk.get_bone_parent(b)
		global.append(global[parent] * local if parent != -1 else local)
		out.append(global[b].origin)
	return out
