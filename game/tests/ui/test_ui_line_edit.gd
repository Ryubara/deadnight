# UILineEdit: typing, the submit key, the read-only state, the tokens in its theme, and a ring only
# for keyboard focus (#9).
extends GdUnitTestSuite

var _field: UILineEdit
var _was_pointer := true
var _was_reduced := false


func before_test() -> void:
	_was_pointer = UIInputMode.pointer
	_was_reduced = UIMotion.reduced
	_field = auto_free(UILineEdit.new())
	_field.placeholder_text = "Your name"
	_field.theme = UIThemeBuilder.build()
	add_child(_field)
	await await_idle_frame()


func after_test() -> void:
	UIInputMode.pointer = _was_pointer
	UIMotion.reduced = _was_reduced


func _type(text: String) -> void:
	for letter in text:
		for pressed in [true, false]:
			var event := InputEventKey.new()
			event.keycode = letter.unicode_at(0) as Key
			event.unicode = letter.unicode_at(0)
			event.pressed = pressed
			Input.parse_input_event(event)
			await await_idle_frame()


func _press(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await await_idle_frame()


func test_typed_letters_land_in_the_focused_field() -> void:
	_field.grab_focus()
	await _type("Ruby")
	assert_str(_field.text).is_equal("Ruby")


func test_enter_submits_the_text() -> void:
	var sent: Array[String] = []
	_field.text_submitted.connect(func(text: String) -> void: sent.append(text))
	_field.grab_focus()
	await _type("Cal")
	await _press(KEY_ENTER)
	assert_array(sent).contains_exactly(["Cal"])


func test_a_field_that_is_not_editable_takes_no_typing() -> void:
	_field.editable = false
	_field.grab_focus()
	await _type("x")
	assert_str(_field.text).is_equal("")


func test_the_theme_styles_the_field_from_tokens() -> void:
	var tokens := UITokens.active()
	var focus := _field.get_theme_stylebox(&"focus") as StyleBoxFlat
	assert_object(focus).is_not_null()
	assert_bool(focus.border_color.is_equal_approx(tokens.accent)).is_true()
	assert_float(_field.custom_minimum_size.y).is_equal(float(tokens.control_height))


func test_focus_from_the_keyboard_rings_the_field_and_a_click_does_not() -> void:
	UIMotion.reduced = true
	UIInputMode.pointer = true
	_field.grab_focus()
	for _i in 4:
		await await_idle_frame()
	assert_float(_field._focus.value).is_equal(0.0)
	_field.release_focus()
	UIInputMode.pointer = false
	_field.grab_focus()
	for _i in 4:
		await await_idle_frame()
	assert_float(_field._focus.value).is_equal(1.0)
