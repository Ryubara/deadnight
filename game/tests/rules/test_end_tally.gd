extends GdUnitTestSuite
## What the end-of-night board counts that the rules did not say before
## (docs/design/end-of-night.md): a round's end names the players who stood at it, and headshot
## kills are a count of their own.


func _rounds_ended(rules: GameRules) -> Array[Dictionary]:
	var log := RulesFixture.record(rules)
	RulesFixture.clear_round(rules)
	return log.of(&"round_ended")


func test_a_round_ends_naming_the_players_who_stood_at_it() -> void:
	var rules := RulesFixture.make_rules(3)
	RulesFixture.into_round_one(rules)
	rules.apply(RulesAction.set_downed(2, true))
	var ended := _rounds_ended(rules)
	assert_int(ended.size()).is_equal(1)
	var standing: Array = ended[0]["standing"]
	assert_array(standing).contains_exactly([1, 3])


func test_a_player_downed_at_the_end_of_a_round_is_got_up_but_does_not_stand_in_it() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	rules.apply(RulesAction.set_downed(2, true))
	var ended := _rounds_ended(rules)
	assert_array(ended[0]["standing"]).contains_exactly([1])
	# The end of the round got them up: they stand in the next one.
	assert_bool(rules.players[2].downed).is_false()


func test_a_headshot_kill_is_counted_and_a_body_kill_or_a_melee_kill_is_not() -> void:
	var rules := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 8.0)
	var ids := rules.zombie_ids()
	assert_int(ids.size()).is_greater_equal(3)
	RulesFixture.kill(rules, 1, ids[0], RulesAction.ZONE_HEAD)
	RulesFixture.kill(rules, 1, ids[1], RulesAction.ZONE_BODY)
	RulesFixture.kill(rules, 1, ids[2], RulesAction.ZONE_HEAD, true)
	assert_int(rules.kills_of(1)).is_equal(3)
	assert_int(rules.headshots_of(1)).is_equal(1)
	assert_int(rules.headshots_of(99)).is_equal(0)
