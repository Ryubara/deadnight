# UIOptionSelector: left, right and accept step it and wrap round the ends, a click on the left
# edge steps back and anywhere else forward, `select` clamps without wrapping, and reduced motion
# snaps the slide (#37).
extends GdUnitTestSuite

const OPTIONS := ["Low", "Medium", "High"]

var _selector: UIOptionSelector
var _changes: Array[int] = []
var _was_reduced := false


func before_test() -> void:
	_was_reduced = UIMotion.reduced
	_changes.clear()
	_selector = auto_free(UIOptionSelector.new())
	_selector.theme = UIThemeBuilder.build()
	_selector.options = PackedStringArray(OPTIONS)
	_selector.selected_changed.connect(func(index: int) -> void: _changes.append(index))
	add_child(_selector)
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	UIMotion.reduced = _was_reduced


func test_right_steps_forward_and_wraps_to_the_first() -> void:
	_selector.grab_focus()
	for _i in 3:
		await WidgetEvents.key(get_tree(), KEY_RIGHT)
	assert_int(_selector.selected).is_equal(0)
	assert_array(_changes).contains_exactly([1, 2, 0])


func test_left_steps_back_and_wraps_to_the_last() -> void:
	_selector.grab_focus()
	await WidgetEvents.key(get_tree(), KEY_LEFT)
	assert_int(_selector.selected).is_equal(2)
	await WidgetEvents.key(get_tree(), KEY_LEFT)
	assert_int(_selector.selected).is_equal(1)


func test_accept_and_the_gamepad_step_forward() -> void:
	_selector.grab_focus()
	await WidgetEvents.key(get_tree(), KEY_ENTER)
	assert_int(_selector.selected).is_equal(1)
	await WidgetEvents.button(get_tree(), JOY_BUTTON_A)
	assert_int(_selector.selected).is_equal(2)
	await WidgetEvents.button(get_tree(), JOY_BUTTON_DPAD_RIGHT)
	assert_int(_selector.selected).is_equal(0)
	await WidgetEvents.button(get_tree(), JOY_BUTTON_DPAD_LEFT)
	assert_int(_selector.selected).is_equal(2)


func test_a_click_on_the_left_edge_steps_back_and_elsewhere_forward() -> void:
	await WidgetEvents.click_at_share(get_tree(), _selector, UIOptionSelector.EDGE_ZONE * 0.5)
	assert_int(_selector.selected).is_equal(2)
	await WidgetEvents.click_at_share(get_tree(), _selector, 0.5)
	assert_int(_selector.selected).is_equal(0)
	await WidgetEvents.click_at_share(get_tree(), _selector, 0.95)
	assert_int(_selector.selected).is_equal(1)


func test_select_clamps_and_does_not_wrap_and_stays_silent_when_asked() -> void:
	_selector.select(99)
	assert_int(_selector.selected).is_equal(2)
	_selector.select(-5, false)
	assert_int(_selector.selected).is_equal(0)
	assert_array(_changes).contains_exactly([2])


func test_one_option_does_not_step() -> void:
	_selector.options = PackedStringArray(["Only"])
	_selector.grab_focus()
	await WidgetEvents.key(get_tree(), KEY_RIGHT)
	assert_int(_selector.selected).is_equal(0)
	assert_array(_changes).is_empty()


func test_the_text_is_the_chosen_option() -> void:
	_selector.select(1)
	assert_str(_selector.text()).is_equal("Medium")


func test_reduced_motion_snaps_the_slide() -> void:
	UIMotion.reduced = true
	_selector.step(1)
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_selector._change.value).is_equal(1.0)


func test_the_slide_runs_on_a_spring_without_reduced_motion() -> void:
	UIMotion.reduced = false
	_selector.step(1)
	await await_idle_frame()
	assert_float(_selector._change.value).is_less(1.0)
	for _i in 120:
		await await_idle_frame()
	assert_float(_selector._change.value).is_equal_approx(1.0, 0.02)
