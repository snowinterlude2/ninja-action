extends SceneTree
## Prints every source clip's length, how far the hips travel (root motion or in place) and its bone prefix.
##   godot --headless --script res://tools/inspect_clips.gd

const SRC := "res://assets/animations/source/"


func _init() -> void:
	for f in DirAccess.get_files_at(SRC):
		if not f.ends_with(".fbx"):
			continue
		var scene: Node = load(SRC + f).instantiate()
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		var meshes := scene.find_children("*", "MeshInstance3D", true, false).size()
		for a_name in ap.get_animation_list():
			var a := ap.get_animation(a_name)
			var hips := a.find_track(NodePath("%s:mixamorig1_Hips" % scene.get_path_to(sk)), Animation.TYPE_POSITION_3D)
			var travel := Vector3.ZERO
			if hips != -1 and a.track_get_key_count(hips) > 1:
				travel = a.track_get_key_value(hips, a.track_get_key_count(hips) - 1) - a.track_get_key_value(hips, 0)
			print("%-32s %-20s len=%.2f meshes=%d hips_travel=%s" % [f, a_name, a.length, meshes, travel])
		scene.free()
	quit()
