# The line that says "click the game once" on every screen while the game's frame has no focus.
extends GdUnitTestSuite

var _hint: ControllerHint


func before_test() -> void:
	_hint = auto_free(ControllerHint.new())
	add_child(_hint)


func test_it_starts_hidden_and_off_the_web_it_stays_hidden() -> void:
	assert_bool(_hint.label.visible).is_false()
	_hint.show_for(GamepadProbe.read())
	assert_bool(_hint.label.visible).is_false()


func test_it_shows_for_a_frame_without_the_focus_and_goes_when_it_has_it() -> void:
	_hint.show_for({"iframe": true, "focus": false, "policy": true, "pads": 0})
	assert_bool(_hint.label.visible).is_true()
	assert_str(_hint.label.text).is_equal("Click the game once to use a controller")
	_hint.show_for({"iframe": true, "focus": true, "policy": true, "pads": 0})
	assert_bool(_hint.label.visible).is_false()


func test_the_line_sits_along_the_bottom_edge_of_the_viewport() -> void:
	_hint.show_for({"iframe": true, "focus": false})
	var view := _hint.get_viewport_rect().size
	assert_vector(_hint.size).is_equal(view)
	var strip := _hint.label.get_global_rect()
	assert_float(strip.size.x).is_equal(view.x)
	assert_float(strip.end.y).is_less_equal(view.y)
	assert_float(strip.position.y).is_greater(view.y - 60.0)
