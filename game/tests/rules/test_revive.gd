# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## Getting a downed player back up, as the rules settle it: the bleed-out clock, a teammate's hold,
## its interruptions, the death at zero, the counts, the snapshot and the round's end.

const STEP := RulesFixture.STEP

var _rules: GameRules
var _record: RulesFixture


func _night(players: int = 2, tuning: RulesTuning = null) -> void:
	_rules = RulesFixture.make_rules(players, 1234, tuning)
	_record = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)


func _down(player_id: int) -> void:
	_rules.apply(RulesAction.blow(player_id, 1000.0))


## Holds the revive for `seconds` in whole steps, as the server would, one tick then one hold.
func _hold(target: int, reviver: int, seconds: float) -> Array[Dictionary]:
	var caused: Array[Dictionary] = []
	for _i in ceili(seconds / STEP - 0.0001):
		caused.append_array(_rules.apply(RulesAction.tick(STEP)))
		caused.append_array(_rules.apply(RulesAction.revive_hold(target, reviver, STEP)))
	return caused


func _seconds() -> float:
	return _rules.tuning.revive.revive_seconds


func test_the_shipped_numbers_are_the_designed_ones() -> void:
	var revive := RulesFixture.tuning().revive
	assert_float(revive.bleed_out_seconds).is_equal(45.0)
	assert_float(revive.revive_seconds).is_equal(3.5)
	assert_float(revive.reach).is_equal(2.0)
	assert_float(revive.health_fraction).is_equal(0.5)
	assert_int(revive.reviver_points).is_equal(0)
	assert_bool(revive.bleed_stops_while_held).is_true()


func test_a_blow_to_zero_starts_the_bleed_out_clock_and_says_how_long() -> void:
	_night()
	_down(1)
	assert_bool(_rules.players[1].downed).is_true()
	assert_bool(_rules.is_dead(1)).is_false()
	assert_float(_rules.bleed_left_of(1)).is_equal(_rules.tuning.revive.bleed_out_seconds)
	var downed := _record.of(&"player_downed")[0]
	assert_float(downed["bleed_seconds"]).is_equal(_rules.tuning.revive.bleed_out_seconds)
	assert_float(_rules.bleed_left_of(2)).is_equal(0.0)


func test_the_clock_runs_down_in_a_round() -> void:
	_night()
	_down(1)
	RulesFixture.run(_rules, 10.0)
	assert_float(_rules.bleed_left_of(1)).is_equal_approx(
		_rules.tuning.revive.bleed_out_seconds - 10.0, 0.05
	)


func test_a_hold_for_the_whole_time_gets_the_player_up_and_names_the_reviver() -> void:
	_night()
	_down(1)
	var caused := _hold(1, 2, _seconds() + 0.1)
	var started := RulesFixture.first(caused, &"revive_started")
	assert_int(started["player_id"]).is_equal(1)
	assert_int(started["reviver_id"]).is_equal(2)
	assert_float(started["seconds"]).is_equal(_seconds())
	var revived := RulesFixture.first(caused, &"player_revived")
	assert_int(revived["player_id"]).is_equal(1)
	assert_int(revived["reviver_id"]).is_equal(2)
	var healed := RulesFixture.first(caused, &"player_healed")
	assert_str(String(healed["reason"])).is_equal("revive")
	assert_bool(_rules.players[1].downed).is_false()
	assert_float(_rules.health_of(1)).is_equal_approx(
		_rules.max_health_of(1) * _rules.tuning.revive.health_fraction, 0.001
	)
	assert_float(_rules.bleed_left_of(1)).is_equal(0.0)
	assert_int(_rules.revives_of(2)).is_equal(1)
	assert_int(_rules.revives_of(1)).is_equal(0)


func test_a_hold_that_is_one_tick_short_does_not_get_the_player_up() -> void:
	_night()
	_down(1)
	_hold(1, 2, _seconds() - 0.1)
	assert_bool(_rules.players[1].downed).is_true()
	assert_float(_rules.revive_fraction_of(1)).is_greater(0.9)
	assert_int(_rules.reviver_of(1)).is_equal(2)
	assert_int(_rules.revives_of(2)).is_equal(0)


func test_a_hold_that_is_not_renewed_is_released_at_the_next_tick_and_starts_over() -> void:
	_night()
	_down(1)
	_hold(1, 2, 1.5)
	assert_float(_rules.revive_fraction_of(1)).is_greater(0.0)
	var caused := _rules.apply(RulesAction.tick(STEP))
	assert_float(_rules.revive_fraction_of(1)).is_greater(0.0)
	assert_int(_record.of(&"revive_interrupted").size()).is_equal(0)
	caused = _rules.apply(RulesAction.tick(STEP))
	var stopped := RulesFixture.first(caused, &"revive_interrupted")
	assert_str(String(stopped["reason"])).is_equal("released")
	assert_int(stopped["reviver_id"]).is_equal(2)
	assert_float(_rules.revive_fraction_of(1)).is_equal(0.0)
	assert_int(_rules.reviver_of(1)).is_equal(0)
	# A new hold needs the whole time again.
	_hold(1, 2, _seconds() - 0.2)
	assert_bool(_rules.players[1].downed).is_true()


func test_an_explicit_release_clears_the_hold_with_its_reason() -> void:
	_night()
	_down(1)
	_hold(1, 2, 1.0)
	var caused := _rules.apply(RulesAction.revive_release(1, &"away"))
	var stopped := RulesFixture.first(caused, &"revive_interrupted")
	assert_str(String(stopped["reason"])).is_equal("away")
	assert_float(_rules.revive_fraction_of(1)).is_equal(0.0)
	# Nothing to release: nothing is said.
	assert_int(_rules.apply(RulesAction.revive_release(1, &"away")).size()).is_equal(0)


func test_a_reviver_who_goes_down_breaks_the_hold() -> void:
	_night(3)
	_down(1)
	_hold(1, 2, 1.0)
	var caused := _rules.apply(RulesAction.blow(2, 1000.0))
	var stopped := RulesFixture.first(caused, &"revive_interrupted")
	assert_str(String(stopped["reason"])).is_equal("reviver_downed")
	assert_int(stopped["player_id"]).is_equal(1)
	assert_float(_rules.revive_fraction_of(1)).is_equal(0.0)
	assert_bool(_rules.players[1].downed).is_true()


func test_a_reviver_who_leaves_breaks_the_hold() -> void:
	_night(3)
	_down(1)
	_hold(1, 2, 1.0)
	var caused := _rules.apply(RulesAction.remove_player(2))
	assert_str(String(RulesFixture.first(caused, &"revive_interrupted")["reason"])).is_equal("left")
	assert_int(_rules.reviver_of(1)).is_equal(0)


func test_the_clock_stands_still_while_the_revive_is_held() -> void:
	_night()
	_down(1)
	_hold(1, 2, 1.0)
	var left := _rules.bleed_left_of(1)
	_hold(1, 2, 1.0)
	assert_float(_rules.bleed_left_of(1)).is_equal_approx(left, 0.05)


func test_the_clock_runs_through_a_hold_when_the_tuning_says_so() -> void:
	var tuning := RulesFixture.tuning()
	tuning.revive.bleed_stops_while_held = false
	_night(2, tuning)
	_down(1)
	_hold(1, 2, 1.0)
	assert_float(_rules.bleed_left_of(1)).is_less(tuning.revive.bleed_out_seconds - 0.9)


func test_a_player_nobody_reaches_bleeds_out_and_is_dead_until_the_round_ends() -> void:
	_night()
	_down(1)
	var caused := RulesFixture.advance(_rules, _rules.tuning.revive.bleed_out_seconds + 0.5, 0.1)
	var died := RulesFixture.first(caused, &"player_died")
	assert_int(died["player_id"]).is_equal(1)
	assert_str(String(died["cause"])).is_equal("bleed_out")
	assert_bool(_rules.is_dead(1)).is_true()
	assert_bool(_rules.players[1].downed).is_true()
	assert_float(_rules.bleed_left_of(1)).is_equal(0.0)
	# Dead is dead: nobody revives it, and nothing is said twice.
	var again := _rules.apply(RulesAction.revive_hold(1, 2, STEP))
	assert_str(String(again[0]["reason"])).is_equal("target_dead")
	assert_int(RulesFixture.advance(_rules, 5.0, 0.1).size()).is_equal(0)


func test_a_dead_player_counts_as_down_for_the_end_of_the_night() -> void:
	_night()
	_down(1)
	RulesFixture.advance(_rules, _rules.tuning.revive.bleed_out_seconds + 0.5, 0.1)
	assert_bool(_rules.is_dead(1)).is_true()
	var caused := _rules.apply(RulesAction.blow(2, 1000.0))
	var over := RulesFixture.first(caused, &"game_over")
	assert_str(String(over["reason"])).is_equal("all_down")


func test_a_dead_player_gets_up_when_the_round_ends_and_nobody_gets_the_credit() -> void:
	_night()
	_down(1)
	RulesFixture.advance(_rules, _rules.tuning.revive.bleed_out_seconds + 0.5, 0.1)
	var ids := _rules.zombie_ids()
	assert_bool(ids.is_empty()).is_false()
	# End the round: every living zombie falls and the plan is spent.
	_rules._plan.clear()
	var caused: Array[Dictionary] = []
	for id in ids:
		caused.append_array(RulesFixture.kill(_rules, 2, id))
	var revived := RulesFixture.first(caused, &"player_revived")
	assert_int(revived["player_id"]).is_equal(1)
	assert_int(revived["reviver_id"]).is_equal(-1)
	assert_bool(_rules.is_dead(1)).is_false()
	assert_bool(_rules.players[1].downed).is_false()
	assert_float(_rules.health_of(1)).is_equal(_rules.max_health_of(1))
	assert_int(_rules.revives_of(2)).is_equal(0)
	assert_int(_rules.revives_of(1)).is_equal(0)


func test_the_rules_refuse_what_cannot_be_revived() -> void:
	_night(3)
	# Nobody is down yet.
	assert_str(String(_rules.apply(RulesAction.revive_hold(1, 2, STEP))[0]["reason"])).is_equal(
		"not_downed"
	)
	_down(1)
	assert_str(String(_rules.apply(RulesAction.revive_hold(1, 1, STEP))[0]["reason"])).is_equal(
		"self_revive"
	)
	assert_str(String(_rules.apply(RulesAction.revive_hold(1, 9, STEP))[0]["reason"])).is_equal(
		"unknown_player"
	)
	assert_str(String(_rules.apply(RulesAction.revive_hold(9, 2, STEP))[0]["reason"])).is_equal(
		"unknown_player"
	)
	_down(2)
	assert_str(String(_rules.apply(RulesAction.revive_hold(1, 2, STEP))[0]["reason"])).is_equal(
		"reviver_downed"
	)
	assert_int(_rules.revives_of(2)).is_equal(0)


func test_a_second_reviver_is_turned_away_while_the_first_holds() -> void:
	_night(3)
	_down(1)
	_rules.apply(RulesAction.revive_hold(1, 2, STEP))
	var refused := _rules.apply(RulesAction.revive_hold(1, 3, STEP))
	assert_str(String(refused[0]["reason"])).is_equal("busy")
	assert_int(_rules.reviver_of(1)).is_equal(2)


func test_nothing_is_revived_outside_a_round() -> void:
	_rules = RulesFixture.make_rules(2)
	_rules.apply(RulesAction.set_downed(1, true))
	var refused := _rules.apply(RulesAction.revive_hold(1, 2, STEP))
	assert_str(String(refused[0]["reason"])).is_equal("wrong_phase")


func test_a_revive_can_pay_the_reviver_when_the_tuning_says_so() -> void:
	var tuning := RulesFixture.tuning()
	tuning.revive.reviver_points = 75
	_night(2, tuning)
	_down(1)
	var before := _rules.points_of(2)
	var caused := _hold(1, 2, _seconds() + 0.1)
	assert_int(_rules.points_of(2)).is_equal(before + 75)
	var paid := RulesFixture.first(caused, &"points_changed")
	assert_str(String(paid["reason"])).is_equal("revive")


func test_a_player_can_be_revived_more_than_once_and_each_is_counted() -> void:
	_night()
	for round_trip in 3:
		_down(1)
		_hold(1, 2, _seconds() + 0.1)
		assert_bool(_rules.players[1].downed).is_false()
	assert_int(_rules.revives_of(2)).is_equal(3)
	assert_int(_rules.downs_of(1)).is_equal(3)


func test_a_forced_down_starts_the_clock_too() -> void:
	_night()
	_rules.apply(RulesAction.set_downed(1, true))
	assert_float(_rules.bleed_left_of(1)).is_equal(_rules.tuning.revive.bleed_out_seconds)
	# And a forced get-up by the server restores all health and clears the clock.
	_rules.apply(RulesAction.set_downed(1, false))
	assert_float(_rules.bleed_left_of(1)).is_equal(0.0)
	assert_float(_rules.health_of(1)).is_equal(_rules.max_health_of(1))


func test_the_clock_a_hold_and_a_death_survive_a_snapshot() -> void:
	_night(3)
	_down(1)
	_down(2)
	RulesFixture.advance(_rules, _rules.tuning.revive.bleed_out_seconds + 0.5, 0.1)
	assert_bool(_rules.is_dead(2)).is_true()
	var copy := RulesFixture.make_rules(3)
	assert_str(String(copy.from_dict(_rules.to_dict()))).is_equal("")
	assert_bool(copy.is_dead(1)).is_true()
	assert_bool(copy.is_dead(2)).is_true()
	assert_float(copy.bleed_left_of(1)).is_equal(0.0)
	assert_bool(copy.players[3].downed).is_false()


func test_a_hold_and_the_revive_count_survive_a_snapshot() -> void:
	_night(3)
	_down(1)
	_hold(1, 2, 1.2)
	var copy := RulesFixture.make_rules(3)
	assert_str(String(copy.from_dict(_rules.to_dict()))).is_equal("")
	assert_int(copy.reviver_of(1)).is_equal(2)
	assert_float(copy.revive_fraction_of(1)).is_equal_approx(_rules.revive_fraction_of(1), 0.0001)
	assert_float(copy.bleed_left_of(1)).is_equal_approx(_rules.bleed_left_of(1), 0.0001)
	_hold(1, 2, _seconds())
	assert_int(_rules.revives_of(2)).is_equal(1)
	var after := RulesFixture.make_rules(3)
	assert_str(String(after.from_dict(_rules.to_dict()))).is_equal("")
	assert_int(after.revives_of(2)).is_equal(1)


func test_the_last_layout_without_revives_is_refused() -> void:
	_night()
	var old := _rules.to_dict()
	old["version"] = 11
	assert_str(String(RulesFixture.make_rules(2).from_dict(old))).is_equal(
		String(GameRules.RESTORE_BAD_VERSION)
	)


func test_a_snapshot_with_a_dead_player_who_is_up_is_refused() -> void:
	_night()
	var data := _rules.to_dict()
	data["players"][1]["dead"] = true
	assert_str(String(RulesFixture.make_rules(2).from_dict(data))).is_equal(
		String(GameRules.RESTORE_MALFORMED)
	)
	data = _rules.to_dict()
	data["players"][1]["bleed_left"] = -1.0
	assert_str(String(RulesFixture.make_rules(2).from_dict(data))).is_equal(
		String(GameRules.RESTORE_MALFORMED)
	)


func test_a_hold_with_a_bad_delta_is_refused_by_the_schema() -> void:
	_night()
	_down(1)
	var refused := _rules.apply(RulesAction.revive_hold(1, 2, -1.0))
	assert_str(String(refused[0]["reason"])).is_equal("out_of_range")
	assert_str(String(_rules.apply(RulesAction.revive_hold(1, 2, NAN))[0]["reason"])).is_equal(
		"out_of_range"
	)
	assert_float(_rules.revive_fraction_of(1)).is_equal(0.0)
