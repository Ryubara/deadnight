# The mouths are parts of their own, free to everyone (Deadnight #1061). Every mouth on every head
# of both characters is closed, stands on the face, keeps the rules of a face that reads small
# (docs/research/character-faces.md) and stays within the character's budgets; every skin leaves it
# dark. Measured in the idle's first frame, as `test_soldier_watertight.gd` measures.
extends GdUnitTestSuite

const BODIES: Array[StringName] = [&"male", &"female"]
## A dark mark at 64 px needs height: the line of #895 at 0.026 m kit (about 26 mm here) was gone.
const MIN_TALL := 0.03
## The widest mouth stops well short of the cheeks: a line up the face read as a mask (#895).
const MAX_WIDE := 0.19
## How far a mouth's front stands out of every head, metres (a little less than in the build: this
## is the model's scale). Under the lower bound, skin shows through it (#1061).
const PROUD := Vector2(0.001, 0.008)
## The mouth's swatch against the darkest skin, in sRGB luminance.
const MIN_CONTRAST := 0.12
## Back faces seen through a mouth at most, as the watertight suite.
const ALLOWED := 0
const PART_MARGIN := 0.06

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


func _mouths() -> Array[StringName]:
	var out: Array[StringName] = []
	for option: Dictionary in LookCatalog.options(&"mouth"):
		out.append(StringName(option["id"]))
	return out


## A bare face (nothing that hides it) with `mouth` on `head` of `body`, read in the idle's first
## frame.
func _dress(mouth: StringName, head: StringName, body: StringName) -> BodyFit:
	for child in _host.get_children():
		_host.remove_child(child)
		child.free()
	var look := CharacterLook.new()
	for slot: StringName in [&"hair", &"headwear", &"eyewear", &"neck", &"arm"]:
		look.parts[slot] = &"none"
	look.parts[&"head"] = head
	look.parts[&"mouth"] = mouth
	look.parts[&"body"] = body
	var model := CharacterAssembler.assemble(look, 0)
	_host.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.seek(0.0, true)
	var fit := BodyFit.new(_host, model.find_child("Skeleton3D", true, false) as Skeleton3D)
	fit.read_pose()
	return fit


## How far the mouth's front stands out of the head along the face's forward: at each corner of
## each triangle that faces out and at its middle, so a front that sinks between its corners shows.
func _stands_out(fit: BodyFit) -> Array[float]:
	var mouth := fit.triangles(["mouth__"])
	var box := BodyFit.bounds_of(mouth).grow(0.03)
	var forward := (BodyFit.bounds_of(mouth).get_center() - fit.bone_point("Head")).slide(
		Vector3.UP
	)
	forward = forward.normalized()
	var near := PackedVector3Array()
	var head := fit.triangles(["head__"])
	for t in head.size() / 3:
		if box.intersects(BodyFit.bounds_of(head.slice(t * 3, t * 3 + 3))):
			near.append_array(head.slice(t * 3, t * 3 + 3))
	var out: Array[float] = []
	for t in mouth.size() / 3:
		var a := mouth[t * 3]
		var b := mouth[t * 3 + 1]
		var c := mouth[t * 3 + 2]
		var corners := [_over(a, near, forward), _over(b, near, forward), _over(c, near, forward)]
		if corners.min() > 0.0:
			out.append_array(corners)
			out.append(_over((a + b + c) / 3.0, near, forward))
	out.sort()
	return out


## How far `point` lies in front of the triangles `near` along `forward`.
func _over(point: Vector3, near: PackedVector3Array, forward: Vector3) -> float:
	for t in near.size() / 3:
		var hit: Variant = Geometry3D.ray_intersects_triangle(
			point + forward, -forward, near[t * 3], near[t * 3 + 1], near[t * 3 + 2]
		)
		if hit != null:
			return (point - (hit as Vector3)).dot(forward)
	return INF


func test_every_mouth_is_free_and_a_look_without_one_wears_the_first() -> void:
	assert_int(_mouths().size()).is_between(6, 8)
	var none := LookUnlocks.new()
	for option: Dictionary in LookCatalog.options(&"mouth"):
		assert_dict(option["gate"]).is_empty()
		var look := CharacterLook.default_look()
		look.parts[&"mouth"] = option["id"]
		assert_str(String(look.without_locked(none).parts[&"mouth"])).is_equal(String(option["id"]))
	assert_str(String(CharacterLook.new().parts[&"mouth"])).is_equal("smile")


func test_every_mouth_on_every_head_is_closed() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for head: Dictionary in LookCatalog.options(&"head"):
			for mouth in _mouths():
				var fit := _dress(mouth, head["id"], body)
				var box := BodyFit.bounds_of(fit.triangles(["mouth__"])).grow(PART_MARGIN)
				await fit.prepare(fit.triangles())
				var seen := fit.see_through(box.get_center(), box.size.length() / 2.0)
				fit.free_bodies()
				if seen.size() > ALLOWED:
					fails.append("%s %s/%s: %d rays" % [body, head["id"], mouth, seen.size()])
	assert_array(fails).is_empty()


func test_every_mouth_on_every_head_stands_on_the_face_and_keeps_its_size() -> void:
	var fails: Array[String] = []
	for body in BODIES:
		for head: Dictionary in LookCatalog.options(&"head"):
			for mouth in _mouths():
				var fit := _dress(mouth, head["id"], body)
				var tag := "%s %s/%s" % [body, head["id"], mouth]
				var box := BodyFit.bounds_of(fit.triangles(["mouth__"]))
				if box.size.y < MIN_TALL or maxf(box.size.x, box.size.z) > MAX_WIDE:
					fails.append("%s: %s" % [tag, box.size])
				var fronts := _stands_out(fit)
				if fronts.is_empty() or fronts[0] < PROUD.x or fronts[-1] > PROUD.y:
					fails.append("%s stands out %s" % [tag, fronts])
	assert_array(fails).is_empty()


func test_every_skin_leaves_the_mouth_dark() -> void:
	var cat := SoldierLook.catalog()
	var px: int = cat.atlas.swatch_px
	for skin in LookCatalog.palette(&"skin").size():
		var image := SoldierLook.atlas_image({"skin": skin})
		var cell: Array = cat.atlas.cells.mouth
		var dark := image.get_pixel(int(cell[0]) * px + px / 2, int(cell[1]) * px + px / 2)
		var face: Color = LookCatalog.palette(&"skin")[skin]["colour"]
		assert_float(face.get_luminance() - dark.get_luminance()).is_greater(MIN_CONTRAST)


func test_every_preset_with_every_mouth_on_both_bodies_is_within_the_budgets() -> void:
	var cat := SoldierLook.catalog()
	var model := SoldierLook.instantiate()
	_host.add_child(model)
	for index in LookCatalog.presets().size():
		for body in BODIES:
			for mouth in _mouths():
				var look := CharacterLook.from_preset(index)
				look.set_body(body)
				look.parts[&"mouth"] = mouth
				var tag := "%s %s %s" % [LookCatalog.presets()[index]["id"], body, mouth]
				var near := SoldierLook.apply(model, look.to_soldier_look())
				assert_int(near).override_failure_message(tag).is_less_equal(int(cat.budget))
				(
					assert_int(SoldierLook.far_triangles(model))
					. override_failure_message(tag)
					. is_less_equal(int(cat.far_budget))
				)


func test_the_mouth_shown_is_the_look_s_own_at_every_distance() -> void:
	var model := SoldierLook.instantiate()
	_host.add_child(model)
	for body in BODIES:
		for mouth in _mouths():
			var look := CharacterLook.default_look()
			look.set_body(body)
			look.parts[&"mouth"] = mouth
			SoldierLook.apply(model, look.to_soldier_look())
			var want := "mouth__%s%s" % [mouth, "__female" if body == LookCatalog.FEMALE else ""]
			var meshes := SoldierLook.part_meshes(model)
			var shown: Array[String] = []
			for mesh_name: String in meshes:
				if mesh_name.begins_with("mouth__") and meshes[mesh_name].visible:
					shown.append(mesh_name)
			assert_array(shown).is_equal([want])
			assert_float((meshes[want] as MeshInstance3D).visibility_range_end).is_equal(0.0)
