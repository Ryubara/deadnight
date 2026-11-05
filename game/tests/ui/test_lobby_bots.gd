# The Bots setting in the lobby (#643): the host's panel has the row, the seat list shows the bots a
# night will seat in rows after the people's seats (a bot holds no seat, #1179), a guest reads the
# host's count, and the count rides the host's changes to the backend.
extends GdUnitTestSuite


func before_test() -> void:
	LobbyScreen.opener = func() -> void: pass


func after_test() -> void:
	LobbyScreen.opener = Callable()


func _screen(api: LobbyFixture.FakeApi) -> LobbyScreen:
	await RouterFixture.clear(get_tree())
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"api": api, "lobby": api.lobby}
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	return screen


func _hosted(members: int) -> LobbyFixture.FakeApi:
	var api := LobbyFixture.FakeApi.new(self)
	var people: Array = [LobbyFixture.member("a", "Ann", 1, true)]
	for i in range(1, members):
		people.append(LobbyFixture.member("p%d" % i, ["Bo", "Cy", "Di"][i - 1], i + 1))
	api.lobby = LobbyFixture.lobby(people)
	return api


func test_the_hosts_panel_has_a_bots_row_from_zero_to_seven() -> void:
	var screen := await _screen(_hosted(1))
	assert_object(screen.rules.row_for("bots")).is_not_null()
	assert_array(Array(screen.rules.bots_selector.options)).is_equal(
		["0", "1", "2", "3", "4", "5", "6", "7"]
	)
	assert_int(screen.rules.settings().bots).is_equal(0)
	assert_bool(screen.rules.bots_selector.focus_mode == Control.FOCUS_ALL).is_true()
	screen.free()


func test_the_host_asks_for_bots_and_the_lobby_lists_them_after_the_seats() -> void:
	var api := _hosted(1)
	var screen := await _screen(api)
	assert_array(screen.seat_texts()).is_equal(
		["1  Ann  HOST", "2  (open)", "3  (open)", "4  (open)"]
	)
	screen.rules.bots_selector.select(2, true)
	assert_int(screen.bots_shown()).is_equal(2)
	# The seats stay the people's, open ones included; the bots follow, with the ids the server gives.
	(
		assert_array(screen.seat_texts())
		. is_equal(
			[
				"1  Ann  HOST",
				"2  (open)",
				"3  (open)",
				"4  (open)",
				"B1  %s  BOT" % NightBots.name_for(NightBots.id_at(0)),
				"B2  %s  BOT" % NightBots.name_for(NightBots.id_at(1)),
			]
		)
	)
	# The change goes to the backend with the count.
	await screen.send_rules()
	assert_int(api.rules_sent.size()).is_equal(1)
	assert_int(api.rules_sent[0].bots).is_equal(2)
	screen.free()


func test_bots_take_no_seat_from_the_people_however_many_are_there() -> void:
	var api := _hosted(3)
	var screen := await _screen(api)
	screen.rules.bots_selector.select(3, true)
	assert_int(screen.bots_shown()).is_equal(3)
	(
		assert_array(screen.seat_texts())
		. is_equal(
			[
				"1  Ann  HOST",
				"2  Bo",
				"3  Cy",
				"4  (open)",
				"B1  %s  BOT" % NightBots.name_for(NightBots.id_at(0)),
				"B2  %s  BOT" % NightBots.name_for(NightBots.id_at(1)),
				"B3  %s  BOT" % NightBots.name_for(NightBots.id_at(2)),
			]
		)
	)
	screen.free()
	# A full room of people still lists every bot the host set.
	var crowded := await _screen(_hosted(4))
	crowded.rules.bots_selector.select(3, true)
	assert_int(crowded.bots_shown()).is_equal(3)
	assert_int(crowded.seat_texts().size()).is_equal(4 + 3)
	crowded.free()


func test_a_guest_reads_the_hosts_bot_count_and_cannot_move_it() -> void:
	var api := _hosted(2)
	api.me = "p1"
	var screen := await _screen(api)
	assert_bool(screen.rules.bots_selector.focus_mode == Control.FOCUS_NONE).is_true()
	api.refreshed = api.lobby.duplicate()
	api.refreshed["settings"] = {
		"count_multiplier": 1.0, "max_alive": 0, "break_seconds": 0.0, "bots": 3
	}
	await screen.watch.poll()
	assert_int(screen.rules.settings().bots).is_equal(3)
	assert_str(screen.rules_text()).ends_with("|3 bots")
	assert_int(screen.bots_shown()).is_equal(3)
	(
		assert_array(screen.seat_texts())
		. is_equal(
			[
				"1  Ann  HOST",
				"2  Bo",
				"3  (open)",
				"4  (open)",
				"B1  %s  BOT" % NightBots.name_for(NightBots.id_at(0)),
				"B2  %s  BOT" % NightBots.name_for(NightBots.id_at(1)),
				"B3  %s  BOT" % NightBots.name_for(NightBots.id_at(2)),
			]
		)
	)
	screen.free()
