class_name ClipFit
extends RefCounted
## Samples the clips the player plays on a dressed Soldier and finds limbs and garments inside the
## body (Deadnight #895): a hand or forearm inside the trunk, the head, the legs or the other arm;
## hair, a hat, glasses or neckwear inside the trunk and shoulders; an armband inside the trunk.
## Each is a vertex of one group of bones inside the surface of the others deeper than `TOLERANCE`
## (`BodyFit.vertices_inside`). Docs: docs/research/soldier-parts.md, "Fit".

## How deep a vertex may sink into another part of the body, metres (the model's own scale, the
## kit's: 0.8 of it in the game). The kit's clips lay a hand on a thigh or the chest; skin touching
## skin is not a fault.
const TOLERANCE := 0.03
## Frames sampled in each clip, spread over its length. Four missed key poses between them (a windup
## at a quarter of a clip, #939).
const SAMPLES := 8
## The checks: name, the groups whose vertices move, the meshes they are taken from (every mesh
## when empty), the groups they must stay out of.
const CHECKS := [
	[
		"left arm",
		["hand.L", "forearm.L"],
		[],
		["trunk", "head", "thigh.L", "thigh.R", "shin.L", "shin.R", "hand.R", "forearm.R"],
	],
	[
		"right arm",
		["hand.R", "forearm.R"],
		[],
		["trunk", "head", "thigh.L", "thigh.R", "shin.L", "shin.R", "hand.L", "forearm.L"],
	],
	# The trunk only: the quick strikes swing the upper arm across the chest, through a bow tie.
	["head pieces", ["head"], ["hair__", "headwear__", "eyewear__", "neck__"], ["trunk"]],
	["armbands", ["upper_arm.L", "upper_arm.R"], ["arm__", "Armband"], ["trunk"]],
]

var _fit: BodyFit
var _player: AnimationPlayer
var _skeleton: Skeleton3D


func _init(fit: BodyFit, model: Node) -> void:
	_fit = fit
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	add_player_clips(_player)


## Puts the clips of the player's own files into the model's library, as `PlayerAnimation` does.
static func add_player_clips(anim_player: AnimationPlayer) -> void:
	var library := anim_player.get_animation_library(&"")
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerAnimation.SPEC))
	var files := [
		[PlayerAnimation.REPAIR_GLB, PlayerAnimation.REPAIR_SPEC, [PlayerAnimation.REPAIR_CLIP]],
		[PlayerAnimation.GRENADE_GLB, PlayerAnimation.GRENADE_SPEC, PlayerAnimation.GRENADE_CLIPS],
		[
			PlayerAnimation.AIM_MOVE_GLB,
			PlayerAnimation.AIM_MOVE_SPEC,
			PlayerAnimation.AIM_MOVES.keys()
		],
		[PlayerAnimation.SPRINT_GLB, PlayerAnimation.SPRINT_SPEC, SprintCarry.CLIPS],
		[QuickStrike.GLB, QuickStrike.SPEC, QuickStrike.CLIPS],
		[DualClips.GLB, DualClips.SPEC, DualClips.CLIPS],
		[DrinkLayer.GLB, DrinkLayer.SPEC, [DrinkLayer.CLIP]],
	]
	for f: Array in files:
		SoldierClipFile.add(library, spec, f[0], f[1], f[2])
	DownedPose.add_clips(anim_player)


## The menu soldier in `look` holding `id` (`MenuHero`, the night's hold), measured on the pose the
## skeleton has while the hand pose is on (read at `skeleton_updated`, when the modifiers have run).
static func menu_fit(host: Node3D, look: CharacterLook, id: StringName) -> Dictionary:
	var hero := MenuHero.new()
	host.add_child(hero)
	hero.show_look(look, id)
	var skeleton := hero.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var poses: Array[Transform3D] = []
	var grab := func() -> void:
		if poses.is_empty():
			for b in skeleton.get_bone_count():
				poses.append(skeleton.get_bone_global_pose(b))
	for _i in 30:
		hero.advance(1.0 / 30.0)
		await host.get_tree().process_frame
	skeleton.skeleton_updated.connect(grab)
	hero.advance(1.0 / 30.0)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var fit := BodyFit.new(host, skeleton)
	var sampler := ClipFit.new(fit, hero.model)
	var found := await sampler.measure(poses)
	fit.free_bodies()
	host.remove_child(hero)
	hero.free()
	return found


## Every clip in the model's library, by name.
func clips() -> PackedStringArray:
	var out := PackedStringArray()
	for clip in _player.get_animation_list():
		out.append(String(clip))
	out.sort()
	return out


## Poses the model at `seconds` into `clip`.
func pose(clip: String, seconds: float) -> void:
	# The clips of the player's own files do not key the fingers: from the rest pose, not from
	# whatever the last clip left them in (the sample would depend on the clip before).
	_skeleton.reset_bone_poses()
	_player.play(StringName(clip))
	_player.seek(seconds, true)
	# Held there: a playing clip goes on with every frame the probes await, and the bones read
	# after the wait (`BodyFit.bone_point`) would be a later pose than the surface read before it.
	_player.pause()


## The checks on the pose the skeleton holds now (or `poses`): {check name: [{mesh, group, depth,
## position}]} for the checks with any vertex too deep.
func measure(poses: Array[Transform3D] = [], stride := 2, only: Array = []) -> Dictionary:
	_fit.read_pose(poses)
	var out := {}
	var checks: Array[Array] = []
	var sets: Array[PackedVector3Array] = []
	for check: Array in CHECKS:
		if only.is_empty() or check[0] in only:
			checks.append(check)
			sets.append(_fit.triangles([], check[3]))
	# Every check's surface goes in at once: one physics frame a pose, not two a check.
	await _fit.prepare_sets(sets)
	for i in checks.size():
		if sets[i].is_empty():
			continue
		_fit.use_set(i)
		var found := _fit.vertices_inside(
			checks[i][1], checks[i][2], BodyFit.bounds_of(sets[i]).grow(0.01), TOLERANCE, stride
		)
		if not found.is_empty():
			out[checks[i][0]] = found
	return out


## Samples every clip (or `only`): {clip: {check: {"count", "depth", "at"}}} for the clips with a
## fault, `at` the seconds of the deepest.
func sample_clips(
	only: PackedStringArray = [], checks: Array = [], samples := SAMPLES
) -> Dictionary:
	var report := {}
	for clip in clips() if only.is_empty() else only:
		var length := _player.get_animation(StringName(clip)).length
		for k in samples:
			var seconds := length * (k + 0.5) / samples
			pose(clip, seconds)
			var found := await measure([], 2, checks)
			for check: String in found:
				var deepest: Dictionary = found[check][0]
				var entry: Dictionary = report.get_or_add(clip, {}).get_or_add(
					check, {"count": 0, "depth": 0.0, "at": 0.0, "mesh": ""}
				)
				entry.count = maxi(entry.count, found[check].size())
				if deepest.depth > entry.depth:
					entry.depth = deepest.depth
					entry.at = seconds
					entry.mesh = "%s %s" % [deepest.mesh, deepest.group]
	return report
