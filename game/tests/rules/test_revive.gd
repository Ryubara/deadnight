extends GdUnitTestSuite
## A teammate raising a downed player: the `revive` action, what it refuses and what it changes.
## The channel (3.5 seconds of holding use beside them) is the night server's
## (`tests/night/test_night_revive.gd`); the rules only take the finished action.

var _t: RulesTuning
var _rules: GameRules
var _log: RulesFixture


func before_test() -> void:
	_t = RulesFixture.tuning()
	_rules = RulesFixture.make_rules(3, 1234, _t)
	_log = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)


func _down(player_id: int) -> void:
	_rules.apply(RulesAction.blow(player_id, 500.0))


func _revive(reviver: int, target: int) -> Array[Dictionary]:
	return _rules.apply(RulesAction.revive(reviver, target))


func _reason(events: Array[Dictionary]) -> String:
	assert_str(events[0]["type"]).is_equal("action_rejected")
	assert_str(events[0]["action"]).is_equal("revive")
	return str(events[0]["reason"])


func test_the_shipped_numbers_are_three_and_a_half_seconds_and_half_health() -> void:
	assert_float(_t.health.revive_seconds).is_equal(3.5)
	assert_float(_t.health.revive_fraction).is_equal(0.5)


func test_a_teammate_gets_a_downed_player_up_with_half_their_health() -> void:
	_down(2)
	var events := _revive(1, 2)
	(
		assert_array(events.map(func(e: Dictionary) -> StringName: return e["type"]))
		. contains_exactly([&"player_healed", &"player_revived"])
	)
	assert_str(events[0]["reason"]).is_equal("revive")
	assert_float(events[0]["health"]).is_equal(50.0)
	assert_int(events[1]["player_id"]).is_equal(2)
	assert_int(events[1]["reviver_id"]).is_equal(1)
	assert_bool(_rules.players[2].downed).is_false()
	assert_float(_rules.health_of(2)).is_equal(50.0)
	# The reviver is untouched, and the one raised mends again after the usual wait.
	assert_float(_rules.health_of(1)).is_equal(100.0)
	assert_float(_rules.players[2].since_blow).is_equal(0.0)
	RulesFixture.run(_rules, _t.health.regen_delay - 1.0)
	assert_float(_rules.health_of(2)).is_equal(50.0)
	RulesFixture.run(_rules, 3.0)
	assert_float(_rules.health_of(2)).is_greater(50.0)


func test_the_end_of_a_round_still_gets_everyone_up_with_all_their_health() -> void:
	RulesFixture.run(_rules, 60.0)
	_down(2)
	_down(3)
	for zombie_id in _log.spawned_ids():
		_rules.apply(RulesAction.zombie_gone(zombie_id))
	assert_int(_log.count(&"player_revived")).is_equal(2)
	assert_int(_log.of(&"player_revived")[0]["reviver_id"]).is_equal(0)
	assert_bool(_rules.players[2].downed).is_false()
	assert_float(_rules.health_of(2)).is_equal(100.0)


func test_a_downed_reviver_a_stranger_and_oneself_are_refused() -> void:
	_down(2)
	_down(3)
	assert_str(_reason(_revive(3, 2))).is_equal("player_downed")
	assert_str(_reason(_revive(9, 2))).is_equal("unknown_player")
	assert_str(_reason(_revive(1, 9))).is_equal("unknown_player")
	assert_str(_reason(_revive(2, 2))).is_equal("self_revive")
	assert_bool(_rules.players[2].downed).is_true()


func test_a_player_who_is_up_cannot_be_revived() -> void:
	var before := _rules.to_dict()
	assert_str(_reason(_revive(1, 2))).is_equal("not_downed")
	assert_dict(_rules.to_dict()).is_equal(before)


func test_a_revive_outside_a_round_is_refused() -> void:
	var idle := RulesFixture.make_rules(2)
	assert_str(idle.apply(RulesAction.revive(1, 2))[0]["reason"]).is_equal("wrong_phase")


func test_the_action_is_checked_like_every_other() -> void:
	assert_dict(RulesAction.validate(RulesAction.revive(1, 2))).is_empty()
	var action := RulesAction.revive(1, 2)
	action.erase("target_id")
	assert_str(RulesAction.validate(action)["reason"]).is_equal("missing_field")
	action["target_id"] = "two"
	assert_str(RulesAction.validate(action)["reason"]).is_equal("wrong_type")


func test_a_snapshot_taken_after_a_revive_restores_the_same_night() -> void:
	_down(2)
	_revive(1, 2)
	var copy := GameRules.new(_t, 1234)
	assert_str(copy.from_dict(_rules.to_dict())).is_equal("")
	assert_dict(copy.to_dict()).is_equal(_rules.to_dict())
	assert_bool(copy.players[2].downed).is_false()
	assert_float(copy.health_of(2)).is_equal(50.0)


func test_a_night_with_the_last_player_down_ends_unless_a_revive_came_first() -> void:
	_down(1)
	_down(2)
	_revive(3, 1)
	var events := _rules.apply(RulesAction.blow(3, 500.0))
	# Player 1 is up again (50 health), so the night goes on with them.
	(
		assert_bool(events.any(func(e: Dictionary) -> bool: return e["type"] == &"game_over"))
		. is_false()
	)
