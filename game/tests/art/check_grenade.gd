## Headless check of the grenade art (Deadnight #102, for the grenades of #99): the model has its
## held and far levels within budget with the Pin and Spoon as their own nodes, and each grenade
## clip plays on the Soldier: the right hand moves, the legs do not (upper-body clips), at
## `release` the hand is moving forward (up and forward for the overhand throw), and through the
## upper-body filter the legs follow Run while the arm follows the clip. When the Soldier with the
## weapon clips is in the tree (#90), the grenade clips are also added to its library and every
## track must find its bone. Build the files first (docs/design/animation.md, Rebuilding).
##
##     godot --headless --path game -s res://tests/art/check_grenade.gd
## Prints MODEL:/CLIP:/RELEASE:/SPLIT:/LIBRARY: lines and exits 1 on any failure.
extends SceneTree

const GRENADE := "res://assets/weapons/grenade/grenade.glb"
const GRENADE_FAR := "res://assets/weapons/grenade/grenade_far.glb"
const CLIPS_GLB := "res://assets/characters/soldier/grenade/soldier_grenade.glb"
const SPEC := "res://assets/characters/soldier/grenade/clips.json"
const SOLDIER := "res://assets/characters/soldier/soldier.glb"
const SOLDIER_SPEC := "res://assets/characters/soldier/clips.json"
const BUDGET := {GRENADE: 1500, GRENADE_FAR: 500}  # world weapon and far level (style bible)
const HAND := "Index1.R"
const LOWER := ["Hips", "UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R", "Foot.L", "Foot.R"]

var fails := 0


func _init() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	printerr(msg)
	fails += 1


func _run() -> void:
	_check_model()
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var soldier: Node3D = (load(CLIPS_GLB) as PackedScene).instantiate()
	root.add_child(soldier)
	var player: AnimationPlayer = soldier.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = soldier.find_child("Skeleton3D", true, false)
	for clip: String in spec.clips:
		_check_clip(player, sk, clip, spec.clips[clip], spec.fps)
	_check_split(soldier, player, sk, spec)
	_check_library(player)
	print("RESULT: ", "ok" if fails == 0 else "%d failures" % fails)
	quit(1 if fails else 0)


func _tris(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			n += (
				idx.size() / 3
				if idx.size()
				else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			)
	for c in node.get_children():
		n += _tris(c)
	return n


func _check_model() -> void:
	for path: String in BUDGET:
		var g: Node3D = (load(path) as PackedScene).instantiate()
		var pin := g.find_child("Pin", true, false) as Node3D
		var spoon := g.find_child("Spoon", true, false) as Node3D
		var tris := _tris(g)
		print(
			(
				"MODEL: %s %d tris (budget %d), Pin %s, Spoon %s"
				% [path.get_file(), tris, BUDGET[path], pin != null, spoon != null]
			)
		)
		if pin == null or spoon == null or not pin is MeshInstance3D or not spoon is MeshInstance3D:
			_fail("the pin and the spoon must be their own mesh nodes in " + path)
		elif pin.get_parent() == g or spoon.get_parent() == g:
			_fail("the pin and spoon hang under the grenade's mesh node, not the scene root")
		if tris > BUDGET[path]:
			_fail("over budget: " + path)
		g.free()


func _hand(sk: Skeleton3D) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(HAND)).origin


func _check_clip(
	player: AnimationPlayer, sk: Skeleton3D, clip: String, info: Dictionary, fps: float
) -> void:
	if not player.has_animation(clip):
		_fail("MISSING clip " + clip)
		return
	var a := player.get_animation(clip)
	if absf(a.length - float(info.seconds)) > 0.05:
		_fail("LENGTH %s %.3f != %.3f" % [clip, a.length, info.seconds])
	player.play(clip)
	var path := 0.0
	var prev := Vector3.ZERO
	var legs_moved := 0.0
	var legs0: Array[Quaternion] = []
	for b: String in LOWER:
		player.seek(0.0, true)
		legs0.append(sk.get_bone_pose_rotation(sk.find_bone(b)))
	var steps := int(info.frames)
	for f in steps + 1:
		player.seek(f / fps, true)
		var h := _hand(sk)
		if f > 0:
			path += h.distance_to(prev)
		prev = h
		for i in LOWER.size():
			legs_moved = maxf(
				legs_moved, legs0[i].angle_to(sk.get_bone_pose_rotation(sk.find_bone(LOWER[i])))
			)
	print(
		(
			"CLIP: %s %d frames, %s, hand path %.2f m, legs turn %.2f deg, events %s"
			% [clip, steps, info.layer, path, rad_to_deg(legs_moved), info.events]
		)
	)
	if path < 0.5:
		_fail("the hand barely moves in " + clip)
	if legs_moved > 0.01 or info.layer != "upper":
		_fail(clip + " must be upper body only (legs keep running)")
	if info.events.has("release"):
		var r: float = info.events.release
		player.seek((r - 1) / fps, true)
		var before := _hand(sk)
		player.seek((r + 1) / fps, true)
		var after := _hand(sk)
		player.seek(r / fps, true)
		var at := _hand(sk)
		var v := (after - before) * fps / 2.0
		var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
		# The Soldier faces +Z in Godot (Blender's -Y).
		print(
			(
				"RELEASE: %s frame %d, hand %s (head at %.2f m), hand velocity %s m/s"
				% [clip, r, at, head.y, v]
			)
		)
		if v.z <= 0.5:
			_fail(clip + ": the hand is not moving forward at release")
		if clip == "Grenade_Throw" and at.y < head.y - 0.3:
			_fail("the overhand throw lets go below the head")
		if clip == "Grenade_Toss" and at.y > head.y - 0.3:
			_fail("the underarm toss lets go above the chest")
	player.stop()


func _check_split(
	soldier: Node3D, player: AnimationPlayer, sk: Skeleton3D, spec: Dictionary
) -> void:
	var tree := AnimationTree.new()
	soldier.add_child(tree)
	var lib := AnimationLibrary.new()
	# The clips file has no locomotion: borrow a leg motion (Grenade_Toss's own legs are still),
	# so build a two-key Run-like stride on UpperLeg.R.
	var stride := Animation.new()
	var skel := String(soldier.get_path_to(sk))
	var t := stride.add_track(Animation.TYPE_ROTATION_3D)
	stride.track_set_path(t, NodePath(skel + ":UpperLeg.R"))
	var rest := sk.get_bone_pose_rotation(sk.find_bone("UpperLeg.R"))
	stride.rotation_track_insert_key(t, 0.0, rest)
	stride.rotation_track_insert_key(t, 0.5, rest * Quaternion(Vector3.RIGHT, 0.6))
	stride.length = 0.5
	lib.add_animation("Stride", stride)
	player.add_animation_library("check", lib)
	tree.anim_player = tree.get_path_to(player)
	var bt := AnimationNodeBlendTree.new()
	var lower := AnimationNodeAnimation.new()
	lower.animation = "check/Stride"
	var upper := AnimationNodeAnimation.new()
	upper.animation = "Grenade_Throw"
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	for b: String in spec.upper_bones:
		blend.set_filter_path(NodePath(skel + ":" + b), true)
	bt.add_node("lower", lower)
	bt.add_node("upper", upper)
	bt.add_node("split", blend)
	bt.connect_node("split", 0, "lower")
	bt.connect_node("split", 1, "upper")
	bt.connect_node("output", 0, "split")
	tree.tree_root = bt
	tree.set("parameters/split/blend_amount", 1.0)
	tree.active = true
	tree.advance(0.0)
	var leg0 := sk.get_bone_pose_rotation(sk.find_bone("UpperLeg.R"))
	tree.advance(0.375)  # frame 9 of the throw: release
	var leg_turn := rad_to_deg(leg0.angle_to(sk.get_bone_pose_rotation(sk.find_bone("UpperLeg.R"))))
	var anim := player.get_animation("Grenade_Throw")
	var tr := anim.find_track(NodePath(skel + ":UpperArm.R"), Animation.TYPE_ROTATION_3D)
	var want: Quaternion = anim.rotation_track_interpolate(tr, 0.375)
	var err := rad_to_deg(sk.get_bone_pose_rotation(sk.find_bone("UpperArm.R")).angle_to(want))
	print(
		(
			"SPLIT: legs follow the lower layer by %.1f deg; UpperArm.R off Grenade_Throw by %.2f deg"
			% [leg_turn, err]
		)
	)
	if leg_turn < 5.0 or err > 2.0:
		_fail("the upper/lower split does not hold for the grenade clips")
	tree.queue_free()


func _check_library(clips_player: AnimationPlayer) -> void:
	if not FileAccess.file_exists(SOLDIER_SPEC):
		print("LIBRARY: skipped (the Soldier with weapon clips, #90, is not in this tree yet)")
		return
	var soldier: Node3D = (load(SOLDIER) as PackedScene).instantiate()
	root.add_child(soldier)
	var player: AnimationPlayer = soldier.find_child("AnimationPlayer", true, false)
	var lib := player.get_animation_library("")
	var missing := 0
	var added := 0
	for clip in clips_player.get_animation_list():
		if not clip.begins_with("Grenade_"):
			continue
		var a := clips_player.get_animation(clip)
		lib.add_animation(clip, a)
		added += 1
		for i in a.get_track_count():
			if (
				soldier.get_node_or_null(NodePath(String(a.track_get_path(i)).get_slice(":", 0)))
				== null
			):
				missing += 1
				continue
			var sk: Skeleton3D = soldier.find_child("Skeleton3D", true, false)
			if sk.find_bone(a.track_get_path(i).get_concatenated_subnames()) < 0:
				missing += 1
	player.play("Grenade_Throw")
	player.advance(0.2)
	print(
		(
			"LIBRARY: %d grenade clips added to soldier.glb's library, %d tracks without a bone"
			% [added, missing]
		)
	)
	if missing:
		_fail("grenade clip tracks do not match the Soldier's skeleton")
	soldier.queue_free()
