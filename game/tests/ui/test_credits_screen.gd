# The credits screen: a long list scrolls inside the card, Back stays on screen at 1280 x 720,
# Up and Down scroll while Back keeps the focus, and Back returns (#85).
extends GdUnitTestSuite

const CREDITS := "res://ui/screens/credits_screen.tscn"
const LINES := 40
const WINDOW := Vector2(1280.0, 720.0)

var _holder: Control


func after_test() -> void:
	if is_instance_valid(_holder):
		_holder.free()
	await RouterFixture.clear(get_tree())


func _list(lines: int) -> CreditsList:
	var list := CreditsList.new()
	var out := PackedStringArray(["# Made by"])
	for i in lines - 1:
		out.append("Credit line %d - what they did" % (i + 1))
	list.lines = out
	return list


func _make(lines: int) -> CreditsScreen:
	var screen := (load(CREDITS) as PackedScene).instantiate() as CreditsScreen
	screen.credits = _list(lines)
	return screen


## A screen of `lines` credits in a window of `WINDOW` pixels, laid out, outside the router.
func _screen(lines: int) -> CreditsScreen:
	_holder = Control.new()
	_holder.size = WINDOW
	add_child(_holder)
	var screen := _make(lines)
	_holder.add_child(screen)
	await await_idle_frame()
	await await_idle_frame()
	return screen


func _tap(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await await_idle_frame()


func test_forty_lines_fit_the_window_and_back_stays_on_screen() -> void:
	var screen := await _screen(LINES)
	var back := screen.back_button.get_global_rect()
	assert_float(back.end.y).is_less_equal(WINDOW.y)
	assert_float(back.position.y).is_greater_equal(0.0)
	# The list is taller than its viewport: it scrolls instead of growing the card.
	assert_float(screen.scroll.get_v_scroll_bar().max_value).is_greater(screen.scroll.size.y)


func test_a_short_list_does_not_scroll() -> void:
	var screen := await _screen(3)
	assert_float(screen.scroll.get_v_scroll_bar().max_value).is_less_equal(screen.scroll.size.y)
	screen.scroll_by(1.0)
	assert_int(screen.scroll.scroll_vertical).is_equal(0)


func test_scroll_by_moves_the_list_and_clamps_at_both_ends() -> void:
	var screen := await _screen(LINES)
	screen.scroll_by(1.0)
	assert_int(screen.scroll.scroll_vertical).is_greater(0)
	screen.scroll_by(-100.0)
	assert_int(screen.scroll.scroll_vertical).is_equal(0)
	screen.scroll_by(100.0)
	var end := int(screen.scroll.get_v_scroll_bar().max_value - screen.scroll.size.y)
	assert_int(screen.scroll.scroll_vertical).is_between(end - 1, end)


func test_down_and_up_scroll_while_back_keeps_the_focus() -> void:
	UIRouter.reset(_make(LINES * 3), UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	var screen := UIRouter.top() as CreditsScreen
	assert_object(get_viewport().gui_get_focus_owner()).is_same(screen.back_button)
	await _tap(&"ui_down")
	var after_down := screen.scroll.scroll_vertical
	assert_int(after_down).is_greater(0)
	await _tap(&"ui_down")
	assert_int(screen.scroll.scroll_vertical).is_greater(after_down)
	await _tap(&"ui_up")
	assert_int(screen.scroll.scroll_vertical).is_equal(after_down)
	await _tap(&"ui_page_down")
	assert_int(screen.scroll.scroll_vertical).is_greater(after_down)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(screen.back_button)


func test_back_returns_to_the_previous_screen() -> void:
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top()
	UIRouter.push(CREDITS, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	await _tap(&"ui_accept")
	await UIRouter.idle
	assert_object(UIRouter.top()).is_same(menu)
