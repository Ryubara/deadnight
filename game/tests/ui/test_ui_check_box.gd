# UICheckBox: toggles on a click and on accept, draws its fill by a spring, and does nothing while
# disabled. Driven with real events (#9).
extends GdUnitTestSuite

var _box: UICheckBox
var _was_reduced := false


func before_test() -> void:
	# A screen another suite left on the router would cover the widget and eat its clicks.
	await RouterFixture.clear(get_tree())
	_was_reduced = UIMotion.reduced
	_box = auto_free(UICheckBox.new())
	_box.text = "Allow late joins"
	_box.theme = UIThemeBuilder.build()
	add_child(_box)
	await await_idle_frame()


func after_test() -> void:
	UIMotion.reduced = _was_reduced


func _press(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await await_idle_frame()


## A click at the centre of the box, in the viewport's own coordinates (the headless window is
## 64 x 64 pixels, so a window position would be scaled by the stretch first).
func _click() -> void:
	var point := _box.get_global_rect().get_center()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = point
		click.global_position = point
		get_viewport().push_input(click, true)
		await await_idle_frame()


func test_a_click_toggles_it_and_emits_toggled() -> void:
	var seen: Array[bool] = []
	_box.toggled.connect(func(on: bool) -> void: seen.append(on))
	await _click()
	assert_bool(_box.button_pressed).is_true()
	await _click()
	assert_bool(_box.button_pressed).is_false()
	assert_array(seen).contains_exactly([true, false])


func test_accept_toggles_the_focused_box() -> void:
	_box.grab_focus()
	await _press(KEY_SPACE)
	assert_bool(_box.button_pressed).is_true()
	await _press(KEY_ENTER)
	assert_bool(_box.button_pressed).is_false()


func test_a_disabled_box_ignores_clicks_and_keys() -> void:
	_box.disabled = true
	await _click()
	assert_bool(_box.button_pressed).is_false()
	await _press(KEY_SPACE)
	assert_bool(_box.button_pressed).is_false()


func test_the_room_for_the_box_comes_from_the_tokens() -> void:
	var tokens := UITokens.active()
	var left := _box.get_theme_stylebox(&"normal").get_content_margin(SIDE_LEFT)
	assert_float(left).is_greater_equal(float(UICheckBox.box_size(tokens)))
	assert_float(_box.custom_minimum_size.y).is_equal(float(tokens.control_height))


func test_the_fill_follows_the_state_on_a_spring() -> void:
	UIMotion.reduced = false
	_box.button_pressed = true
	await await_idle_frame()
	assert_float(_box._on.value).is_less(1.0)
	for _i in 90:
		await await_idle_frame()
	assert_float(_box._on.value).is_between(0.99, 1.2)
	_box.button_pressed = false
	for _i in 120:
		await await_idle_frame()
	assert_float(_box._on.value).is_between(-0.05, 0.01)


func test_reduced_motion_snaps_the_fill() -> void:
	UIMotion.reduced = true
	_box.button_pressed = true
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_box._on.value).is_equal(1.0)


func test_the_preview_states_pin_hover_and_focus() -> void:
	UIMotion.reduced = true
	_box.preview_state = UICheckBox.Preview.HOVER
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_box._hover.value).is_equal(1.0)
	_box.preview_state = UICheckBox.Preview.FOCUS
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_box._focus.value).is_equal(1.0)
