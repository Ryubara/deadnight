# UIGlyph and UIHint: the glyph for an action follows the device in use (keyboard, gamepad, which
# pad), reads the InputMap so a rebound key shows the new key, falls back to a question mark when
# nothing is bound, sinks while the action is held, and the hint hides under a finger (#10).
extends GdUnitTestSuite

const ACTION := &"gds_test_glyph"

var _glyph: UIGlyph


func before_test() -> void:
	UIInputMode.reset()
	UIMotion.reduced = false
	if InputMap.has_action(ACTION):
		InputMap.erase_action(ACTION)
	InputMap.add_action(ACTION)
	InputMap.action_add_event(ACTION, _key(KEY_E))
	InputMap.action_add_event(ACTION, _button(JOY_BUTTON_Y))
	_glyph = auto_free(UIGlyph.new())
	_glyph.action = ACTION
	add_child(_glyph)
	await await_idle_frame()


func after_test() -> void:
	InputMap.erase_action(ACTION)
	UIInputMode.reset()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func test_the_keyboard_shows_the_key_and_the_gamepad_the_button() -> void:
	assert_str(_glyph.caption()).is_equal("E")
	UIInputMode.track(_button(JOY_BUTTON_A))
	assert_str(_glyph.caption()).is_equal("Y")
	UIInputMode.track(_key(KEY_SPACE))
	assert_str(_glyph.caption()).is_equal("E")


func test_the_glyph_follows_a_pad_family_switch() -> void:
	UIInputMode.track(_button(JOY_BUTTON_A))
	_glyph.event = _button(JOY_BUTTON_A)
	assert_str(_glyph.caption()).is_equal("A")
	UIInputMode.family = UIInputMode.Family.NINTENDO
	assert_str(_glyph.caption()).is_equal("B")
	UIInputMode.family = UIInputMode.Family.PLAYSTATION
	(
		assert_str(
			UIGlyph.caption_for(_button(JOY_BUTTON_LEFT_SHOULDER), UIInputMode.Family.PLAYSTATION)
		)
		. is_equal("L1")
	)


func test_captions_for_every_kind_of_binding() -> void:
	assert_str(UIGlyph.caption_for(_key(KEY_ESCAPE))).is_equal("ESC")
	assert_str(UIGlyph.caption_for(_key(KEY_SPACE))).is_equal("SPACE")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	assert_str(UIGlyph.caption_for(click)).is_equal("RMB")
	assert_str(UIGlyph.caption_for(_button(JOY_BUTTON_LEFT_SHOULDER))).is_equal("LB")
	assert_str(UIGlyph.caption_for(_button(JOY_BUTTON_START))).is_equal("START")
	assert_str(UIGlyph.caption_for(_button(JOY_BUTTON_DPAD_LEFT))).is_equal("LEFT")
	assert_str(UIGlyph.caption_for(_button(JOY_BUTTON_LEFT_STICK))).is_equal("L3")
	assert_str(UIGlyph.caption_for(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0))).is_equal("RT")
	(
		assert_str(
			UIGlyph.caption_for(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), UIInputMode.Family.PLAYSTATION)
		)
		. is_equal("R2")
	)
	assert_str(UIGlyph.caption_for(_axis(JOY_AXIS_LEFT_X, -1.0))).is_equal("L")
	assert_str(UIGlyph.caption_for(InputEventScreenTouch.new())).is_equal("?")


func test_a_rebound_key_shows_the_new_key_after_a_refresh() -> void:
	InputMap.action_erase_events(ACTION)
	InputMap.action_add_event(ACTION, _key(KEY_F))
	_glyph.refresh()
	assert_str(_glyph.caption()).is_equal("F")


func test_an_unbound_action_shows_a_question_mark() -> void:
	_glyph.action = &"gds_no_such_action"
	assert_object(_glyph.binding()).is_null()
	assert_str(_glyph.caption()).is_equal("?")
	InputMap.action_erase_events(ACTION)
	_glyph.action = ACTION
	assert_str(_glyph.caption()).is_equal("?")


func test_the_device_can_be_pinned() -> void:
	_glyph.device = UIGlyph.Device.GAMEPAD
	assert_str(_glyph.caption()).is_equal("Y")
	_glyph.device = UIGlyph.Device.KEYBOARD
	UIInputMode.track(_button(JOY_BUTTON_A))
	assert_str(_glyph.caption()).is_equal("E")


func test_a_glyph_is_as_wide_as_its_text_and_never_narrower_than_tall() -> void:
	var short := _glyph.custom_minimum_size
	_glyph.event = _key(KEY_ENTER)
	var long := _glyph.custom_minimum_size
	assert_float(long.x).is_greater(short.x)
	assert_float(short.x).is_greater_equal(short.y)
	assert_float(long.y).is_equal(short.y)


func test_the_glyph_sinks_while_its_action_is_held() -> void:
	assert_bool(_glyph._held).is_false()
	Input.action_press(ACTION)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_glyph._held).is_true()
	Input.action_release(ACTION)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_glyph._held).is_false()


func test_input_mode_reports_a_change_once_and_only_when_it_changed() -> void:
	var seen := [0]
	var count := func() -> void: seen[0] += 1
	UIInputMode.changed().connect(count)
	UIInputMode.track(_button(JOY_BUTTON_A))
	UIInputMode.track(_button(JOY_BUTTON_B))
	assert_int(seen[0]).is_equal(1)
	UIInputMode.track(_key(KEY_E))
	assert_int(seen[0]).is_equal(2)
	UIInputMode.changed().disconnect(count)


func test_pad_names_pick_their_family() -> void:
	assert_int(UIInputMode.family_for("PS5 Controller")).is_equal(UIInputMode.Family.PLAYSTATION)
	assert_int(UIInputMode.family_for("Sony DualSense")).is_equal(UIInputMode.Family.PLAYSTATION)
	assert_int(UIInputMode.family_for("Nintendo Switch Pro Controller")).is_equal(
		UIInputMode.Family.NINTENDO
	)
	assert_int(UIInputMode.family_for("Xbox Series Controller")).is_equal(
		UIInputMode.Family.GENERIC
	)
	assert_int(UIInputMode.family_for("")).is_equal(UIInputMode.Family.GENERIC)


func test_a_hint_pairs_a_glyph_with_its_words_and_hides_under_a_finger() -> void:
	var hint := UIHint.new()
	hint.action = ACTION
	hint.text = "Use"
	add_child(auto_free(hint))
	await await_idle_frame()
	assert_str(hint.glyph.caption()).is_equal("E")
	assert_bool(hint.visible).is_true()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	UIInputMode.track(touch)
	assert_bool(hint.visible).is_false()
	UIInputMode.track(_key(KEY_E))
	assert_bool(hint.visible).is_true()
