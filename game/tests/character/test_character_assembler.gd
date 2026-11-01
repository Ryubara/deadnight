extends GdUnitTestSuite
## The assembly of every preset: the right parts on, the palette on the right materials, the
## seat's armband, and no material shared between two characters.


func _assemble(look: CharacterLook, seat := 0) -> Node3D:
	var model := CharacterAssembler.assemble(look, seat)
	add_child(model)
	auto_free(model)
	return model


## The colour of the surface of `mesh_name` whose source material is called `material`.
func _surface_colour(model: Node3D, mesh_name: String, material: String) -> Color:
	var mesh := model.find_child(mesh_name, true, false) as MeshInstance3D
	for i in mesh.mesh.get_surface_count():
		if mesh.mesh.surface_get_material(i).resource_name == material:
			return (mesh.get_active_material(i) as BaseMaterial3D).albedo_color
	return Color.TRANSPARENT


func test_every_preset_assembles_with_its_palette() -> void:
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		var model := _assemble(look, i)
		assert_object(model.find_child("Body", true, false)).is_not_null()
		assert_that(_surface_colour(model, "Body", "Skin")).is_equal(look.colour(&"skin"))
		assert_that(_surface_colour(model, "Body", "Character_Main")).is_equal(
			look.colour(&"primary")
		)
		assert_that(_surface_colour(model, "Body", "Pants")).is_equal(look.colour(&"secondary"))
		assert_that(_surface_colour(model, "Body", "Black")).is_equal(look.colour(&"hair"))
		assert_that(_surface_colour(model, "Head", "Character_Main")).is_equal(
			look.colour(&"primary")
		)
		assert_that(_surface_colour(model, "Head", "Grey")).is_equal(look.colour(&"accent"))


func test_the_helmet_follows_the_headwear_part() -> void:
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		var model := _assemble(look)
		var wearing: bool = look.parts[&"headwear"] == &"helmet"
		var shell := _surface_colour(model, "Head", "Character_Main")
		assert_float(shell.a).is_equal(1.0 if wearing else 0.0)
		# The face features stay either way.
		assert_float(_surface_colour(model, "Head", "Black").a).is_equal(1.0)


func test_only_one_weapon_is_shown() -> void:
	var model := _assemble(CharacterLook.new())
	var shown: Array[String] = []
	for weapon in model.find_child("Index1_R", true, false).get_children():
		if weapon is MeshInstance3D and (weapon as MeshInstance3D).visible:
			shown.append(weapon.name)
	assert_array(shown).contains_exactly([CharacterAssembler.SHOWN_WEAPON])


func test_the_armband_colour_comes_from_the_seat_never_the_look() -> void:
	var look := CharacterLook.from_preset(4)
	for seat in LookCatalog.ARMBAND_COLOURS.size():
		var model := _assemble(look, seat)
		var band := model.find_child(CharacterAssembler.ARMBAND_NAME, true, false) as MeshInstance3D
		assert_object(band).is_not_null()
		var material := (band.mesh as TorusMesh).material as StandardMaterial3D
		assert_that(material.albedo_color).is_equal(LookCatalog.ARMBAND_COLOURS[seat])
		assert_bool(material.emission_enabled).is_true()


func test_the_four_armband_colours_are_clearly_different() -> void:
	var colours := LookCatalog.ARMBAND_COLOURS
	for a in colours.size():
		for b in range(a + 1, colours.size()):
			var gap := absf(colours[a].h - colours[b].h)
			gap = minf(gap, 1.0 - gap)
			assert_float(gap).is_greater(0.08)


func test_two_characters_do_not_share_materials() -> void:
	var first := _assemble(CharacterLook.from_preset(0))
	var second := _assemble(CharacterLook.from_preset(2))
	assert_that(_surface_colour(first, "Body", "Character_Main")).is_not_equal(
		_surface_colour(second, "Body", "Character_Main")
	)
	# And the file's own material was never changed.
	var plain := (load(CharacterAssembler.SOLDIER) as PackedScene).instantiate()
	add_child(plain)
	auto_free(plain)
	var body := plain.find_child("Body", true, false) as MeshInstance3D
	assert_bool(body.get_surface_override_material(0) == null).is_true()
