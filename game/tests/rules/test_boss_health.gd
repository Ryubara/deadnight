extends GdUnitTestSuite
## The bosses' health after the 25% rise (#688): every boss has a quarter more than before and a
## spawned headliner carries it; the weak spot is untouched.

## Every boss's health multiplier before the rise, by type; a new boss is added here with its own.
const BEFORE_RISE := {&"headliner": 13.0}
## The rise itself: the bosses are 25% tougher.
const RISE := 1.25

var _t: RulesTuning


func before_test() -> void:
	_t = RulesFixture.tuning()


func test_every_boss_has_a_quarter_more_health_and_the_same_weak_spot() -> void:
	var bosses := 0
	for type in _t.roster.types:
		if not type.boss:
			continue
		bosses += 1
		assert_bool(BEFORE_RISE.has(type.id)).is_true()
		assert_float(type.health_multiplier).is_equal_approx(BEFORE_RISE[type.id] * RISE, 0.0001)
	assert_int(bosses).is_equal(BEFORE_RISE.size())
	assert_float(_t.roster.type_of(&"headliner").weak_multiplier).is_equal(2.2)


func test_a_spawned_headliner_has_1_25_times_the_old_health() -> void:
	var rules := RulesFixture.with_one_living(&"headliner", _t)
	var zombie_id: int = rules.zombie_ids()[0]
	var walker := _t.rounds.health_for_round(rules.round_number)
	assert_float(rules.zombie_health(zombie_id)).is_equal_approx(walker * 13.0 * RISE, 0.001)
