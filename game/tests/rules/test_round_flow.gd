extends GdUnitTestSuite
## The round manager: phases, spawn pacing, the cap on the living, round end, game over,
## determinism.

var _rules: GameRules
var _log: RulesFixture


func _begin(player_count: int = 1, seed_value: int = 1234, t: RulesTuning = null) -> void:
	_rules = RulesFixture.make_rules(player_count, seed_value, t)
	_log = RulesFixture.record(_rules)


func _kill_everything() -> void:
	for zombie_id in _log.spawned_ids():
		RulesFixture.kill(_rules, 1, zombie_id)


func test_a_new_night_is_idle_until_started() -> void:
	_begin()
	RulesFixture.run(_rules, 30.0)
	assert_int(_rules.phase).is_equal(GameRules.Phase.IDLE)
	assert_int(_rules.round_number).is_equal(0)
	assert_int(_log.count(&"zombie_spawn_requested")).is_equal(0)


func test_start_waits_out_the_intro_then_round_one_begins() -> void:
	_begin()
	_rules.apply(RulesAction.start())
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	assert_float(_log.of(&"break_started")[0]["seconds"]).is_equal(12.0)
	RulesFixture.run(_rules, 11.0)
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	RulesFixture.run(_rules, 1.5)
	assert_int(_rules.phase).is_equal(GameRules.Phase.ACTIVE)
	assert_int(_rules.round_number).is_equal(1)
	assert_int(_log.of(&"round_started")[0]["round"]).is_equal(1)
	assert_int(_log.of(&"round_started")[0]["zombie_count"]).is_equal(RulesFixture.round_count(1))


func test_the_first_spawn_waits_for_its_delay() -> void:
	_begin()
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 1.4)
	assert_int(_log.count(&"zombie_spawn_requested")).is_equal(0)
	RulesFixture.run(_rules, 0.3)
	assert_int(_log.count(&"zombie_spawn_requested")).is_equal(1)


func test_spawns_are_paced_by_the_interval() -> void:
	_begin()
	RulesFixture.into_round_one(_rules)
	# The first spawn comes after its delay, then one every interval: three by two intervals and a bit.
	var rounds := RulesFixture.tuning().rounds
	RulesFixture.run(_rules, rounds.first_spawn_delay + 2.0 * rounds.spawn_interval(1, 1) + 0.5)
	assert_int(_log.count(&"zombie_spawn_requested")).is_equal(3)


func test_a_round_sends_exactly_its_count_with_the_rounds_health() -> void:
	_begin()
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 60.0)
	var orders := _log.of(&"zombie_spawn_requested")
	assert_int(orders.size()).is_equal(RulesFixture.round_count(1))
	var ids: Dictionary = {}
	for order in orders:
		ids[order["zombie_id"]] = true
		assert_float(order["health"]).is_equal(RulesFixture.round_health(1))
		assert_float(order["speed"]).is_greater(0.0)
	assert_int(ids.size()).is_equal(RulesFixture.round_count(1))


func test_no_more_than_the_cap_are_alive_and_a_kill_lets_the_next_in() -> void:
	var t := RulesFixture.tuning()
	t.rounds.alive_cap_start = 2.0
	_begin(1, 1234, t)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 60.0)
	assert_int(_log.count(&"zombie_spawn_requested")).is_equal(2)
	RulesFixture.kill(_rules, 1, _log.spawned_ids()[0])
	# The waiting spawn is ready at once: the next step lets it in, no burst of banked spawns.
	RulesFixture.run(_rules, 0.1)
	assert_int(_log.count(&"zombie_spawn_requested")).is_equal(3)
	RulesFixture.run(_rules, 0.1)
	assert_int(_log.count(&"zombie_spawn_requested")).is_equal(3)


func test_the_round_ends_when_the_last_zombie_falls_not_before() -> void:
	_begin()
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 60.0)
	var ids := _log.spawned_ids()
	for index in range(ids.size() - 1):
		RulesFixture.kill(_rules, 1, ids[index])
	assert_int(_rules.phase).is_equal(GameRules.Phase.ACTIVE)
	assert_int(_rules.zombies_remaining()).is_equal(1)
	RulesFixture.kill(_rules, 1, ids[ids.size() - 1])
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	assert_int(_log.of(&"round_ended")[0]["round"]).is_equal(1)
	assert_int(_log.of(&"break_started")[1]["next_round"]).is_equal(2)
	assert_float(_log.of(&"break_started")[1]["seconds"]).is_equal(5.0)


func test_a_break_is_five_seconds_in_the_class_and_in_the_shipped_tuning() -> void:
	assert_float(RoundTuning.new().break_seconds).is_equal(5.0)
	assert_float(RulesFixture.tuning().rounds.break_seconds).is_equal(5.0)


func test_the_round_does_not_end_while_zombies_are_still_to_spawn() -> void:
	_begin()
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 2.0)
	RulesFixture.kill(_rules, 1, _log.spawned_ids()[0])
	assert_int(_rules.phase).is_equal(GameRules.Phase.ACTIVE)


func test_after_the_break_the_next_round_is_bigger_and_tougher() -> void:
	_begin()
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 60.0)
	_kill_everything()
	RulesFixture.run(_rules, 20.5)
	assert_int(_rules.round_number).is_equal(2)
	assert_int(_log.of(&"round_started")[1]["zombie_count"]).is_equal(RulesFixture.round_count(2))
	RulesFixture.run(_rules, 60.0)
	var second_round_first := _log.of(&"zombie_spawn_requested")[RulesFixture.round_count(1)]
	assert_float(second_round_first["health"]).is_equal(RulesFixture.round_health(2))


func test_a_skipped_break_starts_the_next_round_at_once() -> void:
	_begin()
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 60.0)
	_kill_everything()
	_rules.apply(RulesAction.skip_break())
	assert_int(_rules.round_number).is_equal(2)
	assert_int(_rules.phase).is_equal(GameRules.Phase.ACTIVE)


func test_more_players_mean_a_bigger_round() -> void:
	_begin(2)
	RulesFixture.into_round_one(_rules)
	assert_int(_log.of(&"round_started")[0]["zombie_count"]).is_equal(
		RulesFixture.round_count(1, 2)
	)


func test_a_zombie_lost_to_the_world_still_counts_toward_the_round() -> void:
	_begin()
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 60.0)
	for zombie_id in _log.spawned_ids():
		_rules.apply(RulesAction.zombie_gone(zombie_id))
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	assert_int(_rules.points_of(1)).is_equal(200 + 30)  # start points plus the round bonus only


func test_everyone_down_ends_the_night() -> void:
	_begin(2)
	RulesFixture.into_round_one(_rules)
	_rules.apply(RulesAction.set_downed(1, true))
	assert_int(_rules.phase).is_equal(GameRules.Phase.ACTIVE)
	_rules.apply(RulesAction.set_downed(2, true))
	assert_int(_rules.phase).is_equal(GameRules.Phase.OVER)
	assert_str(_log.of(&"game_over")[0]["reason"]).is_equal("all_down")
	assert_int(_log.of(&"game_over")[0]["round_reached"]).is_equal(1)
	var spawns := _log.count(&"zombie_spawn_requested")
	RulesFixture.run(_rules, 30.0)
	assert_int(_log.count(&"zombie_spawn_requested")).is_equal(spawns)


func test_a_revived_player_keeps_the_night_going() -> void:
	_begin(2)
	RulesFixture.into_round_one(_rules)
	_rules.apply(RulesAction.set_downed(1, true))
	_rules.apply(RulesAction.set_downed(1, false))
	_rules.apply(RulesAction.set_downed(2, true))
	assert_int(_rules.phase).is_equal(GameRules.Phase.ACTIVE)


func test_same_seed_same_night_different_seed_different_night() -> void:
	var run_a := _spawn_orders(55)
	var run_b := _spawn_orders(55)
	var run_c := _spawn_orders(56)
	assert_array(run_a).is_equal(run_b)
	assert_array(run_a).is_not_equal(run_c)


func _spawn_orders(seed_value: int) -> Array:
	var rules: GameRules = RulesFixture.make_rules(1, seed_value)
	var recorder := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 60.0)
	var orders: Array = []
	for event in recorder.of(&"zombie_spawn_requested"):
		orders.append([event["zombie_id"], event["health"], event["speed"], event["point_roll"]])
	return orders
