# The nightly soak's gates (bots plan, phase 7): `SoakWatch.verdict` holds a night's report to the
# plan's
# numbers, and a short real night with a watch on it reports what it should.
extends GdUnitTestSuite


func _bot(overrides: Dictionary = {}) -> Dictionary:
	var bot := {
		"seat": 2,
		"profile": "Regular",
		"longest_stuck": 1.0,
		"walking_seconds": 200.0,
		"stuck_share": 0.002,
		"idle_threat_longest": 1.0,
		"idle_roam_longest": 1.0,
		"brain_disabled": false,
		"far_longest": 3.0,
		"stance_seconds": 100.0,
		"stance_share": 0.97,
	}
	bot.merge(overrides, true)
	return bot


func _night(bot: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var night := {"errors": 0, "denial_loops": 0, "bots": [bot]}
	night.merge(extra, true)
	return night


func test_a_clean_night_breaks_no_gate_under_any_order() -> void:
	for order in [BotOrders.ROAM, BotOrders.FOLLOW, BotOrders.HOLD]:
		assert_array(SoakWatch.verdict(_night(_bot()), order, true)).is_empty()


func test_each_gate_of_the_plan_is_named_when_it_breaks() -> void:
	var cases := {
		"engine errors": _night(_bot(), {"errors": 2}),
		"rejected-buy loops": _night(_bot(), {"denial_loops": 1}),
		"stuck for": _night(_bot({"longest_stuck": 10.5})),
		"with a zombie in view": _night(_bot({"idle_threat_longest": 5.5})),
		"lost its brain": _night(_bot({"brain_disabled": true})),
		"down to its last dead": _night(_bot(), {"tail_longest": 151.0, "tail_round": 7}),
	}
	for needle: String in cases:
		var broken := SoakWatch.verdict(cases[needle], BotOrders.ROAM, false)
		assert_int(broken.size()).override_failure_message(needle).is_equal(1)
		assert_str(broken[0]).contains(needle)


func test_a_round_that_stood_on_its_last_dead_for_two_minutes_is_not_a_stall() -> void:
	# A boss round with a dry stand-in for a person takes that long on its own (#950).
	var night := _night(_bot(), {"tail_longest": 126.0, "tail_round": 5})
	assert_array(SoakWatch.verdict(night, BotOrders.ROAM, true)).is_empty()


func test_a_gate_of_one_order_applies_to_that_order_only() -> void:
	var idle := _night(_bot({"idle_roam_longest": 9.0}))
	assert_array(SoakWatch.verdict(idle, BotOrders.ROAM, false)).has_size(1)
	assert_array(SoakWatch.verdict(idle, BotOrders.FOLLOW, true)).is_empty()
	var far := _night(_bot({"far_longest": 21.0}))
	assert_array(SoakWatch.verdict(far, BotOrders.FOLLOW, true)).has_size(1)
	assert_array(SoakWatch.verdict(far, BotOrders.ROAM, true)).is_empty()
	assert_array(SoakWatch.verdict(far, BotOrders.FOLLOW, false)).is_empty()
	var drifting := _night(_bot({"stance_share": 0.8}))
	assert_array(SoakWatch.verdict(drifting, BotOrders.HOLD, true)).has_size(1)
	assert_array(SoakWatch.verdict(drifting, BotOrders.FOLLOW, true)).is_empty()
	# A long trip is a report line, not a gate: a boss that stands at the spot keeps the holders off it
	# for as long as it lives, and the stampede's choke takes a minute.
	var away := _night(_bot({"trip_longest": 120.0, "away_seconds": 300.0}))
	assert_array(SoakWatch.verdict(away, BotOrders.HOLD, true)).is_empty()


func test_a_watched_night_reports_the_bots_and_the_gates_hold() -> void:
	var tuning := RulesFixture.tuning()
	var night := await NightFixture.seat(self, 2, tuning, 5, true)
	night.seat(1, BotProfile.regular(), 11)
	night.seat(2, BotProfile.rookie(), 12)
	var watch := SoakWatch.new(night, [], BotOrders.ROAM)
	night.on_event = watch.hear
	night.on_action = watch.act
	night.start_round()
	for _i in 60 * 40:
		night.tick()
		watch.tick()
	var report := watch.report()
	assert_int(report["bots"].size()).is_equal(2)
	assert_int(report["round"]).is_greater_equal(1)
	assert_float(report["game_seconds"]).is_equal_approx(40.0, 0.2)
	var shots := 0
	for bot: Dictionary in report["bots"]:
		shots += bot["shots"]
		assert_float(bot["up_seconds"] + bot["down_seconds"]).is_equal_approx(40.0, 0.2)
		assert_int(bot["shot_hits"]).is_less_equal(bot["shots"])
		assert_int(bot["pellet_hits"]).is_greater_equal(bot["shot_hits"])
	assert_int(shots).is_greater(0)
	assert_array(SoakWatch.verdict(report, BotOrders.ROAM, false)).is_empty()
	night.dispose()
