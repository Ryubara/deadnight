extends GdUnitTestSuite
## The boards across the fence's breaches as rules: they start whole, a zombie tears them off, a
## player puts them back (in a break or a round, for points), and every refusal and snapshot is
## exact. Nothing here draws anything.

var _rules: GameRules
var _log: RulesFixture
var _zombie: int
var _boards: int


func before_test() -> void:
	_rules = RulesFixture.make_rules(2)
	_log = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 2.0)
	_zombie = _log.spawned_ids()[0]
	_boards = _rules.tuning.barricades.boards


func test_every_breach_starts_whole() -> void:
	for id in _rules.tuning.barricades.ids:
		assert_int(_rules.barricades.boards_of(id)).is_equal(_boards)
	assert_int(_rules.tuning.barricades.ids.size()).is_equal(6)


func test_a_torn_board_is_announced_and_counted() -> void:
	var events := _rules.apply(RulesAction.tear_board(&"nw", _zombie))
	assert_int(events.size()).is_equal(1)
	assert_str(events[0]["type"]).is_equal("board_torn")
	assert_str(events[0]["barricade_id"]).is_equal("nw")
	assert_int(events[0]["boards"]).is_equal(_boards - 1)
	assert_int(events[0]["zombie_id"]).is_equal(_zombie)
	assert_int(_rules.barricades.boards_of(&"nw")).is_equal(_boards - 1)
	assert_int(_rules.barricades.boards_of(&"ne")).is_equal(_boards)


func test_an_empty_breach_has_nothing_to_tear() -> void:
	for _i in _boards:
		_rules.apply(RulesAction.tear_board(&"nw", _zombie))
	assert_int(_rules.barricades.boards_of(&"nw")).is_equal(0)
	var events := _rules.apply(RulesAction.tear_board(&"nw", _zombie))
	assert_str(events[0]["reason"]).is_equal("no_boards")
	assert_int(_rules.barricades.boards_of(&"nw")).is_equal(0)


func test_only_a_living_zombie_tears_a_board_off_a_known_breach() -> void:
	var events := _rules.apply(RulesAction.tear_board(&"nw", 9999))
	assert_str(events[0]["reason"]).is_equal("unknown_zombie")
	events = _rules.apply(RulesAction.tear_board(&"nowhere", _zombie))
	assert_str(events[0]["reason"]).is_equal("unknown_barricade")
	assert_int(_log.count(&"board_torn")).is_equal(0)


func test_a_repair_puts_one_board_back_and_pays() -> void:
	_rules.apply(RulesAction.tear_board(&"w", _zombie))
	_rules.apply(RulesAction.tear_board(&"w", _zombie))
	var before := _rules.points_of(1)
	var events := _rules.apply(RulesAction.repair(1, &"w"))
	assert_str(events[0]["type"]).is_equal("board_repaired")
	assert_int(events[0]["boards"]).is_equal(_boards - 1)
	assert_int(events[0]["player_id"]).is_equal(1)
	assert_str(events[1]["type"]).is_equal("points_changed")
	assert_str(events[1]["reason"]).is_equal("repair")
	assert_int(_rules.points_of(1)).is_equal(before + _rules.tuning.economy.repair)
	assert_int(_rules.barricades.boards_of(&"w")).is_equal(_boards - 1)


func test_a_whole_breach_cannot_be_repaired_for_points() -> void:
	var before := _rules.points_of(1)
	var events := _rules.apply(RulesAction.repair(1, &"nw"))
	assert_int(events.size()).is_equal(1)
	assert_str(events[0]["reason"]).is_equal("barricade_full")
	assert_str(events[0]["field"]).is_equal("barricade_id")
	assert_int(_rules.points_of(1)).is_equal(before)


func test_an_unknown_breach_or_player_is_refused() -> void:
	assert_str(_rules.apply(RulesAction.repair(1, &"nowhere"))[0]["reason"]).is_equal(
		"unknown_barricade"
	)
	assert_str(_rules.apply(RulesAction.repair(99, &"nw"))[0]["reason"]).is_equal("unknown_player")


func test_a_downed_player_cannot_repair() -> void:
	_rules.apply(RulesAction.tear_board(&"nw", _zombie))
	_rules.apply(RulesAction.set_downed(1, true))
	var events := _rules.apply(RulesAction.repair(1, &"nw"))
	assert_str(events[0]["reason"]).is_equal("player_downed")
	assert_int(_rules.barricades.boards_of(&"nw")).is_equal(_boards - 1)


func test_repairs_are_for_a_break_or_a_round_not_the_waiting() -> void:
	var waiting := RulesFixture.make_rules(1)
	var events := waiting.apply(RulesAction.repair(1, &"nw"))
	assert_str(events[0]["reason"]).is_equal("wrong_phase")


func test_a_repair_in_the_break_puts_the_board_up_and_pays() -> void:
	_rules.apply(RulesAction.tear_board(&"e", _zombie))
	RulesFixture.run(_rules, 60.0)
	for zombie_id in _log.spawned_ids():
		if _rules.has_zombie(zombie_id):
			RulesFixture.kill(_rules, 1, zombie_id)
	assert_int(_rules.phase).is_equal(GameRules.Phase.BREAK)
	var before := _rules.points_of(1)
	_rules.apply(RulesAction.repair(1, &"e"))
	assert_int(_rules.barricades.boards_of(&"e")).is_equal(_boards)
	assert_int(_rules.points_of(1)).is_equal(before + _rules.tuning.economy.repair)


func test_the_boards_ride_the_snapshot() -> void:
	_rules.apply(RulesAction.tear_board(&"n", _zombie))
	_rules.apply(RulesAction.tear_board(&"n", _zombie))
	_rules.apply(RulesAction.tear_board(&"ne", _zombie))
	var copy := GameRules.new(RulesFixture.tuning(), 1234)
	assert_str(copy.from_bytes(_rules.to_bytes())).is_equal("")
	assert_int(copy.barricades.boards_of(&"n")).is_equal(_boards - 2)
	assert_int(copy.barricades.boards_of(&"ne")).is_equal(_boards - 1)
	assert_int(copy.barricades.boards_of(&"w")).is_equal(_boards)
	assert_dict(copy.to_dict()).is_equal(_rules.to_dict())


func test_a_snapshot_with_bad_boards_is_malformed_and_changes_nothing() -> void:
	var good := _rules.to_dict()
	for bad: Dictionary in [
		{&"nw": _boards + 1, &"ne": 1, &"w": 1, &"e": 1, &"n": 1, &"n2": 1},
		{&"nw": -1, &"ne": 1, &"w": 1, &"e": 1, &"n": 1, &"n2": 1},
		{&"nw": 1, &"ne": 1, &"w": 1, &"e": 1, &"n": 1},
		{&"nw": 1, &"ne": 1, &"w": 1, &"e": 1, &"n": 1, &"n2": 1, &"extra": 1},
		{&"nw": "5", &"ne": 1, &"w": 1, &"e": 1, &"n": 1, &"n2": 1},
	]:
		var snapshot := good.duplicate(true)
		snapshot["barricades"] = bad
		var target := GameRules.new(RulesFixture.tuning(), 1234)
		var before := target.to_dict()
		assert_str(target.from_dict(snapshot)).is_equal("malformed")
		assert_dict(target.to_dict()).is_equal(before)


func test_the_same_actions_make_the_same_boards() -> void:
	var other := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(other)
	RulesFixture.run(other, 2.0)
	for rules: GameRules in [_rules, other]:
		rules.apply(RulesAction.tear_board(&"n2", rules.zombie_ids()[0]))
		rules.apply(RulesAction.tear_board(&"n2", rules.zombie_ids()[0]))
		rules.apply(RulesAction.repair(2, &"n2"))
	assert_dict(_rules.barricades.to_dict()).is_equal(other.barricades.to_dict())
