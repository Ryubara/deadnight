extends GdUnitTestSuite
## The XP the game server (and a solo night's rules) awards a kill at a time: each kill moves only
## its killer's tally, the tally is the settled `XpRules` total, a tick tells a seat once however
## many kills it made, a level crossed is told once with what it gives, a seat with no account earns
## nothing, a late joiner is paid for the rounds it plays, and a report holds what is new.

const FUEL: Array[StringName] = [&"fuel_can"]

var _rules: GameRules
var _award: XpAward
## Everything `end_tick` has said, in order.
var _told: Array[Dictionary] = []


func before_test() -> void:
	_told = []


## A night of `players` (ids 1..n) with an award hearing the rules' events as the server does.
func _night(players: int, accounts: Array[int] = []) -> void:
	_rules = RulesFixture.make_rules(players)
	_award = XpAward.new(FUEL, ChallengeClock.fixed(20401.0 * ChallengeClock.DAY_SECONDS + 60.0))
	_rules.event_emitted.connect(_award.observe)
	for id in accounts:
		_award.register(id, "user-%d" % id, 0, 0)


func _tick() -> Array[Dictionary]:
	var said := _award.end_tick()
	_told.append_array(said)
	return said


func _of(type: StringName, events: Array[Dictionary] = _told) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in events:
		if event["type"] == type:
			found.append(event)
	return found


## Round one played out with `killer` killing every zombie by a head shot. Returns every event the
## award said, a tick at a time.
func _play_round_one(killer: int) -> void:
	_rules.apply(RulesAction.start())
	_rules.apply(RulesAction.skip_break())
	for _i in 4000:
		_rules.apply(RulesAction.tick(RulesFixture.STEP))
		for zombie_id in _rules.zombie_ids():
			RulesFixture.kill(_rules, killer, zombie_id, RulesAction.ZONE_HEAD)
		_tick()
		if _rules.phase == GameRules.Phase.BREAK:
			return


func test_a_kill_moves_exactly_its_killers_tally() -> void:
	_night(2, [1, 2])
	RulesFixture.into_round_one(_rules)
	_tick()
	RulesFixture.run(_rules, 2.0)
	var before_two := _award.night_xp(2)
	var total_two := _award.total_of(2)
	var ids := _rules.zombie_ids()
	assert_int(ids.size()).is_greater(0)
	RulesFixture.kill(_rules, 1, ids[0], RulesAction.ZONE_HEAD)
	var said := _tick()
	# One event, for the killer, with the kill's points in it.
	var gained := _of(XpAward.GAINED, said)
	assert_int(gained.size()).is_equal(1)
	assert_int(gained[0]["player_id"]).is_equal(1)
	assert_int(gained[0]["hundredths"]).is_greater(0)
	assert_bool((gained[0]["sources"] as Dictionary).has(ChallengeStats.POINTS)).is_true()
	assert_int(_award.night_xp(2)).is_equal(before_two)
	assert_int(_award.total_of(2)).is_equal(total_two)
	assert_int(_award.tally.count(2, ChallengeStats.POINTS)).is_equal(0)
	assert_int(_award.tally.count(1, ChallengeStats.POINTS)).is_greater(0)


func test_the_running_tally_equals_the_settled_total_at_the_rounds_end() -> void:
	_night(1, [1])
	# The same events counted the other way: every stat, one total at the end.
	var reference := NightTally.new(FUEL)
	reference.set_present(1)
	_rules.event_emitted.connect(func(event: Dictionary) -> void: reference.observe(event))
	_play_round_one(1)
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	var settled := XpRules.settle(XpRules.stats_of(reference, 1))
	assert_int(settled).is_greater_equal(XpRules.ROUND_XP)
	assert_int(_award.night_xp(1)).is_equal(settled)
	# What the events told, added up, is the tally to the hundredth.
	var told := 0
	for gained in _of(XpAward.GAINED):
		told += int(gained["hundredths"])
	assert_int(told / XpRules.HUNDREDTHS).is_equal(settled)
	assert_int(_of(XpAward.GAINED).back()["xp"]).is_equal(settled)


func test_a_seat_is_told_once_a_tick_however_many_kills() -> void:
	_night(2, [1, 2])
	RulesFixture.into_round_one(_rules)
	_tick()
	RulesFixture.run(_rules, 12.0)
	var ids := _rules.zombie_ids()
	assert_int(ids.size()).is_greater_equal(3)
	for zombie_id in ids:
		RulesFixture.kill(_rules, 1, zombie_id, RulesAction.ZONE_BODY)
	var said := _tick()
	assert_int(_of(XpAward.GAINED, said).size()).is_equal(1)
	# The tick after, with nothing new, says nothing.
	assert_int(_tick().size()).is_equal(0)
	# Both seats in one tick: one event each.
	_rules.apply(RulesAction.grant_points(1, 50))
	_rules.apply(RulesAction.grant_points(2, 50))
	assert_int(_of(XpAward.GAINED, _tick()).size()).is_equal(2)


func test_a_window_tells_a_seat_less_often_but_loses_nothing() -> void:
	_night(1, [1])
	_award.window_ticks = 15
	RulesFixture.into_round_one(_rules)
	var events := 0
	var told := 0
	for _i in 60:
		_rules.apply(RulesAction.grant_points(1, 100))
		for gained in _of(XpAward.GAINED, _award.end_tick()):
			events += 1
			told += int(gained["hundredths"])
	# One a quarter second at 60 ticks a second, where the default would have said 60.
	assert_int(events).is_equal(4)
	for gained in _of(XpAward.GAINED, _award.end_tick(true)):
		told += int(gained["hundredths"])
	assert_int(_award.tally.count(1, ChallengeStats.POINTS)).is_equal(6000)
	assert_int(told).is_equal(_award.night_xp(1) * XpRules.HUNDREDTHS)


func test_a_level_crossed_is_told_once_with_what_it_gives() -> void:
	_night(1)
	# Level 2 is 85 XP: an account at 82 crosses it with the 20 XP of round one.
	_award.register(1, "ann", 82, 0)
	RulesFixture.into_round_one(_rules)
	var said := _tick()
	assert_int(_of(XpAward.LEVEL_UP, said).size()).is_equal(1)
	var up := _of(XpAward.LEVEL_UP, said)[0]
	assert_int(up["level"]).is_equal(2)
	assert_int(up["total"]).is_equal(102)
	# Level 2 gives the plate's cards and an emblem whose art is not drawn: no unlock is told.
	assert_int(_of(XpAward.UNLOCK, said).size()).is_equal(0)
	assert_int(_of(XpAward.TIER_UP, said).size()).is_equal(0)
	# Nothing more is said while the level holds.
	_rules.apply(RulesAction.grant_points(1, 100))
	assert_int(_of(XpAward.LEVEL_UP, _tick()).size()).is_equal(0)
	assert_int(_award.levels()[1]).is_equal(2)


func test_an_unlock_is_told_for_each_item_the_level_gives_and_a_tier_opens_with_its_card() -> void:
	_night(1)
	# Level 5 begins at 340 XP, level 6 at 425; level 6 gives the usher's cap and opens the second
	# tier.
	_award.register(1, "ann", 424, 0)
	_award.add_xp(1, 1, &"test")
	var said := _tick()
	assert_int(_of(XpAward.LEVEL_UP, said)[0]["level"]).is_equal(6)
	var tier := _of(XpAward.TIER_UP, said)
	assert_int(tier.size()).is_equal(1)
	assert_str(tier[0]["tier_name"]).is_equal("Cartoon")
	var unlocks := _of(XpAward.UNLOCK, said)
	assert_int(unlocks.size()).is_equal(1)
	assert_str(unlocks[0]["slot"]).is_equal("headwear")
	assert_str(unlocks[0]["item"]).is_equal("ushers_cap")
	# The order is the card, the tier, then the items.
	var types: Array = said.map(func(event: Dictionary) -> StringName: return event["type"])
	assert_array(types).is_equal(
		[XpAward.GAINED, XpAward.LEVEL_UP, XpAward.TIER_UP, XpAward.UNLOCK]
	)


func test_several_levels_in_one_tick_are_each_told_in_order() -> void:
	_night(1)
	_award.register(1, "ann", 0, 0)
	_award.add_xp(1, 400, &"test")
	var said := _tick()
	var levels: Array = _of(XpAward.LEVEL_UP, said).map(
		func(event: Dictionary) -> int: return event["level"]
	)
	assert_array(levels).is_equal([2, 3, 4, 5])
	# The items of levels 3, 4 and 5 that have art: Cherry, Rolled sleeves and Tan.
	var items: Array = _of(XpAward.UNLOCK, said).map(
		func(event: Dictionary) -> StringName: return event["item"]
	)
	assert_array(items).is_equal([&"cherry", &"rolled_sleeves", &"tan"])


func test_a_seat_with_no_account_earns_nothing_and_a_bot_has_no_level() -> void:
	_night(3, [1])
	RulesFixture.into_round_one(_rules)
	_tick()
	RulesFixture.run(_rules, 12.0)
	var ids := _rules.zombie_ids()
	assert_int(ids.size()).is_greater_equal(2)
	RulesFixture.kill(_rules, 2, ids[0], RulesAction.ZONE_HEAD)
	RulesFixture.kill(_rules, 3, ids[1], RulesAction.ZONE_HEAD)
	assert_int(_tick().size()).is_equal(0)
	assert_int(_award.night_xp(2)).is_equal(0)
	assert_dict(_award.levels()).is_equal({1: 1})
	# A user that is empty is no account.
	_award.register(2, "", 100, 0)
	assert_bool(_award.has_seat(2)).is_false()
	# A night nobody holds an account in costs nothing and says nothing.
	var alone := XpAward.new(FUEL)
	alone.observe({"type": &"points_changed", "player_id": 1, "delta": 10, "reason": &"x"})
	assert_array(alone.end_tick()).is_empty()
	assert_bool(alone.has_accounts()).is_false()


func test_the_kill_switch_pays_nothing() -> void:
	_night(1)
	_award.enabled = false
	_award.register(1, "ann", 0, 0)
	assert_bool(_award.has_seat(1)).is_false()


func test_a_late_joiner_is_paid_for_the_rounds_it_plays_not_the_ones_it_missed() -> void:
	_award = XpAward.new(FUEL)
	_award.register(1, "ann", 0, 0)
	_award.observe({"type": &"round_started", "round": 1})
	_award.observe({"type": &"round_started", "round": 2})
	# Bo sits down in round 2 and is paid from round 3 on.
	_award.register(2, "bo", 0, 2)
	_award.observe({"type": &"round_started", "round": 3})
	assert_int(_award.night_xp(2)).is_equal(XpRules.ROUND_XP)
	_award.observe({"type": &"round_started", "round": 4})
	assert_int(_award.night_xp(2)).is_equal(2 * XpRules.ROUND_XP)
	assert_int(_award.night_xp(1)).is_equal(4 * XpRules.ROUND_XP)


func test_a_person_who_takes_a_seat_does_not_inherit_what_was_counted_in_it() -> void:
	_night(1)
	# The bot in seat 1 has been mending boards.
	for _i in 10:
		_award.tally.observe({"type": &"board_repaired", "player_id": 1})
	_award.register(1, "ann", 0, 0)
	assert_int(_award.tally.count(1, ChallengeStats.BOARDS)).is_equal(0)
	_award.observe({"type": &"board_repaired", "player_id": 1})
	assert_int(_award.night_xp(1)).is_equal(XpRules.BOARD_XP)


func test_the_nights_cap_holds() -> void:
	_night(1, [1])
	_award.add_xp(1, XpRules.NIGHT_CAP + 500, &"test")
	_tick()
	assert_int(_award.night_xp(1)).is_equal(XpRules.NIGHT_CAP)
	assert_int(_award.total_of(1)).is_equal(XpRules.NIGHT_CAP)


func test_a_report_holds_what_is_new_once_and_a_leaver_is_in_the_next() -> void:
	_night(2, [1, 2])
	_play_round_one(1)
	var first := _award.take_report()
	# Both were there for the round; only the killer has the kills' points.
	assert_int(first.size()).is_equal(2)
	var killer := first[0]
	assert_str(killer["user"]).is_equal("user-1")
	assert_int(killer["xp"]).is_equal(_award.night_xp(1))
	assert_int(killer["night_stats"][ChallengeStats.ROUND]).is_equal(1)
	assert_int(first[1]["xp"]).is_equal(XpRules.ROUND_XP)
	assert_array(_award.take_report()).is_empty()
	# More is earned, and the seat leaves before the round ends: it is in the next report, once.
	_rules.apply(RulesAction.grant_points(1, 1000))
	_tick()
	var earned := _award.night_xp(1)
	_award.release(1)
	var next := _award.take_report()
	assert_int(next.size()).is_equal(1)
	assert_int(next[0]["xp"]).is_equal(earned - int(killer["xp"]))
	assert_array(_award.take_report()).is_empty()
	# The night's own report lists every seat left, even one with nothing new.
	var final := _award.take_report(true)
	assert_int(final.size()).is_equal(1)
	assert_int(final[0]["xp"]).is_equal(0)


func test_a_report_claims_the_one_offs_for_a_seat_that_finished_a_round_and_pays_none_itself(
) -> void:
	_night(2)
	_award.register(1, "ann", 0, 0)
	_award.register(2, "bo", 0, 0)
	_play_round_one(1)
	var report := _award.take_report()
	# The backend pays the opening night and the day's first game from the profile it holds: the
	# award adds none of it to the XP, and says only that the seat finished a round, and the day.
	for entry in report:
		assert_bool(entry["finished_round"]).is_true()
		assert_int(entry["day"]).is_equal(20401)
	var is_ann := func(entry: Dictionary) -> bool: return entry["user"] == "ann"
	var ann: Dictionary = report.filter(is_ann)[0]
	assert_int(ann["xp"]).is_equal(XpRules.settle(XpRules.stats_of(_award.tally, 1)))
	# A seat that sat down and left before any round ended has claimed nothing.
	_award.register(3, "cy", 0, 1)
	_award.add_xp(3, 5, &"test")
	var is_cy := func(entry: Dictionary) -> bool: return entry["user"] == "cy"
	var cy: Dictionary = _award.take_report().filter(is_cy)[0]
	assert_bool(cy["finished_round"]).is_false()
	assert_int(cy["xp"]).is_equal(5)


func test_the_xp_is_the_settled_total_whatever_the_account_is_owed() -> void:
	_night(1)
	_award.register(1, "ann", 0, 0)
	_play_round_one(1)
	var settled := XpRules.settle(XpRules.stats_of(_award.tally, 1))
	assert_int(_award.night_xp(1)).is_equal(settled)
