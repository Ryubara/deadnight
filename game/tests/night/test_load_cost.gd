# What the night's loading costs, and that the cuts made to it (#509) stay.
extends GdUnitTestSuite

## How many different lit `StandardMaterial3D` shaders the night draws. The engine builds a lit
## shader's four variants at the first draw, and in a browser each costs 1 to 2 s of loading
## (whatever it draws), so a new settings combination is a deliberate choice: reuse a material that
## exists, or raise this with the measurement of what it adds (`docs/research/web-export.md`).
const LIT_SHADER_BUDGET := 8


func _warmed_night() -> Night:
	var night := Night.new()
	night.warm_up = true
	add_child(night)
	await night.start(Night.Mode.AUTOPILOT, 7)
	return night


## The distinct settings of the lit standard materials the warm-up drew (the kind of mesh left off).
func _lit_standard_kinds(night: Night) -> Array[String]:
	var kinds: Array[String] = []
	for key in night.warmup.ledger.seen:
		var material := key.get_slice("|", 1)
		if (
			material.begins_with("standard:")
			and material.trim_prefix("standard:").begins_with("1,")
		):
			if not kinds.has(material):
				kinds.append(material)
	kinds.sort()
	return kinds


func test_the_night_draws_few_lit_shaders() -> void:
	var night := await _warmed_night()
	var kinds := _lit_standard_kinds(night)
	var message := "%d lit standard materials with different settings (budget %d):\n%s"
	message = message % [kinds.size(), LIT_SHADER_BUDGET, "\n".join(kinds)]
	assert_int(kinds.size()).override_failure_message(message).is_less_equal(LIT_SHADER_BUDGET)
	night.queue_free()


func test_no_lot_material_turns_the_specular_off_with_a_setting_of_its_own() -> void:
	# `specular_mode` DISABLED builds a shader of its own for a material that looks the same with
	# `metallic_specular = 0`; seven lot materials did, which was two shaders and 3 s of loading.
	var dir := DirAccess.open("res://assets/lot/materials")
	assert_object(dir).is_not_null()
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var material := load("res://assets/lot/materials/%s" % file) as BaseMaterial3D
		if material == null:
			continue
		(
			assert_int(material.specular_mode)
			. override_failure_message(
				"%s turns the specular off (use metallic_specular = 0)" % file
			)
			. is_not_equal(BaseMaterial3D.SPECULAR_DISABLED)
		)


func test_the_warm_up_draws_into_a_small_picture_and_gives_the_window_back() -> void:
	# Drawing the lot at the window's size made every warm-up frame cost 0.1 to 0.3 s where the
	# renderer runs on the CPU; the programs do not depend on the size.
	var night := Night.new()
	night.warm_up = true
	add_child(night)
	var sizes: Array[Vector2i] = []
	var disabled: Array[bool] = []
	night.loading.connect(
		func(_fraction: float, text: String) -> void:
			if text.begins_with("Setting the scene"):
				disabled.append(get_viewport().disable_3d)
				for view: SubViewport in get_tree().root.find_children(
					"*", "SubViewport", true, false
				):
					if view.get_parent() is NightWarmup:
						sizes.append(view.size)
	)
	await night.start(Night.Mode.HUMAN, 7)
	assert_array(sizes).is_not_empty()
	for size in sizes:
		assert_int(size.x * size.y).is_less(NightWarmup.VIEW_SIZE.x * NightWarmup.VIEW_SIZE.y + 1)
	assert_array(disabled).contains([true])
	assert_bool(get_viewport().disable_3d).is_false()
	assert_object(get_viewport().get_camera_3d()).is_same(night.player().camera_rig.camera())
	night.queue_free()


func test_the_sounds_load_in_the_background_before_a_night_asks() -> void:
	var service := AudioService.new()
	add_child(service)
	assert_bool(service.background_preloading()).is_false()
	service.start_background_preload()
	assert_bool(service.background_preloading()).is_true()
	var frames := 0
	while service.background_preloading() and frames < 4000:
		service._process(1.0 / 60.0)
		frames += 1
	assert_bool(service.background_preloading()).is_false()
	for id: StringName in SoundCatalog.ids():
		# 0 files left to load: the night's warm-up has nothing to read.
		assert_int(service.preload_sound(id)).is_equal(0)
	# Asking again after it finished does not start it over.
	service.start_background_preload()
	assert_bool(service.background_preloading()).is_false()
	service.queue_free()
