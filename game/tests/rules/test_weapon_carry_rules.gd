extends GdUnitTestSuite
## What the rules say about the carry (#410): the start weapons are carried, a third weapon from the
## wall or the crane replaces the one in hand and the replaced one is a prize and a purchase again.

var _rules: GameRules


func before_test() -> void:
	# Both hands full from the start (the crowbar and the revolver): the replace is the subject.
	_rules = RulesFixture.make_rules(
		1, 5, RulesFixture.full_hands(RulesFixture.steady_crane_tuning())
	)
	_rules.apply(RulesAction.start())
	_rules.apply(RulesAction.skip_break())
	_rules.apply(RulesAction.grant_points(1, 20000))


func _carried() -> Array:
	return _rules.players[1].weapons


func _released(events: Array[Dictionary]) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == &"weapon_released")


func test_a_player_starts_with_the_start_weapons_carried() -> void:
	assert_array(_carried()).contains_exactly([&"weapon_crowbar", &"weapon_pistol"])


func test_a_wall_weapon_replaces_the_one_in_hand_and_releases_it() -> void:
	var events := _rules.apply(RulesAction.buy(1, &"weapon_shotgun", -1, &"pistol"))
	assert_array(_carried()).contains_exactly([&"weapon_crowbar", &"weapon_shotgun"])
	var released := RulesFixture.first(events, &"weapon_released")
	assert_str(released["weapon"]).is_equal("weapon_pistol")
	assert_str(released["taken"]).is_equal("weapon_shotgun")
	var bought := RulesFixture.first(events, &"purchase_made")
	assert_str(bought["detail"]["released"]).is_equal("weapon_pistol")


func test_a_buy_that_names_no_weapon_in_hand_releases_the_oldest() -> void:
	_rules.apply(RulesAction.buy(1, &"weapon_shotgun"))
	assert_array(_carried()).contains_exactly([&"weapon_pistol", &"weapon_shotgun"])


func test_a_refused_buy_replaces_nothing() -> void:
	_rules.apply(RulesAction.buy(1, &"weapon_shotgun", -1, &"pistol"))
	var events := _rules.apply(RulesAction.buy(1, &"weapon_shotgun", -1, &"crowbar"))
	assert_array(_carried()).contains_exactly([&"weapon_crowbar", &"weapon_shotgun"])
	assert_array(_released(events)).is_empty()


func test_the_released_weapon_is_in_the_crane_pool_again_and_the_kept_one_is_not() -> void:
	var item := _rules.tuning.economy.item(&"crane_play")
	assert_array(item.pool_without(_carried())).not_contains([&"weapon_pistol"])
	_rules.apply(RulesAction.buy(1, &"weapon_shotgun", -1, &"pistol"))
	assert_array(item.pool_without(_carried())).contains([&"weapon_pistol"])
	assert_array(item.pool_without(_carried())).not_contains([&"weapon_crowbar"])


func test_a_weapon_released_from_the_wall_can_be_bought_again() -> void:
	_rules.apply(RulesAction.buy(1, &"weapon_shotgun", -1, &"pistol"))
	_rules.apply(RulesAction.buy(1, &"weapon_rifle", -1, &"shotgun"))
	assert_array(_carried()).contains_exactly([&"weapon_crowbar", &"weapon_rifle"])
	var events := _rules.apply(RulesAction.buy(1, &"weapon_shotgun", -1, &"rifle"))
	assert_str(RulesFixture.first(events, &"purchase_made")["item_id"]).is_equal("weapon_shotgun")
	assert_array(_carried()).contains_exactly([&"weapon_crowbar", &"weapon_shotgun"])


func test_the_crane_never_offers_what_is_in_the_hands() -> void:
	for seed_value in 60:
		var rules := RulesFixture.make_rules(1, seed_value, RulesFixture.steady_crane_tuning())
		rules.apply(RulesAction.start())
		rules.apply(RulesAction.grant_points(1, 5000))
		var ready := RulesFixture.first(RulesFixture.play_crane(rules, 1), &"crane_prize_ready")
		assert_array(rules.players[1].weapons).not_contains([ready["weapon"]])


func test_a_crane_prize_replaces_the_weapon_in_hand_and_says_which() -> void:
	var ready := RulesFixture.first(RulesFixture.play_crane(_rules, 1), &"crane_prize_ready")
	var events := _rules.apply(RulesAction.crane_take(1, &"pistol"))
	var taken := RulesFixture.first(events, &"crane_prize_taken")
	assert_str(taken["released"]).is_equal("weapon_pistol")
	assert_array(_carried()).contains_exactly([&"weapon_crowbar", ready["weapon"]])
	assert_str(RulesFixture.first(events, &"weapon_released")["taken"]).is_equal(ready["weapon"])


func test_a_crane_prize_without_a_named_weapon_releases_the_oldest() -> void:
	var ready := RulesFixture.first(RulesFixture.play_crane(_rules, 1), &"crane_prize_ready")
	_rules.apply(RulesAction.crane_take(1))
	assert_array(_carried()).contains_exactly([&"weapon_pistol", ready["weapon"]])


func test_a_recut_goes_with_the_weapon_and_the_next_one_costs_the_same() -> void:
	var base := _rules.price_of(&"upgrade_weapon", 1)
	_rules.apply(RulesAction.buy(1, &"upgrade_weapon", -1, &"pistol"))
	assert_array(_rules.players[1].upgraded).contains_exactly([&"pistol"])
	assert_int(_rules.price_of(&"upgrade_weapon", 1)).is_equal(base)
	_rules.apply(RulesAction.buy(1, &"weapon_shotgun", -1, &"pistol"))
	assert_array(_rules.players[1].upgraded).is_empty()
	assert_int(_rules.price_of(&"upgrade_weapon", 1)).is_equal(base)
	# The next re-cut is for the shotgun, and costs the same.
	var before := _rules.points_of(1)
	_rules.apply(RulesAction.buy(1, &"upgrade_weapon", -1, &"shotgun"))
	assert_int(before - _rules.points_of(1)).is_equal(base)


func test_the_carry_survives_a_snapshot() -> void:
	_rules.apply(RulesAction.buy(1, &"weapon_shotgun", -1, &"pistol"))
	var copy := GameRules.new(_rules.tuning, 5)
	assert_str(copy.from_dict(_rules.to_dict())).is_equal("")
	assert_array(copy.players[1].weapons).contains_exactly([&"weapon_crowbar", &"weapon_shotgun"])
