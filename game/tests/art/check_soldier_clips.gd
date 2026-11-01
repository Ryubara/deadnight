## Headless check of the Soldier's clips (Deadnight #42): every clip in clips.json is in
## soldier.glb with its length, Idle holds the arms down (the kit clips leave them unkeyed; the
## export bakes the file's static pose into them), and an upper clip over a locomotion clip
## through the upper-body bone filter takes the arms from one and the legs from the other.
## Build the .glb first (docs/design/animation.md, Rebuilding).
##
##     godot --headless --path game -s res://tests/art/check_soldier_clips.gd
## Prints CLIPS:/POSE:/SPLIT: lines and exits 1 on any failure.
extends SceneTree

const GLB := "res://assets/characters/soldier/soldier.glb"
const SPEC := "res://assets/characters/soldier/clips.json"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var soldier: Node3D = (load(GLB) as PackedScene).instantiate()
	root.add_child(soldier)
	var player: AnimationPlayer = soldier.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = soldier.find_child("Skeleton3D", true, false)
	var names := player.get_animation_list()
	for clip: String in spec.clips:
		if not player.has_animation(clip):
			printerr("MISSING clip ", clip)
			fails += 1
			continue
		var a := player.get_animation(clip)
		var want: float = spec.clips[clip].seconds
		if absf(a.length - want) > 0.05:
			printerr("LENGTH ", clip, " ", a.length, " != ", want)
			fails += 1
	print(
		"CLIPS: ",
		names.size(),
		" in the file, ",
		spec.clips.size(),
		" in clips.json, bones ",
		sk.get_bone_count()
	)
	# Bones a kit clip does not move must hold the standing pose (arms down), not the skeleton
	# rest, which the exporter writes from Blender's rest pose (arms out). The skeleton's up axis
	# is Z (the armature node turns it).
	var hand := sk.find_bone("Index1.L")
	var shoulder := sk.find_bone("UpperArm.L")
	var rest_drop := (
		sk.get_bone_global_rest(shoulder).origin.z - sk.get_bone_global_rest(hand).origin.z
	)
	player.play("Idle")
	player.advance(0.0)
	var idle_drop := (
		sk.get_bone_global_pose(shoulder).origin.z - sk.get_bone_global_pose(hand).origin.z
	)
	player.stop()
	print(
		(
			"POSE: left hand below the shoulder: rest %.2f m, Idle %.2f m (arms down if > 0.3)"
			% [rest_drop, idle_drop]
		)
	)
	if idle_drop <= 0.3:
		printerr("Idle leaves the arms out")
		fails += 1
	# Upper/lower split: Blend2 at 1.0 with the upper bones filtered: Run legs, Aim_Rifle arms.
	var tree := AnimationTree.new()
	soldier.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	var bt := AnimationNodeBlendTree.new()
	var lower := AnimationNodeAnimation.new()
	lower.animation = "Run"
	var upper := AnimationNodeAnimation.new()
	upper.animation = "Aim_Rifle"
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	var skel_path := String(soldier.get_path_to(sk))
	for b: String in spec.upper_bones:
		blend.set_filter_path(NodePath(skel_path + ":" + b), true)
	bt.add_node("lower", lower)
	bt.add_node("upper", upper)
	bt.add_node("split", blend)
	bt.connect_node("split", 0, "lower")
	bt.connect_node("split", 1, "upper")
	bt.connect_node("output", 0, "split")
	tree.tree_root = bt
	tree.set("parameters/split/blend_amount", 1.0)
	tree.active = true
	var leg := sk.find_bone("UpperLeg.R")
	var arm := sk.find_bone("UpperArm.R")
	var legs: Array[Quaternion] = []
	var arms: Array[Quaternion] = []
	for i in 6:
		tree.advance(0.1)
		legs.append(sk.get_bone_pose_rotation(leg))
		arms.append(sk.get_bone_pose_rotation(arm))
	var leg_moves: bool = legs[0].angle_to(legs[3]) > 0.05
	var aim := player.get_animation("Aim_Rifle")
	var t := aim.find_track(NodePath(skel_path + ":UpperArm.R"), Animation.TYPE_ROTATION_3D)
	var want_arm: Quaternion = aim.rotation_track_interpolate(t, 0.6) if t >= 0 else Quaternion()
	var arm_err := rad_to_deg(arms[5].angle_to(want_arm))
	print(
		"SPLIT: legs move with Run %s; UpperArm.R off Aim_Rifle by %.2f deg" % [leg_moves, arm_err]
	)
	if not leg_moves or arm_err > 2.0:
		fails += 1
	print("RESULT: ", "ok" if fails == 0 else "%d failures" % fails)
	quit(1 if fails else 0)
