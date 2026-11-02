extends GdUnitTestSuite
## The daily rotation is a function of the date: the same day always gives the same three, a day is
## varied, neighbouring days differ, and the clock turns the day at the player's midnight.

const DAY := 20400

var _catalog: ChallengeCatalog


func before_test() -> void:
	_catalog = ChallengeCatalog.load_default()


func test_the_same_day_gives_the_same_three_every_time() -> void:
	assert_array(DailyRotation.deal(_catalog, DAY)).is_equal(DailyRotation.deal(_catalog, DAY))
	var other := ChallengeCatalog.load_default()
	assert_array(DailyRotation.deal(other, DAY)).is_equal(DailyRotation.deal(_catalog, DAY))


func test_asking_for_other_days_first_changes_nothing() -> void:
	var alone := DailyRotation.deal(_catalog, DAY)
	for other in [DAY - 1, DAY + 7, DAY + 1, 3]:
		DailyRotation.deal(_catalog, other)
	assert_array(DailyRotation.deal(_catalog, DAY)).is_equal(alone)


func test_a_day_is_one_short_one_medium_and_one_long() -> void:
	for day in range(DAY, DAY + 60):
		var dealt := DailyRotation.deal(_catalog, day)
		assert_int(dealt.size()).is_equal(3)
		for i in 3:
			assert_int(_catalog.get_def(dealt[i]).tier).is_equal(DailyRotation.TIERS[i])


func test_two_of_one_group_never_share_a_day() -> void:
	for day in range(DAY, DAY + 200):
		var groups := {}
		for id in DailyRotation.deal(_catalog, day):
			var group := _catalog.get_def(id).group
			assert_bool(groups.has(group)).is_false()
			groups[group] = true


func test_neighbouring_days_share_no_challenge_except_across_a_block_start() -> void:
	var repeats := 0
	for day in range(DAY, DAY + 365):
		var yesterday := DailyRotation.deal(_catalog, day - 1)
		for id in DailyRotation.deal(_catalog, day):
			if yesterday.has(id):
				assert_int(posmod(day, DailyRotation.BLOCK_DAYS)).is_equal(0)
				repeats += 1
				break
	assert_int(repeats).is_less_equal(365 / DailyRotation.BLOCK_DAYS + 1)


func test_over_a_year_every_daily_comes_round_and_none_dominates() -> void:
	var seen := {}
	for day in range(DAY, DAY + 365):
		for id in DailyRotation.deal(_catalog, day):
			seen[id] = int(seen.get(id, 0)) + 1
	var all := _catalog.of_family(ChallengeDef.Family.DAILY)
	for def in all:
		assert_bool(seen.has(def.id)).override_failure_message("never dealt: %s" % def.id).is_true()
	var most := 0
	for count: int in seen.values():
		most = maxi(most, count)
	# A tier's pool has at least six, so none may take more than about a third of the days.
	assert_int(most).is_less(365 / 3 + 30)


func test_neighbouring_days_differ() -> void:
	var same := 0
	for day in range(DAY, DAY + 100):
		if DailyRotation.deal(_catalog, day) == DailyRotation.deal(_catalog, day + 1):
			same += 1
	assert_int(same).is_equal(0)


func test_the_day_turns_at_the_players_midnight() -> void:
	var before_midnight := ChallengeClock.fixed(float(DAY + 1) * 86400.0 - 30.0)
	var after_midnight := ChallengeClock.fixed(float(DAY + 1) * 86400.0 + 30.0)
	assert_int(before_midnight.day()).is_equal(DAY)
	assert_int(after_midnight.day()).is_equal(DAY + 1)
	# Two hours east of UTC, 22:30 UTC is already half past midnight of the next day.
	var east := ChallengeClock.fixed(float(DAY) * 86400.0 + 22.5 * 3600.0, 2 * 3600)
	assert_int(east.day()).is_equal(DAY + 1)
	var west := ChallengeClock.fixed(float(DAY) * 86400.0 + 1.0 * 3600.0, -5 * 3600)
	assert_int(west.day()).is_equal(DAY - 1)


func test_time_to_the_next_refresh_counts_down_to_local_midnight() -> void:
	var noon := ChallengeClock.fixed(float(DAY) * 86400.0 + 12.0 * 3600.0)
	assert_int(noon.seconds_to_refresh()).is_equal(12 * 3600)
	var late := ChallengeClock.fixed(float(DAY) * 86400.0 + 86400.0 - 90.0)
	assert_int(late.seconds_to_refresh()).is_equal(90)
	var start := ChallengeClock.fixed(float(DAY) * 86400.0)
	assert_int(start.seconds_to_refresh()).is_equal(86400)


func test_a_day_has_a_readable_date() -> void:
	assert_str(ChallengeClock.date_text(0)).is_equal("1970-01-01")
	assert_str(ChallengeClock.date_text(20453)).is_equal("2025-12-31")
