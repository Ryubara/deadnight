extends GdUnitTestSuite
## What earns points, who may earn them, and how often.

var _rules: GameRules
var _log: RulesFixture
var _zombie: int


func before_test() -> void:
	_rules = RulesFixture.make_rules(2)
	_log = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 2.0)
	_zombie = _log.spawned_ids()[0]


func test_a_player_joins_with_the_starting_points() -> void:
	assert_int(_rules.points_of(1)).is_equal(200)
	var fresh := GameRules.new(RulesFixture.tuning(), 1)
	var events := fresh.apply(RulesAction.add_player(7))
	assert_str(events[0]["type"]).is_equal("player_added")
	assert_int(events[1]["total"]).is_equal(200)
	assert_str(events[1]["reason"]).is_equal("start")


func test_nothing_is_earned_between_rounds() -> void:
	RulesFixture.run(_rules, 60.0)
	for zombie_id in _log.spawned_ids():
		RulesFixture.kill(_rules, 1, zombie_id)
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	var before := _rules.points_of(1)
	_rules.apply(RulesAction.repair(1))
	_rules.apply(RulesAction.hit(1, 1, RulesAction.ZONE_BODY, 20.0))
	assert_int(_rules.points_of(1)).is_equal(before)


func test_repairs_pay_up_to_a_cap_each_round() -> void:
	for _i in 30:
		_rules.apply(RulesAction.repair(1))
	assert_int(_rules.points_of(1)).is_equal(200 + 120)
	assert_int(_rules.points_of(2)).is_equal(200)


func test_the_repair_cap_resets_with_the_next_round() -> void:
	for _i in 30:
		_rules.apply(RulesAction.repair(1))
	RulesFixture.run(_rules, 60.0)
	for zombie_id in _log.spawned_ids():
		RulesFixture.kill(_rules, 1, zombie_id)
	_rules.apply(RulesAction.skip_break())
	var before := _rules.points_of(1)
	for _i in 30:
		_rules.apply(RulesAction.repair(1))
	assert_int(_rules.points_of(1)).is_equal(before + 120)


func test_a_round_pays_a_bonus_to_everyone_on_their_feet() -> void:
	RulesFixture.run(_rules, 60.0)
	_rules.apply(RulesAction.set_downed(2, true))
	for zombie_id in _log.spawned_ids():
		_rules.apply(RulesAction.zombie_gone(zombie_id))
	# Round 1 bonus is 20 + 10. The downed player gets up with a tenth of their points taken
	# instead.
	assert_int(_rules.points_of(1)).is_equal(230)
	assert_int(_rules.points_of(2)).is_equal(180)
	assert_int(_log.count(&"player_revived")).is_equal(1)
	assert_bool((_rules.players[2] as PlayerState).downed).is_false()


func test_the_round_bonus_grows_with_the_round() -> void:
	var economy := RulesFixture.tuning().economy
	assert_int(economy.round_bonus(1)).is_equal(30)
	assert_int(economy.round_bonus(10)).is_equal(120)


func test_granted_points_arrive_with_their_reason() -> void:
	_rules.apply(RulesAction.grant_points(2, 50, &"pickup"))
	assert_int(_rules.points_of(2)).is_equal(250)
	var change: Dictionary = _log.of(&"points_changed").back()
	assert_int(change["player_id"]).is_equal(2)
	assert_int(change["total"]).is_equal(250)
	assert_int(change["delta"]).is_equal(50)
	assert_str(change["reason"]).is_equal("pickup")
