# The preview of a code on the lobby screen: waiting room, night in progress with its round, full,
# gone, left open while the night moves on, and Join.
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


func _screen(api: LobbyFixture.FakeApi, params: Dictionary) -> LobbyScreen:
	await RouterFixture.clear(get_tree())
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = params.merged({"api": api})
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	return screen


func test_a_night_in_progress_says_its_round_before_the_player_joins() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	var screen := await _screen(api, {"preview": LobbyFixture.preview("started", 4, 2)})
	assert_str(screen.status.text).is_equal("Night in progress, round 4. 2 of 4 here.")
	assert_bool(screen.join_button.is_visible_in_tree()).is_true()
	assert_bool(screen.start_button.is_visible_in_tree()).is_false()
	assert_str(screen.leave_button.text).is_equal("Back")
	# Looking joined nobody, and no poll runs for a lobby that is not the player's.
	assert_array(api.joined).is_empty()
	assert_bool(screen.watch.running).is_false()
	# Join on a night in progress goes straight in.
	var members := [
		LobbyFixture.member("a", "Ann", 1, true),
		LobbyFixture.member("b", "Bo", 2),
		LobbyFixture.member("c", "Cy", 3)
	]
	api.lobby = LobbyFixture.lobby(members, "started", 4)
	await screen.join()
	assert_array(api.joined).is_equal(["ABC234"])
	assert_int(api.tickets).is_equal(1)
	assert_int(_entered).is_equal(1)
	screen.free()


func test_a_preview_left_open_follows_the_night_it_reads() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	var screen := await _screen(api, {"preview": LobbyFixture.preview("open", null, 1)})
	assert_str(screen.status.text).is_equal("Waiting room. Ann is hosting, 1 of 4 here.")
	assert_bool(screen._preview_timer.is_stopped()).is_false()
	# The host starts, and a friend joins: the next read says so, with no press of anything.
	api.preview_answer = LobbyFixture.preview("started", 2, 2)
	await screen.refresh_preview()
	assert_str(screen.status.text).is_equal("Night in progress, round 2. 2 of 4 here.")
	assert_bool(screen.join_button.is_visible_in_tree()).is_true()
	api.preview_answer = LobbyFixture.preview("started", 2, 4, true)
	await screen.refresh_preview()
	assert_str(screen.status.text).is_equal("That night is full (4 of 4).")
	assert_bool(screen.join_button.is_visible_in_tree()).is_false()
	# A night that ended says so and offers only Back.
	api.preview_answer = TogetherApi._failed("not_found")
	await screen.refresh_preview()
	assert_str(screen.status.text).is_equal(TogetherApi.TEXTS["not_found"])
	assert_bool(screen._preview_timer.is_stopped()).is_true()
	assert_bool(screen.leave_button.is_visible_in_tree()).is_true()
	screen.free()


func test_a_waiting_room_preview_becomes_the_players_lobby_on_join() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	var screen := await _screen(api, {"preview": LobbyFixture.preview("open", null, 1)})
	assert_str(screen.status.text).is_equal("Waiting room. Ann is hosting, 1 of 4 here.")
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	await screen.join()
	assert_int(api.tickets).is_equal(0)
	assert_bool(screen.watch.running).is_true()
	assert_bool(screen.join_button.is_visible_in_tree()).is_false()
	assert_str(screen.status.text).contains("Waiting for Ann")
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  (open)", "4  (open)"])
	screen.free()


func test_a_full_night_offers_no_join() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	var screen := await _screen(api, {"preview": LobbyFixture.preview("started", 2, 4, true)})
	assert_str(screen.status.text).is_equal("That night is full (4 of 4).")
	assert_bool(screen.join_button.is_visible_in_tree()).is_false()
	assert_str(screen.leave_button.text).is_equal("Back")
	assert_bool(screen.leave_button.is_visible_in_tree()).is_true()
	screen.free()


func test_a_night_that_has_not_reported_a_round_says_only_that_it_is_on() -> void:
	for round_number: Variant in [null, 0]:
		var text := LobbyScreen.preview_text(LobbyFixture.preview("started", round_number, 1))
		assert_str(text).is_equal("Night in progress. 1 of 4 here.")
