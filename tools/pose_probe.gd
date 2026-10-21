extends SceneTree
## Prints where the hands and feet are relative to the hips (character space: +X = character's left, +Z = forward)
## and which way the hips' up axis points, through a source clip. For checking which side a wall move is shot for,
## or whether a move turns the body upside down.
##   godot --headless --script res://tools/pose_probe.gd -- diagonal_wall_run vaulting_2

const SRC := "res://assets/animations/source/"
const P := "mixamorig1_"


func _init() -> void:
	for clip in OS.get_cmdline_user_args():
		var scene: Node = load(SRC + clip + ".fbx").instantiate()
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		var a_name: String = ap.get_animation_list()[0]
		var a := ap.get_animation(a_name)
		print("== %s (%.2fs)" % [clip, a.length])
		for i in 9:
			var t := a.length * i / 8.0
			var g := _pose(sk, a, scene.get_path_to(sk), t)
			var hips := g[sk.find_bone(P + "Hips")]
			var line := "t=%.2f hips=%s up=%s fwd=%s" % [t, _v(hips.origin), _v(hips.basis.y.normalized()), _v(hips.basis.z.normalized())]
			for b in ["LeftFoot", "RightFoot", "LeftHand", "RightHand"]:
				line += " %s=%s" % [b, _v(g[sk.find_bone(P + b)].origin - hips.origin)]
			print(line)
		scene.free()
	quit()


## The clip's global bone transforms at time t, worked out straight from its tracks.
func _pose(sk: Skeleton3D, a: Animation, sk_path: NodePath, t: float) -> Array[Transform3D]:
	var local: Array[Transform3D] = []
	for b in sk.get_bone_count():
		local.append(sk.get_bone_rest(b))
	for tr in a.get_track_count():
		var path := a.track_get_path(tr)
		if String(path.get_concatenated_names()) != String(sk_path):
			continue
		var b := sk.find_bone(String(path.get_concatenated_subnames()))
		if b == -1:
			continue
		match a.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				local[b].basis = Basis(a.rotation_track_interpolate(tr, t))
			Animation.TYPE_POSITION_3D:
				local[b].origin = a.position_track_interpolate(tr, t)
	var global: Array[Transform3D] = []
	for b in sk.get_bone_count():
		var parent := sk.get_bone_parent(b)
		global.append(global[parent] * local[b] if parent != -1 else local[b])
	return global


func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
