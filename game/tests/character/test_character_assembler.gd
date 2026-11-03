extends GdUnitTestSuite
## The assembly of every preset: the right parts on, the palette on the atlas, the idle pose, the
## seat's armband, and no material shared between two characters.

## The armband of every seat, eight of them (#690), is told from every other by more than this
## colour distance (CIE76 in Lab: 2 is the least a person sees, 40 is red against orange): hue alone
## cannot tell eight apart (a white band has none).
const ARMBAND_APART := 30.0


func _assemble(look: CharacterLook, seat := 0) -> Node3D:
	var model := CharacterAssembler.assemble(look, seat)
	add_child(model)
	auto_free(model)
	return model


## The names of the part meshes the model shows.
func _shown(model: Node3D) -> Array[String]:
	var out: Array[String] = []
	var meshes := SoldierLook.part_meshes(model)
	for mesh_name: String in meshes:
		if (meshes[mesh_name] as MeshInstance3D).visible:
			out.append(mesh_name)
	out.sort()
	return out


## The colour painted into the atlas of the model for `channel`.
func _atlas_colour(model: Node3D, channel: String) -> Color:
	var mesh: MeshInstance3D = SoldierLook.part_meshes(model).values()[0]
	var material := mesh.material_override as StandardMaterial3D
	var image := material.albedo_texture.get_image()
	var cell: Array = SoldierLook.catalog()["atlas"]["cells"][channel]
	var swatch: int = SoldierLook.catalog()["atlas"]["swatch_px"]
	return image.get_pixel(int(cell[0]) * swatch + swatch / 2, int(cell[1]) * swatch + swatch / 2)


func test_every_preset_assembles_with_its_parts_and_palette() -> void:
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		var model := _assemble(look, i)
		var expected: Array[String] = SoldierLook.visible_meshes(look.to_soldier_look())
		expected.sort()
		assert_array(_shown(model)).is_equal(expected)
		for channel in LookCatalog.colour_slots():
			var want := look.colour(channel)
			var got := _atlas_colour(model, String(channel))
			assert_float(got.r).is_equal_approx(want.r, 0.01)
			assert_float(got.g).is_equal_approx(want.g, 0.01)
			assert_float(got.b).is_equal_approx(want.b, 0.01)


func test_headwear_and_neckwear_follow_the_look() -> void:
	var look := CharacterLook.from_preset(1)
	assert_str(String(look.parts[&"headwear"])).is_equal("pillbox")
	assert_array(_shown(_assemble(look))).contains(["headwear__pillbox", "neck__bowtie"])
	look.parts[&"headwear"] = &"none"
	assert_bool(_shown(_assemble(look)).has("headwear__pillbox")).is_false()


func test_the_character_stands_in_its_idle_pose() -> void:
	var model := _assemble(CharacterLook.new())
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_str(player.current_animation).is_equal(CharacterAssembler.IDLE)
	assert_bool(player.is_playing()).is_true()


func test_the_armband_colour_comes_from_the_seat_never_the_look() -> void:
	var look := CharacterLook.from_preset(4)
	for seat in LookCatalog.ARMBAND_COLOURS.size():
		var model := _assemble(look, seat)
		var band := model.find_child(CharacterAssembler.ARMBAND_NAME, true, false) as MeshInstance3D
		assert_object(band).is_not_null()
		var material := (band.mesh as TorusMesh).material as StandardMaterial3D
		assert_that(material.albedo_color).is_equal(LookCatalog.ARMBAND_COLOURS[seat])
		assert_bool(material.emission_enabled).is_true()


func test_the_armband_ring_runs_along_the_arm() -> void:
	var model := _assemble(CharacterLook.new())
	var skeleton := model.find_child(CharacterAssembler.SKELETON, true, false) as Skeleton3D
	var band := model.find_child(CharacterAssembler.ARMBAND_NAME, true, false) as MeshInstance3D
	# The ring's axis (its local Y) in the bone's space is the direction to the next bone.
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone(CharacterAssembler.ARMBAND_BONE))
	var next := skeleton.get_bone_global_rest(skeleton.find_bone(CharacterAssembler.ARMBAND_NEXT))
	var arm := (rest.basis.inverse() * (next.origin - rest.origin)).normalized()
	assert_float(band.basis.y.normalized().dot(arm)).is_greater(0.99)


func test_the_eight_armband_colours_are_clearly_different() -> void:
	var colours := LookCatalog.ARMBAND_COLOURS
	assert_int(colours.size()).is_equal(NightHost.MAX_PLAYERS)
	for a in colours.size():
		for b in range(a + 1, colours.size()):
			(
				assert_float(_lab_distance(colours[a], colours[b]))
				. override_failure_message("seats %d and %d" % [a, b])
				. is_greater(ARMBAND_APART)
			)


func _lab_distance(a: Color, b: Color) -> float:
	return _lab(a).distance_to(_lab(b))


func _lab(colour: Color) -> Vector3:
	var linear := colour.srgb_to_linear()
	var x := 0.4124 * linear.r + 0.3576 * linear.g + 0.1805 * linear.b
	var y := 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
	var z := 0.0193 * linear.r + 0.1192 * linear.g + 0.9505 * linear.b
	var fx := _lab_f(x / 0.95047)
	var fy := _lab_f(y)
	var fz := _lab_f(z / 1.08883)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


func test_two_characters_do_not_share_materials() -> void:
	var first := _assemble(CharacterLook.from_preset(0))
	var second := _assemble(CharacterLook.from_preset(2))
	var a: MeshInstance3D = SoldierLook.part_meshes(first).values()[0]
	var b: MeshInstance3D = SoldierLook.part_meshes(second).values()[0]
	assert_bool(a.material_override != b.material_override).is_true()
