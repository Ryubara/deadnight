# UIButton draws its focus ring with the shared UIFocusRing, as the other components do, so the ring
# looks and lands the same on every control (#37).
extends GdUnitTestSuite

## The most frame time a spring gets to settle in: it needs about a second, so this is slack, not
## a tolerance.
const SETTLE_SECONDS := 5.0
## How long pointer focus is watched for a ring that must not light: longer than a ring takes to
## rise.
const WATCH_SECONDS := 0.6

var _button: UIButton
var _was_pointer := true


func before_test() -> void:
	_was_pointer = UIInputMode.pointer
	_button = auto_free(UIButton.new())
	_button.text = "Play"
	add_child(_button)
	await await_idle_frame()


func after_test() -> void:
	UIInputMode.pointer = _was_pointer


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


## Lets `seconds` of frame time pass, in frames of whatever length the run has.
func _watch(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await await_idle_frame()
		elapsed += get_process_delta_time()


func test_the_button_uses_the_shared_focus_ring() -> void:
	assert_object(_button._ring).is_instanceof(UIFocusRing)


func test_keyboard_focus_lights_the_ring_and_pointer_focus_does_not() -> void:
	UIInputMode.pointer = true
	_button.grab_focus()
	await _watch(WATCH_SECONDS)
	assert_float(_button._focus.target).is_equal(0.0)
	assert_float(_button._focus.value).is_equal(0.0)
	_button.release_focus()
	UIInputMode.pointer = false
	_button.grab_focus()
	# One frame is not a length of time: `UISpring` takes a step only for each 1/240 s it is given, so
	# a frame shorter than that (a window with no frame cap, a headless run) leaves the value where it
	# was. What one frame does settle is the target; the value is read once it has left its start.
	await await_idle_frame()
	assert_float(_button._focus.target).is_equal(1.0)
	await _leave(_button._focus, 0.0)
	assert_float(_button._focus.value).is_greater(0.0)
	await _settle(_button._focus)
	assert_bool(_button._focus.is_settled()).is_true()
	assert_float(_button._focus.value).is_equal(1.0)
