## Headless check of the Soldier's repair clip (Deadnight #221): `Repair_Board` is added to the
## Soldier's own library (every track finds its bone), it loops seamlessly (its last frame is its
## first), the right hand travels and comes down to the board at `board_set` (the lowest point of
## the big blow), no leg bone turns (an upper-body clip), and through the upper-body filter the legs
## follow Walk while the arm follows the clip. Build the file first (docs/design/animation.md).
##
##     godot --headless --path game -s res://tests/art/check_repair.gd
## Prints LIBRARY:/CLIP:/LOOP:/BLOW:/SPLIT: lines and exits 1 on any failure.
extends SceneTree

const CLIPS_GLB := "res://assets/characters/soldier/repair/soldier_repair.glb"
const SPEC := "res://assets/characters/soldier/repair/clips.json"
const SOLDIER := "res://assets/characters/soldier/soldier.glb"
const SOLDIER_SPEC := "res://assets/characters/soldier/clips.json"
const CLIP := "Repair_Board"
const HAND := "Index1.R"
const LOWER := ["Hips", "UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R", "Foot.L", "Foot.R"]

var fails := 0


func _init() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	printerr(msg)
	fails += 1


func _run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var info: Dictionary = spec.clips[CLIP]
	var soldier: Node3D = (load(SOLDIER) as PackedScene).instantiate()
	root.add_child(soldier)
	var player: AnimationPlayer = soldier.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = soldier.find_child("Skeleton3D", true, false)
	_add_to_library(soldier, player, sk)
	_check_clip(player, sk, info, spec.fps)
	_check_split(soldier, player, sk)
	print("RESULT: ", "ok" if fails == 0 else "%d failures" % fails)
	quit(1 if fails else 0)


func _hand(sk: Skeleton3D) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(HAND)).origin


func _add_to_library(soldier: Node3D, player: AnimationPlayer, sk: Skeleton3D) -> void:
	var holder: Node = (load(CLIPS_GLB) as PackedScene).instantiate()
	var source: AnimationPlayer = holder.find_child("AnimationPlayer", true, false)
	var a := source.get_animation(CLIP).duplicate(true) as Animation
	holder.free()
	a.loop_mode = Animation.LOOP_LINEAR
	player.get_animation_library("").add_animation(CLIP, a)
	var missing := 0
	for i in a.get_track_count():
		var node := String(a.track_get_path(i)).get_slice(":", 0)
		if soldier.get_node_or_null(NodePath(node)) == null:
			missing += 1
		elif sk.find_bone(a.track_get_path(i).get_concatenated_subnames()) < 0:
			missing += 1
	print("LIBRARY: %s added to soldier.glb's library, %d tracks without a bone" % [CLIP, missing])
	if missing:
		_fail("repair clip tracks do not match the Soldier's skeleton")


func _check_clip(player: AnimationPlayer, sk: Skeleton3D, info: Dictionary, fps: float) -> void:
	var a := player.get_animation(CLIP)
	if absf(a.length - float(info.seconds)) > 0.05:
		_fail("LENGTH %.3f != %.3f" % [a.length, info.seconds])
	if not info.loop or info.layer != "upper":
		_fail("Repair_Board must be an upper-body loop")
	player.play(CLIP)
	var legs0: Array[Quaternion] = []
	player.seek(0.0, true)
	for b: String in LOWER:
		legs0.append(sk.get_bone_pose_rotation(sk.find_bone(b)))
	var first := _hand(sk)
	var path := 0.0
	var prev := first
	var legs_moved := 0.0
	var lowest_frame := 0
	var lowest := INF
	var frames := int(info.frames)
	for f in frames + 1:
		player.seek(f / fps, true)
		var h := _hand(sk)
		path += h.distance_to(prev)
		prev = h
		# The big blow: between the raise (frame 12) and the end, the lowest point of the fist.
		if f >= 12 and h.y < lowest - 0.001:
			lowest = h.y
			lowest_frame = f
		for i in LOWER.size():
			legs_moved = maxf(
				legs_moved, legs0[i].angle_to(sk.get_bone_pose_rotation(sk.find_bone(LOWER[i])))
			)
	var gap := first.distance_to(prev)
	print(
		(
			"CLIP: %s %d frames, %s, loop %s, hand path %.2f m, legs turn %.2f deg, events %s"
			% [CLIP, frames, info.layer, info.loop, path, rad_to_deg(legs_moved), info.events]
		)
	)
	print("LOOP: the hand's first and last frames are %.3f m apart" % gap)
	if path < 1.0:
		_fail("the hand barely moves")
	if legs_moved > 0.01:
		_fail("Repair_Board must leave the legs to the locomotion")
	if gap > 0.01:
		_fail("Repair_Board does not loop seamlessly")
	var board_set: int = info.events.board_set
	player.seek(12.0 / fps, true)
	var raised := _hand(sk).y
	print(
		(
			"BLOW: the fist is lowest at frame %d (board_set %d), %.2f m below the raise"
			% [lowest_frame, board_set, raised - lowest]
		)
	)
	if absi(lowest_frame - board_set) > 1:
		_fail("board_set is not the moment the fist comes down")
	if raised - lowest < 0.2:
		_fail("the blow is too small to read")
	player.stop()


func _check_split(soldier: Node3D, player: AnimationPlayer, sk: Skeleton3D) -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOLDIER_SPEC))
	var skel := String(soldier.get_path_to(sk))
	var tree := AnimationTree.new()
	soldier.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	var bt := AnimationNodeBlendTree.new()
	var lower := AnimationNodeAnimation.new()
	lower.animation = "Walk"
	var upper := AnimationNodeAnimation.new()
	upper.animation = CLIP
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
	tree.advance(0.375)
	var leg_turn := rad_to_deg(leg0.angle_to(sk.get_bone_pose_rotation(sk.find_bone("UpperLeg.R"))))
	var anim := player.get_animation(CLIP)
	var tr := anim.find_track(NodePath(skel + ":UpperArm.R"), Animation.TYPE_ROTATION_3D)
	var want: Quaternion = anim.rotation_track_interpolate(tr, 0.375)
	var err := rad_to_deg(sk.get_bone_pose_rotation(sk.find_bone("UpperArm.R")).angle_to(want))
	print(
		"SPLIT: legs follow Walk by %.1f deg; UpperArm.R off %s by %.2f deg" % [leg_turn, CLIP, err]
	)
	if leg_turn < 5.0 or err > 2.0:
		_fail("the upper/lower split does not hold for the repair clip")
	tree.queue_free()
