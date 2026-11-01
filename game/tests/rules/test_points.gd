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
	# The event says how many grenades they start with, so a client need not know the tuning.
	assert_int(events[0]["grenades"]).is_equal(fresh.grenades_of(7))
	assert_int(events[1]["total"]).is_equal(200)
	assert_str(events[1]["reason"]).is_equal("start")


func test_a_hit_earns_nothing_between_rounds() -> void:
	RulesFixture.run(_rules, 60.0)
	for zombie_id in _log.spawned_ids():
		RulesFixture.kill(_rules, 1, zombie_id)
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	var before := _rules.points_of(1)
	_rules.apply(RulesAction.hit(1, 1, RulesAction.ZONE_BODY, 20.0))
	assert_int(_rules.points_of(1)).is_equal(before)


func test_repairs_pay_up_to_a_cap_each_round() -> void:
	_break_every_board()
	for id in _rules.tuning.barricades.ids:
		for _i in _rules.tuning.barricades.boards:
			_rules.apply(RulesAction.repair(1, id))
	assert_int(_rules.points_of(1)).is_equal(200 + 120)
	assert_int(_rules.points_of(2)).is_equal(200)
	# The boards went up all the same: the cap only stops the pay.
	assert_int(_rules.barricades.boards_of(&"nw")).is_equal(_rules.tuning.barricades.boards)


func test_the_repair_cap_runs_from_one_rounds_end_to_the_next() -> void:
	_break_every_board()
	_end_the_round()
	var before := _rules.points_of(1)
	# In the break the repairs pay, against the same cap the next round's repairs draw on.
	_repair(&"nw")
	_repair(&"ne")
	_repair(&"w")
	assert_int(_rules.points_of(1)).is_equal(before + 120)
	_rules.apply(RulesAction.skip_break())
	_repair(&"e")
	assert_int(_rules.points_of(1)).is_equal(before + 120)
	_end_the_round()
	var after_the_bonus := _rules.points_of(1)
	_repair(&"n")
	assert_int(_rules.points_of(1)).is_equal(after_the_bonus + 5 * 12)


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


## Every board of every breach off, by the zombie the round spawned.
func _break_every_board() -> void:
	for id in _rules.tuning.barricades.ids:
		for _i in _rules.tuning.barricades.boards:
			_rules.apply(RulesAction.tear_board(id, _zombie))


## Player 1 puts every board of one breach back.
func _repair(id: StringName) -> void:
	for _i in _rules.tuning.barricades.boards:
		_rules.apply(RulesAction.repair(1, id))


## Plays the round out: its zombies fall and the break begins.
func _end_the_round() -> void:
	RulesFixture.run(_rules, 60.0)
	for zombie_id in _log.spawned_ids():
		if _rules.has_zombie(zombie_id):
			RulesFixture.kill(_rules, 1, zombie_id)
