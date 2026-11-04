# What the night's loading costs, and that the cuts made to it (#509) stay.
extends GdUnitTestSuite

## How many different lit `StandardMaterial3D` shaders the night draws. The engine builds a lit
## shader's four variants at the first draw, and in a browser each costs 1 to 2 s of loading
## (whatever it draws), so a new settings combination is a deliberate choice: reuse a material that
## exists, or raise this with the measurement of what it adds (`docs/research/web-export.md`).
const LIT_SHADER_BUDGET := 8
## Seconds of sound the night decodes to samples behind its loading bar (the sounds of the banks
## that are not `deferred`, in their files' lengths). The web build decodes them in GDScript, one
## loop pass for every sample, and a CI runner takes seconds for every ten of them. Measured
## 152 s with the weapons' and the voices' banks deferred; the cut of #509 had 166 s. A new weapon's
## sounds go in a bank with `deferred = true` (`docs/research/web-export.md`, "Loading a night").
const WARM_DECODE_BUDGET_S := 170.0
## Frames the warm-up draws behind the loading bar (`NightWarmup.shots`; 96 measured). A browser
## spends a frame's time on every one (0.1 to 0.5 s in a software renderer), so the number is the
## load's length in a unit no runner moves; the web smoke's seconds
## (`tools/web_smoke/night_load_baseline.json`) vary by a factor of three and cannot see less than a
## doubling. A step that draws more raises this on purpose, with the measurement of what it adds.
const WARM_FRAME_BUDGET := 100


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


func test_the_warm_up_draws_few_frames() -> void:
	var night := await _warmed_night()
	var message := "the warm-up drew %d frames (budget %d): a step that draws more adds that many"
	message += " frames, at 0.1 to 0.5 s each in a browser, to every night's loading"
	message = message % [night.warmup.shots, WARM_FRAME_BUDGET]
	assert_int(night.warmup.shots).override_failure_message(message).is_less_equal(
		WARM_FRAME_BUDGET
	)
	night.queue_free()


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


func test_the_sounds_decoded_behind_the_bar_stay_within_the_budget() -> void:
	var seconds := 0.0
	var by_bank := {}
	for id: StringName in SoundCatalog.ids():
		var def := SoundCatalog.get_def(id)
		if def.loop or def.deferred:
			continue
		for variant in range(1, def.variants + 1):
			var stream := load(def.path_for(variant)) as AudioStream
			if PcmStream.fits(stream):
				seconds += stream.get_length()
				var folder := def.path_for(variant).get_base_dir().trim_prefix(SoundCatalog.ROOT)
				by_bank[folder] = float(by_bank.get(folder, 0.0)) + stream.get_length()
	var message := "%.0f s of sound decoded behind the loading bar (budget %.0f s): %s" + "\n"
	message += "Put the new sounds in a bank with `deferred = true` (made once the night runs)."
	message = message % [seconds, WARM_DECODE_BUDGET_S, by_bank]
	assert_float(seconds).override_failure_message(message).is_less_equal(WARM_DECODE_BUDGET_S)


func test_a_deferred_sound_waits_in_a_line_and_is_made_while_the_night_runs() -> void:
	var service: AudioService = auto_free(AudioService.new())
	add_child(service)
	var id := &"shot_ppsh"
	var def := SoundCatalog.get_def(id)
	assert_bool(def.deferred).is_true()
	var path := def.path_for(1)
	# Behind the bar it only queues the files: nothing is read or decoded there.
	assert_int(service.preload_sound_for_night(id)).is_equal(0)
	assert_bool(service._streams.has(path)).is_false()
	assert_bool(service._pcm.has(path)).is_false()
	assert_int(service.decode_pending()).is_equal(def.variants)
	# A sound played before its turn is the Ogg this time, and its takes go to the front of the line.
	var other := SoundCatalog.get_def(&"shot_mp5")
	service.preload_sound_for_night(other.id)
	assert_str(service._decode_queue[0]).is_equal(def.path_for(1))
	service._pick_stream(other, true)
	assert_str(service._decode_queue[0]).is_equal(other.path_for(1))
	service._pick_stream(def, true)
	assert_str(service._decode_queue[0]).is_equal(def.path_for(1))
	assert_object(service._pick_stream(def, true)).is_instanceof(AudioStreamOggVorbis)
	# While the loading bar is up the line waits.
	service.decode_held = true
	for _i in 30:
		service._process(1.0 / 60.0)
	assert_bool(service._pcm.has(path)).is_false()
	service.decode_held = false
	# The service reads and decodes a few milliseconds of them every frame; the line empties.
	var frames := 0
	while service.decode_pending() > 0 and frames < 4000:
		service._process(1.0 / 60.0)
		frames += 1
	assert_int(service.decode_pending()).is_equal(0)
	assert_bool(service._pcm.has(path)).is_true()
	assert_bool(service._pcm.has(other.path_for(1))).is_true()
	# A sound outside the deferred banks is decoded at once.
	var plain := &"points_tick"
	assert_bool(SoundCatalog.get_def(plain).deferred).is_false()
	service.preload_sound_for_night(plain)
	assert_bool(service._pcm.has(SoundCatalog.get_def(plain).path_for(1))).is_true()
