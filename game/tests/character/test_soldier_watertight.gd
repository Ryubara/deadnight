# The dressed Soldier is closed wherever a part meets another (Deadnight #895): every combination
# of the parts that meet at the neck, the wrists and shoulders, the waist and the ankles, on both
# bodies, has no place where the eye looks into a part through an opening and out through the body
# (the material culls back faces). Each part of every slot is also checked whole on both bodies.
# Measured by `BodyFit.see_through` in the idle's first frame. Docs:
# docs/research/soldier-parts.md, "Fit".
extends GdUnitTestSuite

## The places looked at: [bone, towards, along, radius in metres].
const NECK := ["Neck", "Head", 0.5, 0.27]
const WAIST := ["Hips", "Abdomen", 0.75, 0.36]
const ANKLES := [["LowerLeg.L", "Foot.L", 0.62, 0.0], ["LowerLeg.R", "Foot.R", 0.62, 0.0]]
const ANKLE_RADIUS := 0.2
## Where a tall boot's top meets the leg it goes over: [bone, towards, along, radius].
const BOOT_TOPS := [["LowerLeg.L", "Foot.L", 0.3, 0.24], ["LowerLeg.R", "Foot.R", 0.3, 0.24]]
const WRIST_ALONG := 0.82
const WRIST_RADIUS := 0.18
const SHOULDER_RADIUS := 0.22
## A part's own box, looked at whole, grows by this much.
const PART_MARGIN := 0.06
## Back faces seen through a combination at most (a ray grazing an edge can count once).
const ALLOWED := 0
const BODIES: Array[StringName] = [&"male", &"female"]

var _host: Node3D
var _ticks := 60


func before_test() -> void:
	# The probes wait two physics steps for each new surface: step faster than the game does.
	_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 480
	_host = Node3D.new()
	add_child(_host)


func after_test() -> void:
	Engine.physics_ticks_per_second = _ticks
	_host.free()


## A look of `parts` (every other slot empty or its default) on `body`, standing in the idle's
## first frame, and its fit probe with the pose read.
func _dress(parts: Dictionary, body: StringName) -> BodyFit:
	for child in _host.get_children():
		_host.remove_child(child)
		child.free()
	var look := CharacterLook.new()
	for slot: StringName in [&"hair", &"headwear", &"eyewear", &"neck", &"arm"]:
		look.parts[slot] = &"none"
	for slot: StringName in parts:
		look.parts[slot] = parts[slot]
	look.parts[&"body"] = body
	var model := CharacterAssembler.assemble(look, 0)
	_host.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.seek(0.0, true)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var fit := BodyFit.new(_host, skeleton)
	fit.read_pose()
	return fit


func _place(fit: BodyFit, spec: Array) -> Vector3:
	return fit.bone_point(spec[0], spec[1], spec[2])


## Checks the places `where` ([[centre, radius]]) on a dressed look; returns failure lines.
func _check(tag: String, fit: BodyFit, where: Array) -> Array[String]:
	await fit.prepare(fit.triangles())
	var fails: Array[String] = []
	for place: Array in where:
		var seen := fit.see_through(place[0], place[1])
		if seen.size() > ALLOWED:
			fails.append(
				"%s at %s: %d rays see through, first at %s" % [tag, place[0], seen.size(), seen[0]]
			)
	fit.free_bodies()
	return fails


func _options(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for option: Dictionary in LookCatalog.options(slot):
		out.append(StringName(option["id"]))
	return out


func test_the_probe_sees_into_an_open_shell_and_not_into_a_closed_one() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	var arrays := sphere.surface_get_arrays(0)
	var fit := BodyFit.new(_host, null)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var groups := PackedStringArray()
	groups.resize(points.size())
	fit.meshes = [{"name": "ball", "points": points, "indices": indices, "groups": groups}]
	await fit.prepare(fit.triangles())
	assert_int(fit.see_through(Vector3.ZERO, 0.4).size()).is_equal(0)
	assert_float(fit.depth_inside(Vector3(0, 0.1, 0))).is_greater(0.15)
	assert_float(fit.depth_inside(Vector3(0, 0.5, 0))).is_equal(0.0)
	# Cut a cap off the top: looking down into it now sees the inside of the far wall.
	var open := PackedInt32Array()
	for t in indices.size() / 3:
		if points[indices[t * 3]].y < 0.24:
			open.append_array([indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]])
	fit.meshes[0].indices = open
	await fit.prepare(fit.triangles())
	assert_int(fit.see_through(Vector3.ZERO, 0.4).size()).is_greater(10)
	fit.free_bodies()


func test_every_neck_is_closed_with_every_top_and_neckwear() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for head in _options(&"head"):
			for torso in _options(&"torso"):
				for neck in _options(&"neck"):
					var fit := _dress({&"head": head, &"torso": torso, &"neck": neck}, body)
					var tag := "%s %s/%s/%s" % [body, head, torso, neck]
					fails.append_array(await _check(tag, fit, [[_place(fit, NECK), NECK[3]]]))
	assert_array(fails).is_empty()


func test_every_waist_is_closed_with_every_top_and_trousers() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for torso in _options(&"torso"):
			for legs in _options(&"legs"):
				var fit := _dress({&"torso": torso, &"legs": legs}, body)
				var tag := "%s %s/%s" % [body, torso, legs]
				fails.append_array(await _check(tag, fit, [[_place(fit, WAIST), WAIST[3]]]))
	assert_array(fails).is_empty()


func test_every_ankle_is_closed_with_every_trousers_and_shoes() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for legs in _options(&"legs"):
			for feet in _options(&"feet"):
				var fit := _dress({&"legs": legs, &"feet": feet}, body)
				var where := []
				for spec: Array in ANKLES:
					where.append([_place(fit, spec), ANKLE_RADIUS])
				fails.append_array(await _check("%s %s/%s" % [body, legs, feet], fit, where))
	assert_array(fails).is_empty()


## A one-piece top wears its own legs (`hides_legs`, #1078): they meet the shoes in place of the
## trousers, and the suite above does not see them.
func test_every_ankle_of_a_one_piece_top_is_closed_with_every_shoes() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for torso in _options(&"torso"):
			if not SoldierLook.catalog().slots.torso.parts[String(torso)].get("hides_legs", false):
				continue
			for feet in _options(&"feet"):
				var fit := _dress({&"torso": torso, &"feet": feet}, body)
				var where := []
				for spec: Array in ANKLES:
					where.append([_place(fit, spec), ANKLE_RADIUS])
				fails.append_array(await _check("%s %s/%s" % [body, torso, feet], fit, where))
	assert_array(fails).is_empty()


func test_every_wrist_and_shoulder_is_closed_with_every_top_and_armwear() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for torso in _options(&"torso"):
			for arm in _options(&"arm"):
				var fit := _dress({&"torso": torso, &"arm": arm}, body)
				var where := []
				for side in ["L", "R"]:
					where.append(
						[
							fit.bone_point("LowerArm." + side, "Index1." + side, WRIST_ALONG),
							WRIST_RADIUS
						]
					)
					where.append([fit.bone_point("UpperArm." + side), SHOULDER_RADIUS])
				fails.append_array(await _check("%s %s/%s" % [body, torso, arm], fit, where))
	assert_array(fails).is_empty()


## The Creature mask (#1078) is a closed shell the neck comes out of: nothing shows under it, on
## any top and neckwear, where the head's own neck meets it and all over the shell.
func test_the_creature_mask_is_closed_with_every_top_and_neckwear() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for torso in _options(&"torso"):
			for neck in _options(&"neck"):
				var look := {&"headwear": &"creature", &"torso": torso, &"neck": neck}
				var fit := _dress(look, body)
				var head := fit.bone_point("Head")
				var where := [[_place(fit, NECK), NECK[3]], [head, 0.6]]
				fails.append_array(await _check("%s %s/%s" % [body, torso, neck], fit, where))
	assert_array(fails).is_empty()


## The Rubber boots' shaft (#1078) goes over every trouser leg, the bare legs and a one-piece's:
## closed where it ends, under the knee.
func test_the_top_of_a_tall_boot_is_closed_with_every_leg() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for legs in _options(&"legs"):
			fails.append_array(await _boot_tops(body, {&"legs": legs, &"feet": &"rubber"}))
		for torso in [&"coveralls"]:
			fails.append_array(await _boot_tops(body, {&"torso": torso, &"feet": &"rubber"}))
	assert_array(fails).is_empty()


func _boot_tops(body: StringName, parts: Dictionary) -> Array[String]:
	var fit := _dress(parts, body)
	var where := []
	for spec: Array in BOOT_TOPS:
		where.append([_place(fit, spec), spec[3]])
	return await _check("%s %s" % [body, parts], fit, where)


## Every part on its own (with the defaults round it), looked at all over its own box.
func test_every_part_is_closed_on_both_bodies() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for slot in LookCatalog.part_slots():
			if slot == &"body":
				continue
			for part in _options(slot):
				if part == &"none":
					continue
				var fit := _dress({slot: part}, body)
				var mesh := "%s__%s" % [slot, part]
				var box := BodyFit.bounds_of(fit.triangles([mesh])).grow(PART_MARGIN)
				var radius := box.size.length() / 2.0
				fails.append_array(
					await _check("%s %s" % [body, mesh], fit, [[box.get_center(), radius]])
				)
	assert_array(fails).is_empty()
