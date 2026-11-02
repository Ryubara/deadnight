extends GdUnitTestSuite
## Malformed actions are rejected with an event, never a script error, and change nothing.

## One well formed action of every type, by type.
const SAMPLES := {
	&"start": {"type": &"start"},
	&"configure":
	{
		"type": &"configure",
		"settings": {"count_multiplier": 2.0, "max_alive": 12, "break_seconds": 8.0},
	},
	&"tick": {"type": &"tick", "delta": 0.016},
	&"skip_break": {"type": &"skip_break"},
	&"add_player": {"type": &"add_player", "player_id": 9},
	&"remove_player": {"type": &"remove_player", "player_id": 1},
	&"set_downed": {"type": &"set_downed", "player_id": 1, "downed": true},
	&"blow": {"type": &"blow", "player_id": 1, "damage": 12.0, "bearing": 1.0, "source_id": 3},
	&"hit": {"type": &"hit", "player_id": 1, "zombie_id": 1, "zone": &"head", "damage": 20.0},
	&"zombie_gone": {"type": &"zombie_gone", "zombie_id": 1},
	&"repair": {"type": &"repair", "player_id": 1, "barricade_id": &"nw"},
	&"tear_board": {"type": &"tear_board", "barricade_id": &"nw", "zombie_id": 2},
	&"buy": {"type": &"buy", "player_id": 1, "item_id": &"fuel_can"},
	&"crane_take": {"type": &"crane_take", "player_id": 1},
	&"set_circuit": {"type": &"set_circuit", "circuit_id": &"screen_lot", "on": false},
	&"grant_points": {"type": &"grant_points", "player_id": 1, "amount": 10},
	&"use_grenade": {"type": &"use_grenade", "player_id": 1},
	&"revive": {"type": &"revive", "player_id": 1, "target_id": 2},
	&"explosion":
	{
		"type": &"explosion",
		"player_id": 1,
		"victims": [{"zombie_id": 1, "damage": 20.0, "leg_damage": 5.0}],
	},
}

var _rules: GameRules


func before_test() -> void:
	_rules = RulesFixture.make_rules(2)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 2.0)


func _assert_rejected(action: Dictionary, reason: String, field: String = "") -> void:
	var before := _rules.to_dict()
	var events := _rules.apply(action)
	assert_int(events.size()).is_equal(1)
	assert_str(events[0]["type"]).is_equal("action_rejected")
	assert_str(events[0]["reason"]).is_equal(reason)
	if field != "":
		assert_str(events[0]["field"]).is_equal(field)
	assert_dict(_rules.to_dict()).is_equal(before)


func test_every_action_type_has_a_sample() -> void:
	for type: StringName in RulesAction.REQUIRED:
		assert_bool(SAMPLES.has(type)).is_true()
	for type: StringName in SAMPLES:
		assert_dict(RulesAction.validate(SAMPLES[type])).is_empty()


func test_the_builders_make_well_formed_actions() -> void:
	for action: Dictionary in [
		RulesAction.start(),
		RulesAction.configure(MatchSettings.new()),
		RulesAction.tick(0.5),
		RulesAction.skip_break(),
		RulesAction.add_player(3),
		RulesAction.remove_player(3),
		RulesAction.set_downed(3, true),
		RulesAction.blow(1, 12.0, 0.5, 3),
		RulesAction.hit(1, 2, RulesAction.ZONE_LIMB, 5.0, true),
		RulesAction.zombie_gone(2),
		RulesAction.repair(1, &"nw"),
		RulesAction.tear_board(&"nw", 2),
		RulesAction.buy(1, &"fuel_can"),
		RulesAction.crane_take(1),
		RulesAction.set_circuit(&"screen_lot", true),
		RulesAction.grant_points(1, 5, &"pickup"),
		RulesAction.use_grenade(1),
		RulesAction.explosion(1, [{"zombie_id": 2, "damage": 5.0, "leg_damage": 1.0}]),
	]:
		assert_dict(RulesAction.validate(action)).is_empty()


func test_a_missing_field_is_rejected_for_every_type() -> void:
	for type: StringName in RulesAction.REQUIRED:
		for field: String in RulesAction.REQUIRED[type]:
			var action: Dictionary = (SAMPLES[type] as Dictionary).duplicate()
			action.erase(field)
			_assert_rejected(action, "missing_field", field)


func test_a_wrong_type_is_rejected_for_every_field() -> void:
	for type: StringName in RulesAction.REQUIRED:
		for field: String in RulesAction.REQUIRED[type]:
			var action: Dictionary = (SAMPLES[type] as Dictionary).duplicate()
			# A string where a number is wanted, and a number where a name or a flag is.
			var wanted: int = RulesAction.REQUIRED[type][field]
			action[field] = "x" if wanted == TYPE_INT or wanted == TYPE_FLOAT else 7
			_assert_rejected(action, "wrong_type", field)


func test_a_string_player_id_and_a_float_id_are_rejected() -> void:
	_assert_rejected({"type": &"add_player", "player_id": "1"}, "wrong_type", "player_id")
	_assert_rejected(
		{"type": &"hit", "player_id": 1.0, "zombie_id": 1, "zone": &"head", "damage": 1.0},
		"wrong_type",
		"player_id"
	)
	_assert_rejected({"type": &"buy", "player_id": 1}, "missing_field", "item_id")


func test_an_optional_field_of_the_wrong_type_is_rejected() -> void:
	var action: Dictionary = (SAMPLES[&"hit"] as Dictionary).duplicate()
	action["melee"] = "yes"
	_assert_rejected(action, "wrong_type", "melee")


func test_ticks_must_be_finite_and_within_bounds() -> void:
	_assert_rejected(RulesAction.tick(-100.0), "out_of_range", "delta")
	_assert_rejected(RulesAction.tick(NAN), "out_of_range", "delta")
	_assert_rejected(RulesAction.tick(INF), "out_of_range", "delta")
	_assert_rejected(RulesAction.tick(-INF), "out_of_range", "delta")
	_assert_rejected(RulesAction.tick(RulesAction.MAX_TICK + 0.01), "out_of_range", "delta")
	_assert_rejected(RulesAction.tick(1000000.0), "out_of_range", "delta")
	var fuel := _rules.generator.fuel
	_rules.apply(RulesAction.tick(RulesAction.MAX_TICK))
	assert_float(_rules.generator.fuel).is_less(fuel)


func test_a_negative_tick_no_longer_refunds_fuel() -> void:
	var fuel := _rules.generator.fuel
	_rules.apply(RulesAction.tick(-100.0))
	assert_float(_rules.generator.fuel).is_equal(fuel)


func test_hit_damage_and_zone_are_checked() -> void:
	var base: Dictionary = SAMPLES[&"hit"]
	for bad_damage: float in [0.0, -5.0, NAN, INF, RulesAction.MAX_DAMAGE + 1.0]:
		var action := base.duplicate()
		action["damage"] = bad_damage
		_assert_rejected(action, "out_of_range", "damage")
	var action := base.duplicate()
	action["zone"] = &"toe"
	_assert_rejected(action, "out_of_range", "zone")


func test_blow_damage_and_bearing_are_checked() -> void:
	var base: Dictionary = SAMPLES[&"blow"]
	for bad_damage: float in [0.0, -5.0, NAN, INF, RulesAction.MAX_DAMAGE + 1.0]:
		var action := base.duplicate()
		action["damage"] = bad_damage
		_assert_rejected(action, "out_of_range", "damage")
	for bad_bearing: float in [NAN, INF, -INF]:
		var action := base.duplicate()
		action["bearing"] = bad_bearing
		_assert_rejected(action, "out_of_range", "bearing")
	var action := base.duplicate()
	action["source_id"] = "zombie"
	_assert_rejected(action, "wrong_type", "source_id")


func test_grant_points_amount_is_bounded() -> void:
	_assert_rejected(RulesAction.grant_points(1, -50), "out_of_range", "amount")
	_assert_rejected(RulesAction.grant_points(1, 0), "out_of_range", "amount")
	_assert_rejected(
		RulesAction.grant_points(1, RulesAction.MAX_GRANT + 1), "out_of_range", "amount"
	)


func test_unknown_ids_are_rejected_not_crashed_on() -> void:
	var events := _rules.apply(RulesAction.grant_points(99, 10))
	assert_str(events[0]["reason"]).is_equal("unknown_player")
	events = _rules.apply(RulesAction.hit(99, 1, RulesAction.ZONE_BODY, 5.0))
	assert_str(events[0]["reason"]).is_equal("unknown_player")
	# A shop request for a player or an item the rules do not know is a denied purchase.
	events = _rules.apply(RulesAction.buy(99, &"fuel_can"))
	assert_str(events[0]["type"]).is_equal("purchase_denied")
	events = _rules.apply(RulesAction.buy(1, &"nope"))
	assert_str(events[0]["type"]).is_equal("purchase_denied")


func test_a_bad_or_missing_type_is_rejected() -> void:
	_assert_rejected({}, "unknown_action")
	_assert_rejected({"type": 5}, "unknown_action")
	_assert_rejected({"type": &"fly_to_the_moon"}, "unknown_action")
	_assert_rejected({"type": null}, "unknown_action")


func test_strings_work_where_names_do_because_json_has_no_names() -> void:
	var events := _rules.apply(
		{"type": "hit", "player_id": 1, "zombie_id": 1, "zone": "head", "damage": 10}
	)
	assert_str(events[0]["type"]).is_equal("zombie_damaged")
	assert_str(events[0]["zone"]).is_equal("head")
	events = _rules.apply({"type": "buy", "player_id": 1, "item_id": "fuel_can"})
	assert_str(events[0]["type"]).is_not_equal("action_rejected")


func test_a_rejection_names_the_action_that_failed() -> void:
	var events := _rules.apply({"type": &"buy", "player_id": 1})
	assert_str(events[0]["action"]).is_equal("buy")
