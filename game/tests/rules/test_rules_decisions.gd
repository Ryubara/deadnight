extends GdUnitTestSuite
## Three small rules the review of #39 left open (#94): an action sent from inside an event
## listener is refused, a downed player cannot buy, and a night cannot be built without a seed.

## The rules a listener below captured: the listener holds the rules and the rules hold the
## listener, a cycle that is never freed (the "resources still in use at exit" error), so
## `after_test` cuts it.
var _listened: GameRules


func after_test() -> void:
	if _listened != null:
		for connection in _listened.event_emitted.get_connections():
			_listened.event_emitted.disconnect(connection["callable"])
		_listened = null


func test_an_action_sent_from_an_event_listener_is_rejected_and_changes_nothing() -> void:
	var rules := RulesFixture.make_rules(1)
	_listened = rules
	var heard: Array[StringName] = []
	var inner: Array[Array] = []
	rules.event_emitted.connect(
		func(event: Dictionary) -> void:
			heard.append(event["type"])
			if event["type"] == &"phase_changed" and inner.is_empty():
				inner.append(rules.apply(RulesAction.grant_points(1, 500)))
	)
	var points := rules.points_of(1)
	rules.apply(RulesAction.start())
	assert_int(inner.size()).is_equal(1)
	assert_int(inner[0].size()).is_equal(1)
	assert_str(inner[0][0]["type"]).is_equal("action_rejected")
	assert_str(inner[0][0]["reason"]).is_equal("reentrant")
	assert_str(inner[0][0]["action"]).is_equal("grant_points")
	assert_int(rules.points_of(1)).is_equal(points)
	# The listener saw the outer action's events once each, in order, and nothing from the inner one.
	assert_array(heard).is_equal([&"phase_changed", &"break_started"])


func test_apply_works_again_once_the_listeners_have_run() -> void:
	var rules := RulesFixture.make_rules(1)
	_listened = rules
	rules.event_emitted.connect(
		func(event: Dictionary) -> void:
			if event["type"] == &"phase_changed":
				rules.apply(RulesAction.grant_points(1, 500))
	)
	rules.apply(RulesAction.start())
	var points := rules.points_of(1)
	rules.apply(RulesAction.grant_points(1, 25))
	assert_int(rules.points_of(1)).is_equal(points + 25)


func test_a_downed_player_cannot_buy_a_door_a_weapon_or_fuel() -> void:
	var rules := RulesFixture.make_rules(2)
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.grant_points(1, 10000))
	rules.apply(RulesAction.set_downed(1, true))
	var points := rules.points_of(1)
	for item_id in [&"door_concession", &"weapon_shotgun", &"fuel_can"]:
		assert_int(RulesFixture.buy(rules, 1, item_id)).is_equal(GameRules.BuyResult.PLAYER_DOWNED)
	assert_int(rules.points_of(1)).is_equal(points)
	assert_bool(rules.is_door_open(&"door_concession")).is_false()
	assert_array((rules.players[1] as PlayerState).weapons).not_contains([&"weapon_shotgun"])


func test_a_player_who_gets_up_can_buy_again() -> void:
	var rules := RulesFixture.make_rules(2)
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.grant_points(1, 10000))
	rules.apply(RulesAction.set_downed(1, true))
	rules.apply(RulesAction.set_downed(1, false))
	assert_int(RulesFixture.buy(rules, 1, &"weapon_shotgun")).is_equal(GameRules.BuyResult.OK)


func test_the_rules_cannot_be_built_without_a_seed() -> void:
	var init: Dictionary = {}
	for method in (GameRules as Script).get_script_method_list():
		if method["name"] == "_init":
			init = method
	assert_bool(init.is_empty()).is_false()
	assert_int((init["args"] as Array).size()).is_equal(3)
	# Only the match settings (the third) have a default: `GameRules.new()` and
	# `GameRules.new(tuning)` do not compile.
	assert_int((init["default_args"] as Array).size()).is_equal(1)


func test_the_seed_is_in_the_snapshot_and_a_restore_keeps_it() -> void:
	var rules := RulesFixture.make_rules(1, 4242)
	assert_int(rules.to_dict()["seed"]).is_equal(4242)
	var copy := GameRules.new(RulesFixture.tuning(), 1)
	assert_str(copy.from_dict(rules.to_dict())).is_equal("")
	assert_int(copy.rng_seed).is_equal(4242)
