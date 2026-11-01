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


func test_a_body_hit_pays_a_little() -> void:
	_rules.apply(RulesAction.hit(1, _zombie, false))
	assert_int(_rules.points_of(1)).is_equal(204)


func test_a_headshot_hit_pays_double() -> void:
	_rules.apply(RulesAction.hit(1, _zombie, true))
	assert_int(_rules.points_of(1)).is_equal(208)


func test_kills_pay_by_how_they_were_made() -> void:
	RulesFixture.run(_rules, 10.0)
	var ids := _log.spawned_ids()
	_rules.apply(RulesAction.kill(1, ids[0], false, false))
	assert_int(_rules.points_of(1)).is_equal(200 + 60)
	_rules.apply(RulesAction.kill(1, ids[1], true, false))
	assert_int(_rules.points_of(1)).is_equal(260 + 100)
	_rules.apply(RulesAction.kill(1, ids[2], false, true))
	assert_int(_rules.points_of(1)).is_equal(360 + 130)


func test_the_kill_is_credited_and_counted() -> void:
	_rules.apply(RulesAction.kill(1, _zombie, true, false))
	var removed := _log.of(&"zombie_removed")[0]
	assert_int(removed["zombie_id"]).is_equal(_zombie)
	assert_int(removed["killer_id"]).is_equal(1)
	assert_int((_rules.players[1] as PlayerState).kills).is_equal(1)
	assert_int((_rules.players[1] as PlayerState).headshot_kills).is_equal(1)


func test_a_zombie_pays_once_however_many_times_it_is_reported() -> void:
	_rules.apply(RulesAction.kill(1, _zombie, false, false))
	_rules.apply(RulesAction.kill(1, _zombie, false, false))
	_rules.apply(RulesAction.kill(2, _zombie, false, false))
	_rules.apply(RulesAction.hit(1, _zombie, false))
	assert_int(_rules.points_of(1)).is_equal(260)
	assert_int(_rules.points_of(2)).is_equal(200)


func test_a_zombie_that_never_existed_pays_nothing() -> void:
	_rules.apply(RulesAction.hit(1, 9999, false))
	_rules.apply(RulesAction.kill(1, 9999, false, false))
	assert_int(_rules.points_of(1)).is_equal(200)


func test_a_downed_player_earns_nothing_but_the_zombie_still_dies() -> void:
	_rules.apply(RulesAction.set_downed(1, true))
	_rules.apply(RulesAction.hit(1, _zombie, false))
	_rules.apply(RulesAction.kill(1, _zombie, false, false))
	assert_int(_rules.points_of(1)).is_equal(200)
	assert_int(_log.count(&"zombie_removed")).is_equal(1)


func test_nothing_is_earned_between_rounds() -> void:
	RulesFixture.run(_rules, 60.0)
	for zombie_id in _log.spawned_ids():
		_rules.apply(RulesAction.kill(1, zombie_id, false, false))
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	var before := _rules.points_of(1)
	_rules.apply(RulesAction.repair(1))
	_rules.apply(RulesAction.hit(1, 1, false))
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
		_rules.apply(RulesAction.kill(1, zombie_id, false, false))
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
