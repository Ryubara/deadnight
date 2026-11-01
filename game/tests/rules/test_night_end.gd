extends GdUnitTestSuite
## The night ends when nobody is left in it, as well as when everyone is down.


func _game_overs(events: Array[Dictionary]) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == &"game_over")


func test_removing_the_last_player_in_a_round_ends_the_night() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	rules.apply(RulesAction.remove_player(1))
	assert_int(rules.phase).is_equal(GameRules.Phase.ACTIVE)
	var events := rules.apply(RulesAction.remove_player(2))
	var over := _game_overs(events)
	assert_int(over.size()).is_equal(1)
	assert_str(over[0]["reason"]).is_equal("no_players")
	assert_int(over[0]["round_reached"]).is_equal(1)
	assert_int(rules.phase).is_equal(GameRules.Phase.OVER)


func test_removing_the_last_player_in_a_break_ends_the_night() -> void:
	var rules := RulesFixture.make_rules(1)
	rules.apply(RulesAction.start())
	var events := rules.apply(RulesAction.remove_player(1))
	assert_int(_game_overs(events).size()).is_equal(1)
	assert_str(_game_overs(events)[0]["reason"]).is_equal("no_players")
	assert_int(rules.phase).is_equal(GameRules.Phase.OVER)


func test_a_finished_night_stays_finished_and_spawns_nothing() -> void:
	var rules := RulesFixture.make_rules(1)
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	rules.apply(RulesAction.remove_player(1))
	var spawned := log.count(&"zombie_spawn_requested")
	RulesFixture.run(rules, 30.0)
	assert_int(log.count(&"zombie_spawn_requested")).is_equal(spawned)
	assert_int(log.count(&"game_over")).is_equal(1)
	rules.apply(RulesAction.start())
	assert_int(rules.phase).is_equal(GameRules.Phase.OVER)


func test_start_with_no_players_is_rejected_and_nothing_runs() -> void:
	var rules := GameRules.new(RulesFixture.tuning(), 1)
	var events := rules.apply(RulesAction.start())
	assert_int(events.size()).is_equal(1)
	assert_str(events[0]["reason"]).is_equal("no_players")
	assert_str(events[0]["action"]).is_equal("start")
	assert_int(rules.phase).is_equal(GameRules.Phase.IDLE)


func test_leaving_before_the_night_starts_is_not_a_game_over() -> void:
	var rules := RulesFixture.make_rules(1)
	var events := rules.apply(RulesAction.remove_player(1))
	assert_int(_game_overs(events).size()).is_equal(0)
	assert_int(rules.phase).is_equal(GameRules.Phase.IDLE)


func test_everyone_down_is_still_game_over() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	rules.apply(RulesAction.set_downed(1, true))
	var events := rules.apply(RulesAction.set_downed(2, true))
	assert_str(_game_overs(events)[0]["reason"]).is_equal("all_down")


func test_the_last_player_standing_leaving_while_the_other_is_down_ends_it() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	rules.apply(RulesAction.set_downed(1, true))
	assert_int(rules.phase).is_equal(GameRules.Phase.ACTIVE)
	# The one on their feet leaves: the player who remains is down, so the night is over.
	rules.apply(RulesAction.remove_player(2))
	assert_int(rules.phase).is_equal(GameRules.Phase.OVER)
