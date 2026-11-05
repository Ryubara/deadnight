# The main menu driven by real keys and the mouse, the way a player does it: Down and Up walk the
# Play tab's tickets, Up from the first goes to the tab bar, Enter opens the focused item, Esc does
# nothing at the root, hovering an item takes the focus and a click opens it.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"


func before_test() -> void:
	UIInputMode.reset()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()


func after_test() -> void:
	UIInputMode.reset()
	MainMenu.board_factory = Callable()
	await RouterFixture.clear(get_tree())


func _menu() -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	return UIRouter.top() as MainMenu


func _focused_name() -> String:
	var focus := get_viewport().gui_get_focus_owner()
	return "" if focus == null else str(focus.name)


func _tap(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await await_idle_frame()


func _centre(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _hover(control: Control) -> void:
	# Pushed in the viewport's own coordinates: the headless window is 64 x 64 pixels.
	var move := InputEventMouseMotion.new()
	move.position = _centre(control)
	move.global_position = move.position
	get_viewport().push_input(move, true)
	await await_idle_frame()


func _click(control: Control) -> void:
	await _hover(control)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = _centre(control)
		click.global_position = click.position
		get_viewport().push_input(click, true)
		await await_idle_frame()


func test_down_walks_the_starts_and_on_into_the_challenges() -> void:
	var menu := await _menu()
	assert_str(_focused_name()).is_equal("together")
	await _tap(KEY_DOWN)
	assert_str(_focused_name()).is_equal("browser")
	await _tap(KEY_DOWN)
	assert_str(_focused_name()).is_equal("solo")
	await _tap(KEY_DOWN)
	var focus := get_viewport().gui_get_focus_owner()
	assert_bool(focus is ChallengeRow).override_failure_message("focus is %s" % focus).is_true()
	assert_bool(menu.shell.panel(MenuTab.Id.PLAY).is_ancestor_of(focus)).is_true()


func test_up_from_the_first_start_goes_to_the_tab_bar_and_down_comes_back() -> void:
	var menu := await _menu()
	await _tap(KEY_UP)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(
		menu.shell.tab_bar.button(MenuTab.Id.PLAY)
	)
	await _tap(KEY_DOWN)
	assert_str(_focused_name()).is_equal("together")


func test_enter_opens_the_focused_item() -> void:
	var menu := await _menu()
	menu.shell.show_tab(MenuTab.Id.MORE)
	menu.shell.focus_panel()
	await _tap(KEY_ENTER)
	await UIRouter.idle
	assert_int(UIRouter.depth()).is_equal(2)
	assert_str(UIRouter.top().scene_file_path).is_equal("res://ui/screens/settings_screen.tscn")


func test_escape_does_nothing_at_the_root() -> void:
	await _menu()
	await _tap(KEY_ESCAPE)
	assert_bool(UIRouter.busy).is_false()
	assert_int(UIRouter.depth()).is_equal(1)


func test_the_mouse_over_an_item_takes_the_focus() -> void:
	var menu := await _menu()
	var play := menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel
	await _hover(play.button(&"solo"))
	assert_str(_focused_name()).is_equal("solo")


func test_a_click_on_a_tab_and_then_an_item_opens_it() -> void:
	var menu := await _menu()
	await _click(menu.shell.tab_bar.button(MenuTab.Id.MORE))
	assert_int(menu.shell.tab).is_equal(MenuTab.Id.MORE)
	await await_idle_frame()
	await _click((menu.shell.panel(MenuTab.Id.MORE) as MorePanel).button(&"credits"))
	await UIRouter.idle
	assert_str(UIRouter.top().scene_file_path).is_equal("res://ui/screens/credits_screen.tscn")
