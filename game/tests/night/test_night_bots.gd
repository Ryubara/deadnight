# The bots a night seats from the match settings (#643). Solo seats as many as the setting asks,
# beside the person; the rule that fills a room (how many, in which seats, who takes a seat) is the
# same pure function. The room itself, over a socket, is `tests/net/test_room_bots.gd`.
extends GdUnitTestSuite

const SOLO_BOTS := 3


func _night(bots: int) -> Night:
	var night := Night.new()
	night.match_settings = MatchSettings.new()
	night.match_settings.bots = bots
	add_child(night)
	await night.start(Night.Mode.MANUAL, 7)
	return night


func _bot_seats(night: Night) -> Array:
	var seats: Array = []
	for id: int in night.server.rules.players:
		if (night.server.rules.players[id] as PlayerState).bot:
			seats.append(id)
	seats.sort()
	return seats


func test_the_most_a_night_seats_is_the_setting_and_never_more_than_the_free_seats() -> void:
	assert_int(NightBots.SEATS).is_equal(NightHost.MAX_PLAYERS)
	for bots in range(0, 4):
		for people in range(1, 5):
			var seated := NightBots.target(bots, people)
			assert_int(seated).is_less_equal(bots)
			assert_int(seated + people).is_less_equal(NightHost.MAX_PLAYERS)
	assert_int(NightBots.target(3, 1)).is_equal(3)
	assert_int(NightBots.target(3, 2)).is_equal(2)
	assert_int(NightBots.target(3, 3)).is_equal(1)
	assert_int(NightBots.target(3, 4)).is_equal(0)
	assert_int(NightBots.target(0, 1)).is_equal(0)
	# A wild setting is the most there is.
	assert_int(NightBots.target(9, 1)).is_equal(MatchSettings.MAX_BOTS)
	assert_int(NightBots.target(-2, 1)).is_equal(0)


func test_solo_with_three_bots_starts_a_night_with_three_bots() -> void:
	var night := await _night(SOLO_BOTS)
	assert_int(night.server.rules.settings.bots).is_equal(SOLO_BOTS)
	assert_int(night.bots.count()).is_equal(SOLO_BOTS)
	assert_array(_bot_seats(night)).is_equal([2, 3, 4])
	assert_int(night.server.rules.players.size()).is_equal(1 + SOLO_BOTS)
	# The person keeps seat 1 and is no bot.
	assert_bool((night.server.rules.players[1] as PlayerState).bot).is_false()
	for id in [2, 3, 4]:
		assert_object(night.server.body_of(id)).is_not_null()
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_solo_with_no_bots_starts_a_night_for_one() -> void:
	var night := await _night(0)
	assert_int(night.bots.count()).is_equal(0)
	assert_int(night.server.rules.players.size()).is_equal(1)
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_the_bots_of_a_solo_night_play_and_the_client_knows_their_names() -> void:
	var night := await _night(2)
	NightFixture.run(night, 6)
	night.server.rules.apply(RulesAction.skip_break())
	NightFixture.run(night, 240)
	var sent := 0
	for bot in night.bots.host.bots:
		sent += bot.telemetry.commands
	assert_int(sent).is_greater(400)
	# The client heard each seat's name and sees all three in the frame.
	assert_str(night.state.names.get(4, "")).is_equal(NightBots.name_for(4))
	assert_str(night.state.names.get(3, "")).is_equal(NightBots.name_for(3))
	assert_int((night.state.frame["players"] as Dictionary).size()).is_equal(3)
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_every_bot_hears_the_night_the_person_hears() -> void:
	var night := await _night(3)
	NightFixture.run(night, 8)
	for bot: BotClient in night.bots.host.bots:
		assert_bool(bot.state.has_frame()).is_true()
		assert_int((bot.state.frame["players"] as Dictionary).size()).is_equal(4)
		# Each knows the seats that are bots, as the roster labels them.
		assert_bool(bot.bot_ids.has(bot.state.player_id)).is_true()
	await NightFixture.settle_bake(night)
	night.queue_free()
