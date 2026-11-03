# The room's skill and the people it names (#230), on a night with bots seated: every bot plays
# the profile of the setting, wears the name and the look of its skill's cast, and a lowered limit
# sends the bots away while the night goes on. The room over a socket is
# `tests/net/test_room_bot_slots.gd`.
extends GdUnitTestSuite


func _night(bots: int, skill: int) -> Night:
	var night := Night.new()
	night.match_settings = MatchSettings.new()
	night.match_settings.bots = bots
	night.match_settings.bot_skill = skill
	add_child(night)
	await night.start(Night.Mode.MANUAL, 7)
	return night


func _free(night: Night) -> void:
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_every_bot_plays_the_profile_of_the_rooms_skill() -> void:
	for skill in [MatchSettings.SKILL_ROOKIE, MatchSettings.SKILL_VETERAN]:
		var night := await _night(3, skill)
		var title := BotProfile.for_skill(skill).title
		assert_int(night.bots.count()).is_equal(3)
		for bot in night.bots.host.bots:
			assert_str(bot.profile.title).is_equal(title)
		await _free(night)


func test_the_bots_wear_the_names_of_their_skill_and_the_rules_know_them() -> void:
	var night := await _night(3, MatchSettings.SKILL_VETERAN)
	var named: Array[String] = []
	for id in [2, 3, 4]:
		named.append(night.bots.names()[id])
		assert_str(night.bots.names()[id]).is_equal(
			BotRoster.name_for(MatchSettings.SKILL_VETERAN, id)
		)
	assert_array(named).contains_exactly_in_any_order(["Rex", "Sarge", "Hawk"])
	await _free(night)


func test_each_bot_is_dressed_in_its_own_look_on_the_server() -> void:
	var night := await _night(3, MatchSettings.SKILL_ROOKIE)
	var keys := {}
	for id in [2, 3, 4]:
		var held: CharacterLook = night.server.looks.looks[id]
		assert_str(held.key()).is_equal(BotRoster.look_for(MatchSettings.SKILL_ROOKIE, id).key())
		keys[held.key()] = true
	assert_int(keys.size()).is_equal(3)
	# The person keeps the look of their own seat.
	assert_str((night.server.looks.looks[1] as CharacterLook).key()).is_equal(
		CharacterLook.from_preset(0).key()
	)
	await _free(night)


func test_a_lowered_limit_sends_the_bots_away_and_a_raised_one_brings_them_back() -> void:
	var night := await _night(3, MatchSettings.SKILL_REGULAR)
	assert_int(night.bots.count()).is_equal(3)
	night.bots.limit = 1
	night.link.broadcast(night.bots.fill(3, [Night.PLAYER_ID]))
	assert_int(night.bots.count()).is_equal(1)
	# The highest seats left first; the rules and the server lost their seats and bodies too.
	assert_array(night.bots.seats()).is_equal([2])
	assert_array(night.server.rules.players.keys()).contains_exactly_in_any_order([1, 2])
	assert_object(night.server.body_of(4)).is_null()
	assert_bool(night.bots.host.bot_ids.has(4)).is_false()
	night.bots.limit = 0
	night.link.broadcast(night.bots.fill(3, [Night.PLAYER_ID]))
	assert_int(night.bots.count()).is_equal(0)
	night.bots.limit = MatchSettings.MAX_BOTS
	night.link.broadcast(night.bots.fill(3, [Night.PLAYER_ID]))
	assert_int(night.bots.count()).is_equal(3)
	assert_array(night.bots.seats()).is_equal([2, 3, 4])
	await _free(night)
