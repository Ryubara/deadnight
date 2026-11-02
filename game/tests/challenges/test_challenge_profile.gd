extends GdUnitTestSuite
## The profile: dealing and banking dailies, the three orders, counting, quarter marks and ladders.

## Not the first day of a 30-day block (`DailyRotation.BLOCK_DAYS`), so neighbours differ.
const DAY := 20401

var _catalog: ChallengeCatalog
var _profile: ChallengeProfile


func before_test() -> void:
	_catalog = ChallengeCatalog.load_default()
	_profile = ChallengeProfile.fresh(5)


func _ids(entries: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in entries:
		ids.append(StringName(entry["id"]))
	return ids


## Finishes every daily the profile holds.
func _finish_all() -> void:
	for entry in _profile.dailies:
		entry["progress"] = _catalog.get_def(entry["id"]).target


# --- Dealing and banking ---


func test_a_first_day_deals_the_days_three() -> void:
	_profile.refresh(_catalog, DAY)
	assert_array(_ids(_profile.dailies)).is_equal(DailyRotation.deal(_catalog, DAY))
	assert_int(_profile.dealt_day).is_equal(DAY)


func test_opening_twice_on_one_day_changes_nothing() -> void:
	_profile.refresh(_catalog, DAY)
	_profile.dailies[0]["progress"] = 3
	var before := _profile.to_dict()
	assert_array(_profile.refresh(_catalog, DAY)).is_empty()
	assert_dict(_profile.to_dict()).is_equal(before)


func test_a_clock_set_back_deals_nothing_new() -> void:
	_profile.refresh(_catalog, DAY)
	var before := _ids(_profile.dailies)
	_profile.refresh(_catalog, DAY - 3)
	assert_array(_ids(_profile.dailies)).is_equal(before)
	assert_int(_profile.dealt_day).is_equal(DAY)


func test_finished_dailies_leave_at_the_next_day() -> void:
	_profile.refresh(_catalog, DAY)
	_finish_all()
	_profile.refresh(_catalog, DAY + 1)
	assert_array(_ids(_profile.dailies)).is_equal(DailyRotation.deal(_catalog, DAY + 1))


func test_unfinished_dailies_bank_and_keep_their_progress() -> void:
	_profile.refresh(_catalog, DAY)
	var first := _ids(_profile.dailies)
	_profile.dailies[1]["progress"] = 2
	_profile.refresh(_catalog, DAY + 1)
	var today := DailyRotation.deal(_catalog, DAY + 1)
	assert_int(_profile.dailies.size()).is_equal(6)
	assert_array(_ids(_profile.dailies).slice(0, 3)).is_equal(today)
	assert_array(_ids(_profile.dailies).slice(3)).is_equal(first)
	assert_int(_profile.dailies[4]["progress"]).is_equal(2)
	assert_int(_profile.dailies[4]["day"]).is_equal(DAY)


func test_the_bank_holds_three_and_the_oldest_retires() -> void:
	_profile.refresh(_catalog, DAY)
	var first := _ids(_profile.dailies)
	assert_array(_profile.refresh(_catalog, DAY + 1)).is_empty()
	assert_int(_profile.dailies.size()).is_equal(6)
	var second := DailyRotation.deal(_catalog, DAY + 1)
	# Nothing was finished: the bank is full, so the first day's three, the oldest, go.
	var retired := _profile.refresh(_catalog, DAY + 2)
	assert_array(retired).contains_exactly_in_any_order(first)
	assert_int(_profile.dailies.size()).is_equal(6)
	var days: Array = _profile.dailies.map(func(e: Dictionary) -> int: return e["day"])
	assert_bool(days.has(DAY)).is_false()
	assert_array(_ids(_profile.dailies).slice(3)).is_equal(second)


func test_a_banked_daily_dealt_again_is_todays_with_its_progress() -> void:
	# Find a day on which two days on deals something this day dealt (rare, so search).
	var day := DAY
	var shared: Array[StringName] = []
	while shared.is_empty():
		var later := DailyRotation.deal(_catalog, day + 2)
		shared.assign(DailyRotation.deal(_catalog, day).filter(later.has))
		if shared.is_empty():
			day += 1
	_profile.refresh(_catalog, day)
	for entry in _profile.dailies:
		if entry["id"] == shared[0]:
			entry["progress"] = 1
	_profile.refresh(_catalog, day + 1)
	_profile.refresh(_catalog, day + 2)
	var copies := _profile.dailies.filter(func(e: Dictionary) -> bool: return e["id"] == shared[0])
	assert_int(copies.size()).is_equal(1)
	assert_int(copies[0]["progress"]).is_equal(1)
	assert_int(copies[0]["day"]).is_equal(day + 2)


func test_a_player_away_for_a_month_returns_to_a_day_of_three_and_a_full_bank_at_most() -> void:
	_profile.refresh(_catalog, DAY)
	_profile.refresh(_catalog, DAY + 30)
	var again := DailyRotation.deal(_catalog, DAY + 30).filter(
		func(id: StringName) -> bool: return DailyRotation.deal(_catalog, DAY).has(id)
	)
	assert_int(_profile.dailies.size()).is_equal(6 - again.size())
	assert_array(_ids(_profile.dailies).slice(0, 3)).is_equal(
		DailyRotation.deal(_catalog, DAY + 30)
	)


func test_a_challenge_gone_from_the_data_is_dropped() -> void:
	_profile.refresh(_catalog, DAY)
	_profile.dailies.append({"id": &"d_removed", "day": DAY, "progress": 1})
	_profile.orders.append({"id": &"o_removed", "progress": 1})
	_profile.refresh(_catalog, DAY + 1)
	assert_array(_ids(_profile.dailies)).not_contains([&"d_removed"])
	assert_array(_ids(_profile.orders)).not_contains([&"o_removed"])


# --- Orders ---


func test_three_distinct_orders_are_dealt_from_the_pool() -> void:
	_profile.fill_orders(_catalog)
	assert_int(_profile.orders.size()).is_equal(ChallengeProfile.ORDER_SLOTS)
	var ids := _ids(_profile.orders)
	assert_int(ids.size()).is_equal(3)
	assert_bool(ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2]).is_true()
	for id in ids:
		assert_int(_catalog.get_def(id).family).is_equal(ChallengeDef.Family.ORDER)


func test_the_same_seed_deals_the_same_orders_and_another_seed_others() -> void:
	var same := ChallengeProfile.fresh(5)
	same.fill_orders(_catalog)
	_profile.fill_orders(_catalog)
	assert_array(_ids(same.orders)).is_equal(_ids(_profile.orders))
	var differing := 0
	for seed_value in range(1, 30):
		var other := ChallengeProfile.fresh(seed_value)
		other.fill_orders(_catalog)
		if _ids(other.orders) != _ids(_profile.orders):
			differing += 1
	assert_int(differing).is_greater(20)


func test_a_finished_order_stays_until_the_night_is_settled_then_is_replaced() -> void:
	_profile.fill_orders(_catalog)
	var finished_id: StringName = _profile.orders[0]["id"]
	_profile.orders[0]["progress"] = _catalog.get_def(finished_id).target
	var kept := _ids(_profile.orders).slice(1)
	assert_array(_ids(_profile.orders)).contains([finished_id])
	_profile.settle(_catalog)
	assert_int(_profile.orders.size()).is_equal(3)
	assert_array(_ids(_profile.orders)).not_contains([finished_id])
	for id in kept:
		assert_array(_ids(_profile.orders)).contains([id])
	assert_array(_profile.recent_orders).contains([finished_id])


func test_an_order_keeps_its_progress_when_the_dailies_turn() -> void:
	_profile.refresh(_catalog, DAY)
	_profile.orders[1]["progress"] = 2
	_profile.refresh(_catalog, DAY + 5)
	assert_int(_profile.orders[1]["progress"]).is_equal(2)


func test_swapping_an_order_is_free_and_unlimited_and_loses_only_its_own_progress() -> void:
	_profile.fill_orders(_catalog)
	_profile.orders[2]["progress"] = 4
	var before := _ids(_profile.orders)
	for _i in 12:
		var kept: Dictionary = _profile.orders[0].duplicate()
		assert_bool(_profile.swap_order(_catalog, 1)).is_true()
		assert_dict(_profile.orders[0]).is_equal(kept)
		assert_int(_profile.orders[1]["progress"]).is_equal(0)
	assert_int(_profile.orders[2]["progress"]).is_equal(4)
	assert_array(_ids(_profile.orders)).is_not_equal(before)
	assert_bool(_profile.swap_order(_catalog, 3)).is_false()


func test_no_order_asks_for_a_thing_the_night_cannot_count() -> void:
	# Every order's stat is one the tally makes, so a slot can always be finished.
	var weapons := WeaponCatalog.IDS
	var types: Array[StringName] = []
	for type: ZombieType in RulesFixture.tuning().roster.types:
		types.append(type.id)
	for def in _catalog.of_family(ChallengeDef.Family.ORDER):
		assert_bool(ChallengeStats.is_known(def.stat, weapons, types)).is_true()
