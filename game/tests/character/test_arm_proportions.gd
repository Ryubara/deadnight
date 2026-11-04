# The Soldier's arms in proportion (Deadnight #978): every starting look, his and hers, has the
# arm the style asks for against its height, the forearm no longer than the upper arm, and in every
# hold of the menu's stage the arm keeps those lengths (the hand pose only turns bones) and the left
# hand still reaches the place the weapon's grip gives it. Measured on the shown meshes at their
# bind pose (the T-pose the build skins them in), in the model's own metres (kit metres x 0.8).
# Docs: docs/design/characters.md, "Proportions"; tools/blender/soldier_arms.py.
extends GdUnitTestSuite

const MeasureArms := preload("res://tests/art/measure_arms.gd")

## The arm (upper arm, forearm and hand to the furthest fingertip) over the height (sole to the top
## of the head, hair and hats left out): 0.547 with the kit's arm, 0.507 after #978.
const ARM_TO_HEIGHT := 0.507
const ARM_TOLERANCE := 0.005
## The forearm over the upper arm: 1.13 with the kit's, 0.91 after #978 (a person's is about 0.8).
const FOREARM_TO_UPPER_MAX := 0.95
## How far a bone may differ from its rest length in a hold, and how far the left hand bone may stop
## from its place on the fore-end (metres).
const STRETCH_TOLERANCE := 0.001
const REACH_TOLERANCE := 0.002
const FINGERS := ["Index", "Middle", "Pinky", "Thumb"]
const HEAD_PREFIX := "head__"
const LEFT_OUT := ["hair__", "headwear__", "eyewear__"]


## {height, upper, forearm, hand, arm} of the look's shown near meshes at their bind pose.
static func proportions(look: CharacterLook) -> Dictionary:
	var model := CharacterAssembler.assemble(look, 0)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var joints := {}
	var sole := INF
	var top := -INF
	var hand := 0.0
	var wrist := Vector3.ZERO
	var along := Vector3.ZERO
	var meshes: Array[MeshInstance3D] = []
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin == null or not mi.visible or not HandContact.is_near(mi):
			continue
		meshes.append(mi)
		for i in mi.skin.get_bind_count():
			joints[String(mi.skin.get_bind_name(i))] = (
				mi.skin.get_bind_pose(i).affine_inverse().origin
			)
	var shoulder: Vector3 = joints["UpperArm.L"]
	var elbow: Vector3 = joints["LowerArm.L"]
	wrist = joints["Index1.L"]
	along = (wrist - elbow).normalized()
	for mi in meshes:
		var name := String(mi.name)
		var counted := not LEFT_OUT.any(func(p: String) -> bool: return name.begins_with(p))
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := bones.size() / maxi(vertices.size(), 1)
			for v in vertices.size():
				var p := vertices[v]
				if counted:
					sole = minf(sole, p.y)
					if name.begins_with(HEAD_PREFIX):
						top = maxf(top, p.y)
				var best := -1
				var best_w := -1.0
				for k in influences:
					if weights[v * influences + k] > best_w:
						best_w = weights[v * influences + k]
						best = bones[v * influences + k]
				var bone := String(mi.skin.get_bind_name(best)) if best >= 0 else ""
				if (
					bone.ends_with(".L")
					and FINGERS.any(func(f: String) -> bool: return bone.begins_with(f))
				):
					hand = maxf(hand, (p - wrist).dot(along))
	model.free()
	var upper := shoulder.distance_to(elbow)
	var forearm := elbow.distance_to(wrist)
	return {
		"height": top - sole,
		"upper": upper,
		"forearm": forearm,
		"hand": hand,
		"arm": upper + forearm + hand,
	}


func test_every_look_has_the_arm_in_proportion() -> void:
	var lines: Array[String] = []
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		var m := proportions(look)
		var ratio: float = m.arm / m.height
		var tag := "preset %d (%s)" % [i, look.body()]
		lines.append("%s arm/height %.3f forearm/upper %.2f" % [tag, ratio, m.forearm / m.upper])
		(
			assert_float(ratio)
			. override_failure_message(
				"%s: arm %.3f m over height %.3f m = %.3f" % [tag, m.arm, m.height, ratio]
			)
			. is_between(ARM_TO_HEIGHT - ARM_TOLERANCE, ARM_TO_HEIGHT + ARM_TOLERANCE)
		)
		(
			assert_float(m.forearm / m.upper)
			. override_failure_message(
				"%s: forearm %.3f longer than the upper arm %.3f allows" % [tag, m.forearm, m.upper]
			)
			. is_less_equal(FOREARM_TO_UPPER_MAX)
		)
	print("\n".join(lines))


func test_her_arm_is_his() -> void:
	var his := proportions(CharacterLook.from_preset(0))
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		if look.body() != LookCatalog.FEMALE:
			continue
		var hers := proportions(look)
		for key: String in ["upper", "forearm", "hand", "height"]:
			(
				assert_float(hers[key])
				. override_failure_message("preset %d %s" % [i, key])
				. is_equal_approx(his[key], 0.002)
			)


func test_every_hold_keeps_the_arm_and_reaches_the_weapon() -> void:
	var host := Node3D.new()
	add_child(host)
	var rest := proportions(CharacterLook.from_preset(0))
	var fails: Array[String] = []
	for preset in [0, 10]:
		for id in MenuHero.available():
			var m: Dictionary = await MeasureArms.measure(
				host, CharacterLook.from_preset(preset), id
			)
			for side: String in ["R", "L"]:
				var arm: Dictionary = m[side]
				for key: String in ["upper", "forearm"]:
					var drawn: float = arm["fore" if key == "forearm" else key]
					var want: float = rest[key] * MenuHero.MODEL_SCALE
					if absf(drawn - want) > STRETCH_TOLERANCE:
						fails.append(
							"%d %s %s %s %.4f, at rest %.4f" % [preset, id, side, key, drawn, want]
						)
			if m.L.miss > REACH_TOLERANCE:
				fails.append(
					"%d %s: left hand %.3f m short of the fore-end" % [preset, id, m.L.miss]
				)
	host.free()
	assert_array(fails).is_empty()
