extends GdUnitTestSuite
## The shield of a player's arrival by helicopter (#1057, `ArrivalPlay`), as the rules run it: from
## the client's word that its drop began to its word that it landed (or the cap), nothing hurts the
## player; a moment of grace follows; a seat has one drop; and a player in the helicopter is not a
## player standing for the game over.

const STEP := 1.0 / 60.0

var _t: RulesTuning
var _rules: GameRules


func before_test() -> void:
	_t = RulesFixture.tuning()
	_rules = RulesFixture.make_rules(2, 99, _t)
	RulesFixture.into_round_one(_rules)


func _blow(player_id := 1, damage := 30.0) -> Array[Dictionary]:
	return _rules.apply(RulesAction.blow(player_id, damage))


func _rejected(events: Array[Dictionary]) -> StringName:
	return RulesFixture.first(events, &"action_rejected").get("reason", &"")


func test_the_drop_shields_the_player_from_every_blow() -> void:
	var health := _rules.health_of(1)
	var began := _rules.apply(RulesAction.arrival(1, true))
	assert_int(RulesFixture.first(began, &"player_dropping")["player_id"]).is_equal(1)
	assert_bool(_rules.players[1].is_dropping()).is_true()
	var events := _blow()
	assert_str(String(_rejected(events))).is_equal("shielded")
	assert_dict(RulesFixture.first(events, &"player_hurt")).is_empty()
	assert_float(_rules.health_of(1)).is_equal(health)
	# A blast is the same blow: the grenade's and the ray gun's reach the player by it.
	_rules.apply(RulesAction.blow(1, 500.0, 0.0, -1, &"grenade", 1))
	assert_float(_rules.health_of(1)).is_equal(health)
	assert_bool(_rules.players[1].downed).is_false()


func test_the_player_next_to_them_is_hurt_as_ever() -> void:
	_rules.apply(RulesAction.arrival(1, true))
	var events := _blow(2)
	assert_dict(RulesFixture.first(events, &"player_hurt")).is_not_empty()


func test_landing_ends_the_drop_and_a_moment_of_grace_follows() -> void:
	_rules.apply(RulesAction.arrival(1, true))
	RulesFixture.advance(_rules, 2.0)
	var landed := _rules.apply(RulesAction.arrival(1, false))
	assert_int(RulesFixture.first(landed, &"player_landed")["player_id"]).is_equal(1)
	assert_bool(_rules.players[1].is_dropping()).is_false()
	assert_bool(_rules.players[1].is_shielded()).is_true()
	assert_str(String(_rejected(_blow()))).is_equal("shielded")
	# The grace runs out and the next blow lands.
	RulesFixture.advance(_rules, _t.arrival.grace_seconds + 0.1)
	assert_bool(_rules.players[1].is_shielded()).is_false()
	assert_dict(RulesFixture.first(_blow(), &"player_hurt")).is_not_empty()


func test_a_client_that_never_lands_is_shielded_no_longer_than_the_cap() -> void:
	_rules.apply(RulesAction.arrival(1, true))
	var events := RulesFixture.advance(_rules, _t.arrival.cap_seconds - 0.5)
	assert_dict(RulesFixture.first(events, &"player_landed")).is_empty()
	assert_bool(_rules.players[1].is_dropping()).is_true()
	events = RulesFixture.advance(_rules, 1.0)
	assert_int(RulesFixture.first(events, &"player_landed")["player_id"]).is_equal(1)
	assert_bool(_rules.players[1].is_dropping()).is_false()
	RulesFixture.advance(_rules, _t.arrival.grace_seconds + 0.1)
	assert_bool(_rules.players[1].is_shielded()).is_false()


func test_a_seat_has_one_drop() -> void:
	_rules.apply(RulesAction.arrival(1, true))
	_rules.apply(RulesAction.arrival(1, false))
	RulesFixture.advance(_rules, _t.arrival.grace_seconds + 0.1)
	var again := _rules.apply(RulesAction.arrival(1, true))
	assert_str(String(_rejected(again))).is_equal("already_dropped")
	assert_bool(_rules.players[1].is_shielded()).is_false()
	assert_dict(RulesFixture.first(_blow(), &"player_hurt")).is_not_empty()


func test_landing_when_not_dropping_does_nothing() -> void:
	var events := _rules.apply(RulesAction.arrival(1, false))
	assert_str(String(_rejected(events))).is_equal("not_dropping")
	assert_bool(_rules.players[1].is_shielded()).is_false()


func test_a_bot_has_no_drop() -> void:
	_rules.apply(RulesAction.add_player(3, true))
	var events := _rules.apply(RulesAction.arrival(3, true))
	assert_str(String(_rejected(events))).is_equal("bot")
	assert_bool(_rules.players[3].is_shielded()).is_false()


func test_an_unknown_player_is_refused() -> void:
	var events := _rules.apply(RulesAction.arrival(9, true))
	assert_str(String(_rejected(events))).is_equal("unknown_player")


func test_a_drop_cannot_begin_before_the_night_or_after_it() -> void:
	var idle := RulesFixture.make_rules(1, 5)
	assert_str(String(_rejected(idle.apply(RulesAction.arrival(1, true))))).is_equal("wrong_phase")
	_rules.apply(RulesAction.set_downed(1, true))
	_rules.apply(RulesAction.set_downed(2, true))
	assert_int(_rules.phase).is_equal(GameRules.Phase.OVER)
	assert_str(String(_rejected(_rules.apply(RulesAction.arrival(1, true))))).is_equal(
		"wrong_phase"
	)


func test_a_late_join_in_a_round_is_shielded_the_same() -> void:
	_rules.apply(RulesAction.add_player(3))
	_rules.apply(RulesAction.arrival(3, true))
	assert_str(String(_rejected(_blow(3)))).is_equal("shielded")


func test_a_drop_the_tuning_turns_off_is_refused() -> void:
	_t.arrival.enabled = false
	var rules := RulesFixture.make_rules(1, 7, _t)
	RulesFixture.into_round_one(rules)
	var events := rules.apply(RulesAction.arrival(1, true))
	assert_str(String(RulesFixture.first(events, &"action_rejected")["reason"])).is_equal(
		"arrival_off"
	)


func test_a_shielded_player_is_standing_for_the_game_over() -> void:
	# Player 2 goes down; player 1 is in the helicopter, so the team is not all down.
	_rules.apply(RulesAction.arrival(1, true))
	_rules.apply(RulesAction.set_downed(2, true))
	assert_int(_rules.phase).is_equal(GameRules.Phase.ACTIVE)
	assert_bool(_rules.players[1].downed).is_false()


func test_the_shield_rides_the_snapshot() -> void:
	_rules.apply(RulesAction.arrival(1, true))
	RulesFixture.advance(_rules, 1.0)
	var copy := GameRules.new(_t, 99)
	assert_str(String(copy.from_dict(_rules.to_dict()))).is_equal("")
	assert_float(copy.players[1].drop_left).is_equal_approx(_rules.players[1].drop_left, 0.0001)
	assert_bool(copy.players[1].dropped).is_true()
	assert_bool(copy.players[1].is_dropping()).is_true()
	assert_str(String(_rejected(copy.apply(RulesAction.blow(1, 30.0))))).is_equal("shielded")
	_rules.apply(RulesAction.arrival(1, false))
	copy.from_dict(_rules.to_dict())
	assert_float(copy.players[1].grace_left).is_equal_approx(_t.arrival.grace_seconds, 0.0001)


func test_the_numbers_are_the_tunings() -> void:
	assert_float(_t.arrival.cap_seconds).is_greater(_t.arrival.night_seconds)
	assert_float(_t.arrival.grace_seconds).is_greater(0.0)
	assert_float(_t.arrival.late_seconds).is_less(_t.arrival.night_seconds)
	assert_float(_t.arrival.seconds_for(true)).is_equal(_t.arrival.night_seconds)
	assert_float(_t.arrival.seconds_for(false)).is_equal(_t.arrival.late_seconds)
