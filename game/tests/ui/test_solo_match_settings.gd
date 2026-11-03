# Solo offers the match settings a room host sets (#620): the menu's Solo opens the Play screen,
# that screen and the room's lobby show every setting `MatchSettings` has (one definition, so a new
# setting cannot reach rooms and miss solo), the chosen values reach the running night's rules, and
# the screen fits a desktop window and a phone held sideways.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const PLAY := "res://ui/screens/play_screen.tscn"
## The canvas a 19.5:9 phone gives the menu (the phone factor halves 1080 to 540 units).
const PHONE_CANVAS := Vector2(1168.0, 540.0)
const DESKTOP_CANVAS := Vector2(1280.0, 720.0)


func before_test() -> void:
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()


func after_test() -> void:
	MainMenu.board_factory = Callable()
	NightScreen.match_settings = null
	await RouterFixture.clear(get_tree())


func _open_menu() -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	return UIRouter.top() as MainMenu


## Solo as the player asks for it: the Play tab's Solo button.
func _press_solo(menu: MainMenu) -> void:
	menu.shell.context.request(&"solo")
	await UIRouter.idle
	await await_idle_frame()


func _lobby() -> LobbyScreen:
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	screen.params = {"api": api, "lobby": api.lobby}
	add_child(screen)
	screen.watch.every = 3600.0
	return screen


func _boxed(canvas: Vector2) -> Array:
	var holder := Control.new()
	holder.size = canvas
	add_child(holder)
	var screen := (load(PLAY) as PackedScene).instantiate() as PlayScreen
	holder.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return [holder, screen]


func test_solo_opens_the_play_screen_before_the_night() -> void:
	var menu := await _open_menu()
	await _press_solo(menu)
	assert_object(UIRouter.top()).is_instanceof(PlayScreen)
	assert_str(MainMenu.ROUTES[&"solo"][0]).is_equal(PLAY)
	assert_int(UIRouter.depth()).is_equal(2)


func test_solo_shows_every_setting_a_room_host_sees() -> void:
	var menu := await _open_menu()
	await _press_solo(menu)
	var solo := UIRouter.top() as PlayScreen
	var lobby := _lobby()
	var every: Array = MatchSettings.KEYS.keys()
	assert_array(solo.panel.setting_keys()).contains_exactly_in_any_order(every)
	assert_array(lobby.rules.setting_keys()).contains_exactly_in_any_order(every)
	# One row per setting, in the order the room shows them.
	assert_array(solo.panel.setting_keys()).is_equal(lobby.rules.setting_keys())
	for key: String in every:
		assert_object(solo.panel.row_for(key)).is_not_null()
		assert_bool(solo.panel.row_for(key).is_visible_in_tree()).is_true()
	lobby.free()


func test_a_setting_without_a_row_is_found() -> void:
	# What the check above stands on: a panel that lacks a key `MatchSettings` has names it.
	var panel := MatchSettingsPanel.new()
	assert_array(panel.missing_keys()).is_empty()
	panel.rows.erase("break_seconds")
	assert_array(panel.missing_keys()).is_equal(["break_seconds"])
	panel.free()


func test_solo_with_other_multipliers_runs_them_in_the_night() -> void:
	var menu := await _open_menu()
	await _press_solo(menu)
	var solo := UIRouter.top() as PlayScreen
	var chosen := MatchSettings.new()
	chosen.count_multiplier = 3.0
	chosen.max_alive = 11
	chosen.break_seconds = 14.0
	solo.panel.set_settings(chosen)
	solo.start_button.pressed.emit()
	await UIRouter.idle
	var night_screen := UIRouter.top() as NightScreen
	assert_object(night_screen).is_not_null()
	await night_screen.night.ready_to_play
	var rules := night_screen.night.server.rules
	assert_bool(rules.settings.same_as(chosen)).is_true()
	assert_float(rules.settings.count_multiplier).is_equal(3.0)
	assert_float(rules.settings.break_for(rules.tuning.rounds)).is_equal(14.0)
	rules.apply(RulesAction.skip_break())
	var tuned := rules.tuning.rounds.zombies_for_round(1, 1)
	assert_int(rules._round_total).is_equal(roundi(tuned * 3.0))


func test_leaving_the_play_screen_goes_back_to_the_menu_and_starts_nothing() -> void:
	var menu := await _open_menu()
	await _press_solo(menu)
	var solo := UIRouter.top() as PlayScreen
	solo.back_button.pressed.emit()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_same(menu)
	assert_object(NightScreen.match_settings).is_null()


func test_the_play_screen_fits_a_desktop_window_and_a_phone_held_sideways() -> void:
	for canvas: Vector2 in [DESKTOP_CANVAS, PHONE_CANVAS]:
		var made := await _boxed(canvas)
		var holder := made[0] as Control
		var screen := made[1] as PlayScreen
		var wanted: Array[Control] = [screen.start_button, screen.reset_button, screen.back_button]
		for key: String in MatchSettings.KEYS:
			wanted.append(screen.panel.row_for(key))
		for control in wanted:
			var rect := control.get_global_rect()
			assert_float(rect.position.y).is_greater_equal(-0.5)
			assert_float(rect.end.y).is_less_equal(canvas.y + 0.5)
			assert_float(rect.end.x).is_less_equal(canvas.x + 0.5)
		for key: String in MatchSettings.KEYS:
			# The hints are the desktop's; a phone has no room for them. (A headless run measures
			# text as nothing, so the real fit is the capture's check, `solo_settings_tour.gd`.)
			var hint := screen.panel.row_for(key).hint
			assert_bool(hint.is_empty()).is_equal(canvas == PHONE_CANVAS)
		if canvas == PHONE_CANVAS:
			# A finger: 44 px is 61 units at the phone factor.
			for control in wanted:
				assert_float(control.size.y).is_greater_equal(MenuLook.TAP_TARGET - 0.5)
		holder.free()


func test_solo_and_the_room_both_offer_the_bots_setting() -> void:
	var menu := await _open_menu()
	await _press_solo(menu)
	var solo := UIRouter.top() as PlayScreen
	var lobby := _lobby()
	for panel: MatchSettingsPanel in [solo.panel, lobby.rules]:
		assert_object(panel.row_for("bots")).is_not_null()
		assert_bool(panel.row_for("bots").is_visible_in_tree()).is_true()
		panel.set_settings(MatchSettings.new())
		panel.bots_selector.select(3, true)
		assert_int(panel.settings().bots).is_equal(3)
	lobby.free()


func test_solo_with_three_bots_runs_a_night_with_three_bots() -> void:
	var menu := await _open_menu()
	await _press_solo(menu)
	var solo := UIRouter.top() as PlayScreen
	solo.panel.bots_selector.select(3, true)
	solo.start_button.pressed.emit()
	await UIRouter.idle
	var night_screen := UIRouter.top() as NightScreen
	assert_object(night_screen).is_not_null()
	await night_screen.night.ready_to_play
	var night := night_screen.night
	assert_int(night.server.rules.settings.bots).is_equal(3)
	assert_int(night.bots.count()).is_equal(3)
	assert_int(night.server.rules.players.size()).is_equal(4)
