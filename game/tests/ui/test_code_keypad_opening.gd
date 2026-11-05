extends GdUnitTestSuite
## When the room code's keypad is up and how it sits on the screen (Deadnight #1183): only while a
## finger has the field, never taking the focus from it, away again when the finger goes elsewhere,
## and sized in the window's own pixels.

var _field: LineEdit
var _keypad: CodeKeypad
var _host: Control


func before_test() -> void:
	_host = auto_free(Control.new())
	add_child(_host)
	_field = LineEdit.new()
	_field.max_length = 8
	_field.text_changed.connect(
		func(text: String) -> void:
			var upper := text.to_upper()
			if upper != text:
				var at := _field.caret_column
				_field.text = upper
				_field.caret_column = at
	)
	_host.add_child(_field)
	_keypad = CodeKeypad.attach(_field, _host)
	await await_idle_frame()


func after_test() -> void:
	CodeKeypad.covering = 0.0


func _finger_on_the_field() -> void:
	var press := InputEventMouseButton.new()
	press.pressed = true
	press.device = InputEvent.DEVICE_ID_EMULATION
	_keypad._input(press)
	_field.grab_focus()


func _type(letters: String) -> void:
	for letter in letters:
		_keypad.key_for(letter).pressed.emit()


func test_a_finger_on_the_field_opens_the_keypad_and_losing_the_focus_closes_it() -> void:
	assert_bool(_keypad.is_open()).is_false()
	_finger_on_the_field()
	assert_bool(_keypad.is_open()).is_true()
	assert_float(CodeKeypad.covering).is_greater(0.0)
	_field.release_focus()
	assert_bool(_keypad.is_open()).is_false()
	assert_float(CodeKeypad.covering).is_equal(0.0)


func test_a_keyboard_or_a_mouse_reaching_the_field_does_not_open_it() -> void:
	_field.grab_focus()
	assert_bool(_keypad.is_open()).is_false()
	_field.release_focus()
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.device = 0  # a real mouse
	_keypad._input(click)
	_field.grab_focus()
	assert_bool(_keypad.is_open()).is_false()


func _finger_at(at: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.pressed = true
	press.device = InputEvent.DEVICE_ID_EMULATION
	press.position = at
	_keypad._input(press)


func test_a_finger_down_away_from_the_keypad_and_the_field_puts_the_keypad_away() -> void:
	_field.position = Vector2(500.0, 500.0)
	_finger_on_the_field()
	assert_bool(_keypad.is_open()).is_true()
	_finger_at(Vector2(5.0, 5.0))
	assert_bool(_keypad.is_open()).is_false()
	assert_bool(_field.has_focus()).is_false()


func test_a_finger_on_the_keypad_or_the_field_leaves_it_up() -> void:
	_field.position = Vector2(500.0, 500.0)
	_finger_on_the_field()
	_finger_at(_keypad.panel.get_global_rect().get_center())
	assert_bool(_keypad.is_open()).is_true()
	_finger_at(_field.get_global_rect().get_center())
	assert_bool(_keypad.is_open()).is_true()
	assert_bool(_field.has_focus()).is_true()


func test_a_finger_on_the_field_after_join_brings_the_keypad_back() -> void:
	_finger_on_the_field()
	_keypad.join_key.pressed.emit()
	assert_bool(_keypad.is_open()).is_false()
	assert_bool(_field.has_focus()).is_true()
	var press := InputEventMouseButton.new()
	press.pressed = true
	press.device = InputEvent.DEVICE_ID_EMULATION
	_keypad._on_field_input(press)
	assert_bool(_keypad.is_open()).is_true()


func test_a_touch_event_counts_as_a_finger_too() -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	assert_bool(CodeKeypad.is_finger_press(touch)).is_true()
	touch.pressed = false
	assert_bool(CodeKeypad.is_finger_press(touch)).is_false()


func test_a_key_takes_no_focus_so_the_field_keeps_it() -> void:
	_finger_on_the_field()
	for key: UIButton in _keypad.find_children("*", "UIButton", true, false):
		assert_int(key.focus_mode).is_equal(Control.FOCUS_NONE)
	_type("A")
	assert_bool(_field.has_focus()).is_true()


func test_hovering_a_key_leaves_the_focus_on_the_field() -> void:
	_finger_on_the_field()
	var key := _keypad.key_for("A")
	key.mouse_entered.emit()
	assert_bool(_field.has_focus()).is_true()
	assert_bool(key.has_focus()).is_false()


func test_a_field_with_the_keypad_does_not_ask_for_the_system_keyboard() -> void:
	assert_bool(_field.virtual_keyboard_enabled).is_false()


func test_a_hidden_field_closes_the_keypad() -> void:
	_finger_on_the_field()
	_field.hide()
	assert_bool(_keypad.is_open()).is_false()


func test_a_key_is_a_tenth_of_the_short_side_tall_in_the_windows_own_pixels() -> void:
	# A phone page: 844 x 390 CSS pixels at the pixel ratio of 2 the page reports, which is not "a
	# phone" to `MenuScale`, so the screen runs at one unit = 0.36 pixel.
	_keypad.layout_for(Vector2(1688.0, 780.0), Vector2(2337.0, 1080.0))
	var per_unit := 1688.0 / 2337.0
	assert_float(_keypad.key_height * per_unit).is_equal_approx(78.0, 0.5)
	# At the phone factor the same window shows half the units and a key is as many pixels.
	_keypad.layout_for(Vector2(1688.0, 780.0), Vector2(1168.5, 540.0))
	assert_float(_keypad.key_height * (1688.0 / 1168.5)).is_equal_approx(78.0, 0.5)


func test_a_key_is_never_less_than_a_fingertip_nor_more_than_a_part_of_the_screen() -> void:
	_keypad.layout_for(Vector2(800.0, 450.0), Vector2(1920.0, 1080.0))
	assert_float(_keypad.key_height * (800.0 / 1920.0)).is_equal_approx(CodeKeypad.KEY_MIN_PX, 0.5)
	_keypad.layout_for(Vector2(4000.0, 3000.0), Vector2(1920.0, 1080.0))
	assert_float(_keypad.key_height).is_less_equal(1080.0 * CodeKeypad.KEY_MAX_SHARE + 0.01)


func test_the_keypad_leaves_the_field_most_of_the_screen_in_a_phone_window() -> void:
	_keypad.layout_for(Vector2(1688.0, 780.0), Vector2(2337.0, 1080.0))
	_keypad.open()
	await await_idle_frame()
	assert_float(CodeKeypad.covering).is_less(1080.0 * 0.6)
	assert_float(CodeKeypad.covering).is_greater(1080.0 * 0.3)


func test_the_keys_are_laid_out_inside_the_screen_s_width() -> void:
	var units := get_viewport().get_visible_rect().size
	_keypad.layout_for(units * 0.36, units)
	_finger_on_the_field()
	await await_idle_frame()
	var width := units.x
	for key: UIButton in _keypad.find_children("*", "UIButton", true, false):
		var rect := key.get_global_rect()
		assert_float(rect.position.x).is_greater_equal(0.0)
		assert_float(rect.end.x).is_less_equal(width + 0.5)


func test_the_keypad_has_the_menu_s_theme() -> void:
	assert_object(_keypad.panel.theme).is_not_null()
