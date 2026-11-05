# The main menu: the game starts on it, the shell and the sign are built, Quit is left out on
# the web, the credits list parses, and each ask a panel makes opens its screen through the router.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"


func before_test() -> void:
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()


func after_test() -> void:
	MainMenu.board_factory = Callable()
	await RouterFixture.clear(get_tree())


func _show() -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	return UIRouter.top() as MainMenu


func test_a_menu_shown_by_the_router_focuses_the_first_start() -> void:
	var menu := await _show()
	var play := menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel
	assert_bool(menu.has_entered()).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(play.button(&"together"))


func test_a_screen_pushed_over_the_menu_stops_its_stage_and_the_return_restarts_it() -> void:
	var menu := await _show()
	UIRouter.push("res://ui/screens/credits_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	assert_int(menu.shell.view.viewport().render_target_update_mode).is_equal(
		SubViewport.UPDATE_DISABLED
	)
	UIRouter.pop()
	await UIRouter.idle
	await await_idle_frame()
	assert_int(menu.shell.view.viewport().render_target_update_mode).is_not_equal(
		SubViewport.UPDATE_DISABLED
	)
	assert_bool(menu.shell.is_visible_in_tree()).is_true()


func test_the_menu_comes_back_on_the_tab_it_left_with_the_focus_in_it() -> void:
	var menu := await _show()
	menu.shell.show_tab(MenuTab.Id.MORE)
	(menu.shell.panel(MenuTab.Id.MORE) as MorePanel).button(&"credits").pressed.emit()
	await UIRouter.idle
	UIRouter.pop()
	await UIRouter.idle
	await await_idle_frame()
	assert_int(menu.shell.tab).is_equal(MenuTab.Id.MORE)
	var focus := get_viewport().gui_get_focus_owner()
	assert_bool(focus != null and menu.shell.panel(MenuTab.Id.MORE).is_ancestor_of(focus)).is_true()


func test_main_scene_starts_on_the_main_menu() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	runner.invoke("queue_free")


func test_the_menu_has_the_sign_and_every_tab() -> void:
	var menu := await _show()
	assert_object(menu.find_child("Sign", true, false)).is_instanceof(NeonSign)
	for id in MenuTab.ORDER:
		assert_object(menu.shell.panel(id)).is_not_null()


func test_quit_is_hidden_on_the_web() -> void:
	assert_bool(MainMenu.has_quit(true)).is_false()
	assert_bool(MainMenu.has_quit(false)).is_true()


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


func test_each_ask_opens_its_screen() -> void:
	var menu := await _show()
	var expected := {
		&"together": "res://ui/screens/together_screen.tscn",
		&"settings": "res://ui/screens/settings_screen.tscn",
		&"credits": "res://ui/screens/credits_screen.tscn",
	}
	for id: StringName in expected:
		menu.shell.context.request(id)
		await UIRouter.idle
		assert_int(UIRouter.depth()).is_equal(2)
		assert_str(UIRouter.top().scene_file_path).is_equal(expected[id])
		UIRouter.pop()
		await UIRouter.idle
		assert_object(UIRouter.top()).is_same(menu)


func test_the_server_browser_is_a_route_of_the_menu_and_no_route_is_a_second_way_in() -> void:
	# The Play tab's second start opens the list of nights (`test_server_browser.gd` presses a row).
	assert_str(MainMenu.ROUTES[&"browser"][0]).is_equal(MainMenu.BROWSER_SCREEN)
	for id: StringName in MainMenu.ROUTES:
		assert_bool(String(id).begins_with("quick")).is_false()


func test_solo_opens_the_play_screen() -> void:
	# The route table is the check: the Play screen sets the night's rules and then opens the night
	# (`test_solo_match_settings.gd` presses Solo and runs it).
	assert_str(MainMenu.ROUTES[&"solo"][0]).is_equal(MainMenu.PLAY_SCREEN)
	assert_str(MainMenu.PLAY_SCREEN).is_equal("res://ui/screens/play_screen.tscn")


func test_the_board_the_account_replaces_the_file_with_shows_in_the_open_menu() -> void:
	var path := ChallengeFixture.save_path("menu_account")
	var clock := ChallengeFixture.clock_on(20401)
	MainMenu.board_factory = func() -> Object: return ChallengeBoard.open(path, clock)
	var menu := await _show()
	var board := menu.shell.context.board as ChallengeBoard
	assert_int(int(board.profile.lifetime.get(&"kills", 0))).is_zero()
	# The read at sign-in lands after the menu is up: the account's board has 40 kills.
	var theirs := ChallengeProfile.fresh_for("an-account")
	theirs.apply(board.catalog, &"kills", 40, 40)
	var answer := {
		"ok": true, "found": true, "revision": 3, "schema_version": 1, "data": theirs.to_dict()
	}
	assert_bool(ChallengeUplink.adopt(answer, "an-account", path)).is_true()
	ChallengeBoard.file_replaced(path)
	assert_int(int(board.profile.lifetime[&"kills"])).is_equal(40)
	assert_str(board.profile.account).is_equal("an-account")


func test_a_night_that_wrote_the_board_shows_when_the_menu_comes_back() -> void:
	var path := ChallengeFixture.save_path("menu_night")
	var clock := ChallengeFixture.clock_on(20401)
	MainMenu.board_factory = func() -> Object: return ChallengeBoard.open(path, clock)
	var menu := await _show()
	var board := menu.shell.context.board as ChallengeBoard
	UIRouter.push("res://ui/screens/credits_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	# The night, over this screen, counts into a board of its own and saves it.
	var night_board := ChallengeBoard.open(path, clock)
	night_board.profile.apply(night_board.catalog, &"kills", 25, 25)
	night_board.save()
	assert_int(int(board.profile.lifetime.get(&"kills", 0))).is_zero()
	UIRouter.pop()
	await UIRouter.idle
	await await_idle_frame()
	assert_int(int(board.profile.lifetime[&"kills"])).is_equal(25)
