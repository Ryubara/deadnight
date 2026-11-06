# gdlint: disable=max-public-methods
# The Server Browser (Deadnight #1180): the list of public
# nights, lobbies that wait and matches in progress, one press from a night. These tests run it
# against a backend that answers from the test (`BrowserFixture.FakeApi`);
# `tests/net/test_server_browser_online.gd` runs it over the real one.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const BROWSER := "res://ui/screens/server_browser_screen.tscn"
const LOBBY := "res://ui/screens/lobby_screen.tscn"

var _api: BrowserFixture.FakeApi
var _entered := 0


func before_test() -> void:
	_entered = 0
	_api = BrowserFixture.FakeApi.new(self)
	_api.nights = BrowserFixture.nights()
	for night: Dictionary in _api.nights:
		_api.by_code[night["code"]] = BrowserFixture.lobby_of(
			night["code"], night["kind"] == "match", night["map"]
		)
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	NightScreen.join_map = ""
	NightScreen.return_lobby = {}
	NightScreen.return_api = null
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	ServerBrowserScreen.api_factory = func(_parent: Node) -> TogetherApi: return _api
	ServerBrowserScreen.opener = func() -> void: _entered += 1


func after_test() -> void:
	ServerBrowserScreen.api_factory = Callable()
	ServerBrowserScreen.opener = Callable()
	MainMenu.board_factory = Callable()
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	NightScreen.join_map = ""
	NightScreen.return_lobby = {}
	NightScreen.return_api = null
	await RouterFixture.clear(get_tree())
	await get_tree().process_frame
	Audio.stop_all()


## The browser alone on the router, with its list in.
func _open(with_api: TogetherApi = null) -> ServerBrowserScreen:
	var params := {"api": with_api} if with_api != null else {}
	UIRouter.reset(BROWSER, UITransition.Kind.CUT, params)
	await UIRouter.idle
	var screen := UIRouter.top() as ServerBrowserScreen
	await _until(
		func() -> bool:
			return screen.feed.state != NightListFeed.State.IDLE and not screen.feed.is_asking()
	)
	await await_idle_frame()
	return screen


## Waits up to `seconds` for `condition`, a frame at a time; true if it came.
func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().process_frame
	return true


func _lobby_on_top() -> LobbyScreen:
	await _until(func() -> bool: return UIRouter.top() is LobbyScreen and not UIRouter.busy)
	await await_idle_frame()
	return UIRouter.top() as LobbyScreen


func _focused_code() -> String:
	var focus := get_viewport().gui_get_focus_owner()
	return (focus as NightRow).entry.code if focus is NightRow else ""


# --- Where it opens from ---


func test_the_play_tab_has_the_server_browser_as_its_second_start() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	var menu := UIRouter.top() as MainMenu
	var play := menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel
	assert_str(play.button(&"browser").title).is_equal("Server browser")
	for route: Array in PlayPanel.ROUTES:
		assert_bool(str(route[1]).to_lower().begins_with("quick")).is_false()
	play.button(&"browser").pressed.emit()
	await UIRouter.idle
	await await_idle_frame()
	assert_object(UIRouter.top()).is_instanceof(ServerBrowserScreen)
	assert_int(UIRouter.depth()).is_equal(2)


func test_no_start_of_the_play_tab_writes_its_note_over_its_title() -> void:
	# The note is drawn at the right of a plain start; a title long enough ran into it (the first
	# words of this one did, and the fit sweep cannot see text drawn inside a button).
	var tokens := UITokens.active()
	var panel := PlayPanel.new()
	var room := panel.width(false) - MenuItemButton.PAD - (MenuItemButton.PERF_FROM_RIGHT + 40.0)
	panel.free()
	for index in range(1, PlayPanel.ROUTES.size()):
		var route: Array = PlayPanel.ROUTES[index]
		var title := (
			tokens
			. font_display
			. get_string_size(
				str(route[1]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, MenuLook.SIZE_TITLE
			)
			. x
		)
		var note := (
			tokens
			. font_text
			. get_string_size(str(route[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, MenuLook.SIZE_CAPTION)
			. x
		)
		(
			assert_float(title + note + 24.0)
			. override_failure_message(
				"%s: title %.0f and note %.0f in %.0f" % [route[1], title, note, room]
			)
			. is_less(room)
		)


func test_the_play_together_screen_offers_the_browser_as_its_first_choice() -> void:
	UIRouter.reset("res://ui/screens/together_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	var together := UIRouter.top() as TogetherScreen
	assert_str(together.browser_button.text).is_equal("Server browser")
	together.browser_button.pressed.emit()
	await UIRouter.idle
	await await_idle_frame()
	assert_object(UIRouter.top()).is_instanceof(ServerBrowserScreen)


# --- What it shows ---


func test_it_lists_lobbies_and_matches_in_the_backends_order() -> void:
	var screen := await _open()
	assert_int(screen.rows().size()).is_equal(5)
	var codes: Array[String] = []
	for row in screen.rows():
		codes.append(row.entry.code)
	assert_array(codes).is_equal(["KITE42", "LAMP77", "ROSE19", "MOTH05", "FULL88"])
	assert_str(screen.count_label.text).is_equal("5 NIGHTS")


func test_a_row_tells_a_waiting_lobby_from_a_night_in_progress_at_a_glance() -> void:
	var screen := await _open()
	assert_str(screen.row_of("LAMP77").chip_text()).is_equal("WAITING")
	assert_str(screen.row_of("ROSE19").chip_text()).is_equal("WAITING")
	assert_str(screen.row_of("KITE42").chip_text()).is_equal("IN PROGRESS  ROUND 6")
	assert_str(screen.row_of("MOTH05").chip_text()).is_equal("IN PROGRESS  ROUND 11")
	assert_str(screen.row_of("FULL88").chip_text()).is_equal("FULL")
	# And the screen says how many of each.
	assert_str(screen.status.text).contains("2 waiting to start")
	assert_str(screen.status.text).contains("3 in progress")


func test_a_row_names_the_map_the_people_out_of_eight_and_leaves_the_bots_out_of_them() -> void:
	var screen := await _open()
	var kite := screen.row_of("KITE42")
	assert_str(kite.entry.map().title).is_equal("Drive-in lot")
	assert_str(kite.entry.people_text()).is_equal("3 of 8")
	assert_str(kite.entry.bots_text()).is_equal("+2 bots")
	assert_str(screen.row_of("LAMP77").entry.map().title).is_equal("The back rooms")
	assert_str(kite.accessibility_name).contains("3 of 8 people")
	assert_object(kite.entry.map().preview()).is_not_null()


func test_empty_loading_and_failed_are_said_in_words() -> void:
	_api.nights = []
	var empty := await _open()
	assert_str(empty.status.text).is_equal(ServerBrowserScreen.EMPTY)
	assert_int(empty.rows().size()).is_equal(0)
	# Create a night is the way on, and takes the focus.
	assert_int(empty.create_button.variant).is_equal(UIButton.Variant.PRIMARY)
	await _until(func() -> bool: return empty.create_button.has_focus())
	assert_bool(empty.create_button.has_focus()).is_true()

	_api.list_failure = "network"
	var failed := await _open()
	assert_str(failed.status.text).is_equal(TogetherApi.TEXTS["network"])
	assert_str(failed.refresh_button.text).is_equal("Try again")
	# Try again, with the network back, shows the list.
	_api.list_failure = ""
	_api.nights = BrowserFixture.nights()
	failed.feed.clock = func() -> float: return Time.get_ticks_msec() / 1000.0 + 100.0
	failed.refresh_button.pressed.emit()
	await _until(func() -> bool: return failed.rows().size() == 5)
	assert_int(failed.rows().size()).is_equal(5)
	assert_str(failed.refresh_button.text).is_equal("Refresh")

	_api.hold_list = true
	UIRouter.reset(BROWSER, UITransition.Kind.CUT)
	await UIRouter.idle
	var loading := UIRouter.top() as ServerBrowserScreen
	await _until(func() -> bool: return loading.status.text == ServerBrowserScreen.LOADING)
	assert_str(loading.status.text).is_equal(ServerBrowserScreen.LOADING)
	_api.released.emit()


func test_a_sign_in_that_fails_is_said_in_words_and_the_slot_says_the_list_did_not_load() -> void:
	_api.sign_in_failure = "network"
	UIRouter.reset(BROWSER, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as ServerBrowserScreen
	await _until(func() -> bool: return screen.status.text == TogetherApi.TEXTS["network"])
	assert_str(screen.status.text).is_equal(TogetherApi.TEXTS["network"])
	assert_str(screen.slot.text).is_equal(ServerBrowserScreen.SLOT_FAILED)
	assert_str(screen.refresh_button.text).is_equal("Try again")
	assert_int(_api.list_calls).is_equal(0)
	# Try again signs in again, and the list comes.
	_api.sign_in_failure = ""
	screen.refresh_button.pressed.emit()
	await _until(func() -> bool: return screen.rows().size() == 5)
	assert_int(screen.rows().size()).is_equal(5)


func test_the_first_row_has_the_focus_when_the_list_arrives() -> void:
	var screen := await _open()
	await _until(func() -> bool: return _focused_code() == "KITE42")
	assert_str(_focused_code()).is_equal("KITE42")
	assert_bool(screen.back_button.has_focus()).is_false()


# --- A press ---


func test_one_press_on_a_waiting_lobby_puts_the_player_in_its_lobby() -> void:
	var screen := await _open()
	screen.row_of("LAMP77").pressed.emit()
	var lobby := await _lobby_on_top()
	assert_object(lobby).is_not_null()
	assert_array(_api.joined).is_equal(["LAMP77"])
	assert_int(lobby.mode).is_equal(LobbyScreen.Mode.LIVE)
	assert_str(lobby.code_label.text).is_equal("LAMP77")
	assert_int(_api.tickets).is_equal(0)
	assert_int(_entered).is_equal(0)


func test_one_press_on_a_night_in_progress_goes_straight_into_the_night() -> void:
	var screen := await _open()
	screen.row_of("MOTH05").pressed.emit()
	await _until(func() -> bool: return _entered > 0)
	assert_array(_api.joined).is_equal(["MOTH05"])
	assert_int(_api.tickets).is_equal(1)
	assert_int(_entered).is_equal(1)
	assert_str(NightScreen.join_ticket).is_equal("t-1")
	assert_str(NightScreen.join_map).is_equal("small_indoor")
	assert_bool(NightScreen.return_lobby.is_empty()).is_false()
	assert_str(str(NightScreen.return_lobby["code"])).is_equal("MOTH05")
	# No screen came between: the browser is still the one on top (the real opener pushes the
	# night).
	assert_object(UIRouter.top()).is_same(screen)


func test_a_lobby_and_a_match_are_joined_the_same_way_by_the_rows_code() -> void:
	var screen := await _open()
	screen.row_of("KITE42").pressed.emit()
	await _until(func() -> bool: return _entered > 0)
	assert_array(_api.joined).is_equal(["KITE42"])
	assert_int(_api.created).is_equal(0)


func test_a_press_while_the_join_is_on_its_way_is_one_join() -> void:
	_api.hold_join = true
	var screen := await _open()
	var row := screen.row_of("LAMP77")
	row.pressed.emit()
	await await_idle_frame()
	assert_bool(screen.is_busy()).is_true()
	assert_str(row.chip_text()).is_equal("JOINING...")
	row.pressed.emit()
	screen.row_of("ROSE19").pressed.emit()
	assert_array(_api.joined).is_equal(["LAMP77"])
	# The screen cannot be left while the answer is on its way.
	assert_bool(screen.allow_back).is_false()
	_api.released.emit()
	await _lobby_on_top()
	assert_array(_api.joined).is_equal(["LAMP77"])


func test_a_full_night_is_refused_in_words_and_asks_nothing() -> void:
	var screen := await _open()
	screen.row_of("FULL88").pressed.emit()
	assert_array(_api.joined).is_empty()
	assert_str(screen.note.text).is_equal(ServerBrowserScreen.FULL)
	assert_bool(screen.is_busy()).is_false()


func test_a_night_that_ended_while_the_list_was_open_says_so_and_the_list_is_read_again() -> void:
	var screen := await _open()
	_api.join_failure = "not_found"
	_api.nights = BrowserFixture.nights().slice(1)
	screen.row_of("KITE42").pressed.emit()
	await _until(func() -> bool: return screen.rows().size() == 4)
	assert_str(screen.note.text).is_equal(ServerBrowserScreen.GONE)
	assert_bool(screen.is_busy()).is_false()
	assert_bool(screen.allow_back).is_true()
	assert_object(screen.row_of("KITE42")).is_null()


func test_a_night_that_filled_while_the_list_was_open_is_refused_by_the_backend_in_words() -> void:
	var screen := await _open()
	_api.join_failure = "full"
	screen.row_of("ROSE19").pressed.emit()
	await _until(func() -> bool: return screen.note.text != "" and not screen.is_busy())
	assert_str(screen.note.text).is_equal(TogetherApi.TEXTS["full"])
	assert_bool(screen.is_busy()).is_false()
	assert_int(UIRouter.depth()).is_equal(1)


# --- While it is open ---


func test_the_list_follows_the_backend_and_the_focus_stays_on_the_row_the_player_is_on() -> void:
	var screen := await _open()
	screen.row_of("ROSE19").grab_focus()
	await await_idle_frame()
	assert_str(_focused_code()).is_equal("ROSE19")
	# A new night appears above, and one fills: the rows are rebuilt around the focused one.
	var changed := BrowserFixture.nights()
	changed.insert(0, BrowserFixture.row("NEW001", "drive_in", "lobby", 1, "Zed"))
	changed[3] = BrowserFixture.row("ROSE19", "drive_in", "lobby", 7, "Cy", 3)
	_api.nights = changed
	screen.feed.clock = func() -> float: return Time.get_ticks_msec() / 1000.0 + 50.0
	screen.feed.refresh()
	await _until(func() -> bool: return screen.rows().size() == 6)
	await await_idle_frame()
	await await_idle_frame()
	assert_str(screen.rows()[0].entry.code).is_equal("NEW001")
	assert_str(_focused_code()).is_equal("ROSE19")
	assert_str(screen.row_of("ROSE19").entry.people_text()).is_equal("7 of 8")


func test_a_night_that_filled_is_shown_full_and_a_night_that_ended_is_gone() -> void:
	var screen := await _open()
	var changed := BrowserFixture.nights()
	changed[0] = BrowserFixture.row("KITE42", "drive_in", "match", 8, "Ann", 2, 6)
	changed.remove_at(1)
	_api.nights = changed
	screen.feed.clock = func() -> float: return Time.get_ticks_msec() / 1000.0 + 50.0
	screen.feed.refresh()
	await _until(func() -> bool: return screen.rows().size() == 4)
	assert_str(screen.row_of("KITE42").chip_text()).is_equal("FULL")
	assert_object(screen.row_of("LAMP77")).is_null()
	assert_str(screen.status.text).contains("in progress")


func test_a_row_removed_under_the_focus_hands_it_to_the_row_now_in_its_place() -> void:
	var screen := await _open()
	screen.row_of("LAMP77").grab_focus()
	await await_idle_frame()
	var changed := BrowserFixture.nights()
	changed.remove_at(1)
	_api.nights = changed
	screen.feed.clock = func() -> float: return Time.get_ticks_msec() / 1000.0 + 50.0
	screen.feed.refresh()
	await _until(func() -> bool: return screen.rows().size() == 4)
	await await_idle_frame()
	await await_idle_frame()
	assert_str(_focused_code()).is_equal("ROSE19")


func test_the_list_is_read_again_when_the_player_comes_back_from_a_night() -> void:
	var screen := await _open()
	var before := _api.list_calls
	screen.row_of("MOTH05").pressed.emit()
	await _until(func() -> bool: return _entered > 0)
	# The player leaves the night: whatever is on top goes, and the browser shows again.
	screen.screen_resume()
	await _until(func() -> bool: return _api.list_calls > before)
	assert_int(_api.list_calls).is_greater(before)
	assert_bool(screen.is_busy()).is_false()
	assert_bool(screen.allow_back).is_true()


# --- From inside a lobby ---


func _lobby_then_browser() -> Array:
	var host := LobbyFixture.member("a", "Me", 1, true)
	var bo := LobbyFixture.member("b", "Bo", 2)
	_api.lobby = LobbyFixture.lobby([host, bo])
	UIRouter.reset(LOBBY, UITransition.Kind.CUT, {"api": _api, "lobby": _api.lobby})
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.watch.every = 3600.0
	await await_idle_frame()
	lobby.browse_button.pressed.emit()
	await UIRouter.idle
	await await_idle_frame()
	var screen := UIRouter.top() as ServerBrowserScreen
	await _until(func() -> bool: return screen.rows().size() == 5)
	return [lobby, screen]


func test_a_lobby_has_a_server_browser_button_and_it_opens_the_list_over_the_lobby() -> void:
	var both := await _lobby_then_browser()
	var lobby: LobbyScreen = both[0]
	var screen: ServerBrowserScreen = both[1]
	assert_int(UIRouter.depth()).is_equal(2)
	assert_object(UIRouter.screens()[0]).is_same(lobby)
	assert_object(screen.from_lobby).is_not_null()
	assert_str(str(screen.from_lobby["id"])).is_equal("l1")


func test_back_from_the_browser_returns_to_the_lobby_still_a_member() -> void:
	var both := await _lobby_then_browser()
	var lobby: LobbyScreen = both[0]
	var screen: ServerBrowserScreen = both[1]
	screen.back_button.pressed.emit()
	await UIRouter.idle
	await await_idle_frame()
	assert_object(UIRouter.top()).is_same(lobby)
	assert_array(_api.left).is_empty()
	assert_array(_api.joined).is_empty()


func test_the_lobby_the_player_is_in_is_marked_and_a_press_on_it_goes_back() -> void:
	var host := LobbyFixture.member("a", "Me", 1, true)
	_api.lobby = LobbyFixture.lobby([host])
	_api.lobby["id"] = "id-ROSE19"
	_api.lobby["code"] = "ROSE19"
	UIRouter.reset(LOBBY, UITransition.Kind.CUT, {"api": _api, "lobby": _api.lobby})
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.watch.every = 3600.0
	lobby.browse_button.pressed.emit()
	await UIRouter.idle
	var screen := UIRouter.top() as ServerBrowserScreen
	await _until(func() -> bool: return screen.rows().size() == 5)
	var mine := screen.row_of("ROSE19")
	assert_bool(mine.here).is_true()
	assert_str(mine.chip_text()).is_equal("YOUR NIGHT")
	mine.pressed.emit()
	await UIRouter.idle
	await await_idle_frame()
	assert_object(UIRouter.top()).is_same(lobby)
	assert_array(_api.joined).is_empty()


func test_a_press_on_a_row_from_inside_a_lobby_moves_the_player_with_no_leave_and_no_stop() -> void:
	var both := await _lobby_then_browser()
	var old_lobby: LobbyScreen = both[0]
	var screen: ServerBrowserScreen = both[1]
	var ref: WeakRef = weakref(old_lobby)
	screen.row_of("LAMP77").pressed.emit()
	var next := await _lobby_on_top()
	# The new lobby is on top and live; the old lobby screen is gone and said nothing to the
	# backend.
	assert_str(next.code_label.text).is_equal("LAMP77")
	assert_array(_api.joined).is_equal(["LAMP77"])
	await _until(func() -> bool: return ref.get_ref() == null)
	assert_object(ref.get_ref()).is_null()
	assert_array(_api.left).is_empty()
	for held in UIRouter.screens():
		assert_bool(held == old_lobby).is_false()


func test_a_press_on_a_night_in_progress_from_inside_a_lobby_moves_the_player_into_it() -> void:
	var both := await _lobby_then_browser()
	var old_lobby: LobbyScreen = both[0]
	var screen: ServerBrowserScreen = both[1]
	var ref: WeakRef = weakref(old_lobby)
	screen.row_of("KITE42").pressed.emit()
	await _until(func() -> bool: return _entered > 0)
	await _until(func() -> bool: return ref.get_ref() == null)
	assert_object(ref.get_ref()).is_null()
	assert_array(_api.left).is_empty()
	assert_int(_api.tickets).is_equal(1)


func test_a_press_that_is_refused_from_inside_a_lobby_leaves_the_lobby_where_it_was() -> void:
	var both := await _lobby_then_browser()
	var old_lobby: LobbyScreen = both[0]
	var screen: ServerBrowserScreen = both[1]
	_api.join_failure = "full"
	screen.row_of("ROSE19").pressed.emit()
	await _until(func() -> bool: return screen.note.text != "" and not screen.is_busy())
	assert_bool(is_instance_valid(old_lobby)).is_true()
	assert_bool(old_lobby.is_queued_for_deletion()).is_false()
	screen.back_button.pressed.emit()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_same(old_lobby)


func test_the_lobby_is_kept_alive_while_the_browser_is_open_over_it() -> void:
	var both := await _lobby_then_browser()
	assert_object(both[1]).is_not_null()
	# Each list read also reads the lobby the player is in, as its own (covered) screen cannot.
	assert_int(_api.refreshes).is_greater(0)


func test_a_lobby_opened_from_the_browser_can_open_the_list_again_and_leave_goes_back_to_it(
) -> void:
	var screen := await _open()
	screen.row_of("LAMP77").pressed.emit()
	var lobby := await _lobby_on_top()
	assert_bool(lobby.browse_button.visible).is_true()
	# From that lobby, the list again over it, and a press on another night moves the player there.
	lobby.browse_button.pressed.emit()
	await UIRouter.idle
	await await_idle_frame()
	var again := UIRouter.top() as ServerBrowserScreen
	assert_object(again).is_not_same(screen)
	await _until(func() -> bool: return again.rows().size() == 5)
	again.row_of("ROSE19").pressed.emit()
	var next := await _lobby_on_top()
	assert_str(next.code_label.text).is_equal("ROSE19")
	assert_array(_api.left).is_empty()
	# And Leave goes back to the first list.
	next.leave_button.pressed.emit()
	await UIRouter.idle
	await await_idle_frame()
	assert_object(UIRouter.top()).is_same(screen)


# --- The footer ---


func test_create_a_night_makes_a_lobby_and_opens_it() -> void:
	var screen := await _open()
	screen.create_button.pressed.emit()
	var lobby := await _lobby_on_top()
	assert_int(_api.created).is_equal(1)
	assert_object(lobby).is_not_null()


func test_back_pops_the_browser() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	menu.shell.context.request(&"browser")
	await UIRouter.idle
	await await_idle_frame()
	var screen := UIRouter.top() as ServerBrowserScreen
	assert_object(screen).is_not_null()
	screen.back_button.pressed.emit()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_same(menu)


# --- Keyboard, gamepad and touch ---


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await await_idle_frame()


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await await_idle_frame()


func test_the_keyboard_walks_the_rows_and_enter_joins() -> void:
	var screen := await _open()
	await _until(func() -> bool: return _focused_code() == "KITE42")
	await _key(KEY_DOWN)
	assert_str(_focused_code()).is_equal("LAMP77")
	await _key(KEY_DOWN)
	assert_str(_focused_code()).is_equal("ROSE19")
	await _key(KEY_UP)
	assert_str(_focused_code()).is_equal("LAMP77")
	await _key(KEY_ENTER)
	await _lobby_on_top()
	assert_array(_api.joined).is_equal(["LAMP77"])
	assert_object(screen).is_not_null()


func test_the_gamepad_walks_the_rows_and_a_joins() -> void:
	await _open()
	await _until(func() -> bool: return _focused_code() == "KITE42")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_str(_focused_code()).is_equal("MOTH05")
	await _pad(JOY_BUTTON_A)
	await _until(func() -> bool: return _entered > 0)
	assert_array(_api.joined).is_equal(["MOTH05"])


func test_the_gamepad_reaches_the_footer_from_the_last_row_and_b_goes_back() -> void:
	var screen := await _open()
	screen.row_of("FULL88").grab_focus()
	await await_idle_frame()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_bool(screen.refresh_button.has_focus()).is_true()
	await _pad(JOY_BUTTON_DPAD_UP)
	assert_str(_focused_code()).is_equal("FULL88")


func test_a_touch_on_a_row_joins_it() -> void:
	var screen := await _open()
	var row := screen.row_of("LAMP77")
	var at := get_viewport().get_final_transform() * row.get_global_rect().get_center()
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = at
		touch.pressed = pressed
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
		await await_idle_frame()
	await _lobby_on_top()
	assert_array(_api.joined).is_equal(["LAMP77"])


func test_a_mouse_click_on_a_row_joins_it() -> void:
	var screen := await _open()
	var row := screen.row_of("LAMP77")
	var at := row.get_global_rect().get_center()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		get_viewport().push_input(click, true)
		await await_idle_frame()
	await _lobby_on_top()
	assert_array(_api.joined).is_equal(["LAMP77"])


# --- The phone ---


func test_on_a_phone_held_sideways_the_rows_are_the_phones_and_a_tap_target_tall() -> void:
	var screen := await _open()
	# A desktop canvas is 1080 units tall; a phone page with the phone scale is 540 (1688 x 780 at
	# ratio 2 is 1169 x 540 units), and the rows are the phone's there.
	screen.size = Vector2(1920.0, 1080.0)
	screen._fit()
	assert_bool(screen.compact).is_false()
	assert_float(screen.rows()[0].custom_minimum_size.y).is_equal(NightRow.HEIGHT)
	screen.size = Vector2(1169.0, 540.0)
	screen._fit()
	assert_bool(screen.compact).is_true()
	assert_float(screen.rows()[0].custom_minimum_size.y).is_equal(NightRow.COMPACT_HEIGHT)
	assert_float(NightRow.COMPACT_HEIGHT).is_greater_equal(MenuLook.TAP_TARGET)
	# In CSS pixels on the real phone page: a unit is 0.72 CSS px, so the compact row is over 44 px.
	var css_per_unit := MenuScale.pixels_per_unit(Vector2i(1688, 780), 2.0) / 2.0
	assert_float(NightRow.COMPACT_HEIGHT * css_per_unit).is_greater_equal(44.0)
