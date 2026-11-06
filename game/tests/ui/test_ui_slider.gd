# UISlider: the keyboard and the d-pad step it, a click lands where it points (the invisible grabber
# the theme gives the engine matches what is drawn), it stops at its ends, a disabled slider ignores
# input, and reduced motion snaps the fill (#37).
extends GdUnitTestSuite

const WIDTH := 400.0
## The most frame time a spring gets to settle in: it needs about a second, so this is slack, not
## a tolerance.
const SETTLE_SECONDS := 5.0

var _slider: UISlider
var _was_reduced := false


func before_test() -> void:
	# A screen another suite left on the router would cover the widget and eat its clicks.
	await RouterFixture.clear(get_tree())
	_was_reduced = UIMotion.reduced
	_slider = auto_free(UISlider.new())
	_slider.theme = UIThemeBuilder.build()
	_slider.min_value = 0.0
	_slider.max_value = 100.0
	_slider.step = 5.0
	_slider.value = 50.0
	_slider.custom_minimum_size.x = WIDTH
	add_child(_slider)
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


func test_left_and_right_step_the_value() -> void:
	_slider.grab_focus()
	await WidgetEvents.key(get_tree(), KEY_RIGHT)
	assert_float(_slider.value).is_equal(55.0)
	await WidgetEvents.key(get_tree(), KEY_LEFT)
	await WidgetEvents.key(get_tree(), KEY_LEFT)
	assert_float(_slider.value).is_equal(45.0)


func test_the_dpad_steps_it_too() -> void:
	_slider.grab_focus()
	await WidgetEvents.button(get_tree(), JOY_BUTTON_DPAD_RIGHT)
	assert_float(_slider.value).is_equal(55.0)
	await WidgetEvents.button(get_tree(), JOY_BUTTON_DPAD_LEFT)
	assert_float(_slider.value).is_equal(50.0)


func test_it_stops_at_both_ends() -> void:
	_slider.grab_focus()
	_slider.value = 100.0
	await WidgetEvents.key(get_tree(), KEY_RIGHT)
	assert_float(_slider.value).is_equal(100.0)
	_slider.value = 0.0
	await WidgetEvents.key(get_tree(), KEY_LEFT)
	assert_float(_slider.value).is_equal(0.0)


func test_a_click_at_sixty_percent_lands_there() -> void:
	# The thumb is as wide as the controls are tall, and the value runs between its two extreme
	# centres: a click at 60 % of the width is (x - thumb / 2) / (width - thumb) of the range.
	var thumb := float(UITokens.active().control_height)
	var x := _slider.size.x * 0.6
	await WidgetEvents.click(get_tree(), _slider, Vector2(x, _slider.size.y * 0.5))
	var expected := clampf((x - thumb * 0.5) / (_slider.size.x - thumb), 0.0, 1.0) * 100.0
	assert_float(_slider.value).is_equal_approx(expected, 5.0)
	assert_float(_slider.value).is_between(55.0, 65.0)


func test_a_click_near_either_end_reaches_it() -> void:
	await WidgetEvents.click_at_share(get_tree(), _slider, 0.99)
	assert_float(_slider.value).is_equal(100.0)
	await WidgetEvents.click_at_share(get_tree(), _slider, 0.01)
	assert_float(_slider.value).is_equal(0.0)


func test_value_changed_fires_once_per_step() -> void:
	var seen: Array[float] = []
	_slider.value_changed.connect(func(value: float) -> void: seen.append(value))
	_slider.grab_focus()
	await WidgetEvents.key(get_tree(), KEY_RIGHT)
	await WidgetEvents.key(get_tree(), KEY_RIGHT)
	assert_array(seen).contains_exactly([55.0, 60.0])


func test_a_slider_that_is_not_editable_ignores_keys_and_clicks() -> void:
	_slider.editable = false
	_slider.grab_focus()
	await WidgetEvents.key(get_tree(), KEY_RIGHT)
	await WidgetEvents.click_at_share(get_tree(), _slider, 0.9)
	assert_float(_slider.value).is_equal(50.0)


func test_the_fill_follows_the_value_on_a_spring() -> void:
	UIMotion.reduced = false
	_slider.value = 100.0
	# One frame is not a length of time: `UISpring` takes a step only for each 1/240 s it is given, so
	# a frame shorter than that (a window with no frame cap, a headless run) leaves the value where it
	# was. What one frame does settle is the target; the value is read once it has left its start.
	await await_idle_frame()
	assert_float(_slider._shown.target).is_equal(1.0)
	await _leave(_slider._shown, 0.5)
	assert_float(_slider._shown.value).is_greater(0.5)
	assert_float(_slider._shown.value).is_less(1.0)
	await _settle(_slider._shown)
	assert_bool(_slider._shown.is_settled()).is_true()
	assert_float(_slider._shown.value).is_equal(1.0)


func test_reduced_motion_snaps_the_fill() -> void:
	UIMotion.reduced = true
	_slider.value = 100.0
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_slider._shown.value).is_equal(1.0)
