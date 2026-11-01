# A gamepad drives the menu: real joypad events (not `pressed.emit()`) move focus, A opens a screen,
# B goes back, and B on the first screen does nothing. The bindings live in project.godot.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"

var _was_reduced := false


func before_test() -> void:
	# Reduced motion makes the items usable at once and the transitions short fades.
	_was_reduced = UIMotion.reduced
	UIMotion.reduced = true
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	(UIRouter.top() as UIScreen).focus_initial()


func after_test() -> void:
	UIMotion.reduced = _was_reduced
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle


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


func test_dpad_moves_focus_and_stops_at_the_ends() -> void:
	assert_str(_focused_name()).is_equal("Play")
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_str(_focused_name()).is_equal("Play")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_str(_focused_name()).is_equal("Settings")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_str(_focused_name()).is_equal("Credits")


func test_a_opens_credits_and_b_returns() -> void:
	var menu := UIRouter.top()
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_DPAD_DOWN)
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


func test_b_at_the_root_does_nothing() -> void:
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
