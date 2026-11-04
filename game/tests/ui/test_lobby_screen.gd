# gdlint:disable=max-public-methods
# The lobby screen: what each player reads and can press in the waiting room, the preview of a
# code, the host's Start, a guest's Play, the host role moving, and the ways out.
extends GdUnitTestSuite

var _entered := 0


func before_test() -> void:
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	_entered = 0
	LobbyScreen.opener = func() -> void: _entered += 1


func after_test() -> void:
	LobbyScreen.play_as_bot = false
	NightScreen.join_as_bot = false
	LobbyScreen.opener = Callable()
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""


func _instance() -> LobbyScreen:
	return (load("res://ui/screens/lobby_screen.tscn") as PackedScene).instantiate() as LobbyScreen


func _screen(api: LobbyFixture.FakeApi, params: Dictionary) -> LobbyScreen:
	await RouterFixture.clear(get_tree())
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = params.merged({"api": api})
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	return screen


func test_the_screen_asks_through_an_api_under_itself_not_under_the_screen_it_covers() -> void:
	# A covered screen is not processed, and neither are the requests made under it: the lobby
	# screen opened from Play together would otherwise never get an answer (found in the browser).
	var covered := auto_free(Control.new()) as Control
	add_child(covered)
	var api := TogetherApi.new(covered)
	api.isolated = true
	var held := LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	await RouterFixture.clear(get_tree())
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"api": api, "lobby": held}
	add_child(screen)
	assert_object(screen.api.owner_node()).is_same(screen)
	assert_object(screen.api).is_not_same(api)
	screen.free()


func test_the_host_sees_the_code_the_seats_and_start() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
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
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.start_button.is_visible_in_tree()).is_false()
	assert_str(screen.status.text).contains("Waiting for Ann to start the night")
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  (open)", "4  (open)"])
	screen.free()


func test_a_join_a_leave_and_an_away_member_show_in_the_seats_within_a_poll() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	api.refreshed = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	await screen.watch.poll()
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  (open)", "4  (open)"])
	assert_str(screen.note.text).is_equal("Bo joined.")
	api.refreshed = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2, false, true)]
	)
	await screen.watch.poll()
	assert_str(screen.seat_texts()[1]).is_equal("2  Bo  AWAY")
	api.refreshed = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	await screen.watch.poll()
	assert_str(screen.note.text).is_equal("Bo left.")
	assert_str(screen.seat_texts()[1]).is_equal("2  (open)")
	screen.free()


func test_when_the_host_leaves_the_next_seat_gets_start_and_is_told() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.start_button.is_visible_in_tree()).is_false()
	api.refreshed = LobbyFixture.lobby([LobbyFixture.member("b", "Bo", 1, true)])
	await screen.watch.poll()
	assert_bool(screen.start_button.is_visible_in_tree()).is_true()
	assert_str(screen.note.text).contains("Ann left.")
	assert_str(screen.note.text).contains("You are the host now.")
	assert_array(screen.seat_texts()).is_equal(
		["1  Bo  HOST", "2  (open)", "3  (open)", "4  (open)"]
	)
	screen.free()


func test_start_asks_the_backend_then_takes_a_ticket_and_goes_in() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	api.started = LobbyFixture.lobby([api.lobby["members"][0]], "started", 0)
	var screen := await _screen(api, {"lobby": api.lobby})
	await screen.start()
	assert_int(api.tickets).is_equal(1)
	assert_str(NightScreen.join_ticket).is_equal("t-1")
	assert_str(NightScreen.join_url).is_equal("ws://127.0.0.1:1")
	assert_int(_entered).is_equal(1)
	assert_bool(NightScreen.join_as_bot).is_false()
	# On the way into the night the seat is not given up when this screen goes.
	screen.free()
	await get_tree().process_frame
	assert_array(api.left).is_empty()


func test_the_autopilot_flag_reaches_the_night_the_lobby_opens() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	api.started = LobbyFixture.lobby([api.lobby["members"][0]], "started", 0)
	LobbyScreen.play_as_bot = true
	var screen := await _screen(api, {"lobby": api.lobby})
	await screen.start()
	assert_bool(NightScreen.join_as_bot).is_true()
	screen.free()


func test_a_start_the_backend_refuses_says_why_and_keeps_the_lobby_open() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
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
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.play_button.is_visible_in_tree()).is_false()
	api.refreshed = LobbyFixture.lobby(api.lobby["members"], "started", 0)
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
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	var screen := await _screen(api, {"lobby": api.lobby})
	await get_tree().process_frame
	# A guest waiting has nothing to press but Copy and Leave; Play takes the focus when it shows.
	assert_object(screen.get_viewport().gui_get_focus_owner()).is_not_same(screen.play_button)
	api.refreshed = LobbyFixture.lobby(api.lobby["members"], "started", 0)
	await screen.watch.poll()
	await get_tree().process_frame
	assert_object(screen.get_viewport().gui_get_focus_owner()).is_same(screen.play_button)
	screen.free()
	# The host starts on Start.
	var host_api := LobbyFixture.FakeApi.new(self)
	host_api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var host_screen := await _screen(host_api, {"lobby": host_api.lobby})
	await get_tree().process_frame
	assert_object(host_screen.get_viewport().gui_get_focus_owner()).is_same(
		host_screen.start_button
	)
	host_screen.free()


func test_leaving_gives_the_seat_up() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	screen.free()
	await get_tree().process_frame
	assert_array(api.left).is_equal(["l1"])


func test_a_player_the_backend_dropped_is_told_and_has_only_back() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	var failing := LobbyFixture.FailingApi.new(self)
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


func test_sharing_in_discord_is_offered_only_inside_an_activity() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(TogetherScreen.can_share()).is_false()
	assert_bool(screen.share_button.is_visible_in_tree()).is_false()
	screen.free()


## A page that refuses every copy, as a frame whose host blocks the clipboard.
func _refusing_clipboard() -> WebClipboard:
	var clipboard := auto_free(WebClipboard.new()) as WebClipboard
	clipboard.in_frame = true
	clipboard.eval_js = func(js: String) -> Variant:
		return "NotAllowedError" if js.contains(".write") else null
	add_child(clipboard)
	return clipboard


func test_a_copy_the_window_cannot_make_shows_the_code_selected_and_says_how() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
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
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
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
	var api := LobbyFixture.FakeApi.new(self)
	var members := [
		LobbyFixture.member("a", "Ann", 1, true),
		LobbyFixture.member("b", "Bo", 2),
		LobbyFixture.member("c", "Cy", 3),
		LobbyFixture.member("d", "Di", 4),
	]
	api.lobby = LobbyFixture.lobby(members)
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


func _rules(count: float, alive: int, break_seconds: float) -> Dictionary:
	return {"count_multiplier": count, "max_alive": alive, "break_seconds": break_seconds}


func test_the_host_moves_the_rules_and_they_go_to_the_backend_once_the_host_pauses() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.rules.is_visible_in_tree()).is_true()
	assert_bool(screen.rules_editable()).is_true()
	assert_str(screen.rules_text()).is_equal(
		"1x|Auto|%d s" % roundi(screen.rules.break_slider.value)
	)
	# Two quick changes are one request: the last of them.
	screen.rules.count_selector.select(2, true)
	screen.rules.alive_slider.value = 14
	assert_int(api.rules_sent.size()).is_equal(0)
	await screen.send_rules()
	assert_int(api.rules_sent.size()).is_equal(1)
	assert_float(api.rules_sent[0].count_multiplier).is_equal(3.0)
	assert_int(api.rules_sent[0].max_alive).is_equal(14)
	# The host's panel is not overwritten by the lobby's answer to their own request.
	api.refreshed = api.lobby
	await screen.watch.poll()
	assert_int(screen.rules.settings().max_alive).is_equal(14)
	assert_str(screen.rules_text()).starts_with("3x|14|")
	screen.free()


func test_a_refused_change_says_why_and_a_second_change_follows_the_first() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	api.rules_failure = "bad_settings"
	screen.rules.alive_slider.value = 5
	await screen.send_rules()
	assert_str(screen.note.text).is_equal(TogetherApi.TEXTS["bad_settings"])
	api.rules_failure = ""
	screen.rules.alive_slider.value = 6
	await screen.send_rules()
	assert_int(api.rules_sent.size()).is_equal(1)
	assert_int(api.rules_sent[0].max_alive).is_equal(6)
	screen.free()


func test_start_carries_the_rules_the_panel_shows_even_when_the_last_change_was_not_sent() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	api.started = LobbyFixture.lobby([api.lobby["members"][0]], "started", 0)
	var screen := await _screen(api, {"lobby": api.lobby})
	screen.rules.count_selector.select(1, true)
	await screen.start()
	assert_int(api.started_with.size()).is_equal(1)
	assert_float((api.started_with[0] as MatchSettings).count_multiplier).is_equal(2.0)
	# The change that was waiting is not sent after the start.
	await screen.send_rules()
	assert_int(api.rules_sent.size()).is_equal(0)
	screen.free()


func test_a_guest_reads_the_hosts_rules_and_cannot_move_them() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.rules.is_visible_in_tree()).is_true()
	assert_bool(screen.rules_editable()).is_false()
	assert_bool(screen.rules.alive_slider.editable).is_false()
	api.refreshed = api.lobby.duplicate()
	api.refreshed["settings"] = _rules(3.0, 14, 9.0)
	await screen.watch.poll()
	assert_str(screen.rules_text()).is_equal("3x|14|9 s")
	assert_bool(screen.rules.alive_slider.editable).is_false()
	# A change the host makes later shows within a poll.
	api.refreshed = api.refreshed.duplicate()
	api.refreshed["settings"] = _rules(2.0, 0, 0.0)
	await screen.watch.poll()
	assert_str(screen.rules_text()).starts_with("2x|Auto|")
	# A guest's panel sends nothing, whatever moves it.
	screen.rules.alive_slider.value = 20
	await screen.send_rules()
	assert_int(api.rules_sent.size()).is_equal(0)
	screen.free()


func test_the_next_host_takes_the_panel_with_the_rules_the_lobby_holds() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	api.lobby["settings"] = _rules(3.0, 14, 9.0)
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.rules_editable()).is_false()
	api.refreshed = LobbyFixture.lobby([LobbyFixture.member("b", "Bo", 1, true)])
	api.refreshed["settings"] = _rules(3.0, 14, 9.0)
	await screen.watch.poll()
	assert_bool(screen.rules_editable()).is_true()
	assert_bool(screen.rules.alive_slider.editable).is_true()
	assert_str(screen.rules_text()).is_equal("3x|14|9 s")
	screen.free()


func test_the_rules_are_fixed_once_the_night_has_started_and_not_shown_in_a_preview() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	var screen := await _screen(api, {"lobby": api.lobby})
	api.refreshed = LobbyFixture.lobby(api.lobby["members"], "started", 2)
	api.refreshed["settings"] = _rules(2.0, 10, 0.0)
	await screen.watch.poll()
	assert_bool(screen.rules_editable()).is_false()
	assert_str(screen.rules_text()).starts_with("2x|10|")
	screen.free()
	var seen := LobbyFixture.FakeApi.new(self)
	seen.preview_answer = LobbyFixture.preview("open", null, 1)
	var previewing := await _screen(seen, {"preview": seen.preview_answer})
	assert_bool(previewing.rules.is_visible_in_tree()).is_false()
	previewing.free()


# --- The map (#624) ---


func test_the_host_picks_the_map_and_it_goes_to_the_backend_with_the_other_rules() -> void:
	StubMaps.install_picker_set()
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_str(screen.rules.map_picker.selected_id).is_equal("drive_in")
	assert_bool(screen.rules.map_picker.is_editable()).is_true()
	screen.rules.map_picker.card_for(StubMaps.ID).pressed.emit()
	await screen.send_rules()
	assert_int(api.rules_sent.size()).is_equal(1)
	assert_str(api.rules_sent[0].map).is_equal(StubMaps.ID)
	assert_str(api.lobby["settings"]["map"]).is_equal(StubMaps.ID)
	# The card of a map that is not built chooses nothing, so nothing is sent.
	screen.rules.map_picker.card_for(StubMaps.LOCKED_ID).pressed.emit()
	await screen.send_rules()
	assert_int(api.rules_sent.size()).is_equal(1)
	screen.free()
	StubMaps.remove()


func test_the_host_picks_the_second_map_from_the_lobby() -> void:
	StubMaps.remove()
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var screen := await _screen(api, {"lobby": api.lobby})
	var card := screen.rules.map_picker.card_for("small_indoor")
	assert_bool(card.is_locked()).is_false()
	card.pressed.emit()
	await screen.send_rules()
	assert_int(api.rules_sent.size()).is_equal(1)
	assert_str(api.rules_sent[0].map).is_equal("small_indoor")
	assert_str(api.lobby["settings"]["map"]).is_equal("small_indoor")
	screen.free()


func test_a_guest_sees_the_hosts_map_and_cannot_change_it() -> void:
	StubMaps.install()
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_str(screen.rules.map_picker.selected_id).is_equal("drive_in")
	api.refreshed = api.lobby.duplicate()
	api.refreshed["settings"] = _rules(1.0, 0, 0.0).merged({"map": StubMaps.ID})
	await screen.watch.poll()
	assert_str(screen.rules.map_picker.selected_id).is_equal(StubMaps.ID)
	assert_bool(screen.rules.map_picker.is_editable()).is_false()
	screen.rules.map_picker.card_for("drive_in").pressed.emit()
	assert_str(screen.rules.map_picker.selected_id).is_equal(StubMaps.ID)
	await screen.send_rules()
	assert_int(api.rules_sent.size()).is_equal(0)
	# Play opens the night on the map the lobby holds, so the world is built on it before the WELCOME.
	api.refreshed = LobbyFixture.lobby(api.lobby["members"], "started", null)
	api.refreshed["settings"] = _rules(1.0, 0, 0.0).merged({"map": StubMaps.ID})
	await screen.watch.poll()
	await screen._go_in(false)
	assert_str(NightScreen.join_map).is_equal(StubMaps.ID)
	NightScreen.join_map = ""
	screen.free()
	StubMaps.remove()


func test_a_code_looked_at_shows_the_map_of_the_room_before_joining() -> void:
	StubMaps.install()
	var api := LobbyFixture.FakeApi.new(self)
	api.preview_answer = LobbyFixture.preview("open", null, 1)
	var plain := await _screen(api, {"preview": api.preview_answer})
	assert_bool(plain.map_card.is_visible_in_tree()).is_true()
	assert_str(plain.map_card.info.id).is_equal("drive_in")
	assert_int(plain.map_card.focus_mode).is_equal(Control.FOCUS_NONE)
	plain.free()
	var other := LobbyFixture.preview("open", null, 2)
	other["map"] = StubMaps.ID
	api.preview_answer = other
	var shown := await _screen(api, {"preview": other})
	assert_str(shown.map_card.info.id).is_equal(StubMaps.ID)
	assert_str(shown.map_card.info.title).is_equal("Stub lot")
	# A lobby of the player's own shows the map in its rules, not as a second card.
	shown.free()
	var held := LobbyFixture.FakeApi.new(self)
	held.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var live := await _screen(held, {"lobby": held.lobby})
	assert_bool(live.map_card.visible).is_false()
	assert_bool(live.rules.map_picker.is_visible_in_tree()).is_true()
	live.free()
	StubMaps.remove()


func test_a_backend_that_keeps_no_rules_is_said_to_the_host_not_left_to_lose_them() -> void:
	# A backend from before the rules sends lobbies with no `settings` at all, and ignores the rules
	# a start carries: the host's choices would vanish (Deadnight #944).
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	api.lobby.erase("settings")
	var screen := await _screen(api, {"lobby": api.lobby})
	assert_bool(screen.rules_supported()).is_false()
	assert_bool(screen.rules_editable()).is_false()
	assert_bool(screen._rules_note.visible).is_true()
	assert_str(screen._rules_note.text).contains("out of date")
	# One that keeps them says nothing.
	var current := LobbyFixture.FakeApi.new(self)
	current.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	var fine := await _screen(current, {"lobby": current.lobby})
	assert_bool(fine.rules_supported()).is_true()
	assert_bool(fine.rules_editable()).is_true()
	assert_bool(fine._rules_note.visible).is_false()
