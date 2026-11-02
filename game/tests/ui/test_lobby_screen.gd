# The lobby screen: what each player reads and can press in the waiting room, the preview of a
# code, the host's Start, a guest's Play, the host role moving, and the ways out.
extends GdUnitTestSuite


## The backend's answers, from the test: no network.
class FakeApi:
	extends TogetherApi
	var me := "a"
	var lobby := {}
	var refreshed := {}
	var started: Dictionary = {}
	var start_failure := ""
	var joined: Array[String] = []
	var left: Array[String] = []
	var tickets := 0

	func my_id() -> String:
		return me

	func sign_in(_display_name: String = "") -> Dictionary:
		return {"ok": true}

	func refresh(_held: Dictionary) -> Dictionary:
		return {"ok": true, "lobby": refreshed if not refreshed.is_empty() else lobby}

	func start(_held: Dictionary) -> Dictionary:
		if start_failure != "":
			return TogetherApi._failed(start_failure)
		return {"ok": true, "lobby": started}

	func join_code(code: String) -> Dictionary:
		joined.append(code)
		return {"ok": true, "lobby": lobby}

	func leave(held: Dictionary) -> Dictionary:
		left.append(str(held["id"]))
		return {"ok": true}

	func detached(_parent: Node) -> TogetherApi:
		return self

	func ticket(_held: Dictionary) -> Dictionary:
		tickets += 1
		return {
			"ok": true,
			"url": "ws://127.0.0.1:1",
			"activity_path": "/server",
			"ticket": "t-%d" % tickets,
			"match": "m1",
		}


## Every answer says the player is not a member any more.
class FailingApi:
	extends FakeApi

	func refresh(_held: Dictionary) -> Dictionary:
		return TogetherApi._failed("not_member")


var _entered := 0


func before_test() -> void:
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	_entered = 0
	LobbyScreen.opener = func() -> void: _entered += 1


func after_test() -> void:
	LobbyScreen.opener = Callable()
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""


func _member(
	id: String, member_name: String, seat: int, host := false, away := false
) -> Dictionary:
	return {"userId": id, "name": member_name, "seat": seat, "host": host, "away": away}


func _lobby(members: Array, state := "open", round_number: Variant = null) -> Dictionary:
	return {
		"id": "l1",
		"code": "ABC234",
		"hostId": members[0]["userId"],
		"maxPlayers": 4,
		"members": members,
		"state": state,
		"round": round_number,
		"players": null,
	}


func _preview(state: String, round_number: Variant, players: int, full := false) -> Dictionary:
	return {
		"code": "ABC234",
		"state": state,
		"round": round_number,
		"players": players,
		"maxPlayers": 4,
		"full": full,
		"hostName": "Ann",
		"names": ["Ann", "Bo", "Cy", "Di"].slice(0, players),
	}


func _instance() -> LobbyScreen:
	return (load("res://ui/screens/lobby_screen.tscn") as PackedScene).instantiate() as LobbyScreen


func _screen(api: FakeApi, params: Dictionary) -> LobbyScreen:
	await RouterFixture.clear(get_tree())
	var screen := _instance()
	screen.params = params.merged({"api": api})
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	return screen


func test_the_host_sees_the_code_the_seats_and_start() -> void:
	var api := FakeApi.new(self)
	api.lobby = _lobby([_member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_str(screen.code_label.text).is_equal("ABC234")
	assert_array(screen.seat_texts()).is_equal(
		["1  Ann  HOST", "2  (open)", "3  (open)", "4  (open)"]
	)
	assert_bool(screen.start_button.is_visible_in_tree()).is_true()
	assert_bool(screen.play_button.is_visible_in_tree()).is_false()
	assert_str(screen.status.text).contains("1 of 4 here")
	assert_str(screen.leave_button.text).is_equal("Leave")
	# Nothing here is an address or an id.
	for shown in [screen.status.text, screen.note.text, screen.code_label.text]:
		assert_str(shown).not_contains("ws://")
		assert_str(shown).not_contains("http")
	screen.free()


func test_a_guest_waits_for_the_host_and_has_no_start() -> void:
	var api := FakeApi.new(self)
	api.me = "b"
	api.lobby = _lobby([_member("a", "Ann", 1, true), _member("b", "Bo", 2)])
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.start_button.is_visible_in_tree()).is_false()
	assert_str(screen.status.text).contains("Waiting for Ann to start the night")
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  (open)", "4  (open)"])
	screen.free()


func test_a_join_a_leave_and_an_away_member_show_in_the_seats_within_a_poll() -> void:
	var api := FakeApi.new(self)
	api.lobby = _lobby([_member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	api.refreshed = _lobby([_member("a", "Ann", 1, true), _member("b", "Bo", 2)])
	await screen.watch.poll()
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  (open)", "4  (open)"])
	assert_str(screen.note.text).is_equal("Bo joined.")
	api.refreshed = _lobby([_member("a", "Ann", 1, true), _member("b", "Bo", 2, false, true)])
	await screen.watch.poll()
	assert_str(screen.seat_texts()[1]).is_equal("2  Bo  AWAY")
	api.refreshed = _lobby([_member("a", "Ann", 1, true)])
	await screen.watch.poll()
	assert_str(screen.note.text).is_equal("Bo left.")
	assert_str(screen.seat_texts()[1]).is_equal("2  (open)")
	screen.free()


func test_when_the_host_leaves_the_next_seat_gets_start_and_is_told() -> void:
	var api := FakeApi.new(self)
	api.me = "b"
	api.lobby = _lobby([_member("a", "Ann", 1, true), _member("b", "Bo", 2)])
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.start_button.is_visible_in_tree()).is_false()
	api.refreshed = _lobby([_member("b", "Bo", 1, true)])
	await screen.watch.poll()
	assert_bool(screen.start_button.is_visible_in_tree()).is_true()
	assert_str(screen.note.text).contains("Ann left.")
	assert_str(screen.note.text).contains("You are the host now.")
	assert_array(screen.seat_texts()).is_equal(
		["1  Bo  HOST", "2  (open)", "3  (open)", "4  (open)"]
	)
	screen.free()


func test_start_asks_the_backend_then_takes_a_ticket_and_goes_in() -> void:
	var api := FakeApi.new(self)
	api.lobby = _lobby([_member("a", "Ann", 1, true)])
	api.started = _lobby([api.lobby["members"][0]], "started", 0)
	var screen := await _screen(api, {"lobby": api.lobby})
	await screen.start()
	assert_int(api.tickets).is_equal(1)
	assert_str(NightScreen.join_ticket).is_equal("t-1")
	assert_str(NightScreen.join_url).is_equal("ws://127.0.0.1:1")
	assert_int(_entered).is_equal(1)
	# On the way into the night the seat is not given up when this screen goes.
	screen.free()
	await get_tree().process_frame
	assert_array(api.left).is_empty()


func test_a_start_the_backend_refuses_says_why_and_keeps_the_lobby_open() -> void:
	var api := FakeApi.new(self)
	api.lobby = _lobby([_member("a", "Ann", 1, true)])
	api.start_failure = "no_server"
	var screen := await _screen(api, {"lobby": api.lobby})
	await screen.start()
	assert_str(screen.note.text).contains("servers are busy")
	assert_bool(screen.start_button.is_visible_in_tree()).is_true()
	assert_bool(screen.start_button.disabled).is_false()
	assert_int(_entered).is_equal(0)
	assert_int(api.tickets).is_equal(0)
	screen.free()


func test_a_guest_sees_the_start_and_presses_play_once() -> void:
	var api := FakeApi.new(self)
	api.me = "b"
	api.lobby = _lobby([_member("a", "Ann", 1, true), _member("b", "Bo", 2)])
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.play_button.is_visible_in_tree()).is_false()
	api.refreshed = _lobby(api.lobby["members"], "started", 0)
	await screen.watch.poll()
	assert_str(screen.status.text).is_equal("Ann started the night. Press Play.")
	assert_bool(screen.play_button.is_visible_in_tree()).is_true()
	# Nothing walked the guest in: a click is also what lets a browser lock the mouse.
	assert_int(_entered).is_equal(0)
	screen.play_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(api.tickets).is_equal(1)
	assert_int(_entered).is_equal(1)
	screen.free()


func test_the_focus_starts_on_the_main_button_and_follows_the_host_start_to_play() -> void:
	var api := FakeApi.new(self)
	api.me = "b"
	api.lobby = _lobby([_member("a", "Ann", 1, true), _member("b", "Bo", 2)])
	var screen := await _screen(api, {"lobby": api.lobby})
	await get_tree().process_frame
	# A guest waiting has nothing to press but Copy and Leave; Play takes the focus when it shows.
	assert_object(screen.get_viewport().gui_get_focus_owner()).is_not_same(screen.play_button)
	api.refreshed = _lobby(api.lobby["members"], "started", 0)
	await screen.watch.poll()
	await get_tree().process_frame
	assert_object(screen.get_viewport().gui_get_focus_owner()).is_same(screen.play_button)
	screen.free()
	# The host starts on Start.
	var host_api := FakeApi.new(self)
	host_api.lobby = _lobby([_member("a", "Ann", 1, true)])
	var host_screen := await _screen(host_api, {"lobby": host_api.lobby})
	await get_tree().process_frame
	assert_object(host_screen.get_viewport().gui_get_focus_owner()).is_same(
		host_screen.start_button
	)
	host_screen.free()


func test_leaving_gives_the_seat_up() -> void:
	var api := FakeApi.new(self)
	api.lobby = _lobby([_member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	screen.free()
	await get_tree().process_frame
	assert_array(api.left).is_equal(["l1"])


func test_a_player_the_backend_dropped_is_told_and_has_only_back() -> void:
	var api := FakeApi.new(self)
	api.lobby = _lobby([_member("a", "Ann", 1, true), _member("b", "Bo", 2)])
	var failing := FailingApi.new(self)
	failing.me = "b"
	failing.lobby = api.lobby
	var screen := await _screen(failing, {"lobby": api.lobby})
	await screen.watch.poll()
	assert_str(screen.status.text).is_equal(TogetherApi.TEXTS["not_member"])
	assert_str(screen.leave_button.text).is_equal("Back")
	assert_bool(screen.start_button.is_visible_in_tree()).is_false()
	assert_bool(screen.play_button.is_visible_in_tree()).is_false()
	# There is no seat to give up.
	screen.free()
	await get_tree().process_frame
	assert_array(failing.left).is_empty()


func test_a_night_in_progress_says_its_round_before_the_player_joins() -> void:
	var api := FakeApi.new(self)
	var screen := await _screen(api, {"preview": _preview("started", 4, 2)})
	assert_str(screen.status.text).is_equal("Night in progress, round 4. 2 of 4 here.")
	assert_bool(screen.join_button.is_visible_in_tree()).is_true()
	assert_bool(screen.start_button.is_visible_in_tree()).is_false()
	assert_str(screen.leave_button.text).is_equal("Back")
	# Looking joined nobody, and no poll runs for a lobby that is not the player's.
	assert_array(api.joined).is_empty()
	assert_bool(screen.watch.running).is_false()
	# Join on a night in progress goes straight in.
	var members := [_member("a", "Ann", 1, true), _member("b", "Bo", 2), _member("c", "Cy", 3)]
	api.lobby = _lobby(members, "started", 4)
	await screen.join()
	assert_array(api.joined).is_equal(["ABC234"])
	assert_int(api.tickets).is_equal(1)
	assert_int(_entered).is_equal(1)
	screen.free()


func test_a_waiting_room_preview_becomes_the_players_lobby_on_join() -> void:
	var api := FakeApi.new(self)
	api.me = "b"
	var screen := await _screen(api, {"preview": _preview("open", null, 1)})
	assert_str(screen.status.text).is_equal("Waiting room. Ann is hosting, 1 of 4 here.")
	api.lobby = _lobby([_member("a", "Ann", 1, true), _member("b", "Bo", 2)])
	await screen.join()
	assert_int(api.tickets).is_equal(0)
	assert_bool(screen.watch.running).is_true()
	assert_bool(screen.join_button.is_visible_in_tree()).is_false()
	assert_str(screen.status.text).contains("Waiting for Ann")
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  (open)", "4  (open)"])
	screen.free()


func test_a_full_night_offers_no_join() -> void:
	var api := FakeApi.new(self)
	var screen := await _screen(api, {"preview": _preview("started", 2, 4, true)})
	assert_str(screen.status.text).is_equal("That night is full (4 of 4).")
	assert_bool(screen.join_button.is_visible_in_tree()).is_false()
	assert_str(screen.leave_button.text).is_equal("Back")
	assert_bool(screen.leave_button.is_visible_in_tree()).is_true()
	screen.free()


func test_a_night_that_has_not_reported_a_round_says_only_that_it_is_on() -> void:
	for round_number: Variant in [null, 0]:
		var text := LobbyScreen.preview_text(_preview("started", round_number, 1))
		assert_str(text).is_equal("Night in progress. 1 of 4 here.")


## A page that refuses every copy, as a frame whose host blocks the clipboard.
func _refusing_clipboard() -> WebClipboard:
	var clipboard := auto_free(WebClipboard.new()) as WebClipboard
	clipboard.in_frame = true
	clipboard.eval_js = func(js: String) -> Variant:
		return "NotAllowedError" if js.contains(".write") else null
	add_child(clipboard)
	return clipboard


func test_a_copy_the_window_cannot_make_shows_the_code_selected_and_says_how() -> void:
	var api := FakeApi.new(self)
	api.lobby = _lobby([_member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	var clipboard := _refusing_clipboard()
	screen.copy_code_button.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	assert_bool(screen.copy_field.is_visible_in_tree()).is_true()
	assert_str(screen.copy_field.get_selected_text()).is_equal("ABC234")
	assert_str(screen.note.text).is_equal(TogetherScreen.COPY_BLOCKED)
	assert_str(screen.note.text).not_contains("copied")
	assert_str(clipboard._offered).is_equal("ABC234")
	screen.free()


func test_a_copy_that_works_says_copied_and_shows_no_field() -> void:
	var api := FakeApi.new(self)
	api.lobby = _lobby([_member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	WebClipboard.current = null  # a tab or the desktop: the engine's own copy
	screen.copy_code_button.pressed.emit()
	await get_tree().create_timer(0.2).timeout
	assert_str(screen.note.text).is_equal("Code copied.")
	assert_bool(screen.copy_field.is_visible_in_tree()).is_false()
	screen.free()


## The tallest the screen gets (four seats, the web link, the blocked-copy line and the selected
## text) still fits a 720-high window: the invite panel of the Together screen did not. What does
## not fit scrolls, with Start and Leave in view.
func test_the_tallest_lobby_fits_a_720_high_window() -> void:
	var api := FakeApi.new(self)
	var members := [
		_member("a", "Ann", 1, true),
		_member("b", "Bo", 2),
		_member("c", "Cy", 3),
		_member("d", "Di", 4),
	]
	api.lobby = _lobby(members)
	await RouterFixture.clear(get_tree())
	var window := auto_free(SubViewport.new()) as SubViewport
	window.size = Vector2i(1280, 720)
	add_child(window)
	var screen := _instance()
	screen.params = {"lobby": api.lobby, "api": api}
	window.add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	screen.link_label.text = "https://example.invalid/deadnight/index.html?room=ABC234"
	screen.link_label.visible = true
	screen.copy_link_button.visible = true
	screen.copy_field.text = screen.link_label.text
	screen.copy_field.visible = true
	screen.note.text = TogetherScreen.COPY_BLOCKED
	await get_tree().process_frame
	await get_tree().process_frame
	var panel := screen.find_children("*", "UIPanel", true, false)[0] as UIPanel
	assert_float(panel.get_combined_minimum_size().y).is_less(720.0)
	assert_float(panel.size.y).is_less(720.0)
	var scroll := screen._scroll
	assert_float(scroll.size.y).is_less_equal(720.0 - LobbyScreen.PANEL_MARGIN + 0.5)
	# The buttons sit in two rows, the start beside Leave.
	assert_bool(screen.start_button.get_parent() == screen.leave_button.get_parent()).is_true()
	(
		assert_bool(screen.copy_link_button.get_parent() == screen.copy_code_button.get_parent())
		. is_true()
	)
	screen.free()
