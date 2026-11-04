extends GdUnitTestSuite
## Every line of `XpRules` against a hand-built tally, the cap, the one-off awards, and that the
## running total a server adds to (`live`) is the same number the finished night settles to.

const H := XpRules.HUNDREDTHS


func _change(stat: StringName, value: int, delta: int, player: int = 1) -> Dictionary:
	return {"player_id": player, "stat": stat, "value": value, "delta": delta}


func test_a_round_reached_pays_20_and_10_past_round_20() -> void:
	assert_int(XpRules.round_xp(0)).is_equal(0)
	assert_int(XpRules.round_xp(1)).is_equal(20)
	assert_int(XpRules.round_xp(20)).is_equal(400)
	assert_int(XpRules.round_xp(21)).is_equal(410)
	assert_int(XpRules.round_xp(30)).is_equal(500)
	assert_int(XpRules.settle({ChallengeStats.ROUND: 5})).is_equal(100)


func test_a_point_is_a_hundredth_so_a_kill_raises_the_bar() -> void:
	# 1 XP per 100 points: a 60 point kill is 60 hundredths of an XP, kept as it is earned.
	assert_int(XpRules.live(_change(ChallengeStats.POINTS, 60, 60))).is_equal(60)
	assert_int(XpRules.settle({ChallengeStats.POINTS: 100})).is_equal(1)
	assert_int(XpRules.settle({ChallengeStats.POINTS: 99})).is_equal(0)
	assert_int(XpRules.settle({ChallengeStats.POINTS: 12345})).is_equal(123)


func test_the_chores_pay_a_little_and_boards_stop_at_100() -> void:
	assert_int(XpRules.settle({ChallengeStats.BOARDS: 10})).is_equal(20)
	assert_int(XpRules.settle({ChallengeStats.BOARDS: 50})).is_equal(100)
	assert_int(XpRules.settle({ChallengeStats.BOARDS: 51})).is_equal(100)
	assert_int(XpRules.settle({ChallengeStats.BOARDS: 5000})).is_equal(100)
	assert_int(XpRules.settle({ChallengeStats.DOORS: 2})).is_equal(30)
	assert_int(XpRules.settle({ChallengeStats.FUEL_CANS: 3})).is_equal(45)


func test_a_boss_pays_50_and_a_revive_40_up_to_five_a_night() -> void:
	assert_int(XpRules.settle({ChallengeStats.KILLS_BOSS: 1})).is_equal(50)
	assert_int(XpRules.settle({ChallengeStats.REVIVES: 1})).is_equal(40)
	assert_int(XpRules.settle({ChallengeStats.REVIVES: 5})).is_equal(200)
	assert_int(XpRules.settle({ChallengeStats.REVIVES: 9})).is_equal(200)


func test_kills_and_other_stats_pay_only_through_their_points() -> void:
	var stats := {ChallengeStats.KILLS: 300, ChallengeStats.KILLS_HEAD: 100}
	assert_int(XpRules.settle(stats)).is_zero()
	assert_int(XpRules.worth(&"nothing_at_all", 5)).is_zero()


func test_the_one_off_awards_and_the_challenges() -> void:
	assert_int(XpRules.settle({}, {"opening_night": true})).is_equal(50)
	assert_int(XpRules.settle({}, {"first_game_of_the_day": true})).is_equal(100)
	assert_int(XpRules.settle({}, {"challenge_xp": 75})).is_equal(75)
	var all := {"opening_night": true, "first_game_of_the_day": true, "challenge_xp": 25}
	assert_int(XpRules.settle({ChallengeStats.ROUND: 2}, all)).is_equal(40 + 50 + 100 + 25)


func test_a_night_is_capped_at_1500() -> void:
	assert_int(XpRules.settle({ChallengeStats.POINTS: 10000000})).is_equal(XpRules.NIGHT_CAP)
	assert_int(XpRules.settle({ChallengeStats.POINTS: 149900})).is_equal(1499)
	assert_int(XpRules.settle({ChallengeStats.POINTS: 150000})).is_equal(1500)
	var with_order := XpRules.settle({ChallengeStats.POINTS: 150000}, {"challenge_xp": 600})
	assert_int(with_order).is_equal(1500)
	var meter := XpMeter.new(1)
	assert_bool(meter.capped()).is_false()
	meter.observe(_change(ChallengeStats.POINTS, 200000, 200000))
	assert_int(meter.xp()).is_equal(1500)
	assert_bool(meter.capped()).is_true()
	assert_int(meter.hundredths()).is_equal(200000)


func test_the_meter_counts_only_its_own_player() -> void:
	var meter := XpMeter.new(2)
	assert_int(meter.observe(_change(ChallengeStats.POINTS, 500, 500, 1))).is_zero()
	assert_int(meter.observe(_change(ChallengeStats.POINTS, 300, 300, 2))).is_equal(300)
	assert_int(meter.hundredths()).is_equal(300)
	meter.add_xp(40)
	assert_int(meter.xp()).is_equal(43)


func test_a_best_stat_pays_for_each_new_round_only_once() -> void:
	var meter := XpMeter.new(1)
	assert_int(meter.observe(_change(ChallengeStats.ROUND, 1, 1))).is_equal(20 * H)
	assert_int(meter.observe(_change(ChallengeStats.ROUND, 4, 3))).is_equal(60 * H)
	# Crossing round 20 pays the late rate for the rounds past it.
	var crossing := meter.observe(_change(ChallengeStats.ROUND, 22, 18))
	assert_int(crossing).is_equal(16 * 20 * H + 2 * 10 * H)


func test_live_equals_settle_for_a_night_fed_change_by_change() -> void:
	var tally := {
		ChallengeStats.ROUND: 7,
		ChallengeStats.POINTS: 3417,
		ChallengeStats.BOARDS: 60,
		ChallengeStats.DOORS: 2,
		ChallengeStats.FUEL_CANS: 1,
		ChallengeStats.KILLS_BOSS: 1,
		ChallengeStats.REVIVES: 6,
	}
	var meter := XpMeter.new(1)
	var running: Dictionary = {}
	# Counted a few at a time (points seven at a time, the worst case for rounding), interleaved.
	var left := tally.duplicate()
	while not left.is_empty():
		for stat: StringName in left.keys():
			var step := mini(int(left[stat]), 7 if stat == ChallengeStats.POINTS else 1)
			running[stat] = int(running.get(stat, 0)) + step
			meter.observe(_change(stat, running[stat], step))
			left[stat] = int(left[stat]) - step
			if int(left[stat]) == 0:
				left.erase(stat)
	assert_int(running[ChallengeStats.POINTS]).is_equal(3417)
	meter.add_xp(150)
	assert_int(meter.xp()).is_equal(XpRules.settle(tally, {"challenge_xp": 150}))
	# And in hundredths, with nothing lost to a rounding on the way.
	var settled := _hundredths_of(tally) + XpRules.award_hundredths({"challenge_xp": 150})
	assert_int(meter.hundredths()).is_equal(settled)


func _hundredths_of(tally: Dictionary) -> int:
	var total := 0
	for stat: StringName in tally:
		total += XpRules.worth(stat, int(tally[stat]))
	return total
