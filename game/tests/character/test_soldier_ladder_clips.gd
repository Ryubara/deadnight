# Wave two of the ladder's pieces (Deadnight #1078) in the clips the player plays, sampled as
# `test_soldier_clip_fit.gd` samples wave one, in a suite of its own so the shards stay even:
# - the head pieces out of the shoulders, on the tall collars and the open ones;
# - the arms out of what stands off the body: the mask, the boots' shafts and the skirt;
# - the skirt, which `ClipFit` cannot judge: its wall is thin, so a knee through it is never
#   "inside" it. A leg is through when a place on the wall lies inside the leg's tube, a hand is
#   under the skirt when a ray from it out, away from the hips, still meets the wall.
# What the suite allows past the tolerance is in `clip_fit_recorded.json`, "ladder two" and "skirt".
# Docs: docs/research/soldier-parts.md, "The ladder's pieces".
extends GdUnitTestSuite

const RECORDED := "res://tests/character/clip_fit_recorded.json"
## How much deeper than recorded a clip may go (the sampling's own spread), metres.
const SLACK := 0.005
## The deepest an arm may be recorded at here, and the wall in a knee, metres.
const ARM_MOST := 0.1
const LEG_MOST := 0.15
const HEAD_SAMPLES := 3
## Frames of each clip for the skirt, which swings with the legs.
const SKIRT_SAMPLES := 6
## The head and neck pieces, each on a tall and on an open collar: [preset, parts].
const HEAD_LOOKS := [
	[0, {&"headwear": &"creature", &"torso": &"vest"}],
	[8, {&"headwear": &"creature", &"torso": &"jacket", &"neck": &"film"}],
	[10, {&"headwear": &"creature", &"neck": &"scarf"}],
	[0, {&"neck": &"film", &"torso": &"vest", &"hair": &"crew"}],
	[8, {&"neck": &"film", &"hair": &"bob"}],
]
## What stands off the body, where a hand can go: [preset, parts].
const ARM_LOOKS := [
	[0, {&"headwear": &"creature"}],
	[10, {&"headwear": &"creature"}],
	[0, {&"feet": &"rubber"}],
	[0, {&"legs": &"swing"}],
	[10, {&"legs": &"swing"}],
]
const SKIRT_LOOKS: Array[int] = [0, 10]
## The skirt's faces by their swatches: the legs under it are skin and socks.
const OUTSIDE_SWATCHES := [&"secondary", &"accent"]
const INSIDE_SWATCHES := [&"secondary_shade"]
## The bones of each leg, and the furthest a place can be from the leg's line and be in it, metres.
const LEG_BONES := [["UpperLeg.L", "LowerLeg.L", "Foot.L"], ["UpperLeg.R", "LowerLeg.R", "Foot.R"]]
const LEG_REACH := 0.2
## How far down the thigh the legs under the skirt begin.
const LEG_FROM := 0.75

var _host: Node3D
var _ticks := 60


func before_test() -> void:
	# The probes wait two physics steps for each new surface: step faster than the game does.
	_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 480
	await RouterFixture.clear(get_tree())
	_host = Node3D.new()
	add_child(_host)


func after_test() -> void:
	Engine.physics_ticks_per_second = _ticks
	_host.free()


func _look(entry: Array) -> CharacterLook:
	var look := CharacterLook.from_preset(entry[0])
	for slot: StringName in entry[1]:
		look.parts[slot] = entry[1][slot]
	return look


func _model(look: CharacterLook) -> Node3D:
	var model := CharacterAssembler.assemble(look, 0)
	_host.add_child(model)
	return model


func _drop(model: Node3D, fit: BodyFit) -> void:
	fit.free_bodies()
	_host.remove_child(model)
	model.free()


func test_the_mask_and_the_film_stay_out_of_the_shoulders_in_every_clip() -> void:
	var fails: Array[String] = []
	for entry: Array in HEAD_LOOKS:
		var model := _model(_look(entry))
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var fit := BodyFit.new(_host, skeleton)
		var report := await ClipFit.new(fit, model).sample_clips([], ["head pieces"], HEAD_SAMPLES)
		for clip: String in report:
			var e: Dictionary = report[clip]["head pieces"]
			fails.append("%s %s: %.3f m at %.2f s (%s)" % [entry[1], clip, e.depth, e.at, e.mesh])
		_drop(model, fit)
	assert_array(fails).is_empty()


## No clip goes deeper than the tolerance but those recorded under "ladder two": a forearm under the
## mask's rim in the grenade's windup, a hand at the skirt in the run's swing.
func test_the_arms_stay_out_of_what_stands_off_the_body() -> void:
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDED))
	var known: Dictionary = recorded.get("ladder two", {})
	var fails: Array[String] = []
	for entry: Array in ARM_LOOKS:
		var model := _model(_look(entry))
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var fit := BodyFit.new(_host, skeleton)
		var report := await ClipFit.new(fit, model).sample_clips([], ["left arm", "right arm"])
		for clip: String in report:
			for check: String in report[clip]:
				var depth: float = report[clip][check].depth
				var allowed: float = known.get(clip, {}).get(check, ClipFit.TOLERANCE) + SLACK
				if depth > allowed:
					var at: float = report[clip][check].at
					fails.append("%s %s %s: %.3f m at %.2f s" % [entry[1], clip, check, depth, at])
		_drop(model, fit)
	assert_array(fails).is_empty()


## What is recorded stays small: the mask's rim over a forearm in one windup, and the skirt, whose
## sixteen sides cannot hold a knee at full stride.
func test_the_recorded_depths_stay_small() -> void:
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDED))
	for clip: String in recorded["ladder two"]:
		for check: String in recorded["ladder two"][clip]:
			assert_float(recorded["ladder two"][clip][check]).is_less_equal(ARM_MOST)
	for clip: String in recorded["skirt"]:
		var known: Dictionary = recorded["skirt"][clip]
		assert_float(known.get("leg", 0.0)).is_less_equal(LEG_MOST)
		assert_float(known.get("hand", 0.0)).is_less_equal(ARM_MOST)


## The cell of a uv on the atlas, as parts.json names cells.
static func _cell(uv: Vector2) -> Vector2i:
	var cat := SoldierLook.catalog()
	var px := float(cat.atlas.swatch_px)
	return Vector2i(
		int(uv.x * float(cat.atlas.size[0]) / px), int(uv.y * float(cat.atlas.size[1]) / px)
	)


## Per vertex of the shown skirt part: 1 on the skirt's outside, 2 anywhere else on the skirt (its
## inside and its waist), 0 on the legs under it.
func _skirt_vertices(model: Node3D) -> Dictionary:
	var cat := SoldierLook.catalog()
	var kinds := {}
	for swatch: StringName in OUTSIDE_SWATCHES:
		kinds[Vector2i(cat.atlas.cells[swatch][0], cat.atlas.cells[swatch][1])] = 1
	for swatch: StringName in INSIDE_SWATCHES:
		kinds[Vector2i(cat.atlas.cells[swatch][0], cat.atlas.cells[swatch][1])] = 2
	var out := {}
	var meshes := SoldierLook.part_meshes(model)
	for mesh_name: String in meshes:
		if not mesh_name.begins_with("legs__swing"):
			continue
		var uvs: PackedVector2Array = (
			(meshes[mesh_name] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		)
		var kind := PackedByteArray()
		kind.resize(uvs.size())
		for v in uvs.size():
			kind[v] = kinds.get(_cell(uvs[v]), 0)
		out[mesh_name] = kind
	return out


## The faces in the pose read whose first corner is of `kind`, as `BodyFit.prepare` takes them.
func _faces(fit: BodyFit, marks: Dictionary, kind: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for m: Dictionary in fit.meshes:
		if not marks.has(m.name):
			continue
		var marked: PackedByteArray = marks[m.name]
		var points: PackedVector3Array = m.points
		var indices: PackedInt32Array = m.indices
		for t in indices.size() / 3:
			if marked[indices[t * 3]] == kind:
				out.append(points[indices[t * 3]])
				out.append(points[indices[t * 3 + 1]])
				out.append(points[indices[t * 3 + 2]])
	return out


## Places on the wall: each corner, each face's middle and each edge's. Its faces are big and a
## knee can come through between its corners.
static func _wall_points(wall: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for t in wall.size() / 3:
		var a := wall[t * 3]
		var b := wall[t * 3 + 1]
		var c := wall[t * 3 + 2]
		out.append_array(PackedVector3Array([a, (a + b) / 2.0, (a + c) / 2.0, (a + b + c) / 3.0]))
	return out


## How deep the wall lies inside a leg, on the legs' surface prepared. The legs end above the knee
## under the skirt, so each is the end of the thigh and the shin: a place is in a leg when it is
## beside that line, not past its ends, and nothing lies between it and the line; its depth is the
## way on out of the leg.
func _wall_in_legs(fit: BodyFit, places: PackedVector3Array) -> float:
	var deepest := 0.0
	for leg: Array in LEG_BONES:
		var knee := fit.bone_point(leg[1])
		var top := fit.bone_point(leg[0]).lerp(knee, LEG_FROM)
		var ankle := fit.bone_point(leg[2])
		for place in places:
			var on_thigh := Geometry3D.get_closest_point_to_segment(place, top, knee)
			var on_shin := Geometry3D.get_closest_point_to_segment(place, knee, ankle)
			var near := (
				on_thigh if on_thigh.distance_to(place) < on_shin.distance_to(place) else on_shin
			)
			var along := place - near
			if near.is_equal_approx(top) or near.is_equal_approx(ankle):
				continue
			if along.length() > LEG_REACH or along.length() < 0.001:
				continue
			if not fit.first_hit(near, place).is_empty():
				continue
			var out := fit.first_hit(place, place + along.normalized() * LEG_REACH)
			if not out.is_empty():
				deepest = maxf(deepest, float(out[0]))
	return deepest


## How far under the wall a hand has gone, on the wall prepared: a ray from the hand out, away from
## the hips, still meets it.
func _hands_under_wall(fit: BodyFit) -> float:
	var hips := fit.bone_point("Hips")
	var deepest := 0.0
	for m: Dictionary in fit.meshes:
		var points: PackedVector3Array = m.points
		var groups: PackedStringArray = m.groups
		for v in points.size():
			if groups[v].begins_with("hand"):
				var p := points[v]
				var out := Vector3(p.x - hips.x, 0.0, p.z - hips.z).normalized()
				var hit := fit.first_hit(p, p + out * 0.6)
				if not hit.is_empty():
					deepest = maxf(deepest, float(hit[0]))
	return deepest


func test_the_swing_skirt_holds_the_legs_in_and_keeps_the_hands_out() -> void:
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDED))
	var known: Dictionary = recorded.get("skirt", {})
	var fails: Array[String] = []
	for preset in SKIRT_LOOKS:
		var look := CharacterLook.from_preset(preset)
		look.parts[&"legs"] = &"swing"
		var model := _model(look)
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var fit := BodyFit.new(_host, skeleton)
		var sampler := ClipFit.new(fit, model)
		var marks := _skirt_vertices(model)
		assert_int(marks.size()).is_equal(1)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for clip in sampler.clips():
			var length := player.get_animation(StringName(clip)).length
			var worst := {"leg": 0.0, "hand": 0.0}
			for k in SKIRT_SAMPLES:
				sampler.pose(clip, length * (k + 0.5) / SKIRT_SAMPLES)
				fit.read_pose()
				var wall := _faces(fit, marks, 1)
				await fit.prepare_sets([_faces(fit, marks, 0), wall])
				fit.use_set(0)
				worst.leg = maxf(worst.leg, _wall_in_legs(fit, _wall_points(wall)))
				fit.use_set(1)
				worst.hand = maxf(worst.hand, _hands_under_wall(fit))
			for part: String in worst:
				var allowed: float = known.get(clip, {}).get(part, ClipFit.TOLERANCE) + SLACK
				if worst[part] > allowed:
					fails.append("%d %s %s: %.3f m" % [preset, clip, part, worst[part]])
		_drop(model, fit)
	assert_array(fails).is_empty()
