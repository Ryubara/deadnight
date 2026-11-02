# UIToggle: a click and the accept keys flip it, a disabled toggle ignores both, its knob rides a
# spring, and reduced motion snaps it (#37).
extends GdUnitTestSuite

var _toggle: UIToggle
var _was_reduced := false


func before_test() -> void:
	# A screen another suite left on the router would cover the widget and eat its clicks.
	await RouterFixture.clear(get_tree())
	_was_reduced = UIMotion.reduced
	_toggle = auto_free(UIToggle.new())
	_toggle.theme = UIThemeBuilder.build()
	add_child(_toggle)
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	UIMotion.reduced = _was_reduced


func test_a_click_flips_it_and_emits_toggled() -> void:
	var seen: Array[bool] = []
	_toggle.toggled.connect(func(on: bool) -> void: seen.append(on))
	await WidgetEvents.click_at_share(get_tree(), _toggle, 0.5)
	assert_bool(_toggle.button_pressed).is_true()
	await WidgetEvents.click_at_share(get_tree(), _toggle, 0.5)
	assert_bool(_toggle.button_pressed).is_false()
	assert_array(seen).contains_exactly([true, false])


func test_accept_keys_and_the_gamepad_flip_it() -> void:
	_toggle.grab_focus()
	await WidgetEvents.key(get_tree(), KEY_ENTER)
	assert_bool(_toggle.button_pressed).is_true()
	await WidgetEvents.key(get_tree(), KEY_SPACE)
	assert_bool(_toggle.button_pressed).is_false()
	await WidgetEvents.button(get_tree(), JOY_BUTTON_A)
	assert_bool(_toggle.button_pressed).is_true()


func test_a_disabled_toggle_ignores_clicks_and_keys() -> void:
	_toggle.disabled = true
	await WidgetEvents.click_at_share(get_tree(), _toggle, 0.5)
	assert_bool(_toggle.button_pressed).is_false()
	_toggle.grab_focus()
	await WidgetEvents.key(get_tree(), KEY_ENTER)
	assert_bool(_toggle.button_pressed).is_false()


func test_its_size_comes_from_the_tokens() -> void:
	var tokens := UITokens.active()
	assert_float(_toggle.custom_minimum_size.y).is_equal(float(tokens.control_height))
	assert_float(_toggle.custom_minimum_size.x).is_equal_approx(
		float(tokens.control_height) * UIToggle.WIDTH_RATIO, 0.01
	)


func test_the_knob_rides_a_spring_to_the_new_side() -> void:
	UIMotion.reduced = false
	_toggle.button_pressed = true
	await await_idle_frame()
	assert_float(_toggle._on.value).is_less(1.0)
	for _i in 120:
		await await_idle_frame()
	assert_float(_toggle._on.value).is_equal_approx(1.0, 0.02)


func test_reduced_motion_snaps_the_knob() -> void:
	UIMotion.reduced = true
	_toggle.button_pressed = true
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_toggle._on.value).is_equal(1.0)
	_toggle.button_pressed = false
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_toggle._on.value).is_equal(0.0)
