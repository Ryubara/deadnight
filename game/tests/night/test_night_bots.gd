# The bots a night seats from the match settings (#643). Solo seats as many as the setting asks,
# beside the person; the rule that fills a room (how many, in which ids) is the same pure function.
# A bot holds no seat of the 8 of the people: its id starts at `NightBots.FIRST_ID` (#1179). The
# room itself, over a socket, is `tests/net/test_room_bots.gd`.
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


func test_the_cap_of_8_is_people_and_the_bots_come_on_top_with_ids_that_never_collide() -> void:
	# The limits written in two places are held equal here.
	assert_int(LookServer.SEATS).is_equal(NightHost.MAX_PLAYERS)
	assert_int(LookServer.BOT_SEATS).is_equal(MatchSettings.MAX_BOTS)
	assert_int(NightHost.MAX_SEATS).is_equal(NightHost.MAX_PLAYERS + MatchSettings.MAX_BOTS)
	# The first bot id is above every person's, and the last bot's still fits the wire's id bytes.
	assert_int(NightBots.FIRST_ID).is_greater(NightHost.MAX_PLAYERS)
	assert_int(NightBots.id_at(MatchSettings.MAX_BOTS - 1)).is_less_equal(0xFF)
	for index in MatchSettings.MAX_BOTS:
		assert_bool(NightBots.is_bot_id(NightBots.id_at(index))).is_true()
		assert_int(NightBots.number_of(NightBots.id_at(index))).is_equal(index + 1)
	for person in range(1, NightHost.MAX_PLAYERS + 1):
		assert_bool(NightBots.is_bot_id(person)).is_false()
	# The setting is the count, whatever the people: 8 of them leave no bot out.
	for bots in range(0, MatchSettings.MAX_BOTS + 1):
		assert_int(NightBots.target(bots)).is_equal(bots)
	# A wild setting is the most there is.
	assert_int(NightBots.target(99)).is_equal(MatchSettings.MAX_BOTS)
	assert_int(NightBots.target(-2)).is_equal(0)


func test_solo_with_three_bots_starts_a_night_with_three_bots() -> void:
	var night := await _night(SOLO_BOTS)
	assert_int(night.server.rules.settings.bots).is_equal(SOLO_BOTS)
	assert_int(night.bots.count()).is_equal(SOLO_BOTS)
	assert_array(_bot_seats(night)).is_equal([101, 102, 103])
	assert_int(night.server.rules.players.size()).is_equal(1 + SOLO_BOTS)
	# The person keeps id 1 and is no bot.
	assert_bool((night.server.rules.players[1] as PlayerState).bot).is_false()
	for id in [101, 102, 103]:
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
	assert_str(night.state.names.get(102, "")).is_equal(NightBots.name_for(102))
	assert_str(night.state.names.get(101, "")).is_equal(NightBots.name_for(101))
	assert_str(NightBots.name_for(102)).is_equal("Fern")
	assert_int((night.state.frame["players"] as Dictionary).size()).is_equal(3)
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_solo_with_seven_bots_seats_seven_with_names_and_spots_of_their_own() -> void:
	var night := await _night(MatchSettings.MAX_BOTS)
	assert_array(_bot_seats(night)).is_equal([101, 102, 103, 104, 105, 106, 107])
	assert_int(night.server.rules.players.size()).is_equal(1 + MatchSettings.MAX_BOTS)
	var names: Array[String] = []
	var spots: Array[Vector3] = []
	for id in range(NightBots.FIRST_ID, NightBots.id_at(MatchSettings.MAX_BOTS)):
		names.append(NightBots.name_for(id))
		var at := night.server.body_of(id).global_position
		for other in spots:
			assert_float(at.distance_to(other)).override_failure_message("seat %d" % id).is_greater(
				1.0
			)
		spots.append(at)
	for i in names.size():
		assert_int(names.find(names[i])).is_equal(i)
	NightFixture.run(night, 8)
	assert_int((night.state.frame["players"] as Dictionary).size()).is_equal(
		1 + MatchSettings.MAX_BOTS
	)
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
