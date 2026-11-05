extends GdUnitTestSuite
## A blast that killed says how many dead it left (`blast_resolved`, #1074): once, after the zombie
## events of the blast, with who threw it, and not at all for a blast that killed nothing.

var _rules: GameRules
var _log: RulesFixture
var _zombie: int


func before_test() -> void:
	_rules = RulesFixture.make_rules(1, 1234, RulesFixture.tuning())
	_log = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 12.0)
	_zombie = _log.spawned_ids()[0]


func test_a_blast_that_killed_says_how_many_dead_it_left_after_their_events() -> void:
	# Three zombies, the blast kills two and only hurts the third (#1074).
	_rules._plan.assign([&"walker", &"walker"])
	RulesFixture.run(_rules, 6.0)
	var ids := _rules.zombie_ids()
	assert_int(ids.size()).is_greater_equal(3)
	var victims: Array = []
	for i in 3:
		var damage := RulesFixture.KILLING_DAMAGE if i < 2 else 1.0
		victims.append({"zombie_id": ids[i], "damage": damage, "leg_damage": 0.0})
	var events := _rules.apply(RulesAction.explosion(1, victims))
	var resolved := events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"blast_resolved"
	)
	assert_array(resolved).has_size(1)
	assert_int(resolved[0]["kills"]).is_equal(2)
	assert_int(resolved[0]["hits"]).is_equal(3)
	assert_int(resolved[0]["player_id"]).is_equal(1)
	# It comes last: after every zombie event the blast made.
	assert_str(events[events.size() - 1]["type"]).is_equal("blast_resolved")


func test_a_blast_that_killed_nothing_says_nothing_of_the_dead() -> void:
	var victim := {"zombie_id": _zombie, "damage": 1.0, "leg_damage": 0.0}
	var events := _rules.apply(RulesAction.explosion(1, [victim]))
	(
		assert_array(events.map(func(e: Dictionary) -> Variant: return e["type"]))
		. not_contains([&"blast_resolved"])
	)
