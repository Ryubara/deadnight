# UIButton draws its focus ring with the shared UIFocusRing, as the other components do, so the ring
# looks and lands the same on every control (#37).
extends GdUnitTestSuite

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


func test_the_button_uses_the_shared_focus_ring() -> void:
	assert_object(_button._ring).is_instanceof(UIFocusRing)


func test_keyboard_focus_lights_the_ring_and_pointer_focus_does_not() -> void:
	UIInputMode.pointer = true
	_button.grab_focus()
	for _i in 60:
		await await_idle_frame()
	assert_float(_button._focus.value).is_equal(0.0)
	_button.release_focus()
	UIInputMode.pointer = false
	_button.grab_focus()
	for _i in 90:
		await await_idle_frame()
	assert_float(_button._focus.value).is_between(0.99, 1.2)
