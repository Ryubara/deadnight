extends GdUnitTestSuite
## The look as data: the catalogue is consistent, every preset round-trips through the save form
## and the wire form, bad input falls back instead of failing, and locked options never survive.


func test_there_are_eight_distinct_presets() -> void:
	var keys := {}
	for i in LookCatalog.presets().size():
		keys[CharacterLook.from_preset(i).key()] = true
	assert_int(LookCatalog.presets().size()).is_equal(8)
	assert_int(keys.size()).is_equal(8)


func test_the_default_look_is_the_first_preset() -> void:
	assert_bool(CharacterLook.default_look().equals(CharacterLook.from_preset(0))).is_true()
	assert_bool(LookStore.load_look().equals(CharacterLook.from_preset(0))).is_true()


func test_every_slot_starts_with_a_free_entry_and_fits_a_byte() -> void:
	for slot in LookCatalog.colour_slots():
		assert_dict(LookCatalog.palette(slot)[0]["gate"]).is_empty()
		assert_int(LookCatalog.palette(slot).size()).is_less(256)
	for slot in LookCatalog.part_slots():
		assert_int(LookCatalog.options(slot).size()).is_greater(0)
		assert_dict(LookCatalog.options(slot)[0]["gate"]).is_empty()
		assert_int(LookCatalog.options(slot).size()).is_less(256)


func test_every_preset_uses_only_free_options() -> void:
	var unlocks := LookUnlocks.new()
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		assert_bool(look.equals(look.without_locked(unlocks))).is_true()


func test_every_preset_round_trips_through_dict_json_and_bytes() -> void:
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		assert_bool(CharacterLook.from_dict(look.to_dict()).equals(look)).is_true()
		assert_bool(CharacterLook.from_json(look.to_json()).equals(look)).is_true()
		var bytes := look.to_bytes()
		assert_int(bytes.size()).is_equal(CharacterLook.wire_size())
		assert_bool(CharacterLook.from_bytes(bytes).equals(look)).is_true()


func test_the_wire_form_is_small() -> void:
	assert_int(CharacterLook.wire_size()).is_less_equal(16)


func test_a_saved_look_with_unknown_or_wrong_entries_falls_back_slot_by_slot() -> void:
	var data := CharacterLook.from_preset(1).to_dict()
	assert_str(data["parts"]["headwear"]).is_equal("pillbox")
	data["parts"]["headwear"] = "jetpack"
	data["colours"]["skin"] = "not_a_colour"
	data["colours"]["secondary"] = 7
	var look := CharacterLook.from_dict(data)
	assert_str(String(look.parts[&"headwear"])).is_equal("none")
	assert_int(look.colours[&"skin"]).is_equal(0)
	assert_int(look.colours[&"secondary"]).is_equal(0)
	# What was fine stays.
	assert_int(look.colours[&"primary"]).is_equal(CharacterLook.from_preset(1).colours[&"primary"])


func test_garbage_yields_the_default_look() -> void:
	for junk: Variant in [null, 5, "text", [], {"parts": 3, "colours": "x"}]:
		assert_bool(CharacterLook.from_dict(junk).equals(CharacterLook.new())).is_true()
	assert_bool(CharacterLook.from_json("{not json").equals(CharacterLook.new())).is_true()
	assert_bool(CharacterLook.from_json("").equals(CharacterLook.new())).is_true()


func test_bytes_of_the_wrong_version_or_length_are_refused() -> void:
	var good := CharacterLook.from_preset(2).to_bytes()
	var other_version := good.duplicate()
	other_version[0] = CharacterLook.VERSION + 1
	assert_object(CharacterLook.from_bytes(other_version)).is_null()
	assert_object(CharacterLook.from_bytes(good.slice(0, 5))).is_null()
	assert_object(CharacterLook.from_bytes(PackedByteArray())).is_null()
	var longer := good.duplicate()
	longer.append(0)
	assert_object(CharacterLook.from_bytes(longer)).is_null()


func test_out_of_range_indices_become_the_first_option() -> void:
	var bytes := CharacterLook.from_preset(2).to_bytes()
	for i in range(1, bytes.size()):
		bytes[i] = 255
	var look := CharacterLook.from_bytes(bytes)
	assert_bool(look.equals(CharacterLook.new())).is_true()


func test_locked_options_are_put_back() -> void:
	var look := CharacterLook.new()
	look.colours[&"primary"] = 11
	look.colours[&"accent"] = 14
	var plain := look.without_locked(LookUnlocks.new())
	assert_int(plain.colours[&"primary"]).is_equal(0)
	assert_int(plain.colours[&"accent"]).is_equal(0)
	var rich := LookUnlocks.new()
	rich.billing_level = 10
	rich.grant(&"accent", &"teal")
	var kept := look.without_locked(rich)
	assert_int(kept.colours[&"primary"]).is_equal(11)
	assert_int(kept.colours[&"accent"]).is_equal(14)


func test_a_random_look_is_repeatable_and_never_locked() -> void:
	var first := RandomNumberGenerator.new()
	first.seed = 7
	var second := RandomNumberGenerator.new()
	second.seed = 7
	var unlocks := LookUnlocks.new()
	for i in 50:
		var a := CharacterLook.randomized(first)
		var b := CharacterLook.randomized(second)
		assert_bool(a.equals(b)).is_true()
		assert_bool(a.equals(a.without_locked(unlocks))).is_true()


func test_save_and_restore_through_the_settings_file() -> void:
	var path := "user://look_store_test.cfg"
	var old_path := Settings.path
	Settings.path = path
	Settings.reset_defaults()
	var look := CharacterLook.from_preset(5)
	LookStore.save_look(look)
	# A fresh read from disk, as after a restart.
	Settings.load_from_disk()
	assert_bool(LookStore.load_look().equals(look)).is_true()
	# A hand-edited file that wears a locked item does not keep it.
	var edited := look.duplicate_look()
	edited.colours[&"primary"] = 11
	Settings.set_value(SettingsService.CHARACTER_LOOK, edited.to_json())
	assert_int(LookStore.load_look().colours[&"primary"]).is_equal(0)
	Settings.reset_defaults()
	Settings.save()
	Settings.path = old_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_an_oversized_saved_text_is_ignored() -> void:
	var old_path := Settings.path
	Settings.path = "user://look_store_test2.cfg"
	Settings.set_value(SettingsService.CHARACTER_LOOK, "x".repeat(SettingsService.MAX_TEXT + 1))
	assert_str(Settings.get_value(SettingsService.CHARACTER_LOOK)).is_empty()
	Settings.reset_defaults()
	Settings.path = old_path
