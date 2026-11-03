extends GdUnitTestSuite
## The bosses' health: a quarter more than before #688 (13 to 16.25), then x15 since the six
## firearms (#793: with their rounds on sale the headliner's time to kill read 31.5 s against the
## gate's 30; docs/research/balance-simulator.md). A spawned headliner carries it; the weak spot
## is untouched.

## Every boss's health multiplier, by type; a new boss is added here with its own.
const MULTIPLIER := {&"headliner": 15.0}
## What the multiplier is against the one before #688 (13): still 15% tougher.
const BEFORE_RISE := {&"headliner": 13.0}

var _t: RulesTuning


func before_test() -> void:
	_t = RulesFixture.tuning()


func test_every_boss_is_tougher_than_before_the_rise_and_has_the_same_weak_spot() -> void:
	var bosses := 0
	for type in _t.roster.types:
		if not type.boss:
			continue
		bosses += 1
		assert_bool(MULTIPLIER.has(type.id)).is_true()
		assert_float(type.health_multiplier).is_equal_approx(MULTIPLIER[type.id], 0.0001)
		assert_float(type.health_multiplier).is_greater(BEFORE_RISE[type.id])
	assert_int(bosses).is_equal(MULTIPLIER.size())
	assert_float(_t.roster.type_of(&"headliner").weak_multiplier).is_equal(2.2)


func test_a_spawned_headliner_has_its_multiplier_of_the_walkers_health() -> void:
	var rules := RulesFixture.with_one_living(&"headliner", _t)
	var zombie_id: int = rules.zombie_ids()[0]
	var walker := _t.rounds.health_for_round(rules.round_number)
	assert_float(rules.zombie_health(zombie_id)).is_equal_approx(
		walker * MULTIPLIER[&"headliner"], 0.001
	)
