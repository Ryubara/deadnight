extends GdUnitTestSuite
## The odd and together stats (`NightMoments`, #1074) of the stand and of the night: the round
## reached without spending, the map and the company a night ended with, a seat taken over and the
## tally that keeps only some stats.

var _b: MomentsBench


func before_test() -> void:
	_b = MomentsBench.new()


# --- The stand ---


func test_the_round_reached_without_spending_is_a_best_and_a_purchase_ends_it() -> void:
	_b.join(1)
	_b.join(2)
	_b.start(1)
	_b.finish(1, [1, 2])
	_b.buy(2, &"weapon_shotgun", 900)
	for round_number in range(2, 5):
		_b.start(round_number)
		_b.finish(round_number, [1, 2])
	assert_int(_b.n(1, ChallengeStats.ROUND_UNSPENT)).is_equal(4)
	assert_int(_b.n(2, ChallengeStats.ROUND_UNSPENT)).is_equal(1)


func test_a_player_who_came_after_the_first_round_has_not_gone_without_spending() -> void:
	_b.join(1)
	_b.start(1)
	_b.finish(1, [1])
	_b.join(2)
	_b.start(2)
	_b.start(3)
	assert_int(_b.n(1, ChallengeStats.ROUND_UNSPENT)).is_equal(3)
	assert_int(_b.n(2, ChallengeStats.ROUND_UNSPENT)).is_equal(0)


func test_a_points_loss_is_no_spending_and_a_purchase_is_what_it_cost() -> void:
	_b.join(1)
	_b.start(1)
	_b.feed(
		{
			"type": &"points_changed",
			"player_id": 1,
			"total": 100,
			"delta": -50,
			"reason": &"down_penalty"
		}
	)
	_b.feed(
		{"type": &"purchase_denied", "player_id": 1, "item_id": &"door_concession", "result": 5}
	)
	_b.start(2)
	assert_int(_b.n(1, ChallengeStats.POINTS_SPENT)).is_equal(0)
	assert_int(_b.n(1, ChallengeStats.ROUND_UNSPENT)).is_equal(2)
	_b.buy(1, &"ammo_pistol", 40)
	_b.buy(1, &"door_concession", 350)
	assert_int(_b.n(1, ChallengeStats.POINTS_SPENT)).is_equal(390)
	_b.start(3)
	assert_int(_b.n(1, ChallengeStats.ROUND_UNSPENT)).is_equal(2)


# --- The night ---


func test_a_night_is_counted_for_its_map_and_for_the_people_in_it() -> void:
	_b.join(1)
	_b.join(2)
	_b.join(3, true)
	_b.feed({"type": &"game_over", "reason": &"all_down", "round_reached": 4})
	for id in [1, 2, 3]:
		assert_int(_b.n(id, ChallengeStats.map_nights(&"drive_in"))).is_equal(1)
		assert_int(_b.n(id, ChallengeStats.map_nights(&"small_indoor"))).is_equal(0)
	assert_int(_b.n(1, ChallengeStats.NIGHTS_TOGETHER)).is_equal(1)
	assert_int(_b.n(2, ChallengeStats.NIGHTS_TOGETHER)).is_equal(1)
	# A bot is not another person.
	assert_int(_b.n(3, ChallengeStats.NIGHTS_TOGETHER)).is_equal(0)


func test_a_person_with_only_bots_beside_them_has_not_played_together() -> void:
	_b.join(1)
	_b.join(2, true)
	_b.join(3, true)
	_b.feed({"type": &"game_over", "reason": &"all_down", "round_reached": 2})
	assert_int(_b.n(1, ChallengeStats.NIGHTS_TOGETHER)).is_equal(0)


func test_the_map_is_the_one_the_settings_name_and_a_night_that_left_before_the_end_has_none(
) -> void:
	_b.tally = NightTally.new()
	_b.join(1)
	var settings := MatchSettings.new()
	settings.map = "small_indoor"
	_b.feed({"type": &"settings_changed", "settings": settings.to_dict()})
	_b.feed({"type": &"game_over", "reason": &"no_players", "round_reached": 1})
	assert_int(_b.n(1, ChallengeStats.map_nights(&"small_indoor"))).is_equal(1)
	assert_int(_b.n(1, ChallengeStats.map_nights(&"drive_in"))).is_equal(0)


func test_a_seat_taken_over_starts_with_nothing_and_a_new_night_forgets_the_old_one() -> void:
	_b.join(1)
	_b.start(1)
	_b.shot(1, &"pistol")
	_b.kill(1)
	_b.tally.forget(1)
	# Whoever sat down was not there for the round that was under way.
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_UNFIRED)).is_equal(0)
	assert_int(_b.n(1, ChallengeStats.ROUNDS_NO_KILLS)).is_equal(0)
	_b.start(2)
	_b.finish(2, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_UNFIRED)).is_equal(1)
	assert_int(_b.n(1, ChallengeStats.ROUNDS_NO_KILLS)).is_equal(1)
	_b.tally.reset()
	_b.join(1)
	_b.start(1)
	_b.shot(1, &"pistol")
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_UNFIRED)).is_equal(0)


func test_a_tally_that_keeps_only_some_stats_does_none_of_this() -> void:
	var kept := NightTally.new()
	kept.keep_only([ChallengeStats.ROUNDS_UNFIRED, ChallengeStats.ROUNDS])
	kept.observe({"type": &"player_added", "player_id": 1, "bot": false})
	kept.observe({"type": &"round_started", "round": 1})
	kept.observe({"type": &"round_ended", "round": 1, "standing": [1]})
	# What the moments would have counted is not even worked out, kept or not.
	assert_int(kept.count(1, ChallengeStats.ROUNDS_UNFIRED)).is_equal(0)
	assert_int(kept.count(1, ChallengeStats.ROUNDS)).is_equal(1)


func test_the_tick_of_a_frame_is_a_server_step() -> void:
	assert_float(NightMoments.TICK_SECONDS).is_equal(Night.STEP)


func test_every_event_it_listens_to_reaches_it_from_the_server() -> void:
	for type in NightMoments.LISTENS:
		(
			assert_bool(ChallengeAward.HEARD.has(type))
			. override_failure_message("the server's award does not pass on %s" % type)
			. is_true()
		)
