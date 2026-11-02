# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## A downed player's bleed-out, as the rules settle it: the clock, its pause while a teammate holds
## the revive, the death at zero, who counts as dead, the revive counts and the snapshot. The
## `revive` action itself is `test_revive.gd`; the hold is the night server's channel.

const STEP := RulesFixture.STEP

var _rules: GameRules
var _record: RulesFixture


func _night(players: int = 2, tuning: RulesTuning = null) -> void:
	_rules = RulesFixture.make_rules(players, 1234, tuning)
	_record = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)


func _down(player_id: int) -> void:
	_rules.apply(RulesAction.blow(player_id, 1000.0))


## Seconds of ticks, as the server sends them: `held` are the downed players a teammate holds.
func _run(seconds: float, held: Array = []) -> Array[Dictionary]:
	var caused: Array[Dictionary] = []
	for _i in ceili(seconds / STEP - 0.0001):
		caused.append_array(_rules.apply(RulesAction.tick(STEP, held)))
	return caused


func _bleed_seconds() -> float:
	return _rules.tuning.revive.bleed_out_seconds


func test_the_shipped_numbers_are_the_decided_ones() -> void:
	var tuning := RulesFixture.tuning()
	assert_float(tuning.revive.bleed_out_seconds).is_equal(45.0)
	assert_int(tuning.revive.reviver_points).is_equal(0)
	assert_bool(tuning.revive.bleed_stops_while_held).is_true()
	assert_float(tuning.health.revive_seconds).is_equal(3.5)
	assert_float(tuning.health.revive_fraction).is_equal(0.5)
	assert_float(NightTuning.shipped().revive_reach).is_equal(2.0)


func test_a_blow_to_zero_starts_the_bleed_out_clock_and_says_how_long() -> void:
	_night()
	_down(1)
	assert_bool(_rules.players[1].downed).is_true()
	assert_bool(_rules.is_dead(1)).is_false()
	assert_float(_rules.bleed_left_of(1)).is_equal(_bleed_seconds())
	assert_float(_record.of(&"player_downed")[0]["bleed_seconds"]).is_equal(_bleed_seconds())
	assert_float(_rules.bleed_left_of(2)).is_equal(0.0)


func test_a_forced_down_starts_the_clock_too_and_a_forced_get_up_clears_it() -> void:
	_night()
	_rules.apply(RulesAction.set_downed(1, true))
	assert_float(_rules.bleed_left_of(1)).is_equal(_bleed_seconds())
	_rules.apply(RulesAction.set_downed(1, false))
	assert_float(_rules.bleed_left_of(1)).is_equal(0.0)
	assert_float(_rules.health_of(1)).is_equal(_rules.max_health_of(1))


func test_the_clock_runs_down_in_a_round() -> void:
	_night()
	_down(1)
	_run(10.0)
	assert_float(_rules.bleed_left_of(1)).is_equal_approx(_bleed_seconds() - 10.0, 0.05)


func test_the_clock_stands_still_while_a_teammate_holds_the_revive() -> void:
	_night()
	_down(1)
	_run(10.0)
	var left := _rules.bleed_left_of(1)
	_run(10.0, [1])
	assert_float(_rules.bleed_left_of(1)).is_equal(left)
	_run(1.0)
	assert_float(_rules.bleed_left_of(1)).is_less(left)


func test_the_clock_runs_through_a_hold_when_the_tuning_says_so() -> void:
	var tuning := RulesFixture.tuning()
	tuning.revive.bleed_stops_while_held = false
	_night(2, tuning)
	_down(1)
	_run(10.0, [1])
	assert_float(_rules.bleed_left_of(1)).is_less(_bleed_seconds() - 9.0)


func test_a_player_nobody_reaches_bleeds_out_and_is_dead_until_the_round_ends() -> void:
	_night()
	_down(1)
	var caused := _run(_bleed_seconds() + 0.5)
	var died := RulesFixture.first(caused, &"player_died")
	assert_int(died["player_id"]).is_equal(1)
	assert_str(String(died["cause"])).is_equal("bleed_out")
	assert_bool(_rules.is_dead(1)).is_true()
	assert_bool(_rules.players[1].downed).is_true()
	assert_float(_rules.bleed_left_of(1)).is_equal(0.0)
	# Said once, not every tick.
	assert_int(_run(5.0).size()).is_equal(0)


func test_a_dead_player_cannot_be_revived() -> void:
	_night()
	_down(1)
	_run(_bleed_seconds() + 0.5)
	var refused := _rules.apply(RulesAction.revive(2, 1))
	assert_str(String(refused[0]["reason"])).is_equal("target_dead")
	assert_bool(_rules.is_dead(1)).is_true()
	assert_int(_rules.revives_of(2)).is_equal(0)


func test_a_dead_player_counts_as_down_for_the_end_of_the_night() -> void:
	_night()
	_down(1)
	_run(_bleed_seconds() + 0.5)
	var caused := _rules.apply(RulesAction.blow(2, 1000.0))
	var over := RulesFixture.first(caused, &"game_over")
	assert_str(String(over["reason"])).is_equal("all_down")


func test_a_dead_player_gets_up_when_the_round_ends_and_nobody_gets_the_credit() -> void:
	_night()
	_down(1)
	_run(_bleed_seconds() + 0.5)
	var ids := _rules.zombie_ids()
	assert_bool(ids.is_empty()).is_false()
	_rules._plan.clear()
	var caused: Array[Dictionary] = []
	for id in ids:
		caused.append_array(RulesFixture.kill(_rules, 2, id))
	var revived := RulesFixture.first(caused, &"player_revived")
	assert_int(revived["player_id"]).is_equal(1)
	assert_int(revived["reviver_id"]).is_equal(0)
	assert_bool(_rules.is_dead(1)).is_false()
	assert_bool(_rules.players[1].downed).is_false()
	assert_float(_rules.health_of(1)).is_equal(_rules.max_health_of(1))
	assert_int(_rules.revives_of(2)).is_equal(0)
	assert_int(_rules.revives_of(1)).is_equal(0)


func test_a_revive_is_counted_for_the_reviver_and_clears_the_clock() -> void:
	_night()
	_down(1)
	_run(5.0)
	_rules.apply(RulesAction.revive(2, 1))
	assert_int(_rules.revives_of(2)).is_equal(1)
	assert_int(_rules.revives_of(1)).is_equal(0)
	assert_float(_rules.bleed_left_of(1)).is_equal(0.0)
	assert_bool(_rules.is_dead(1)).is_false()
	# Down again, the clock starts from the top.
	_down(1)
	assert_float(_rules.bleed_left_of(1)).is_equal(_bleed_seconds())
	_rules.apply(RulesAction.revive(2, 1))
	assert_int(_rules.revives_of(2)).is_equal(2)
	assert_int(_rules.downs_of(1)).is_equal(2)


func test_a_refused_revive_counts_for_nobody() -> void:
	_night(3)
	_rules.apply(RulesAction.revive(2, 1))
	_down(1)
	_down(2)
	_rules.apply(RulesAction.revive(2, 1))
	assert_int(_rules.revives_of(2)).is_equal(0)


func test_a_revive_can_pay_the_reviver_when_the_tuning_says_so() -> void:
	var tuning := RulesFixture.tuning()
	tuning.revive.reviver_points = 75
	_night(2, tuning)
	_down(1)
	var before := _rules.points_of(2)
	var caused := _rules.apply(RulesAction.revive(2, 1))
	assert_int(_rules.points_of(2)).is_equal(before + 75)
	assert_str(String(RulesFixture.first(caused, &"points_changed")["reason"])).is_equal("revive")


func test_a_revive_pays_nothing_by_default() -> void:
	_night()
	_down(1)
	var before := _rules.points_of(2)
	var caused := _rules.apply(RulesAction.revive(2, 1))
	assert_int(_rules.points_of(2)).is_equal(before)
	assert_dict(RulesFixture.first(caused, &"points_changed")).is_empty()


func test_the_clock_and_a_death_survive_a_snapshot() -> void:
	_night(3)
	_down(1)
	_down(2)
	_run(10.0, [1])
	_run(_bleed_seconds() + 0.5)
	assert_bool(_rules.is_dead(1)).is_true()
	assert_bool(_rules.is_dead(2)).is_true()
	var copy := RulesFixture.make_rules(3)
	assert_str(String(copy.from_dict(_rules.to_dict()))).is_equal("")
	assert_bool(copy.is_dead(1)).is_true()
	assert_bool(copy.is_dead(2)).is_true()
	assert_float(copy.bleed_left_of(1)).is_equal(0.0)
	assert_bool(copy.players[3].downed).is_false()


func test_a_clock_and_the_revive_count_survive_a_snapshot() -> void:
	_night(3)
	_down(1)
	_down(3)
	_rules.apply(RulesAction.revive(2, 3))
	_run(7.0)
	var copy := RulesFixture.make_rules(3)
	assert_str(String(copy.from_dict(_rules.to_dict()))).is_equal("")
	assert_float(copy.bleed_left_of(1)).is_equal_approx(_rules.bleed_left_of(1), 0.0001)
	assert_int(copy.revives_of(2)).is_equal(1)
	assert_dict(copy.to_dict()).is_equal(_rules.to_dict())


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


func test_a_tick_with_a_held_list_is_checked_like_any_action() -> void:
	assert_dict(RulesAction.validate(RulesAction.tick(0.1, [1, 2]))).is_empty()
	var action := RulesAction.tick(0.1, [1])
	action["held"] = "one"
	assert_str(RulesAction.validate(action)["reason"]).is_equal("wrong_type")
	assert_bool(RulesAction.tick(0.1).has("held")).is_false()
