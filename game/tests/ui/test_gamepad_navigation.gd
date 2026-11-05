# A gamepad drives the menu: real joypad events (not `pressed.emit()`) move focus, the
# bumpers change tab, A opens a screen, B goes back, and B on the first screen only goes to the
# tab bar. The bindings live in project.godot.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"

var _was_reduced := false


func before_test() -> void:
	# Reduced motion makes the transitions short fades.
	_was_reduced = UIMotion.reduced
	UIMotion.reduced = true
	UIInputMode.reset()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	(UIRouter.top() as UIScreen).focus_initial()
	await await_idle_frame()


func after_test() -> void:
	UIMotion.reduced = _was_reduced
	UIInputMode.reset()
	MainMenu.board_factory = Callable()
	await RouterFixture.clear(get_tree())


## Presses and releases a joypad button the way a device would: through the input system.
func _tap(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await await_idle_frame()


func _focused_name() -> String:
	return str(UIRouter.top().get_viewport().gui_get_focus_owner().name)


func test_the_default_ui_actions_have_gamepad_buttons() -> void:
	var accept := _buttons("ui_accept")
	var cancel := _buttons("ui_cancel")
	assert_array(accept).contains([JOY_BUTTON_A, JOY_BUTTON_START])
	assert_array(cancel).contains_exactly([JOY_BUTTON_B])
	# The keyboard still works, and the settings screen's rebinding finds both kinds of event.
	assert_bool(InputMap.action_has_event(&"ui_accept", _key(KEY_ENTER))).is_true()
	assert_bool(InputMap.action_has_event(&"ui_cancel", _key(KEY_ESCAPE))).is_true()


func test_dpad_moves_focus_down_the_starts_and_up_to_the_tab_bar() -> void:
	assert_str(_focused_name()).is_equal("together")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_str(_focused_name()).is_equal("browser")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_str(_focused_name()).is_equal("solo")
	await _tap(JOY_BUTTON_DPAD_UP)
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_str(_focused_name()).is_equal("together")
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_str(_focused_name()).is_equal("Play")


func test_the_bumpers_change_tab_and_a_opens_credits_and_b_returns() -> void:
	var menu := UIRouter.top()
	for _i in 4:
		await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	assert_str(_focused_name()).is_equal("settings")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_str(_focused_name()).is_equal("credits")
	await _tap(JOY_BUTTON_A)
	await UIRouter.idle
	assert_int(UIRouter.depth()).is_equal(2)
	assert_str(UIRouter.top().scene_file_path).is_equal(CREDITS)
	await _tap(JOY_BUTTON_B)
	await UIRouter.idle
	assert_int(UIRouter.depth()).is_equal(1)
	assert_object(UIRouter.top()).is_same(menu)


func test_start_accepts_too() -> void:
	await _tap(JOY_BUTTON_START)
	await UIRouter.idle
	assert_int(UIRouter.depth()).is_equal(2)


func test_b_at_the_root_only_goes_to_the_tab_bar() -> void:
	await _tap(JOY_BUTTON_B)
	assert_bool(UIRouter.busy).is_false()
	assert_int(UIRouter.depth()).is_equal(1)
	assert_str(_focused_name()).is_equal("Play")


func _buttons(action: StringName) -> Array:
	var out: Array = []
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			out.append((event as InputEventJoypadButton).button_index)
	return out


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event
