extends GdUnitTestSuite
## The menu's ambience and music sit under the menu's hints on every speaker (#926, #979), and they
## cost the night's loading nothing. `tools/audio/menu_speakers.py` puts a recording of the five
## beds and of every hint through a laptop speaker and a phone speaker and writes
## `menu_bed_levels.json`: the trims it ran at, the hints' levels, and the worst margins it found.
## This test pins those: a trim or a hint level that changed since asks for the check to be run
## again, and the margins it found have to be the kit's (a hint 10 dB over the bed's momentary
## loudness is plain; in the hints' own band 6 dB over the bed's loud moments). The load: the
## projector and the crickets are the Ogg files the night already loads, so the night's warm-up has
## nothing more to read or decode for them; the music and the wind are three small streams that only
## the menu reads.

const PIN := "res://tests/core/menu_bed_levels.json"
const TARGETS := "res://tests/core/menu_sound_levels.json"
## The bed's five files together (the music and the wind are 1.5 MB of it).
const MAX_BED_BYTES := 2 * 1024 * 1024


func _pin() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PIN))


func test_the_trims_are_the_ones_the_speaker_check_ran_at() -> void:
	var trims: Dictionary = _pin()["trims"]
	for id: String in trims:
		(
			assert_float(SoundCatalog.get_def(StringName(id)).volume_db)
			. override_failure_message(
				(
					"%s changed: run tools/audio/menu_speakers.py again and update menu_bed_levels.json"
					% id
				)
			)
			. is_equal(float(trims[id]))
		)
	assert_int(trims.size()).is_equal(MenuAmbience.BEDS.size())


func test_the_hints_are_the_levels_the_speaker_check_ran_at() -> void:
	var ran_at: Dictionary = _pin()["hint_targets_dbfs"]
	var targets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TARGETS))
	for key: String in ran_at:
		(
			assert_float(float(targets[key]["target_dbfs"]))
			. override_failure_message(
				(
					"%s changed: run tools/audio/menu_speakers.py again and update menu_bed_levels.json"
					% key
				)
			)
			. is_equal(float(ran_at[key]))
		)


func test_every_hint_is_plain_over_the_bed_on_every_speaker() -> void:
	var pin := _pin()
	var gates: Dictionary = pin["gates"]
	var worst: Dictionary = pin["worst"]
	assert_array(worst.keys()).contains_exactly_in_any_order(["flat", "laptop", "phone"])
	for model: String in worst:
		(
			assert_float(float(worst[model]["over_bed_db"]))
			. override_failure_message("%s: a hint is not 10 dB over the bed" % model)
			. is_greater_equal(10.0)
		)
		(
			assert_float(float(worst[model]["in_band_db"]))
			. override_failure_message("%s: a hint is buried by the crickets" % model)
			. is_greater_equal(6.0)
		)
		assert_float(float(gates["over_bed_db"])).is_equal(10.0)
		assert_float(float(gates["in_band_db"])).is_equal(6.0)


func test_the_bed_is_quieter_than_every_hint_and_than_the_nights_own_beds() -> void:
	var worst: Dictionary = _pin()["worst"]
	# The bed's loudest 400 ms on a flat speaker, against the night's crickets alone (-49.9 LUFS
	# before the Ambience slider) and the night's beds together (-37.9): quiet, not silent.
	assert_float(float(worst["flat"]["bed_lufs_m"])).is_between(-52.0, -38.0)
	assert_float(float(worst["laptop"]["bed_lufs_m"])).is_less(float(worst["flat"]["bed_lufs_m"]))
	assert_float(float(worst["phone"]["bed_lufs_m"])).is_less(float(worst["laptop"]["bed_lufs_m"]))


func test_the_bed_is_small_and_only_the_music_and_the_wind_are_files_of_its_own() -> void:
	var bytes := 0
	var night := {}
	for id: StringName in [&"bed_crickets", &"bed_projector"]:
		night[SoundCatalog.get_def(id).path_for(1)] = true
	var own: Array[StringName] = []
	for id in MenuAmbience.BEDS:
		var path := SoundCatalog.get_def(id).path_for(1)
		if not night.has(path):
			own.append(id)
		bytes += FileAccess.get_file_as_bytes(path).size()
	assert_array(own).contains_exactly_in_any_order(
		[&"bed_menu_pad", &"bed_menu_bells", &"bed_menu_wind"]
	)
	assert_int(bytes).is_less(MAX_BED_BYTES)


func test_the_nights_warm_up_has_nothing_more_to_read_or_decode_for_the_bed() -> void:
	var audio := AudioService.new()
	add_child(audio)
	# What the night's loading bar does, in the catalog's order: the night's beds first.
	var loaded := 0
	for id: StringName in [&"bed_crickets", &"bed_projector"]:
		loaded += audio.preload_sound_for_night(id)
	assert_int(loaded).is_equal(2)
	# The menu's crickets and motor are those two files: nothing more for the night to read. The
	# music and the wind are menu-only streams, never decoded to samples (they are not in the night).
	for id: StringName in [&"bed_menu_projector", &"bed_menu_crickets"]:
		assert_int(audio.preload_sound_for_night(id)).override_failure_message(id).is_equal(0)
	assert_int(audio.decode_pending()).is_equal(0)
	audio.free()
	Audio.install_ui_hook()
