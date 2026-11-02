# UIScroll: a long list scrolls, stops at both ends, scrolls on the keys when asked, follows the
# focus, and says when there is more above or below (#9).
extends GdUnitTestSuite

const LINES := 40
const AREA := Vector2(400.0, 300.0)

var _scroll: UIScroll
var _lines: VBoxContainer
var _was_reduced := false


func before_test() -> void:
	_was_reduced = UIMotion.reduced
	_scroll = auto_free(UIScroll.new())
	_scroll.custom_minimum_size = AREA
	_lines = VBoxContainer.new()
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_lines)
	for index in LINES:
		var label := Label.new()
		label.text = "Line %d" % index
		_lines.add_child(label)
	add_child(_scroll)
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	UIMotion.reduced = _was_reduced


func _tap(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await await_idle_frame()


func test_a_long_list_has_room_to_scroll() -> void:
	assert_float(_scroll.scroll_end()).is_greater(0.0)
	assert_bool(_scroll.has_more_above()).is_false()
	assert_bool(_scroll.has_more_below()).is_true()


func test_scroll_by_moves_and_stops_at_both_ends() -> void:
	_scroll.scroll_by(1.0)
	assert_int(_scroll.scroll_vertical).is_greater(0)
	_scroll.scroll_by(-1000.0)
	assert_int(_scroll.scroll_vertical).is_equal(0)
	_scroll.scroll_by(1000.0)
	assert_int(_scroll.scroll_vertical).is_equal(int(_scroll.scroll_end()))
	assert_bool(_scroll.has_more_above()).is_true()
	assert_bool(_scroll.has_more_below()).is_false()


func test_keys_scroll_only_when_keyboard_scroll_is_on() -> void:
	assert_int(_scroll.focus_mode).is_equal(Control.FOCUS_NONE)
	_scroll.keyboard_scroll = true
	assert_int(_scroll.focus_mode).is_equal(Control.FOCUS_ALL)
	_scroll.grab_focus()
	await _tap(&"ui_down")
	var after_down := _scroll.scroll_vertical
	assert_int(after_down).is_greater(0)
	await _tap(&"ui_page_down")
	assert_int(_scroll.scroll_vertical).is_greater(after_down)
	await _tap(&"ui_end")
	assert_int(_scroll.scroll_vertical).is_equal(int(_scroll.scroll_end()))
	await _tap(&"ui_home")
	assert_int(_scroll.scroll_vertical).is_equal(0)
	await _tap(&"ui_up")
	assert_int(_scroll.scroll_vertical).is_equal(0)


func test_a_short_list_does_not_scroll() -> void:
	for index in range(_lines.get_child_count() - 1, 2, -1):
		_lines.get_child(index).free()
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_scroll.scroll_end()).is_equal(0.0)
	_scroll.scroll_by(5.0)
	assert_int(_scroll.scroll_vertical).is_equal(0)
	assert_bool(_scroll.has_more_below()).is_false()


func test_the_edge_shade_springs_follow_whether_there_is_more() -> void:
	UIMotion.reduced = true
	_scroll.scroll_vertical = 0
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_scroll._top.value).is_equal(0.0)
	assert_float(_scroll._bottom.value).is_equal(1.0)
	_scroll.scroll_vertical = int(_scroll.scroll_end())
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_scroll._top.value).is_equal(1.0)
	assert_float(_scroll._bottom.value).is_equal(0.0)


func test_the_scroll_follows_a_focused_control_out_of_view() -> void:
	var far := Button.new()
	far.text = "Far"
	_lines.add_child(far)
	await await_idle_frame()
	await await_idle_frame()
	far.grab_focus()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_scroll.scroll_vertical).is_greater(0)
