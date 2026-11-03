extends GdUnitTestSuite
## Spending: doors, weapons, the crane, tonics and fuel; every refusal; the signals.

var _rules: GameRules
var _log: RulesFixture


func _begin(seed_value: int = 1234) -> void:
	_rules = RulesFixture.make_rules(2, seed_value)
	_log = RulesFixture.record(_rules)
	_rules.apply(RulesAction.start())


func _rich(player_id: int = 1, amount: int = 10000) -> void:
	_rules.apply(RulesAction.grant_points(player_id, amount))


func test_nothing_can_be_bought_before_the_night_starts() -> void:
	_rules = RulesFixture.make_rules(1)
	_rich()
	assert_int(RulesFixture.buy(_rules, 1, &"door_concession")).is_equal(
		GameRules.BuyResult.WRONG_PHASE
	)


func test_a_door_costs_its_price_and_opens_for_everyone() -> void:
	_begin()
	_rich(1, 200)  # 400 in all
	assert_int(RulesFixture.buy(_rules, 1, &"door_concession")).is_equal(GameRules.BuyResult.OK)
	assert_int(_rules.points_of(1)).is_equal(400 - 350)
	assert_bool(_rules.is_door_open(&"door_concession")).is_true()
	assert_str(_log.of(&"door_opened")[0]["door_id"]).is_equal("door_concession")
	assert_int(_log.of(&"purchase_made")[0]["price"]).is_equal(350)


func test_a_door_cannot_be_bought_twice() -> void:
	_begin()
	_rich()
	RulesFixture.buy(_rules, 1, &"door_concession")
	var before := _rules.points_of(2)
	assert_int(RulesFixture.buy(_rules, 2, &"door_concession")).is_equal(
		GameRules.BuyResult.ALREADY_OWNED
	)
	assert_int(_rules.points_of(2)).is_equal(before)


func test_the_lot_opens_outward() -> void:
	_begin()
	_rich()
	assert_int(RulesFixture.buy(_rules, 1, &"door_booth")).is_equal(GameRules.BuyResult.LOCKED)
	RulesFixture.buy(_rules, 1, &"door_concession")
	assert_int(RulesFixture.buy(_rules, 1, &"door_booth")).is_equal(GameRules.BuyResult.OK)
	assert_int(RulesFixture.buy(_rules, 1, &"door_back_lot")).is_equal(GameRules.BuyResult.OK)


func test_too_few_points_is_refused_and_nothing_changes() -> void:
	_begin()
	assert_int(RulesFixture.buy(_rules, 1, &"door_concession")).is_equal(
		GameRules.BuyResult.NOT_ENOUGH_POINTS
	)
	assert_int(_rules.points_of(1)).is_equal(200)
	assert_bool(_rules.is_door_open(&"door_concession")).is_false()
	assert_int(_log.of(&"purchase_denied")[0]["result"]).is_equal(
		GameRules.BuyResult.NOT_ENOUGH_POINTS
	)
	assert_int(_log.count(&"purchase_made")).is_equal(0)


func test_unknown_players_and_items_are_refused() -> void:
	_begin()
	assert_int(RulesFixture.buy(_rules, 99, &"door_concession")).is_equal(
		GameRules.BuyResult.UNKNOWN_PLAYER
	)
	assert_int(RulesFixture.buy(_rules, 1, &"nonsense")).is_equal(GameRules.BuyResult.UNKNOWN_ITEM)
	assert_int(_rules.price_of(&"nonsense")).is_equal(-1)


func test_a_weapon_belongs_to_the_buyer_alone() -> void:
	_begin()
	_rich()
	assert_int(RulesFixture.buy(_rules, 1, &"weapon_shotgun")).is_equal(GameRules.BuyResult.OK)
	assert_array((_rules.players[1] as PlayerState).weapons).contains([&"weapon_shotgun"])
	assert_array((_rules.players[2] as PlayerState).weapons).contains_exactly(
		RulesFixture.start_weapons()
	)
	assert_int(RulesFixture.buy(_rules, 1, &"weapon_shotgun")).is_equal(
		GameRules.BuyResult.ALREADY_OWNED
	)
	assert_int(RulesFixture.buy(_rules, 2, &"weapon_shotgun")).is_equal(
		GameRules.BuyResult.NOT_ENOUGH_POINTS
	)


func test_a_tonic_is_bought_once_and_four_at_most() -> void:
	_begin()
	_rich()
	assert_int(RulesFixture.buy(_rules, 1, &"tonic_hearty")).is_equal(GameRules.BuyResult.OK)
	assert_int(RulesFixture.buy(_rules, 1, &"tonic_hearty")).is_equal(
		GameRules.BuyResult.ALREADY_OWNED
	)
	RulesFixture.buy(_rules, 1, &"tonic_swift_rescue")
	RulesFixture.buy(_rules, 1, &"tonic_double_shot")
	RulesFixture.buy(_rules, 1, &"tonic_quick_load")
	assert_int((_rules.players[1] as PlayerState).tonics.size()).is_equal(4)
	var tuning := RulesFixture.tuning()
	tuning.economy.max_tonics = 3
	var capped: GameRules = RulesFixture.make_rules(1, 1, tuning)
	capped.apply(RulesAction.start())
	capped.apply(RulesAction.grant_points(1, 10000))
	RulesFixture.buy(capped, 1, &"tonic_hearty")
	RulesFixture.buy(capped, 1, &"tonic_swift_rescue")
	RulesFixture.buy(capped, 1, &"tonic_double_shot")
	assert_int(RulesFixture.buy(capped, 1, &"tonic_quick_load")).is_equal(
		GameRules.BuyResult.LIMIT_REACHED
	)


func test_fuel_refills_the_tank_at_the_rounds_price() -> void:
	_begin()
	_rich()
	_rules.generator.fuel = 50.0
	assert_int(RulesFixture.buy(_rules, 1, &"fuel_can")).is_equal(GameRules.BuyResult.OK)
	assert_float(_rules.generator.fuel).is_equal_approx(75.0, 0.001)
	assert_int(_rules.points_of(1)).is_equal(10200 - 100)
	assert_float(_log.of(&"purchase_made")[0]["detail"]["fuel"]).is_equal(25.0)


func test_fuel_gets_dearer_each_round() -> void:
	_begin()
	assert_int(_rules.price_of(&"fuel_can")).is_equal(100)
	_rules.round_number = 5
	assert_int(_rules.price_of(&"fuel_can")).is_equal(100 + 20 * 4)


func test_a_partial_fill_pays_only_for_the_room() -> void:
	_begin()
	_rich()
	_rules.apply(RulesAction.skip_break())
	# 100 - 10 = 90 in the tank: room for 10 of a 25-unit can, so 10/25 of the price.
	_rules.generator.fuel = 90.0
	var before := _rules.points_of(1)
	assert_int(RulesFixture.buy(_rules, 1, &"fuel_can")).is_equal(GameRules.BuyResult.OK)
	assert_float(_rules.generator.fuel).is_equal(100.0)
	assert_int(before - _rules.points_of(1)).is_equal(40)


func test_a_full_tank_refuses_fuel() -> void:
	_begin()
	_rich()
	assert_int(RulesFixture.buy(_rules, 1, &"fuel_can")).is_equal(GameRules.BuyResult.TANK_FULL)
	assert_int(_rules.points_of(1)).is_equal(10200)


func test_spending_is_tracked_per_player() -> void:
	_begin()
	_rich()
	RulesFixture.buy(_rules, 1, &"weapon_shotgun")
	assert_int((_rules.players[1] as PlayerState).points_spent).is_equal(900)
	assert_int((_rules.players[2] as PlayerState).points_spent).is_equal(0)
