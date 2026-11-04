extends GdUnitTestSuite
## The look as data: the catalogue is consistent, every preset round-trips through the save form
## and the wire form, bad input falls back instead of failing, and locked options never survive.


func test_there_are_eight_distinct_presets_of_his_then_four_of_hers() -> void:
	var keys := {}
	var bodies: Array[StringName] = []
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		keys[look.key()] = true
		bodies.append(look.body())
	assert_int(LookCatalog.presets().size()).is_equal(12)
	assert_int(keys.size()).is_equal(12)
	# His eight keep their places (a seat's starting look is the preset of its index).
	for i in 8:
		assert_str(String(bodies[i])).is_equal("male")
	for i in range(8, 12):
		assert_str(String(bodies[i])).is_equal("female")


func test_switching_the_character_swaps_only_a_cut_of_the_other_one() -> void:
	var look := CharacterLook.from_preset(0)  # Greaser: pompadour
	var before := look.duplicate_look()
	look.set_body(LookCatalog.FEMALE)
	assert_str(String(look.body())).is_equal("female")
	assert_str(String(look.parts[&"hair"])).is_equal("bob")
	for slot in LookCatalog.part_slots():
		if slot not in [LookCatalog.BODY_SLOT, &"hair"]:
			assert_str(String(look.parts[slot])).is_equal(String(before.parts[slot]))
	assert_dict(look.colours).is_equal(before.colours)
	look.set_body(LookCatalog.MALE)
	assert_str(String(look.parts[&"hair"])).is_equal("crew")
	# A cut either character wears stays.
	var soda := CharacterLook.from_preset(4)
	assert_str(String(soda.parts[&"hair"])).is_equal("ponytail")
	soda.set_body(LookCatalog.FEMALE)
	assert_str(String(soda.parts[&"hair"])).is_equal("ponytail")
	# An unknown character changes nothing.
	soda.set_body(&"robot")
	assert_str(String(soda.body())).is_equal("female")


func test_a_look_saved_before_the_character_choice_is_his() -> void:
	var data := CharacterLook.from_preset(3).to_dict()
	(data["parts"] as Dictionary).erase("body")
	data["version"] = 1
	var look := CharacterLook.from_dict(data)
	assert_str(String(look.body())).is_equal("male")
	assert_str(String(look.parts[&"hair"])).is_equal("flattop")


func test_a_random_look_for_her_is_hers_with_a_cut_she_wears() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 40:
		var look := CharacterLook.randomized(rng, null, LookCatalog.FEMALE)
		assert_str(String(look.body())).is_equal("female")
		assert_bool(LookCatalog.hair_body(look.parts[&"hair"]) in [&"", &"female"]).is_true()


func test_the_default_look_is_the_first_preset() -> void:
	assert_bool(CharacterLook.default_look().equals(CharacterLook.from_preset(0))).is_true()
	# Worn by a player who owns all of it; a new one wears what they own of it.
	var everything := LookUnlocks.at_level(LevelCurve.MAX_LEVEL)
	assert_bool(LookStore.load_look(everything).equals(CharacterLook.from_preset(0))).is_true()
	var starter := LookUnlocks.new()
	var first := LookStore.load_look(starter)
	assert_bool(first.equals(first.without_locked(starter))).is_true()
	assert_bool(first.equals(CharacterLook.from_preset(0))).is_false()


func test_every_slot_has_a_free_entry_and_fits_a_byte() -> void:
	var starter := LookUnlocks.new()
	for slot in LookCatalog.colour_slots():
		assert_dict(LookCatalog.palette(slot)[0]["gate"]).is_empty()
		assert_int(LookCatalog.first_open_colour(slot, starter)).is_equal(0)
		assert_int(LookCatalog.palette(slot).size()).is_less(256)
	for slot in LookCatalog.part_slots():
		assert_int(LookCatalog.options(slot).size()).is_greater(0)
		# The first of a slot is not always free (the boots are the shoes' first, from level 12): what a
		# new player falls back to is.
		var open := LookCatalog.first_open(slot, starter)
		var entry: Dictionary = LookCatalog.options(slot)[LookCatalog.option_index(slot, open)]
		assert_dict(entry["gate"]).is_empty()
		assert_int(LookCatalog.options(slot).size()).is_less(256)


func test_a_preset_is_whole_for_a_player_who_owns_it_and_repaired_for_one_who_does_not() -> void:
	var everything := LookUnlocks.at_level(LevelCurve.MAX_LEVEL)
	var starter := LookUnlocks.new()
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		assert_bool(look.equals(look.without_locked(everything))).is_true()
		var plain := look.without_locked(starter)
		assert_bool(plain.equals(plain.without_locked(starter))).is_true()


func test_every_preset_round_trips_through_dict_json_and_bytes() -> void:
	for i in LookCatalog.presets().size():
		var look := CharacterLook.from_preset(i)
		assert_bool(CharacterLook.from_dict(look.to_dict()).equals(look)).is_true()
		assert_bool(CharacterLook.from_json(look.to_json()).equals(look)).is_true()
		var bytes := look.to_bytes()
		assert_int(bytes.size()).is_equal(CharacterLook.wire_size())
		assert_bool(CharacterLook.from_bytes(bytes).equals(look)).is_true()


## `look` as a build from before the mouth (#1061) sent it: version 2, no mouth's byte.
func _version_2_bytes(look: CharacterLook) -> PackedByteArray:
	var bytes := look.to_bytes()
	bytes[0] = 2
	bytes.remove_at(CharacterLook.wire_slots(3).find(&"mouth") + 1)
	return bytes


func test_a_look_from_before_the_mouth_wears_the_first_and_keeps_the_rest() -> void:
	var look := CharacterLook.from_preset(6)
	look.colours[&"accent"] = 3
	var bytes := _version_2_bytes(look)
	assert_int(bytes.size()).is_equal(16)
	assert_int(bytes.size()).is_equal(CharacterLook.wire_size(2))
	assert_bool(CharacterLook.from_bytes(bytes).equals(look)).is_true()
	# Its slots are read at their old places: a mouth chosen here is not sent, the rest is.
	look.parts[&"mouth"] = &"teeth"
	var read := CharacterLook.from_bytes(_version_2_bytes(look))
	assert_str(String(read.parts[&"mouth"])).is_equal("smile")
	assert_str(String(read.parts[&"body"])).is_equal(String(look.parts[&"body"]))
	assert_int(read.colours[&"accent"]).is_equal(3)


func test_a_mouth_travels_in_the_look() -> void:
	for option: Dictionary in LookCatalog.options(&"mouth"):
		var look := CharacterLook.from_preset(1)
		look.parts[&"mouth"] = option["id"]
		var read := CharacterLook.from_bytes(look.to_bytes())
		assert_str(String(read.parts[&"mouth"])).is_equal(String(option["id"]))
		assert_str(String(CharacterLook.from_dict(look.to_dict()).parts[&"mouth"])).is_equal(
			String(option["id"])
		)


func test_a_look_saved_before_the_mouth_keeps_everything_and_wears_the_first() -> void:
	var look := CharacterLook.from_preset(5)
	var data := look.to_dict()
	(data["parts"] as Dictionary).erase("mouth")
	data["version"] = 2
	assert_bool(CharacterLook.from_dict(data).equals(look)).is_true()
	data["parts"]["mouth"] = "fangs"
	assert_str(String(CharacterLook.from_dict(data).parts[&"mouth"])).is_equal("smile")


func test_the_wire_form_is_small() -> void:
	assert_int(CharacterLook.wire_size()).is_less_equal(17)


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
	other_version[0] = CharacterLook.OLDEST_VERSION - 1
	assert_object(CharacterLook.from_bytes(other_version)).is_null()
	# The old version's byte with the new length, and the new one's with the old length.
	other_version[0] = CharacterLook.OLDEST_VERSION
	assert_object(CharacterLook.from_bytes(other_version)).is_null()
	assert_object(CharacterLook.from_bytes(good.slice(0, good.size() - 1))).is_null()
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
	var rich := LookUnlocks.at_level(42)
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
	var everything := LookUnlocks.at_level(LevelCurve.MAX_LEVEL)
	assert_bool(LookStore.load_look(everything).equals(look)).is_true()
	# A hand-edited file that wears a locked item does not keep it.
	var edited := look.duplicate_look()
	edited.colours[&"primary"] = 11
	Settings.set_value(SettingsService.CHARACTER_LOOK, edited.to_json())
	assert_int(LookStore.load_look(LookUnlocks.new()).colours[&"primary"]).is_equal(0)
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
