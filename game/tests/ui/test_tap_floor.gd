extends GdUnitTestSuite
## The least size of what a finger presses on a phone's canvas (#1197): the kit's controls are 52
## units high, 37.6 CSS pixels at the phone factor, and a phone's canvas raises them to a tap
## target (64 units, 44.4 and over). A bigger canvas gives back the height they had.


func test_a_phone_canvas_raises_a_slider_a_toggle_a_selector_and_a_field_to_a_tap_target() -> void:
	var host: Control = auto_free(Control.new())
	var controls: Array[Control] = [
		UISlider.new(), UIToggle.new(), UIOptionSelector.new(), UICheckBox.new(), LineEdit.new()
	]
	for control in controls:
		host.add_child(control)
	var before: Array[float] = []
	for control in controls:
		before.append(control.custom_minimum_size.y)
	TapFloor.fit(host, true)
	for control in controls:
		assert_float(control.custom_minimum_size.y).is_greater_equal(MenuLook.TAP_TARGET)
	TapFloor.fit(host, false)
	for index in controls.size():
		assert_float(controls[index].custom_minimum_size.y).is_equal(before[index])


func test_the_control_given_is_raised_too_not_only_what_is_under_it() -> void:
	var field: LineEdit = auto_free(LineEdit.new())
	TapFloor.fit(field, true)
	assert_float(field.custom_minimum_size.y).is_greater_equal(MenuLook.TAP_TARGET)


func test_a_control_already_taller_keeps_its_height() -> void:
	var host: Control = auto_free(Control.new())
	var slider := UISlider.new()
	host.add_child(slider)
	slider.custom_minimum_size.y = 90.0
	TapFloor.fit(host, true)
	assert_float(slider.custom_minimum_size.y).is_equal(90.0)
	TapFloor.fit(host, false)
	assert_float(slider.custom_minimum_size.y).is_equal(90.0)


func test_a_canvas_of_540_units_is_a_phones_and_one_of_1080_is_not() -> void:
	assert_bool(TapFloor.phone_canvas(Vector2(1169, 540))).is_true()
	assert_bool(TapFloor.phone_canvas(Vector2(960, 540))).is_true()
	assert_bool(TapFloor.phone_canvas(Vector2(1920, 1080))).is_false()
	assert_bool(TapFloor.phone_canvas(Vector2(1920, 1000))).is_false()
