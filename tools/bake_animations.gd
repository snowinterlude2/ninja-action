extends SceneTree
## Bakes the Mixamo clips in assets/animations/source/ into one AnimationLibrary (assets/animations/ninja_locomotion.res).
## For each clip it renames it, sets looping, and splits the hips' travel off the hips:
##   INPLACE  - drops the hips' sideways and forward travel (keeps the bob), for loops the code moves.
##   AIR      - also drops the hips' rise and fall, so jumps don't double the physics arc.
##   ROOT     - moves the travel onto a "RootMotion" track that the controller reads and applies to the body, and
##              takes the hips' turn off them too (onto a RootMotion rotation track), so the body stays facing
##              the way the move goes instead of ending sideways.
## Clips listed in MIRRORED also get a flipped copy (left and right bones swapped, motion mirrored sideways).
## Run headless after importing:
##   godot --headless --import ; godot --headless --script res://tools/bake_animations.gd

enum { INPLACE, AIR, ROOT, ROOT_Y }

const SRC := "res://assets/animations/source/"
const OUT := "res://assets/animations/ninja_locomotion.res"
const SKELETON := "Skeleton3D"
const PREFIX := "mixamorig1_"
const HIPS := PREFIX + "Hips"
## Where root motion lands. A Node3D with this name sits under the ninja's model root.
const ROOT_TRACK := "RootMotion"
const FPS := 30.0

## Clip name in the game -> [source file, mode, loops]. ROOT_Y also moves the hips' height onto the root track
## (vaults and wall moves, where the body really goes up and over).
const CLIPS := {
	"idle": ["mlp_idle", INPLACE, true],
	"walk": ["mlp_walking", INPLACE, true],
	"run": ["mlp_standard_run", INPLACE, true],
	"run_alt": ["aap_running", INPLACE, true],
	"sprint": ["sprint", INPLACE, true],
	"strafe_walk_l": ["mlp_left_strafe_walking", INPLACE, true],
	"strafe_walk_r": ["mlp_right_strafe_walking", INPLACE, true],
	"strafe_run_l": ["mlp_left_strafe", INPLACE, true],
	"strafe_run_r": ["mlp_right_strafe", INPLACE, true],
	"crouch_walk_l": ["aap_crouched_sneaking_left", INPLACE, true],
	"crouch_walk_r": ["crouched_sneaking_right", INPLACE, true],
	"turn_l": ["mlp_left_turn_90", INPLACE, false],
	"turn_r": ["mlp_right_turn_90", INPLACE, false],
	"start_walk": ["start_walking", ROOT, false],
	"run_stop": ["aap_run_to_stop", ROOT, false],
	"run_turn": ["running_to_turn", ROOT, false],
	"change_direction": ["change_direction", ROOT, false],
	"crouch_down": ["standing_to_crouched", INPLACE, false],
	"crouch_up": ["crouch_to_stand", INPLACE, false],
	"jump_idle": ["mlp_jump", AIR, false],
	"jump_up": ["aap_jumping_up", AIR, false],
	"jump_run": ["running_jump", AIR, false],
	"jump_big": ["big_jump", AIR, false],
	"jump_flip": ["jumping", AIR, false],
	"fall": ["aap_falling_idle", AIR, true],
	"jump_down": ["jumping_down", ROOT_Y, false],
	"land_roll": ["aap_falling_to_roll", ROOT, false],
	"land_hard": ["aap_hard_landing", ROOT, false],
	"roll": ["stand_to_roll", ROOT, false],
	"roll_side": ["rolling", ROOT, false],
	"slide": ["sliding", ROOT, false],
	"vault_high": ["vaulting", ROOT_Y, false],
	"vault": ["vaulting_2", ROOT_Y, false],
	"wall_run": ["diagonal_wall_run", ROOT_Y, false],
	"wall_jump": ["jump_from_wall", ROOT_Y, false],
	"wall_flip": ["run_wall_flip", ROOT_Y, false],
}
## Clip -> name of its flipped copy.
const MIRRORED := {
	"wall_run": "wall_run_mirror",
	"wall_jump": "wall_jump_mirror",
	"vault": "vault_mirror",
	"vault_high": "vault_high_mirror",
	"run_turn": "run_turn_mirror",
	"roll_side": "roll_side_mirror",
}


func _init() -> void:
	var lib := AnimationLibrary.new()
	for clip_name in CLIPS:
		var info: Array = CLIPS[clip_name]
		var scene: Node = load(SRC + info[0] + ".fbx").instantiate()
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var sk: Skeleton3D = scene.get_node(SKELETON)
		var src := ap.get_animation(ap.get_animation_list()[0])
		var anim := _bake(src, sk, info[1])
		anim.loop_mode = Animation.LOOP_LINEAR if info[2] else Animation.LOOP_NONE
		lib.add_animation(clip_name, anim)
		if MIRRORED.has(clip_name):
			var m := _mirror(anim, sk)
			m.loop_mode = anim.loop_mode
			lib.add_animation(MIRRORED[clip_name], m)
		scene.free()
		print("baked %s (%.2fs)" % [clip_name, anim.length])
	var err := ResourceSaver.save(lib, OUT)
	print("saved %s: %s" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)


## Resamples every bone at FPS, so the mirror step and the root split work on matching keys.
func _bake(src: Animation, sk: Skeleton3D, mode: int) -> Animation:
	var anim := Animation.new()
	anim.length = src.length
	var frames := int(round(src.length * FPS))
	var hips_rest := sk.get_bone_rest(sk.find_bone(HIPS)).origin
	var hips_pos := src.find_track(NodePath(SKELETON + ":" + HIPS), Animation.TYPE_POSITION_3D)
	var start := src.position_track_interpolate(hips_pos, 0.0) if hips_pos != -1 else hips_rest
	var root := -1
	var root_rot := -1
	var hips_rot := src.find_track(NodePath(SKELETON + ":" + HIPS), Animation.TYPE_ROTATION_3D)
	var start_rot := src.rotation_track_interpolate(hips_rot, 0.0) if hips_rot != -1 else Quaternion()
	if mode == ROOT or mode == ROOT_Y:
		root = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(root, NodePath(ROOT_TRACK))
		root_rot = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(root_rot, NodePath(ROOT_TRACK))
	for t in src.get_track_count():
		var type := src.track_get_type(t)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(src.track_get_path(t).get_concatenated_subnames())
		# only the hips keep a position track; other bones' translation never changes in Mixamo clips
		if type == Animation.TYPE_POSITION_3D and bone != HIPS:
			continue
		var nt := anim.add_track(type)
		anim.track_set_path(nt, src.track_get_path(t))
		for f in frames + 1:
			var time: float = min(f / FPS, src.length)
			if type == Animation.TYPE_ROTATION_3D:
				var q := src.rotation_track_interpolate(t, time)
				if root_rot != -1 and t == hips_rot:
					# the hips' turn since the first frame (its twist around up) goes to the root track
					var rel := q * start_rot.inverse()
					var yaw := Quaternion(0.0, rel.y, 0.0, rel.w).normalized()
					q = yaw.inverse() * q
					anim.rotation_track_insert_key(root_rot, time, yaw)
				anim.rotation_track_insert_key(nt, time, q)
				continue
			var p := src.position_track_interpolate(t, time)
			var travel := p - start
			var keep := Vector3(start.x, p.y, start.z)
			var moved := Vector3(travel.x, 0.0, travel.z)
			if mode == AIR:
				keep.y = start.y
			elif mode == ROOT_Y:
				keep.y = start.y
				moved.y = travel.y
			anim.position_track_insert_key(nt, time, keep)
			if root != -1:
				anim.position_track_insert_key(root, time, moved)
	return anim


## Mirrors across the character's side-to-side axis (X). Each bone takes its left/right twin's pose, reflected,
## and is corrected by its rest pose so the result is a proper rotation in the bone's own axes.
func _mirror(src: Animation, sk: Skeleton3D) -> Animation:
	var anim := Animation.new()
	anim.length = src.length
	var flip := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	var count := sk.get_bone_count()
	var rest_global: Array[Basis] = []
	for b in count:
		rest_global.append(sk.get_bone_global_rest(b).basis)
	var twin := PackedInt32Array()
	for b in count:
		var n := sk.get_bone_name(b)
		var other := n.replace("Left", "@").replace("Right", "Left").replace("@", "Right")
		twin.append(sk.find_bone(other) if sk.find_bone(other) != -1 else b)
	var rot_track := {}
	var tracks := {}
	for t in src.get_track_count():
		var path := src.track_get_path(t)
		var nt := anim.add_track(src.track_get_type(t))
		anim.track_set_path(nt, path)
		tracks[t] = nt
		if src.track_get_type(t) == Animation.TYPE_ROTATION_3D and path.get_subname_count() > 0:
			rot_track[sk.find_bone(String(path.get_concatenated_subnames()))] = t
	var key_count := src.track_get_key_count(rot_track.values()[0])
	for k in key_count:
		var time := src.track_get_key_time(rot_track.values()[0], k)
		# this frame's global bone rotations
		var global: Array[Basis] = []
		for b in count:
			var local := Basis(src.rotation_track_interpolate(rot_track[b], time)) if rot_track.has(b) else sk.get_bone_rest(b).basis
			var parent := sk.get_bone_parent(b)
			global.append(global[parent] * local if parent != -1 else local)
		var mirrored: Array[Basis] = []
		for b in count:
			var tw := twin[b]
			mirrored.append(flip * global[tw] * rest_global[tw].inverse() * flip * rest_global[b])
		for b in count:
			if not rot_track.has(b):
				continue
			var parent := sk.get_bone_parent(b)
			var local := mirrored[parent].inverse() * mirrored[b] if parent != -1 else mirrored[b]
			anim.rotation_track_insert_key(tracks[rot_track[b]], time, local.get_rotation_quaternion())
	for t in src.get_track_count():
		if src.track_get_type(t) == Animation.TYPE_ROTATION_3D and src.track_get_path(t).get_subname_count() == 0:
			# the root's turn, reflected: a turn to the left becomes a turn to the right
			for k in src.track_get_key_count(t):
				var q: Quaternion = src.track_get_key_value(t, k)
				anim.rotation_track_insert_key(tracks[t], src.track_get_key_time(t, k), Quaternion(q.x, -q.y, -q.z, q.w))
			continue
		if src.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		for k in src.track_get_key_count(t):
			var p: Vector3 = src.track_get_key_value(t, k)
			anim.position_track_insert_key(tracks[t], src.track_get_key_time(t, k), Vector3(-p.x, p.y, p.z))
	return anim
