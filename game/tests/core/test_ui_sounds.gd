extends GdUnitTestSuite
## The menu's sound rules (#894, `UiSounds`): the quiet hints have a gap and a burst cap, never
## follow a heavier sound closely and are not made on a touch screen or by a mouse that did not
## move; a slider ticks once for a step, not for a frame, and higher with its value; a toggle
## says which way it went; a control with no role in the table is found, a written silence
## plays nothing.

var _audio: AudioService
var _rows: UiSounds


func before_test() -> void:
	_audio = AudioService.new()
	_audio.seed_random(3)
	add_child(_audio)
	_audio.set_process(false)
	_rows = _audio.ui
	UIInputMode.reset()
	UIInputMode.pointer = true


func after_test() -> void:
	_audio.free()
	UIInputMode.reset()
	Audio.install_ui_hook()


func _control(role: StringName) -> Button:
	var control: Button = auto_free(Button.new())
	add_child(control)
	UiSounds.tag(control, role)
	return control


func _count(id: StringName) -> int:
	return _rows.started.count(id)


func test_a_hover_makes_the_bulb_tick_and_a_second_one_too_soon_does_not() -> void:
	var ticket := _control(&"ticket")
	assert_bool(_rows.handle(&"hover", ticket)).is_true()
	_audio.advance(UiSounds.HINT_GAP * 0.4)
	assert_bool(_rows.handle(&"hover", ticket)).is_false()
	_audio.advance(UiSounds.HINT_GAP)
	assert_bool(_rows.handle(&"hover", ticket)).is_true()
	assert_int(_count(&"ui_hover")).is_equal(2)


func test_a_sweep_over_a_column_of_rows_is_a_few_ticks_not_a_machine_gun() -> void:
	var ticket := _control(&"ticket")
	# A pointer crossing a row every 90 ms for four seconds: past the gap, so only the burst
	# cap holds.
	var times: Array[float] = []
	var now := 0.0
	for _i in 44:
		if _rows.handle(&"hover", ticket):
			times.append(now)
		_audio.advance(0.09)
		now += 0.09
	for time in times:
		var inside := times.filter(
			func(other: float) -> bool: return other >= time and other < time + UiSounds.HINT_WINDOW
		)
		assert_int(inside.size()).is_less_equal(UiSounds.HINT_BURST)
	assert_int(times.size()).is_greater(8)
	assert_int(times.size()).is_less(30)


func test_no_hint_is_made_on_a_touch_screen_but_the_tap_is_a_press() -> void:
	var ticket := _control(&"ticket")
	UIInputMode.touch = true
	assert_bool(_rows.handle(&"hover", ticket)).is_false()
	assert_bool(_rows.handle(&"focus", ticket)).is_false()
	assert_bool(_rows.handle(&"press", ticket)).is_true()


func test_the_pointer_hovers_and_the_keys_focus_and_neither_makes_both() -> void:
	var ticket := _control(&"ticket")
	UIInputMode.pointer = true
	assert_bool(_rows.handle(&"focus", ticket)).is_false()
	assert_bool(_rows.handle(&"hover", ticket)).is_true()
	_audio.advance(1.0)
	UIInputMode.pointer = false
	assert_bool(_rows.handle(&"hover", ticket)).is_false()
	assert_bool(_rows.handle(&"focus", ticket)).is_true()


func test_a_hint_stays_quiet_just_after_a_heavier_sound() -> void:
	var ticket := _control(&"ticket")
	assert_bool(_rows.handle(&"press", ticket)).is_true()
	_audio.advance(UiSounds.HINT_AFTER_STRONG * 0.5)
	assert_bool(_rows.handle(&"hover", ticket)).is_false()
	_audio.advance(UiSounds.HINT_AFTER_STRONG)
	assert_bool(_rows.handle(&"hover", ticket)).is_true()


func test_a_slider_ticks_once_for_a_step_with_a_gap_and_only_while_it_is_used() -> void:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = 25.0
	auto_free(slider)
	add_child(slider)
	UiSounds.tag(slider, &"slider")
	# Set by code, with no pointer on it and no focus: not a step the player took.
	assert_bool(_rows.handle(&"tick", slider)).is_false()
	slider.grab_focus()
	var made := 0
	for _i in 60:
		if _rows.handle(&"tick", slider):
			made += 1
		_audio.advance(1.0 / 60.0)
	# A second of ticks asked for every frame: the gap lets a bit over a dozen through.
	assert_int(made).is_less_equal(int(ceil(1.0 / UiSounds.TICK_GAP)) + 1)
	assert_int(made).is_greater(8)


func test_a_sliders_tick_rises_with_its_value() -> void:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	auto_free(slider)
	add_child(slider)
	slider.value = 0.0
	var low := _rows._pitch_for(&"tick", slider)
	slider.value = 100.0
	var high := _rows._pitch_for(&"tick", slider)
	assert_float(low).is_equal(UiSounds.TICK_PITCH_LOW)
	assert_float(high).is_equal(UiSounds.TICK_PITCH_HIGH)


func test_a_tab_is_a_little_higher_going_on_and_lower_coming_back() -> void:
	var bar := _control(&"tab_bar")
	bar.set_meta(UiSounds.DIRECTION_META, 1)
	var forward := _rows._pitch_for(&"tab", bar)
	bar.set_meta(UiSounds.DIRECTION_META, -1)
	var back := _rows._pitch_for(&"tab", bar)
	assert_float(forward).is_greater(0.0)
	assert_float(back).is_equal(-forward)


func test_a_switch_says_which_way_it_went() -> void:
	var toggle := _control(&"toggle")
	assert_bool(_rows.handle(&"on", toggle)).is_true()
	_audio.advance(0.2)
	assert_bool(_rows.handle(&"off", toggle)).is_true()
	assert_array(_rows.started).is_equal([&"ui_toggle_on", &"ui_toggle_off"])


func test_a_back_button_and_a_start_button_are_known_by_their_words() -> void:
	var back := UIButton.new()
	back.text = "Back"
	back.variant = UIButton.Variant.PRIMARY
	var start := UIButton.new()
	start.text = "Start the night"
	start.variant = UIButton.Variant.PRIMARY
	var plain := UIButton.new()
	plain.text = "Resume"
	plain.variant = UIButton.Variant.SECONDARY
	for button: UIButton in [back, start, plain]:
		auto_free(button)
		add_child(button)
	assert_str(UiSounds.role_of(back)).is_equal("back_button")
	assert_str(UiSounds.role_of(start)).is_equal("commit_button")
	assert_str(UiSounds.role_of(plain)).is_equal("button_secondary")


func test_a_control_with_no_role_is_reported_and_a_silent_row_plays_nothing() -> void:
	var stray: Button = auto_free(Button.new())
	add_child(stray)
	_rows.handle(&"press", stray)
	assert_array(_rows.misses).contains(["<Button>/press"])
	var field := _control(&"field")
	assert_bool(_rows.handle(&"press", field)).is_false()
	var ticket := _control(&"ticket")
	_rows.misses.clear()
	_rows.handle(&"on", ticket)
	assert_array(_rows.misses).contains(["ticket/on"])


func test_the_same_sound_is_not_started_twice_in_a_blink() -> void:
	var ticket := _control(&"ticket")
	assert_bool(_rows.handle(&"press", ticket)).is_true()
	assert_bool(_rows.handle(&"press", ticket)).is_false()
	_audio.advance(UiSounds.SAME_GAP * 2.0)
	assert_bool(_rows.handle(&"press", ticket)).is_true()


func test_the_router_and_screens_have_the_whole_vocabulary_in_the_any_row() -> void:
	var router := Node.new()
	auto_free(router)
	for cue: StringName in [&"push", &"pop", &"back", &"tab", &"confirm", &"refuse", &"sign"]:
		_audio.advance(1.0)
		assert_bool(_rows.handle(cue, router)).override_failure_message(cue).is_true()


func test_the_level_a_play_varies_by_is_small() -> void:
	assert_float(UiSounds.LEVEL_JITTER_DB).is_less_equal(1.0)
