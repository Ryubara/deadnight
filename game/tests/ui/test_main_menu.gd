# The main menu: the game starts on it, every item exists, Quit is left out on the web, the
# credits list parses, and each item opens its screen through the router.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"


func _menu() -> MainMenu:
	var menu: MainMenu = auto_free((load(MENU) as PackedScene).instantiate())
	add_child(menu)
	return menu


func test_main_scene_starts_on_the_main_menu() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	runner.invoke("queue_free")


func test_menu_has_every_item() -> void:
	var menu := _menu()
	for item in ["Play", "Settings", "Credits", "Quit"]:
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
		"Play": "res://ui/screens/play_screen.tscn",
		"Settings": "res://ui/screens/settings_screen.tscn",
		"Credits": "res://ui/screens/credits_screen.tscn",
	}
	for item in expected:
		var menu := UIRouter.top()
		(menu.find_child(item, true, false) as UIButton).pressed.emit()
		await UIRouter.idle
		assert_int(UIRouter.depth()).is_equal(2)
		assert_str(UIRouter.top().scene_file_path).is_equal(expected[item])
		UIRouter.pop()
		await UIRouter.idle
		assert_object(UIRouter.top()).is_same(menu)
