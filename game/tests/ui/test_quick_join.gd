# Quick join on the main menu (#526): pressing it finds the first open public night and goes in,
# without the Play together screen. A search shows "Finding a night..." with Cancel; a night not
# found, or a call that failed, says what the Play together screen says and offers Create a night.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const TOGETHER := "res://ui/screens/together_screen.tscn"

var _entered := 0
var _api: FakeQuickApi
var _host: NightHost


## The backend's answers, from the test: no network. `hold` keeps the search out until `released`.
class FakeQuickApi:
	extends TogetherApi
	signal released
	var hold := false
	var failure := ""
	var url := "ws://127.0.0.1:1"
	var signed_as: Array[String] = []
	var quick_calls := 0
	var ticket_calls := 0
	var created := 0
	var left: Array[String] = []
	## The map the lobby it finds says (its settings), when not the default.
	var found_map := ""

	func sign_in(display_name: String = "") -> Dictionary:
		signed_as.append(display_name)
		return {"ok": true}

	func quick() -> Dictionary:
		quick_calls += 1
		if hold:
			await released
		if failure != "":
			return TogetherApi._failed(failure)
		var found := {"id": "q1", "code": "QUICK1", "state": "started"}
		if found_map != "":
			found["settings"] = {
				"count_multiplier": 1.0, "max_alive": 0, "break_seconds": 0.0, "map": found_map
			}
		return {"ok": true, "lobby": found}

	func ticket(_held: Dictionary) -> Dictionary:
		ticket_calls += 1
		return {
			"ok": true,
			"url": url,
			"activity_path": "/server",
			"ticket": "t-quick",
			"match": "m1",
		}

	func create_lobby() -> Dictionary:
		created += 1
		var host := {"userId": "a", "name": "Ann", "seat": 1, "host": true, "away": false}
		return {"ok": true, "lobby": LobbyFixture.lobby([host])}

	func my_id() -> String:
		return "a"

	func leave(held: Dictionary) -> Dictionary:
		left.append(str(held["id"]))
		return {"ok": true}

	func detached(_parent: Node) -> TogetherApi:
		return self


func before_test() -> void:
	_entered = 0
	_api = FakeQuickApi.new(self)
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	QuickJoinOverlay.api_factory = func(_parent: Node) -> TogetherApi: return _api
	QuickJoinOverlay.opener = func() -> void: _entered += 1


func after_test() -> void:
	QuickJoinOverlay.api_factory = Callable()
	QuickJoinOverlay.opener = Callable()
	MainMenu.board_factory = Callable()
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	await RouterFixture.clear(get_tree())
	if is_instance_valid(_host):
		_host.get_parent().queue_free()
	await get_tree().process_frame
	Audio.stop_all()


func _menu() -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	return UIRouter.top() as MainMenu


func _press_quick_join(menu: MainMenu) -> void:
	var play := menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel
	play.button(&"quick_join").pressed.emit()


func _card(menu: MainMenu) -> QuickJoinOverlay:
	return menu.find_child("QuickJoin", true, false) as QuickJoinOverlay


## Waits up to `seconds` for `condition`, a frame at a time; true if it came.
func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().process_frame
	return true


## Presses nothing: waits until the card on the menu has failed and returns it.
func _failed_card(menu: MainMenu) -> QuickJoinOverlay:
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 20000:
		var card := _card(menu)
		if card != null and card.state == QuickJoinOverlay.State.FAILED:
			return card
		await get_tree().process_frame
	return null


## Whether the node a weak reference held is gone.
func _gone(ref: WeakRef) -> bool:
	return ref.get_ref() == null


func _together_screens() -> int:
	var count := 0
	for screen in UIRouter.screens():
		if screen is TogetherScreen:
			count += 1
	return count


func test_the_quick_join_route_never_opens_the_play_together_screen() -> void:
	# The route table has no entry for it, and Play together keeps its own.
	assert_bool(MainMenu.ROUTES.has(&"quick_join")).is_false()
	assert_str(MainMenu.ROUTES[&"together"][0]).is_equal(TOGETHER)
	for id: StringName in MainMenu.ROUTES:
		if id != &"together":
			assert_str(MainMenu.ROUTES[id][0]).is_not_equal(TOGETHER)


func test_pressing_quick_join_joins_the_first_night_found_and_never_opens_play_together() -> void:
	var menu := await _menu()
	_press_quick_join(menu)
	await _until(func() -> bool: return _entered > 0)
	assert_int(_api.quick_calls).is_equal(1)
	assert_int(_api.ticket_calls).is_equal(1)
	assert_int(_entered).is_equal(1)
	assert_str(NightScreen.join_url).is_equal("ws://127.0.0.1:1")
	assert_str(NightScreen.join_ticket).is_equal("t-quick")
	assert_int(_together_screens()).is_equal(0)
	# The saved name is not asked for again here: no name means `Guest NNNN` (the backend's).
	assert_array(_api.signed_as).is_equal([""])


func test_a_player_with_a_saved_name_signs_in_with_it() -> void:
	var before: String = Settings.get_value(SettingsService.PROFILE_CACHE)
	Settings.set_value(SettingsService.PROFILE_CACHE, "")
	MenuProfile.save_name("Bo")
	var menu := await _menu()
	_press_quick_join(menu)
	await _until(func() -> bool: return _entered > 0)
	assert_array(_api.signed_as).is_equal(["Bo"])
	Settings.set_value(SettingsService.PROFILE_CACHE, before)


func test_it_says_finding_a_night_with_cancel_while_it_searches() -> void:
	_api.hold = true
	var menu := await _menu()
	_press_quick_join(menu)
	await _until(func() -> bool: return _api.quick_calls > 0)
	var card := _card(menu)
	assert_object(card).is_not_null()
	assert_str(card.text()).is_equal("Finding a night...")
	assert_bool(card.cancel_button.is_visible_in_tree()).is_true()
	assert_bool(card.create_button.is_visible_in_tree()).is_false()
	# The player stays on the menu.
	assert_object(UIRouter.top()).is_same(menu)
	assert_int(_together_screens()).is_equal(0)
	_api.released.emit()
	await _until(func() -> bool: return _entered > 0)


func test_cancel_goes_back_to_the_menu_and_leaves_the_night_the_search_found() -> void:
	_api.hold = true
	var menu := await _menu()
	_press_quick_join(menu)
	await _until(func() -> bool: return _api.quick_calls > 0)
	var card := _card(menu)
	var gone: WeakRef = weakref(card)
	card.cancel_button.pressed.emit()
	assert_bool(card.visible).is_false()
	# The search was still out: it ends, the night it found is left, and nothing opens.
	_api.released.emit()
	await _until(func() -> bool: return _gone(gone))
	assert_array(_api.left).is_equal(["q1"])
	assert_int(_entered).is_equal(0)
	assert_str(NightScreen.join_url).is_equal("")
	assert_object(UIRouter.top()).is_same(menu)
	assert_object(_card(menu)).is_null()


func test_escape_cancels_the_search() -> void:
	_api.hold = true
	var menu := await _menu()
	_press_quick_join(menu)
	await _until(func() -> bool: return _api.quick_calls > 0)
	var card := _card(menu)
	var gone: WeakRef = weakref(card)
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	card._input(escape)
	assert_bool(card.visible).is_false()
	_api.released.emit()
	await _until(func() -> bool: return _gone(gone))
	assert_int(_entered).is_equal(0)


func test_no_night_found_says_what_play_together_says_and_offers_create_a_night() -> void:
	_api.failure = "no_server"
	var menu := await _menu()
	_press_quick_join(menu)
	var card: QuickJoinOverlay = await _failed_card(menu)
	assert_str(card.text()).is_equal(TogetherApi.TEXTS["no_server"])
	assert_bool(card.create_button.is_visible_in_tree()).is_true()
	assert_bool(card.close_button.is_visible_in_tree()).is_true()
	assert_int(_entered).is_equal(0)
	assert_int(_api.ticket_calls).is_equal(0)
	assert_int(_together_screens()).is_equal(0)


func test_a_failed_call_says_the_network_text() -> void:
	_api.failure = "network"
	var menu := await _menu()
	_press_quick_join(menu)
	var card: QuickJoinOverlay = await _failed_card(menu)
	assert_str(card.text()).is_equal(TogetherApi.TEXTS["network"])
	assert_bool(card.create_button.is_visible_in_tree()).is_true()
	# The same words as the Play together screen shows for the same answer (a named player is not
	# asked for a name first).
	var before: String = Settings.get_value(SettingsService.PROFILE_CACHE)
	MenuProfile.save_name("Bo")
	var together := (load(TOGETHER) as PackedScene).instantiate() as TogetherScreen
	add_child(together)
	together.api = _api
	_api.failure = "network"
	await together._quick()
	assert_str(together.status.text).is_equal(card.text())
	together.queue_free()
	Settings.set_value(SettingsService.PROFILE_CACHE, before)


func test_close_after_a_failure_returns_to_the_menu_with_its_focus() -> void:
	_api.failure = "network"
	var menu := await _menu()
	_press_quick_join(menu)
	var card: QuickJoinOverlay = await _failed_card(menu)
	var gone: WeakRef = weakref(card)
	card.close_button.pressed.emit()
	await await_idle_frame()
	assert_bool(_gone(gone)).is_true()
	assert_object(UIRouter.top()).is_same(menu)
	var focus := get_viewport().gui_get_focus_owner()
	(
		assert_bool(focus != null and menu.shell.is_ancestor_of(focus))
		. override_failure_message("focus is on %s" % focus)
		. is_true()
	)


func test_create_a_night_after_a_failure_opens_the_lobby_of_a_night_of_your_own() -> void:
	_api.failure = "no_server"
	var menu := await _menu()
	_press_quick_join(menu)
	var card: QuickJoinOverlay = await _failed_card(menu)
	card.create_button.pressed.emit()
	await _until(func() -> bool: return UIRouter.top() is LobbyScreen and not UIRouter.busy)
	var lobby := UIRouter.top() as LobbyScreen
	assert_int(_api.created).is_equal(1)
	assert_object(lobby).is_not_null()
	assert_int(lobby.mode).is_equal(LobbyScreen.Mode.LIVE)
	assert_str(lobby.code_label.text).is_equal("ABC234")
	assert_int(_together_screens()).is_equal(0)


func test_the_card_keeps_the_keys_on_its_own_buttons() -> void:
	_api.failure = "network"
	var menu := await _menu()
	_press_quick_join(menu)
	var card: QuickJoinOverlay = await _failed_card(menu)
	# Down from Create a night reaches Close; nothing of the menu is a neighbour.
	assert_object(card.create_button.get_node(card.create_button.focus_neighbor_bottom)).is_same(
		card.close_button
	)
	assert_object(card.close_button.get_node(card.close_button.focus_neighbor_bottom)).is_same(
		card.create_button
	)
	# A tab key (Q and E) does not turn the menu's tabs behind the card.
	var tab_before := menu.shell.tab
	var key := InputEventKey.new()
	key.keycode = MenuNav.NEXT_KEY
	key.pressed = true
	card._input(key)
	assert_int(menu.shell.tab).is_equal(tab_before)


## The whole way, over a real socket: the press finds a night, takes the ticket and the player is
## running in a game server's room, with Play together never on the stack.
func test_pressing_quick_join_lands_in_a_joined_room() -> void:
	QuickJoinOverlay.opener = Callable()
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	viewport.add_child(_host)
	assert_bool(await _until(func() -> bool: return _host.serving, 30.0)).is_true()
	_api.url = "ws://127.0.0.1:%d" % _host.listener.port()
	var warm_up := NightScreen.warm_up_enabled
	NightScreen.warm_up_enabled = true
	var menu := await _menu()
	_press_quick_join(menu)
	var arrived := await _until(func() -> bool: return UIRouter.top() is NightScreen, 30.0)
	assert_bool(arrived).is_true()
	if UIRouter.busy:
		await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	var running := await _until(func() -> bool: return screen.night.running, 60.0)
	NightScreen.warm_up_enabled = warm_up
	assert_bool(running).is_true()
	assert_bool(screen.night.is_paused()).is_false()
	assert_int(_together_screens()).is_equal(0)
	assert_bool(await _until(func() -> bool: return _host.player_count() >= 1, 10.0)).is_true()


func test_quick_join_shows_the_map_of_the_night_it_found_and_opens_the_night_on_it() -> void:
	StubMaps.install()
	_api.found_map = StubMaps.ID
	_api.hold = true
	var menu := await _menu()
	_press_quick_join(menu)
	await _until(func() -> bool: return _api.quick_calls > 0)
	var card := _card(menu)
	assert_bool(card.map_card.visible).is_false()
	_api.released.emit()
	await _until(func() -> bool: return _entered > 0)
	assert_str(NightScreen.join_map).is_equal(StubMaps.ID)
	NightScreen.join_map = ""
	StubMaps.remove()


func test_quick_join_card_names_the_map_while_the_night_is_being_found() -> void:
	# The card sits under the status line from the moment the backend answers: the lot when the
	# night's lobby says nothing (a night nobody set rules for), the lobby's own map otherwise.
	StubMaps.install()
	var overlay := QuickJoinOverlay.new()
	add_child(overlay)
	await get_tree().process_frame
	overlay._lobby = {"id": "q1", "code": "QUICK1", "state": "started"}
	overlay._show_map()
	assert_bool(overlay.map_card.visible).is_true()
	assert_str(overlay.map_card.info.id).is_equal("drive_in")
	overlay._lobby = {"id": "q1", "map": StubMaps.ID, "settings": null}
	overlay._show_map()
	assert_str(overlay.map_card.info.title).is_equal("Stub lot")
	assert_int(overlay.map_card.focus_mode).is_equal(Control.FOCUS_NONE)
	overlay.free()
	StubMaps.remove()
