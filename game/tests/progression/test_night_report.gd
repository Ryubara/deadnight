extends GdUnitTestSuite
## The night report's numbers (`NightReport`, `ReportTracker`): the lines are the night's XP cut
## into whole XP and add up to the total exactly, whatever the fractions and the cap; the total is
## the settled `XpRules` number and the one the game server's `XpAward` tells; and a client reads
## the same for a solo night, a night of four, a Guest account (an account like any other) and a
## night with no account at all, which shows what it would have paid and is not kept.

const FUEL: Array[StringName] = [&"fuel_can"]
const SEATS := 4
const CHALLENGE_XP := 25

var _rules: GameRules
var _award: XpAward
var _states: Dictionary[int, ClientState] = {}
var _trackers: Dictionary[int, ReportTracker] = {}
var _reference: NightTally
var _heard: Array[Dictionary] = []


func _sum(lines: Array) -> int:
	var total := 0
	for line: Dictionary in lines:
		total += int(line["xp"])
	return total


func _xp_of(line_id: StringName, lines: Array) -> int:
	for line: Dictionary in lines:
		if line["id"] == line_id:
			return int(line["xp"])
	return 0


# --- The lines ---------------------------------------------------------------------------------


func test_lines_of_a_known_night_are_the_whole_xp_each_line_paid() -> void:
	var sources := {
		ChallengeStats.ROUND: 4 * 20 * 100,
		ChallengeStats.POINTS: 1230,
		ChallengeStats.BOARDS: 6 * 2 * 100,
		ChallengeStats.DOORS: 15 * 100,
		ChallengeStats.REVIVES: 40 * 100,
		XpAward.OPENING_NIGHT: 5000,
		XpAward.FIRST_GAME: 10000,
	}
	var xp := XpRules.to_xp(8000 + 1230 + 1200 + 1500 + 4000 + 5000 + 10000)
	var lines := NightReport.lines(sources, xp)
	assert_int(_sum(lines)).is_equal(xp)
	assert_int(_xp_of(&"rounds", lines)).is_equal(80)
	# 12.30 XP of points: the fraction is kept by whoever lost most to the rounding.
	assert_int(_xp_of(&"points", lines)).is_between(12, 13)
	assert_int(_xp_of(&"upkeep", lines)).is_equal(27)
	assert_int(_xp_of(&"rescues", lines)).is_equal(40)
	assert_int(_xp_of(&"opening_night", lines)).is_equal(50)
	assert_int(_xp_of(&"first_game", lines)).is_equal(100)
	# Only what paid is a line, in the order of the table.
	var ids: Array[StringName] = []
	for line: Dictionary in lines:
		ids.append(line["id"])
	assert_array(ids).is_equal(
		[&"rounds", &"points", &"upkeep", &"rescues", &"opening_night", &"first_game"]
	)


func test_two_halves_that_make_a_whole_xp_give_it_to_the_first_line_of_the_table() -> void:
	var lines := NightReport.lines({ChallengeStats.POINTS: 60, ChallengeStats.BOARDS: 60}, 1)
	assert_array(lines).has_size(1)
	assert_str(str(lines[0]["id"])).is_equal("points")
	assert_int(_sum(lines)).is_equal(1)


func test_lines_add_up_to_the_total_for_any_split_of_any_night() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1068
	var stats := NightReport.LINES.map(func(line: Dictionary) -> Array: return line["sources"])
	for night in 400:
		var sources := {}
		for group: Array in stats:
			for source: StringName in group:
				if rng.randf() < 0.6:
					sources[source] = rng.randi_range(0, 60000)
		var hundredths := 0
		for source: StringName in sources:
			hundredths += int(sources[source])
		var xp := XpRules.to_xp(hundredths)
		var lines := NightReport.lines(sources, xp)
		assert_int(_sum(lines)).is_equal(xp)
		for line: Dictionary in lines:
			if line["id"] != NightReport.CAP["id"]:
				assert_int(line["xp"]).is_greater(0)


func test_a_night_over_the_cap_shows_what_the_cap_took_as_a_last_line() -> void:
	var sources := {ChallengeStats.ROUND: 900 * 100, XpAward.CHALLENGE: 800 * 100}
	var xp := XpRules.to_xp(1700 * 100)
	assert_int(xp).is_equal(XpRules.NIGHT_CAP)
	var lines := NightReport.lines(sources, xp)
	assert_int(_sum(lines)).is_equal(XpRules.NIGHT_CAP)
	assert_str(str(lines.back()["id"])).is_equal("cap")
	assert_int(lines.back()["xp"]).is_equal(-200)


func test_xp_no_source_shows_is_other_so_the_lines_still_add_up() -> void:
	# A client that joined late never heard what paid the first 30 XP.
	var lines := NightReport.lines({ChallengeStats.ROUND: 2000}, 50)
	assert_int(_sum(lines)).is_equal(50)
	assert_int(_xp_of(&"other", lines)).is_equal(30)
	var odd := NightReport.lines({&"something_new": 700}, 7)
	assert_int(_xp_of(&"other", odd)).is_equal(7)


# --- The level bar -----------------------------------------------------------------------------


func test_a_night_that_crosses_levels_lists_them_and_what_they_give() -> void:
	# Level 2 begins at 85 XP, level 5 at 340: an account at 80 that earns 270 ends at 350.
	var model := NightReport.compose({ChallengeStats.ROUND: 27000}, 270, 80, true)
	assert_bool(model["kept"]).is_true()
	assert_int(model["level_from"]).is_equal(1)
	assert_int(model["level_to"]).is_equal(5)
	assert_array(model["crossed"]).is_equal([2, 3, 4, 5])
	var items: Array[StringName] = []
	for row: Dictionary in model["unlocked"]:
		items.append(row["item"])
	assert_array(items).is_equal(
		[
			&"calling_cards",
			&"admit_one",
			&"cherry",
			&"rolled_sleeves",
			&"tan",
			&"doors_open",
			&"doors_open"
		]
	)
	assert_float(model["fraction_from"]).is_equal(0.0)
	assert_int(model["in_level"]).is_equal(10)
	# Level 5 is the last of the first tier: 85 XP to leave it.
	assert_float(model["fraction_to"]).is_equal_approx(10.0 / 85.0, 0.0001)
	assert_int(model["to_leave"]).is_equal(85)
	assert_int(model["to_next"]).is_equal(75)
	assert_int(model["next"]["level"]).is_equal(6)
	assert_str(model["next"]["label"]).is_equal("ushers cap")


func test_a_night_inside_a_level_keeps_where_it_began_on_the_bar() -> void:
	var model := NightReport.compose({ChallengeStats.ROUND: 2000}, 20, 30, true)
	assert_int(model["level_from"]).is_equal(1)
	assert_int(model["level_to"]).is_equal(1)
	assert_array(model["crossed"]).is_empty()
	assert_array(model["unlocked"]).is_empty()
	assert_float(model["fraction_from"]).is_equal_approx(30.0 / 85.0, 0.0001)
	assert_float(model["fraction_to"]).is_equal_approx(50.0 / 85.0, 0.0001)
	# Level 2 opens the calling cards, so that is what the bar points at.
	assert_int(model["next"]["level"]).is_equal(2)
	assert_str(model["next"]["label"]).is_equal("calling cards")


func test_the_top_of_the_ladder_has_a_full_bar_and_nothing_next() -> void:
	var model := NightReport.compose(
		{ChallengeStats.ROUND: 2000}, 20, LevelCurve.total() + 500, true
	)
	assert_int(model["level_to"]).is_equal(LevelCurve.MAX_LEVEL)
	assert_int(model["to_leave"]).is_zero()
	assert_float(model["fraction_to"]).is_equal(1.0)
	assert_dict(model["next"]).is_empty()


func test_a_night_nobody_keeps_has_lines_and_no_bar() -> void:
	var model := NightReport.compose({ChallengeStats.ROUND: 2000}, 20, 0, false)
	assert_bool(model["kept"]).is_false()
	assert_int(_sum(model["lines"])).is_equal(20)
	assert_bool(model.has("level_to")).is_false()


# --- What a client reads from the night --------------------------------------------------------


## A night of `SEATS` seats with an award hearing the rules as the game server does, and a client
## state with a report tracker for each seat that hears what every client would hear.
func _night(accounts: Array[int], seats: int = SEATS) -> void:
	_rules = RulesFixture.make_rules(seats)
	_award = XpAward.new(FUEL, ChallengeClock.fixed(20401.0 * ChallengeClock.DAY_SECONDS + 60.0))
	_reference = NightTally.new(FUEL)
	_heard = []
	_rules.event_emitted.connect(
		func(event: Dictionary) -> void:
			_heard.append(event)
			_award.observe(event)
			_reference.observe(event)
	)
	for id in range(1, seats + 1):
		_reference.set_present(id)
		if accounts.has(id):
			_award.register(id, "user-%d" % id, 80 * id, 0)
		var state := ClientState.new()
		state.player_id = id
		state.load_levels({"levels": _award.levels(), "account_xp": _award.total_of(id)})
		var tracker := ReportTracker.new()
		tracker.attach(state, FUEL)
		_states[id] = state
		_trackers[id] = tracker


## Every client hears the rules' events, then the award's for the tick.
func _tick() -> void:
	var told: Array[Dictionary] = _heard.duplicate()
	told.append_array(_award.end_tick())
	_heard = []
	for id in _states:
		_states[id].apply_events(told)


func _play_round_one() -> void:
	RulesFixture.into_round_one(_rules)
	_tick()
	for _i in 4000:
		_rules.apply(RulesAction.tick(RulesFixture.STEP))
		for zombie_id in _rules.zombie_ids():
			# Seat 1 and seat 2 share the kills, seat 3 is paid points and seat 4 does nothing.
			var killer := 1 if zombie_id % 2 == 0 else 2
			RulesFixture.kill(_rules, killer, zombie_id, RulesAction.ZONE_HEAD)
		_tick()
		if _rules.phase == GameRules.Phase.BREAK:
			break
	_rules.apply(RulesAction.grant_points(3, 750))
	_award.add_xp(1, XpRules.OPENING_NIGHT_XP, XpAward.OPENING_NIGHT)
	_award.add_xp(1, CHALLENGE_XP, XpAward.CHALLENGE)
	_tick()


func test_every_seat_of_a_night_of_four_reads_the_servers_tally() -> void:
	_night([1, 2, 3, 4])
	_play_round_one()
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	for id in range(1, SEATS + 1):
		var model := _trackers[id].model()
		assert_bool(model["kept"]).is_true()
		var server := _award.night_xp(id)
		assert_int(server).is_greater_equal(XpRules.ROUND_XP)
		# The report is the server's number, and the settled number, and its lines add up to it.
		assert_int(model["xp"]).is_equal(server)
		assert_int(_sum(model["lines"])).is_equal(server)
		var awards := {}
		if id == 1:
			awards = {"opening_night": true, "challenge_xp": CHALLENGE_XP}
		assert_int(XpRules.settle(XpRules.stats_of(_reference, id), awards)).is_equal(server)
		# The bar ends where the account does.
		assert_int(model["in_level"] + LevelCurve.xp_for(model["level_to"])).is_equal(
			_award.total_of(id)
		)
		assert_int(model["level_to"]).is_equal(LevelCurve.level_of(_award.total_of(id)))
	# Seat 1 has the one-off lines and the challenge; seat 4 only the round it stood in.
	var first: Array = _trackers[1].model()["lines"]
	assert_int(_xp_of(&"opening_night", first)).is_equal(XpRules.OPENING_NIGHT_XP)
	assert_int(_xp_of(&"challenges", first)).is_equal(CHALLENGE_XP)
	assert_int(_xp_of(&"rounds", first)).is_equal(XpRules.ROUND_XP)
	assert_int(_xp_of(&"points", first)).is_greater(0)
	var last: Array = _trackers[4].model()["lines"]
	assert_array(last).has_size(1)
	assert_int(_xp_of(&"rounds", last)).is_equal(XpRules.ROUND_XP)
	assert_int(_xp_of(&"points", _trackers[3].model()["lines"])).is_greater_equal(7)


func test_a_solo_night_with_an_account_reads_the_local_rules_tally() -> void:
	_night([1], 1)
	_play_round_one()
	var model := _trackers[1].model()
	assert_bool(model["kept"]).is_true()
	assert_int(model["xp"]).is_equal(_award.night_xp(1))
	assert_int(_sum(model["lines"])).is_equal(model["xp"])
	assert_int(model["level_from"]).is_equal(LevelCurve.level_of(80))


func test_a_night_with_no_account_would_have_paid_what_the_rules_say_and_is_not_kept() -> void:
	_night([], 2)
	_play_round_one()
	assert_int(_award.night_xp(1)).is_zero()
	for id in [1, 2]:
		var tracker := _trackers[id]
		var model := tracker.model()
		assert_bool(model["kept"]).is_false()
		assert_bool(tracker.is_kept()).is_false()
		var settled := XpRules.settle(XpRules.stats_of(_reference, id))
		assert_int(settled).is_greater_equal(XpRules.ROUND_XP)
		assert_int(model["xp"]).is_equal(settled)
		assert_int(_sum(model["lines"])).is_equal(settled)
		assert_bool(model.has("level_to")).is_false()


func test_a_seat_a_bot_holds_beside_accounts_is_not_kept() -> void:
	_night([1, 2])
	_play_round_one()
	assert_bool(_trackers[3].model()["kept"]).is_false()
	assert_bool(_trackers[1].model()["kept"]).is_true()
	# What seat 3 would have paid is not what any account was told.
	assert_int(_award.night_xp(3)).is_zero()


func test_a_client_that_counts_nothing_for_a_kept_seat_adds_no_per_kill_work() -> void:
	_night([1, 2, 3, 4])
	RulesFixture.into_round_one(_rules)
	_tick()
	var tally: NightTally = _trackers[1]._tally
	assert_int(tally.count(1, ChallengeStats.ROUND)).is_zero()
	for _i in 600:
		_rules.apply(RulesAction.tick(RulesFixture.STEP))
		for zombie_id in _rules.zombie_ids():
			RulesFixture.kill(_rules, 1, zombie_id, RulesAction.ZONE_HEAD)
		_tick()
	assert_int(tally.count(1, ChallengeStats.POINTS)).is_zero()
	assert_int(_trackers[1].night_xp()).is_equal(_award.night_xp(1))
