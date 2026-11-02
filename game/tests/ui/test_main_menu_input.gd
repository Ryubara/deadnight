# The main menu driven by real input events, the way a player does it: key presses move the focus
# and stop at the ends, the mouse hovering an item takes the focus and a click opens it, Esc does
# nothing at the root, and nothing answers before the entrance has brought the items in (#85).
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"
const ITEMS := ["Play", "Join", "Customize", "Settings", "Credits"]


func before_test() -> void:
	MainMenu.items_delay = 0.05


func after_test() -> void:
	MainMenu.items_delay = MainMenu.ITEMS_DELAY
	await RouterFixture.clear(get_tree())


## Shows the menu and waits until its items are in and Play has the focus.
func _menu_entered() -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	if not menu.has_entered():
		await menu.entered
	await await_idle_frame()
	return menu


## Shows the menu with an entrance that does not end during the test.
func _menu_entering() -> MainMenu:
	MainMenu.items_delay = 60.0
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	return UIRouter.top() as MainMenu


func _item(menu: MainMenu, item: String) -> UIButton:
	return menu.find_child(item, true, false) as UIButton


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


## Waits until the router has done what an input asked of it (or has nothing to do).
func _settle() -> void:
	await await_idle_frame()
	if UIRouter.busy:
		await UIRouter.idle


func _centre(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _hover(control: Control) -> void:
	# Pushed in the viewport's own coordinates: the headless window is 64 x 64 pixels, and a
	# window position would be scaled by the stretch before it reached the menu.
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


func test_down_walks_the_items_and_stops_at_the_last() -> void:
	var menu := await _menu_entered()
	var shown := ITEMS.duplicate()
	if MainMenu.has_quit():
		shown.append("Quit")
	assert_str(_focused_name()).is_equal("Play")
	for index in range(1, shown.size()):
		await _tap(KEY_DOWN)
		assert_str(_focused_name()).is_equal(shown[index])
	await _tap(KEY_DOWN)
	assert_str(_focused_name()).is_equal(shown[-1])
	assert_object(UIRouter.top()).is_same(menu)


func test_up_walks_back_and_stops_at_play() -> void:
	await _menu_entered()
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	await _tap(KEY_UP)
	assert_str(_focused_name()).is_equal("Join")
	await _tap(KEY_UP)
	await _tap(KEY_UP)
	assert_str(_focused_name()).is_equal("Play")


func test_enter_opens_the_focused_item() -> void:
	await _menu_entered()
	for _i in 4:
		await _tap(KEY_DOWN)
	assert_str(_focused_name()).is_equal("Credits")
	await _tap(KEY_ENTER)
	await _settle()
	assert_int(UIRouter.depth()).is_equal(2)
	assert_str(UIRouter.top().scene_file_path).is_equal(CREDITS)


func test_escape_does_nothing_at_the_root() -> void:
	var menu := await _menu_entered()
	await _tap(KEY_ESCAPE)
	assert_bool(UIRouter.busy).is_false()
	assert_int(UIRouter.depth()).is_equal(1)
	assert_object(UIRouter.top()).is_same(menu)
	assert_str(_focused_name()).is_equal("Play")


func test_the_mouse_over_an_item_takes_the_focus() -> void:
	var menu := await _menu_entered()
	await _hover(_item(menu, "Settings"))
	assert_str(_focused_name()).is_equal("Settings")
	await _hover(_item(menu, "Join"))
	assert_str(_focused_name()).is_equal("Join")


func test_a_click_opens_the_item() -> void:
	var menu := await _menu_entered()
	await _click(_item(menu, "Credits"))
	await _settle()
	assert_int(UIRouter.depth()).is_equal(2)
	assert_str(UIRouter.top().scene_file_path).is_equal(CREDITS)


func test_a_key_during_the_entrance_takes_no_focus_and_opens_nothing() -> void:
	var menu := await _menu_entering()
	assert_bool(menu.has_entered()).is_false()
	for key in [KEY_DOWN, KEY_UP, KEY_TAB, KEY_ENTER, KEY_SPACE]:
		await _tap(key)
	assert_str(_focused_name()).is_equal("")
	assert_int(UIRouter.depth()).is_equal(1)
	assert_bool(UIRouter.busy).is_false()


func test_the_mouse_during_the_entrance_neither_hovers_nor_clicks() -> void:
	var menu := await _menu_entering()
	await _click(_item(menu, "Play"))
	await _hover(_item(menu, "Settings"))
	assert_str(_focused_name()).is_equal("")
	assert_int(UIRouter.depth()).is_equal(1)
	assert_bool(UIRouter.busy).is_false()


func test_the_items_answer_again_once_the_entrance_ends() -> void:
	var menu := await _menu_entering()
	for item in ITEMS:
		assert_int(_item(menu, item).focus_mode).is_equal(Control.FOCUS_NONE)
		assert_int(_item(menu, item).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	menu.finish_entrance()
	await await_idle_frame()
	for item in ITEMS:
		assert_int(_item(menu, item).focus_mode).is_equal(Control.FOCUS_ALL)
		assert_int(_item(menu, item).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_str(_focused_name()).is_equal("Play")
	await _tap(KEY_DOWN)
	assert_str(_focused_name()).is_equal("Join")
