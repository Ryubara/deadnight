# The main menu: the game starts on it, every item exists, Quit is left out on the web, the
# credits list parses, and each item opens its screen through the router.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"


func _menu() -> MainMenu:
	var menu: MainMenu = auto_free((load(MENU) as PackedScene).instantiate())
	add_child(menu)
	return menu


func before_test() -> void:
	# Short enough that a test waits for it; an entrance a test cuts short does not need it at all.
	MainMenu.items_delay = 0.05


func after_test() -> void:
	MainMenu.items_delay = MainMenu.ITEMS_DELAY
	await RouterFixture.clear(get_tree())


func _focus_inside(root: Node) -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return owner != null and root.is_ancestor_of(owner)


func test_a_menu_entered_normally_focuses_play_once_its_items_rise() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	if not menu.has_entered():
		await menu.entered
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.find_child("Play"))


func test_a_screen_pushed_over_a_fresh_menu_keeps_the_focus() -> void:
	# The entrance would end long after the push: the covered menu brings its items in at once
	# and must not take the focus from the screen over it (#190).
	MainMenu.items_delay = 60.0
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	assert_bool(menu.has_entered()).is_false()
	UIRouter.push("res://ui/screens/credits_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	var covering := UIRouter.top()
	assert_object(covering).is_not_same(menu)
	assert_bool(menu.has_entered()).is_true()
	assert_bool(_focus_inside(covering)).is_true()
	# Whatever ends the entrance later, the menu does not take the focus while it is covered.
	menu.finish_entrance()
	for i in 5:
		await get_tree().process_frame
	assert_bool(_focus_inside(covering)).is_true()


func test_a_menu_that_is_not_the_top_screen_takes_no_focus() -> void:
	UIRouter.reset("res://ui/screens/credits_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	var covering := UIRouter.top()
	var menu := _menu()
	await await_idle_frame()
	menu.finish_entrance()
	assert_bool(_focus_inside(menu)).is_false()
	assert_bool(_focus_inside(covering)).is_true()


func test_the_menu_comes_back_with_its_items_and_the_focus_it_left() -> void:
	MainMenu.items_delay = 60.0
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	UIRouter.push("res://ui/screens/credits_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.pop(UITransition.Kind.CUT)
	await UIRouter.idle
	assert_object(UIRouter.top()).is_same(menu)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.find_child("Play"))


func test_main_scene_starts_on_the_main_menu() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	runner.invoke("queue_free")


func test_menu_has_every_item() -> void:
	var menu := _menu()
	for item in ["Play", "Join", "Settings", "Credits", "Quit"]:
		var button := menu.find_child(item, true, false) as UIButton
		assert_object(button).is_not_null()
		assert_str(button.text).is_equal(item)
	assert_object(menu.find_child("Sign", true, false)).is_instanceof(NeonSign)


func test_quit_is_hidden_on_the_web() -> void:
	assert_bool(MainMenu.has_quit(true)).is_false()
	assert_bool(MainMenu.has_quit(false)).is_true()


func test_play_is_the_first_focus() -> void:
	var menu := _menu()
	await await_idle_frame()
	menu.finish_entrance()
	menu.focus_initial()
	assert_object(menu.get_viewport().gui_get_focus_owner()).is_same(menu.find_child("Play"))


func test_credits_lists_read_as_sections() -> void:
	var list := CreditsList.new()
	list.lines = PackedStringArray(["# One", "Ann - did it", "", "# Two", "Bo"])
	var sections := list.sections()
	assert_int(sections.size()).is_equal(2)
	assert_str(sections[0]["heading"]).is_equal("One")
	assert_array(sections[0]["names"]).contains_exactly(["Ann - did it"])
	assert_array(sections[1]["names"]).contains_exactly(["Bo"])


func test_shipped_credits_are_not_empty() -> void:
	var list := load("res://ui/credits.tres") as CreditsList
	assert_int(list.sections().size()).is_greater(0)


func test_each_item_opens_its_screen() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var expected := {
		"Play": "res://ui/screens/night_screen.tscn",
		"Join": "res://ui/screens/join_screen.tscn",
		"Settings": "res://ui/screens/settings_screen.tscn",
		"Credits": "res://ui/screens/credits_screen.tscn",
	}
	for item in expected:
		var menu := UIRouter.top()
		(menu.find_child(item, true, false) as UIButton).pressed.emit()
		await UIRouter.idle
		assert_int(UIRouter.depth()).is_equal(2)
		assert_str(UIRouter.top().scene_file_path).is_equal(expected[item])
		if UIRouter.top() is NightScreen:
			# Leaving while the lot is still being built would free the night mid-start.
			await (UIRouter.top() as NightScreen).night.ready_to_play
		UIRouter.pop()
		await UIRouter.idle
		assert_object(UIRouter.top()).is_same(menu)
