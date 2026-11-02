extends GdUnitTestSuite
## The menu's account numbers (Billing arithmetic from the progression design) and the way each
## device asks for the next or previous tab.


func test_billing_levels_follow_the_design_curve() -> void:
	assert_int(MenuProfile.xp_to_next(1)).is_equal(180)
	assert_int(MenuProfile.xp_to_next(49)).is_equal(1620)
	assert_int(MenuProfile.level_of(0)).is_equal(1)
	assert_int(MenuProfile.level_of(179)).is_equal(1)
	assert_int(MenuProfile.level_of(180)).is_equal(2)
	# 44,100 in all for levels 1 to 50.
	assert_int(MenuProfile.xp_at(MenuProfile.MAX_LEVEL)).is_equal(44100)
	assert_int(MenuProfile.level_of(44100)).is_equal(MenuProfile.MAX_LEVEL)
	assert_int(MenuProfile.level_of(10000000)).is_equal(MenuProfile.MAX_LEVEL)


func test_progress_inside_a_level() -> void:
	var profile := MenuProfile.from_json(
		MenuProfile.to_json("Ann", MenuProfile.xp_at(14) + 212, 485)
	)
	assert_int(profile.level()).is_equal(14)
	assert_int(profile.xp_in_level()).is_equal(212)
	assert_int(profile.xp_for_level()).is_equal(570)
	assert_float(profile.level_fraction()).is_equal_approx(212.0 / 570.0, 0.0001)
	assert_int(profile.stubs).is_equal(485)
	assert_str(profile.display_name).is_equal("Ann")


func test_an_empty_or_damaged_cache_is_a_new_player() -> void:
	for text in ["", "not json", "[1,2]", '{"xp": "lots", "stubs": -5, "name": "   "}']:
		var profile := MenuProfile.from_json(text)
		assert_int(profile.level()).is_equal(1)
		assert_int(profile.stubs).is_equal(0)
		assert_str(profile.display_name).is_equal(MenuProfile.DEFAULT_NAME)


func test_a_long_name_is_cut() -> void:
	var profile := MenuProfile.from_json(MenuProfile.to_json("A".repeat(60), 0, 0))
	assert_int(profile.display_name.length()).is_equal(MenuProfile.MAX_NAME)


func test_mastery_levels_cost_what_the_design_says() -> void:
	var profile := MenuProfile.from_json(
		MenuProfile.to_json("x", 0, 0, {"rifle": 499, "shotgun": 500, "smg": 8100})
	)
	assert_int(profile.mastery_level(&"rifle")).is_equal(1)
	assert_int(profile.mastery_level(&"shotgun")).is_equal(2)
	assert_int(profile.mastery_level(&"smg")).is_equal(10)
	assert_int(profile.mastery_level(&"none")).is_equal(1)


func _key(code: Key, pressed := true, ctrl := false, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	return event


func _pad(button: JoyButton, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func test_every_device_steps_the_tabs() -> void:
	assert_int(MenuNav.tab_step(_key(KEY_E))).is_equal(1)
	assert_int(MenuNav.tab_step(_key(KEY_Q))).is_equal(-1)
	assert_int(MenuNav.tab_step(_key(KEY_TAB, true, true))).is_equal(1)
	assert_int(MenuNav.tab_step(_key(KEY_TAB, true, true, true))).is_equal(-1)
	assert_int(MenuNav.tab_step(_pad(JOY_BUTTON_RIGHT_SHOULDER))).is_equal(1)
	assert_int(MenuNav.tab_step(_pad(JOY_BUTTON_LEFT_SHOULDER))).is_equal(-1)


func test_releases_repeats_and_other_keys_are_not_asks() -> void:
	assert_int(MenuNav.tab_step(_key(KEY_E, false))).is_equal(0)
	assert_int(MenuNav.tab_step(_pad(JOY_BUTTON_RIGHT_SHOULDER, false))).is_equal(0)
	assert_int(MenuNav.tab_step(_key(KEY_W))).is_equal(0)
	assert_int(MenuNav.tab_step(_pad(JOY_BUTTON_A))).is_equal(0)
	var echo := _key(KEY_E)
	echo.echo = true
	assert_int(MenuNav.tab_step(echo)).is_equal(0)
	assert_int(MenuNav.tab_step(_key(KEY_E, true, true))).is_equal(0)
	assert_int(MenuNav.tab_step(InputEventMouseMotion.new())).is_equal(0)


func test_numbers_are_grouped() -> void:
	assert_str(MenuNav.grouped(0)).is_equal("0")
	assert_str(MenuNav.grouped(999)).is_equal("999")
	assert_str(MenuNav.grouped(1850)).is_equal("1,850")
	assert_str(MenuNav.grouped(1234567)).is_equal("1,234,567")
	assert_str(MenuNav.fraction_text(1850, 3000)).is_equal("1,850/3,000")
