# UIItemList: keys move the choice and stop at the ends, accept activates, a click selects and a
# double click activates, the wheel scrolls, and a long list keeps the choice in view (#9).
extends GdUnitTestSuite

const ROWS := 12

var _list: UIItemList
var _picked: Array[int] = []
var _activated: Array[int] = []


func before_test() -> void:
	# A screen another suite left on the router would cover the widget and eat its clicks.
	await RouterFixture.clear(get_tree())
	_picked.clear()
	_activated.clear()
	_list = auto_free(UIItemList.new())
	var items := PackedStringArray()
	for index in ROWS:
		items.append("Row %d" % index)
	_list.items = items
	_list.visible_rows = 4
	_list.item_selected.connect(func(index: int) -> void: _picked.append(index))
	_list.item_activated.connect(func(index: int) -> void: _activated.append(index))
	add_child(_list)
	await await_idle_frame()
	await await_idle_frame()


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await await_idle_frame()


## A mouse button at `point` (viewport coordinates: the headless window is 64 x 64 pixels).
func _mouse(button: MouseButton, point: Vector2, double := false) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = button
		click.pressed = pressed
		click.position = point
		click.global_position = point
		click.double_click = double and pressed
		get_viewport().push_input(click, true)
		await await_idle_frame()


func _row_centre(index: int) -> Vector2:
	var border := float(UITokens.active().border)
	var local := Vector2(_list.size.x * 0.5, border + (index + 0.5) * _list.row_height())
	return _list.get_global_transform_with_canvas() * local


func test_down_selects_the_first_row_then_walks_and_stops_at_the_last() -> void:
	_list.grab_focus()
	assert_int(_list.selected).is_equal(-1)
	await _key(KEY_DOWN)
	assert_int(_list.selected).is_equal(0)
	for _i in 20:
		await _key(KEY_DOWN)
	assert_int(_list.selected).is_equal(ROWS - 1)
	assert_array(_picked).has_size(ROWS)


func test_up_stops_at_the_first_row() -> void:
	_list.grab_focus()
	_list.select(2, false)
	await _key(KEY_UP)
	await _key(KEY_UP)
	await _key(KEY_UP)
	assert_int(_list.selected).is_equal(0)


func test_home_end_and_pages_jump() -> void:
	_list.grab_focus()
	await _key(KEY_END)
	assert_int(_list.selected).is_equal(ROWS - 1)
	await _key(KEY_HOME)
	assert_int(_list.selected).is_equal(0)
	await _key(KEY_PAGEDOWN)
	assert_int(_list.selected).is_equal(_list.rows_shown())


func test_accept_activates_the_choice_and_nothing_without_one() -> void:
	_list.grab_focus()
	await _key(KEY_ENTER)
	assert_array(_activated).is_empty()
	_list.select(3, false)
	await _key(KEY_ENTER)
	assert_array(_activated).contains_exactly([3])


func test_a_click_selects_the_row_and_a_double_click_activates_it() -> void:
	await _mouse(MOUSE_BUTTON_LEFT, _row_centre(2))
	assert_int(_list.selected).is_equal(2)
	assert_array(_activated).is_empty()
	await _mouse(MOUSE_BUTTON_LEFT, _row_centre(1), true)
	assert_int(_list.selected).is_equal(1)
	assert_array(_activated).contains_exactly([1])


func test_the_wheel_scrolls_the_rows_and_stops_at_the_ends() -> void:
	assert_float(_list.top_row()).is_equal(0.0)
	await _mouse(MOUSE_BUTTON_WHEEL_DOWN, _row_centre(1))
	assert_float(_list._scroll.target).is_greater(0.0)
	for _i in 30:
		await _mouse(MOUSE_BUTTON_WHEEL_DOWN, _row_centre(1))
	assert_float(_list._scroll.target).is_equal(float(ROWS - _list.rows_shown()))
	for _i in 30:
		await _mouse(MOUSE_BUTTON_WHEEL_UP, _row_centre(1))
	assert_float(_list._scroll.target).is_equal(0.0)


func test_a_choice_below_the_view_scrolls_into_it() -> void:
	_list.select(9, false)
	assert_float(_list._scroll.target).is_equal(float(9 + 1 - _list.rows_shown()))
	_list.select(0, false)
	assert_float(_list._scroll.target).is_equal(0.0)


func test_a_row_is_found_from_a_point_and_outside_is_none() -> void:
	assert_int(_list.row_at(Vector2(10.0, UITokens.active().border + 1.0))).is_equal(0)
	assert_int(_list.row_at(Vector2(10.0, -4.0))).is_equal(-1)
	_list.items = PackedStringArray(["a", "b"])
	assert_int(_list.row_at(Vector2(10.0, _list.row_height() * 5.0))).is_equal(-1)


func test_changing_the_items_keeps_the_choice_in_range() -> void:
	_list.select(10, false)
	_list.items = PackedStringArray(["a", "b", "c"])
	assert_int(_list.selected).is_equal(2)
	_list.items = PackedStringArray()
	assert_int(_list.selected).is_equal(-1)
