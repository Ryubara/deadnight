extends GdUnitTestSuite
## The field being typed in stays above whatever covers the bottom of a phone's screen (Deadnight
## #1183).

var _lift: KeyboardLift
var _field: LineEdit
var _cover := 0.0
var _keypad := 0.0


func before_test() -> void:
	_cover = 0.0
	_keypad = 0.0
	_field = auto_free(LineEdit.new())
	_field.position = Vector2(100.0, 600.0)
	_field.size = Vector2(300.0, 50.0)
	add_child(_field)
	_lift = auto_free(KeyboardLift.new())
	_lift.system_cover = func() -> float: return _cover
	_lift.keypad_cover = func() -> float: return _keypad
	add_child(_lift)
	_field.grab_focus()
	await await_idle_frame()


func after_test() -> void:
	UIRouter.offset = Vector2.ZERO
	UIMotion.reduced = false


## The page now says `value` units are covered (what `KeyboardLift` remembers of the last answer is
## dropped).
func _cover_now(value: float) -> void:
	_cover = value
	_lift._system_age = INF


func _height() -> float:
	return get_viewport().get_visible_rect().size.y


func test_nothing_covering_the_page_lifts_nothing() -> void:
	assert_float(_lift.wanted()).is_equal(0.0)


func test_a_field_under_the_keyboard_is_lifted_to_clear_it_by_the_margin() -> void:
	_field.position.y = _height() - 200.0
	_cover_now(500.0)
	var bottom := _field.get_global_rect().end.y
	var free_bottom := _height() - _cover
	assert_float(_lift.wanted()).is_equal_approx(bottom + KeyboardLift.MARGIN - free_bottom, 0.01)


func test_a_field_above_the_keyboard_stays_put() -> void:
	_field.position.y = 40.0
	_cover_now(300.0)
	assert_float(_lift.wanted()).is_equal(0.0)


func test_the_lift_never_takes_the_field_off_the_top() -> void:
	_field.position.y = 120.0
	_cover_now(_height() - 20.0)  # almost the whole page
	assert_float(_lift.wanted()).is_equal_approx(120.0 - KeyboardLift.TOP_MARGIN, 0.01)


func test_a_keypad_lifts_as_a_keyboard_does_and_the_larger_cover_wins() -> void:
	_field.position.y = _height() - 150.0
	_keypad = 400.0
	var by_keypad := _lift.wanted()
	assert_float(by_keypad).is_greater(0.0)
	_cover_now(600.0)
	assert_float(_lift.wanted()).is_greater(by_keypad)
	_cover_now(100.0)
	assert_float(_lift.wanted()).is_equal_approx(by_keypad, 0.01)


func test_a_field_that_cannot_be_typed_in_or_has_lost_the_focus_lifts_nothing() -> void:
	_field.position.y = _height() - 150.0
	_cover_now(500.0)
	assert_float(_lift.wanted()).is_greater(0.0)
	_field.editable = false
	assert_float(_lift.wanted()).is_equal(0.0)
	_field.editable = true
	_field.release_focus()
	assert_float(_lift.wanted()).is_equal(0.0)


func test_the_router_s_layer_follows_and_comes_back() -> void:
	UIMotion.reduced = true
	_field.position.y = _height() - 150.0
	_cover_now(500.0)
	await await_idle_frame()
	await await_idle_frame()
	assert_float(UIRouter.offset.y).is_equal_approx(-_lift.wanted(), 0.01)
	assert_float(UIRouter.offset.y).is_less(0.0)
	_cover_now(0.0)
	await await_idle_frame()
	await await_idle_frame()
	assert_float(UIRouter.offset.y).is_equal(0.0)


func test_the_lift_waits_for_a_finger_that_is_down() -> void:
	UIMotion.reduced = true
	_field.position.y = _height() - 150.0
	_cover_now(500.0)
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.index = 0
	_lift._input(down)
	assert_bool(_lift.finger_down()).is_true()
	await await_idle_frame()
	assert_float(UIRouter.offset.y).is_equal(0.0)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.index = 0
	_lift._input(up)
	assert_bool(_lift.finger_down()).is_false()
	await await_idle_frame()
	await await_idle_frame()
	assert_float(UIRouter.offset.y).is_less(0.0)


func test_the_page_is_asked_at_most_every_tenth_of_a_second() -> void:
	var asked := [0]
	_lift.system_cover = func() -> float:
		asked[0] += 1
		return 0.0
	_lift._system_age = INF
	for i in 5:
		_lift.cover()
		_lift._system_age += 0.01
	assert_int(asked[0]).is_equal(1)


func test_leaving_the_tree_puts_the_layer_back() -> void:
	UIRouter.offset = Vector2(0.0, -80.0)
	remove_child(_lift)
	_lift.free()
	assert_vector(UIRouter.offset).is_equal(Vector2.ZERO)
