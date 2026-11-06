# UIOptionSelector: left, right and accept step it and wrap round the ends, a click on the left
# edge steps back and anywhere else forward, `select` clamps without wrapping, and reduced motion
# snaps the slide (#37).
extends GdUnitTestSuite

const OPTIONS := ["Low", "Medium", "High"]
## The most frame time a spring gets to settle in: it needs about a second, so this is slack, not
## a tolerance.
const SETTLE_SECONDS := 5.0

var _selector: UIOptionSelector
var _changes: Array[int] = []
var _was_reduced := false


func before_test() -> void:
	# A screen another suite left on the router would cover the widget and eat its clicks.
	await RouterFixture.clear(get_tree())
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


## Waits for frames until `spring` has settled, at most `SETTLE_SECONDS` of frame time.
func _settle(spring: UISpring) -> void:
	var elapsed := 0.0
	while not spring.is_settled() and elapsed < SETTLE_SECONDS:
		await await_idle_frame()
		elapsed += get_process_delta_time()


## Waits for frames until `spring` has moved off `from`, at most `SETTLE_SECONDS` of frame time.
func _leave(spring: UISpring, from: float) -> void:
	var elapsed := 0.0
	while spring.value == from and elapsed < SETTLE_SECONDS:
		await await_idle_frame()
		elapsed += get_process_delta_time()


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
	# One frame is not a length of time: `UISpring` takes a step only for each 1/240 s it is given, so
	# a frame shorter than that (a window with no frame cap, a headless run) leaves the value where it
	# was. What one frame does settle is the target; the value is read once it has left its start.
	await await_idle_frame()
	assert_float(_selector._change.target).is_equal(1.0)
	await _leave(_selector._change, 0.0)
	assert_float(_selector._change.value).is_greater(0.0)
	assert_float(_selector._change.value).is_less(1.0)
	await _settle(_selector._change)
	assert_bool(_selector._change.is_settled()).is_true()
	assert_float(_selector._change.value).is_equal(1.0)
