extends GdUnitTestSuite
## The rules own the player's health: blows, downs, mending and the events that say so. The
## night server only turns a zombie's swing into a `blow` action.

const STEP := RulesFixture.STEP

var _t: RulesTuning
var _rules: GameRules
var _log: RulesFixture


func before_test() -> void:
	_t = RulesFixture.tuning()
	_rules = RulesFixture.make_rules(2, 1234, _t)
	_log = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)
	_log.events.clear()


func _blow(player_id: int, damage: float, bearing := 0.0, source := -1) -> Array[Dictionary]:
	return _rules.apply(RulesAction.blow(player_id, damage, bearing, source))


func _of(events: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> StringName: return event["type"])


## Ticks `seconds` and returns the `player_healed` events of them.
func _mend_for(seconds: float) -> Array[Dictionary]:
	var healed: Array[Dictionary] = []
	for _i in ceili(seconds / STEP):
		healed.append_array(_of(_rules.apply(RulesAction.tick(STEP)), &"player_healed"))
	return healed


func test_a_player_starts_with_the_tuned_health_and_the_event_says_so() -> void:
	var rules := GameRules.new(_t, 1)
	var added := rules.apply(RulesAction.add_player(1))
	assert_float(added[0]["health"]).is_equal(_t.health.max_health)
	assert_float(added[0]["max_health"]).is_equal(_t.health.max_health)
	assert_float(rules.health_of(1)).is_equal(100.0)
	assert_float(rules.max_health_of(1)).is_equal(100.0)


func test_the_shipped_numbers_are_the_nights() -> void:
	# 100 health, mending after 5 s without a blow, 25 a second (docs/design/rounds.md).
	assert_float(_t.health.max_health).is_equal(100.0)
	assert_float(_t.health.regen_delay).is_equal(5.0)
	assert_float(_t.health.regen_per_second).is_equal(25.0)


func test_a_blow_takes_health_off_and_names_where_it_came_from() -> void:
	var events := _blow(1, 15.0, 1.25, 7)
	assert_int(events.size()).is_equal(1)
	var hurt := events[0]
	assert_str(hurt["type"]).is_equal("player_hurt")
	assert_int(hurt["player_id"]).is_equal(1)
	assert_float(hurt["damage"]).is_equal(15.0)
	assert_float(hurt["health"]).is_equal(85.0)
	assert_float(hurt["max_health"]).is_equal(100.0)
	assert_float(hurt["bearing"]).is_equal(1.25)
	assert_int(hurt["source_id"]).is_equal(7)
	assert_float(_rules.health_of(1)).is_equal(85.0)
	# The other player is untouched.
	assert_float(_rules.health_of(2)).is_equal(100.0)


func test_a_blow_that_empties_health_downs_the_player_with_the_direction() -> void:
	var events := _blow(1, 120.0, -0.75, 3)
	assert_array(_types(events)).contains_exactly([&"player_hurt", &"player_downed"])
	assert_float(events[0]["health"]).is_equal(0.0)
	# Only what was there is damage taken.
	assert_float(events[0]["damage"]).is_equal(100.0)
	assert_str(events[1]["cause"]).is_equal("blow")
	assert_float(events[1]["bearing"]).is_equal(-0.75)
	assert_bool(_rules.players[1].downed).is_true()
	assert_float(_rules.health_of(1)).is_equal(0.0)


func test_a_blow_says_what_it_was_and_whose_and_a_zombie_swing_says_none() -> void:
	var swing := _blow(1, 10.0, 0.0, 4)
	assert_str(swing[0]["harm"]).is_equal("")
	assert_int(swing[0]["by_id"]).is_equal(0)
	var blast := _rules.apply(RulesAction.blow(2, 30.0, 0.5, -1, &"grenade", 1))
	assert_str(blast[0]["harm"]).is_equal("grenade")
	assert_int(blast[0]["by_id"]).is_equal(1)
	# The down that follows carries the same, so the feed can say "blown up by".
	var downing := _rules.apply(RulesAction.blow(2, 500.0, 0.5, -1, &"grenade", 1))
	assert_array(_types(downing)).contains_exactly([&"player_hurt", &"player_downed"])
	assert_str(downing[1]["harm"]).is_equal("grenade")
	assert_int(downing[1]["by_id"]).is_equal(1)


func test_the_last_player_going_down_ends_the_night() -> void:
	_blow(1, 500.0)
	var events := _blow(2, 500.0)
	var over := _of(events, &"game_over")
	assert_int(over.size()).is_equal(1)
	assert_str(over[0]["reason"]).is_equal("all_down")


func test_a_downed_player_takes_no_more_blows() -> void:
	_blow(1, 500.0)
	var before := _rules.to_dict()
	var events := _blow(1, 10.0)
	assert_int(events.size()).is_equal(1)
	assert_str(events[0]["type"]).is_equal("action_rejected")
	assert_str(events[0]["reason"]).is_equal("player_downed")
	assert_dict(_rules.to_dict()).is_equal(before)


func test_a_blow_outside_a_round_or_on_nobody_is_refused() -> void:
	var idle := RulesFixture.make_rules(1)
	assert_str(idle.apply(RulesAction.blow(1, 5.0))[0]["reason"]).is_equal("wrong_phase")
	assert_str(_blow(9, 5.0)[0]["reason"]).is_equal("unknown_player")


func test_forcing_a_down_empties_health_too() -> void:
	var events := _rules.apply(RulesAction.set_downed(1, true))
	assert_str(events[0]["type"]).is_equal("player_downed")
	assert_str(events[0]["cause"]).is_equal("forced")
	assert_float(_rules.health_of(1)).is_equal(0.0)


func test_health_stays_put_until_the_wait_is_over_then_mends_at_the_tuned_rate() -> void:
	_blow(1, 60.0)
	assert_int(_mend_for(_t.health.regen_delay - 0.1).size()).is_equal(0)
	assert_float(_rules.health_of(1)).is_equal(40.0)
	# One second after the wait: 25 health a second.
	_mend_for(0.1 + 1.0)
	assert_float(_rules.health_of(1)).is_equal_approx(65.0, 0.6)


func test_mending_stops_at_the_most_and_announces_whole_units_only() -> void:
	_blow(1, 10.0)
	var healed := _mend_for(_t.health.regen_delay + 2.0)
	assert_float(_rules.health_of(1)).is_equal(100.0)
	# Ten units mended: ten announcements at most, never one a tick (that would be 120).
	assert_int(healed.size()).is_between(1, 11)
	for event in healed:
		assert_str(event["reason"]).is_equal("regen")
		assert_int(event["player_id"]).is_equal(1)
		assert_float(event["max_health"]).is_equal(100.0)
	assert_float(healed[-1]["health"]).is_equal(100.0)
	# Full health announces nothing more.
	assert_int(_mend_for(1.0).size()).is_equal(0)


func test_a_new_blow_restarts_the_wait() -> void:
	_blow(1, 50.0)
	_mend_for(_t.health.regen_delay - 0.5)
	_blow(1, 10.0)
	assert_float(_rules.health_of(1)).is_equal(40.0)
	_mend_for(_t.health.regen_delay - 0.5)
	assert_float(_rules.health_of(1)).is_equal(40.0)
	_mend_for(1.5)
	assert_float(_rules.health_of(1)).is_greater(40.0)


func test_a_downed_player_does_not_mend() -> void:
	_blow(1, 500.0)
	assert_int(_mend_for(_t.health.regen_delay + 2.0).size()).is_equal(0)
	assert_float(_rules.health_of(1)).is_equal(0.0)


func test_getting_up_gives_all_the_health_back() -> void:
	_blow(1, 500.0)
	var events := _rules.apply(RulesAction.set_downed(1, false))
	assert_array(_types(events)).contains_exactly([&"player_healed", &"player_revived"])
	assert_str(events[0]["reason"]).is_equal("revive")
	assert_float(events[0]["health"]).is_equal(100.0)
	assert_float(_rules.health_of(1)).is_equal(100.0)


func test_a_round_ending_lifts_the_downed_with_full_health() -> void:
	var rules := RulesFixture.make_rules(2, 11, _t)
	RulesFixture.into_round_one(rules)
	rules._plan.assign([&"walker"])
	RulesFixture.run(rules, 2.0)
	rules.apply(RulesAction.blow(1, 500.0))
	var events := RulesFixture.kill(rules, 2, rules.zombie_ids()[0])
	assert_int(rules.phase).is_equal(GameRules.Phase.BREAK)
	assert_array(_of(events, &"player_healed")).has_size(1)
	assert_bool(rules.players[1].downed).is_false()
	assert_float(rules.health_of(1)).is_equal(100.0)


func test_health_survives_a_snapshot_with_its_wait() -> void:
	_blow(1, 30.0, 0.5, 2)
	_mend_for(2.0)
	var copy := GameRules.new(_t, 99)
	assert_str(copy.from_dict(_rules.to_dict())).is_equal("")
	assert_float(copy.health_of(1)).is_equal(70.0)
	assert_float(copy.players[1].since_blow).is_equal_approx(2.0, 0.02)
	# Both go on the same way: the copy mends exactly as the original does.
	for _i in 600:
		_rules.apply(RulesAction.tick(STEP))
		copy.apply(RulesAction.tick(STEP))
	assert_float(copy.health_of(1)).is_equal(_rules.health_of(1))
	assert_dict(copy.to_dict()).is_equal(_rules.to_dict())


func test_a_snapshot_with_health_out_of_range_is_refused() -> void:
	var snapshot := _rules.to_dict()
	snapshot["players"][1]["health"] = 150.0
	var target := GameRules.new(_t, 1)
	assert_str(target.from_dict(snapshot)).is_equal("malformed")
	snapshot["players"][1]["health"] = NAN
	assert_str(target.from_dict(snapshot)).is_equal("malformed")


func test_the_same_blows_make_the_same_night() -> void:
	var other := RulesFixture.make_rules(2, 1234, RulesFixture.tuning())
	RulesFixture.into_round_one(other)
	for rules: GameRules in [_rules, other]:
		rules.apply(RulesAction.blow(1, 35.0, 0.2, 4))
		for _i in 400:
			rules.apply(RulesAction.tick(STEP))
		rules.apply(RulesAction.blow(1, 80.0, 2.0, 5))
	assert_dict(other.to_dict()).is_equal(_rules.to_dict())
