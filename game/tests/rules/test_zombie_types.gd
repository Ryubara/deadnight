extends GdUnitTestSuite
## Zombie types as data: the mix of a round, what a spawn carries, the weak spot, the crawler, what
## each type pays and that the shipped table hangs together.

## Seconds of a round to collect spawns over: most of its zombies (the alive cap holds the rest).
const SPAWN_WINDOW := 40.0

var _t: RulesTuning


func before_test() -> void:
	_t = RulesFixture.tuning()


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Spawns the first zombie of `round_number` by skipping to it: plays rounds with sure kills.
func _spawn_in_round(rules: GameRules, round_number: int) -> Array[Dictionary]:
	var spawned: Array[Dictionary] = []
	rules.event_emitted.connect(
		func(event: Dictionary) -> void:
			if event["type"] == &"zombie_spawn_requested":
				spawned.append(event)
	)
	rules.apply(RulesAction.start())
	while rules.round_number < round_number or rules.phase != GameRules.Phase.ACTIVE:
		if rules.phase == GameRules.Phase.BREAK:
			rules.apply(RulesAction.skip_break())
		else:
			RulesFixture.run(rules, 0.5)
			for zombie_id in rules.zombie_ids():
				RulesFixture.kill(rules, 1, zombie_id)
			if rules.phase == GameRules.Phase.ACTIVE and rules.zombies_remaining() > 0:
				continue
	spawned.clear()
	RulesFixture.run(rules, SPAWN_WINDOW)
	return spawned


func test_the_first_rounds_are_only_walkers() -> void:
	for round_number in [1, 2, 3]:
		var plan := _t.roster.plan_for_round(round_number, 12, _rng())
		assert_int(plan.count(&"walker")).is_equal(12)


func test_a_type_arrives_exactly_as_introduced_on_its_first_round() -> void:
	for type in _t.roster.types:
		if type.boss or type.id == _t.roster.base_id:
			continue
		var before := _t.roster.plan_for_round(type.first_round - 1, 14, _rng())
		var first := _t.roster.plan_for_round(type.first_round, 14, _rng())
		assert_int(before.count(type.id)).is_equal(0)
		assert_int(first.count(type.id)).is_equal(type.intro_count)


func test_each_type_is_introduced_in_a_round_of_its_own() -> void:
	var rounds: Array[int] = []
	for type in _t.roster.types:
		if type.boss or type.id == _t.roster.base_id:
			continue
		assert_bool(rounds.has(type.first_round)).is_false()
		rounds.append(type.first_round)


func test_the_share_of_a_type_grows_and_stops_at_its_cap() -> void:
	var runner := _t.roster.type_of(&"runner")
	assert_float(runner.share_at(runner.first_round - 1)).is_equal(0.0)
	assert_float(runner.share_at(runner.first_round + 1)).is_greater(
		runner.share_at(runner.first_round)
	)
	assert_float(runner.share_at(500)).is_equal(runner.share_max)


func test_a_plan_has_the_count_asked_and_never_holds_a_boss() -> void:
	for round_number in [1, 6, 12, 25]:
		var plan := _t.roster.plan_for_round(round_number, 40, _rng(round_number))
		assert_int(plan.size()).is_equal(40)
		assert_int(plan.count(&"headliner")).is_equal(0)


func test_special_types_never_crowd_out_the_common_dead() -> void:
	var plan := _t.roster.plan_for_round(40, 100, _rng())
	var walkers := plan.count(&"walker")
	assert_int(walkers).is_greater_equal(int(100.0 * (1.0 - _t.roster.max_special_share)))


func test_a_plan_follows_the_seed() -> void:
	assert_array(_t.roster.plan_for_round(9, 30, _rng(5))).is_equal(
		_t.roster.plan_for_round(9, 30, _rng(5))
	)
	assert_array(_t.roster.plan_for_round(9, 30, _rng(5))).is_not_equal(
		_t.roster.plan_for_round(9, 30, _rng(6))
	)


func test_a_spawn_names_its_type_and_what_the_world_needs() -> void:
	var rules := RulesFixture.make_rules(1, 7, _t)
	var spawned := _spawn_in_round(rules, 1)
	assert_array(spawned).is_not_empty()
	var order := spawned[0]
	for key in [
		"zombie_id",
		"zombie_type",
		"look",
		"boss",
		"health",
		"speed",
		"point_roll",
		"damage",
		"knockback",
		"telegraph_seconds",
		"barrier_speed",
		"hit_chance",
	]:
		assert_bool(order.has(key)).override_failure_message("missing %s" % key).is_true()
	assert_str(order["zombie_type"]).is_equal("walker")
	assert_bool(_t.roster.type_of(&"walker").looks.has(order["look"])).is_true()


func test_no_event_field_hides_the_events_own_type() -> void:
	var rules := RulesFixture.make_rules(1, 7, _t)
	var log := RulesFixture.record(rules)
	_spawn_in_round(rules, 4)
	for event in log.events:
		assert_bool(event["type"] is StringName).is_true()
		(
			assert_bool(String(event["type"]).begins_with("zombie_") == event.has("zombie_id"))
			. is_true()
		)
	var spawn := log.of(&"zombie_spawn_requested")[0]
	assert_str(spawn["type"]).is_equal("zombie_spawn_requested")


func test_a_types_health_and_speed_scale_the_rounds() -> void:
	var rules := RulesFixture.make_rules(1, 3, _t)
	var runner_health := _t.roster.type_of(&"runner").health_multiplier
	var found := false
	for round_number in [4, 5, 6]:
		var rules_n := RulesFixture.make_rules(1, 3, _t)
		for order in _spawn_in_round(rules_n, round_number):
			if order["zombie_type"] == &"runner":
				found = true
				assert_float(order["health"]).is_equal_approx(
					_t.rounds.health_for_round(round_number) * runner_health, 0.001
				)
				assert_float(order["speed"]).is_greater(
					_t.rounds.speed_for_round(round_number) * 1.3
				)
	assert_bool(found).is_true()
	assert_object(rules).is_not_null()


func test_extra_players_make_a_boss_tougher() -> void:
	var headliner := _t.roster.type_of(&"headliner")
	assert_float(headliner.health_per_extra_player).is_greater(0.0)


func test_the_weak_spot_multiplies_the_damage() -> void:
	var rules := _rules_with_one_living(&"headliner")
	var zombie_id: int = rules.zombie_ids()[0]
	var before := rules.zombie_health(zombie_id)
	var weak := _t.roster.type_of(&"headliner").weak_multiplier
	rules.apply(RulesAction.hit(1, zombie_id, RulesAction.ZONE_WEAK, 10.0))
	assert_float(before - rules.zombie_health(zombie_id)).is_equal_approx(10.0 * weak, 0.001)
	rules.apply(RulesAction.hit(1, zombie_id, RulesAction.ZONE_BODY, 10.0))
	assert_float(before - rules.zombie_health(zombie_id)).is_equal_approx(10.0 * weak + 10.0, 0.001)


func test_a_weak_spot_hit_on_an_ordinary_zombie_is_plain_damage() -> void:
	var rules := _rules_with_one_living(&"walker")
	var zombie_id: int = rules.zombie_ids()[0]
	var before := rules.zombie_health(zombie_id)
	rules.apply(RulesAction.hit(1, zombie_id, RulesAction.ZONE_WEAK, 10.0))
	assert_float(before - rules.zombie_health(zombie_id)).is_equal_approx(10.0, 0.001)


func test_a_blast_that_takes_the_legs_turns_a_walker_into_a_crawler() -> void:
	var rules := _rules_with_one_living(&"walker")
	var log := RulesFixture.record(rules)
	var zombie_id: int = rules.zombie_ids()[0]
	var health := rules.zombie_health(zombie_id)
	var victim := {"zombie_id": zombie_id, "damage": health * 0.3, "leg_damage": health * 0.3}
	rules.apply(RulesAction.explosion(1, [victim]))
	var crippled := log.of(&"zombie_crippled")
	assert_int(crippled.size()).is_equal(1)
	assert_str(crippled[0]["zombie_type"]).is_equal("crawler")
	assert_str(String(crippled[0]["look"])).is_equal("crawler")
	assert_str(rules.zombie_type(zombie_id)).is_equal("crawler")
	# It dies as what it became, and the snapshot remembers.
	var copy := GameRules.new(_t, 11)
	assert_str(copy.from_wire(rules.to_wire())).is_equal("")
	assert_str(copy.zombie_type(zombie_id)).is_equal("crawler")
	RulesFixture.kill(rules, 1, zombie_id)
	assert_str(log.of(&"zombie_removed")[0]["zombie_type"]).is_equal("crawler")


func test_a_blast_that_does_not_cripple_leaves_the_type_alone() -> void:
	var rules := _rules_with_one_living(&"walker")
	var zombie_id: int = rules.zombie_ids()[0]
	var victim := {"zombie_id": zombie_id, "damage": 1.0, "leg_damage": 0.0}
	rules.apply(RulesAction.explosion(1, [victim]))
	assert_str(rules.zombie_type(zombie_id)).is_equal("walker")


func test_a_type_pays_its_multiplier() -> void:
	var walker := _rules_with_one_living(&"walker")
	var brute := _rules_with_one_living(&"brute")
	var walker_pay := _kill_pay(walker)
	var brute_pay := _kill_pay(brute)
	var multiplier := _t.roster.type_of(&"brute").points_multiplier
	assert_int(walker_pay).is_equal(_t.economy.kill)
	assert_int(brute_pay).is_equal(roundi(_t.economy.kill * multiplier))


func test_a_boss_pays_more_hits_than_an_ordinary_zombie() -> void:
	var rules := _rules_with_one_living(&"headliner")
	var zombie_id: int = rules.zombie_ids()[0]
	var before := rules.points_of(1)
	for _i in 10:
		rules.apply(RulesAction.hit(1, zombie_id, RulesAction.ZONE_BODY, 1.0))
	var paid := rules.points_of(1) - before
	var per_hit := roundi(_t.economy.hit * _t.roster.type_of(&"headliner").points_multiplier)
	assert_int(paid).is_equal(10 * per_hit)


func test_the_shipped_roster_hangs_together() -> void:
	var seen: Dictionary = {}
	assert_object(_t.roster.type_of(_t.roster.base_id)).is_not_null()
	for type in _t.roster.types:
		assert_bool(seen.has(type.id)).is_false()
		seen[type.id] = true
		assert_float(type.health_multiplier).is_greater(0.0)
		assert_float(type.speed_multiplier).is_greater(0.0)
		assert_float(type.damage).is_greater(0.0)
		assert_int(type.first_round).is_greater_equal(1)
		if type.crawls_into != &"":
			assert_object(_t.roster.type_of(type.crawls_into)).is_not_null()


## A night in round 1 with one living zombie forced to `type_id` (by spawning it from a plan).
func _rules_with_one_living(type_id: StringName) -> GameRules:
	return RulesFixture.with_one_living(type_id, _t)


func _kill_pay(rules: GameRules) -> int:
	var before := rules.points_of(1)
	RulesFixture.kill(rules, 1, rules.zombie_ids()[0])
	# The only zombie of the round: its death also ends the round, which pays the round bonus.
	return rules.points_of(1) - before - _t.economy.round_bonus(rules.round_number)
