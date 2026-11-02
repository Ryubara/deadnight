extends GdUnitTestSuite
## The profile: dealing dailies that expire at the next day, and the three orders.

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


# --- Dealing ---


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


func test_a_finished_daily_stays_on_the_board_until_the_day_turns() -> void:
	_profile.refresh(_catalog, DAY)
	_finish_all()
	_profile.refresh(_catalog, DAY)
	assert_int(_profile.dailies.size()).is_equal(3)
	assert_int(_profile.dailies[0]["progress"]).is_equal(
		_catalog.get_def(_profile.dailies[0]["id"]).target
	)


func test_every_daily_expires_at_the_next_day_finished_or_not() -> void:
	_profile.refresh(_catalog, DAY)
	_profile.dailies[0]["progress"] = _catalog.get_def(_profile.dailies[0]["id"]).target
	_profile.dailies[1]["progress"] = 2
	_profile.refresh(_catalog, DAY + 1)
	assert_array(_ids(_profile.dailies)).is_equal(DailyRotation.deal(_catalog, DAY + 1))
	assert_int(_profile.dailies.size()).is_equal(3)
	for entry in _profile.dailies:
		assert_int(entry["progress"]).is_equal(0)
		assert_int(entry["day"]).is_equal(DAY + 1)


func test_nothing_carries_over_however_many_days_pass() -> void:
	_profile.refresh(_catalog, DAY)
	for step in range(1, 6):
		_profile.dailies[0]["progress"] = 1
		_profile.refresh(_catalog, DAY + step)
		assert_int(_profile.dailies.size()).is_equal(3)
		assert_int(_profile.dailies[0]["progress"]).is_equal(0)
	_profile.refresh(_catalog, DAY + 40)
	assert_array(_ids(_profile.dailies)).is_equal(DailyRotation.deal(_catalog, DAY + 40))
	assert_int(_profile.dailies.size()).is_equal(3)


func test_a_daily_dealt_again_later_starts_from_zero() -> void:
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
	_profile.refresh(_catalog, day + 2)
	for entry in _profile.dailies:
		if entry["id"] == shared[0]:
			assert_int(entry["progress"]).is_equal(0)


func test_no_streak_or_count_of_days_is_kept() -> void:
	_profile.refresh(_catalog, DAY)
	var keys := _profile.to_dict().keys()
	for banned in ["streak", "bank", "banked", "days_played", "login"]:
		assert_array(keys).not_contains([banned])


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
