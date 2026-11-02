extends GdUnitTestSuite
## The tune-up in the shop (item `upgrade_weapon`): priced by the item, one per weapon, only for a
## weapon the server found in the buyer's hand and the tuning allows, and named in the purchase.
## The hearty tonic beside it: the first perk with an effect, more health.

var _rules: GameRules
var _log: RulesFixture


func _begin(points: int = 10000) -> void:
	_rules = RulesFixture.make_rules(1)
	_log = RulesFixture.record(_rules)
	_rules.apply(RulesAction.start())
	_rules.apply(RulesAction.grant_points(1, points))


func _tune(weapon: StringName) -> int:
	for event in _rules.apply(RulesAction.buy(1, &"upgrade_weapon", -1, weapon)):
		if event["type"] == &"purchase_denied":
			return event["result"]
	return GameRules.BuyResult.OK


func test_the_tune_up_is_a_shop_item_with_a_price() -> void:
	var item := RulesFixture.tuning().economy.item(&"upgrade_weapon")
	assert_object(item).is_not_null()
	assert_int(item.kind).is_equal(ShopItem.Kind.UPGRADE)
	assert_int(item.price).is_greater(0)


func test_a_tune_up_costs_the_price_and_names_the_weapon() -> void:
	_begin()
	var price := _rules.price_of(&"upgrade_weapon")
	assert_int(_tune(&"rifle")).is_equal(GameRules.BuyResult.OK)
	assert_int(_rules.points_of(1)).is_equal(10200 - price)
	var made := _log.of(&"purchase_made")[0]
	assert_str(made["detail"]["upgrade"]).is_equal("rifle")
	assert_array(_rules.players[1].upgraded).contains_exactly([&"rifle"])


func test_a_weapon_is_tuned_up_once_but_another_can_be() -> void:
	_begin()
	_tune(&"rifle")
	assert_int(_tune(&"rifle")).is_equal(GameRules.BuyResult.ALREADY_OWNED)
	assert_int(_tune(&"pistol")).is_equal(GameRules.BuyResult.OK)
	assert_array(_rules.players[1].upgraded).contains_exactly([&"rifle", &"pistol"])


func test_nothing_in_hand_or_a_crowbar_is_refused_and_costs_nothing() -> void:
	_begin()
	assert_int(_tune(&"")).is_equal(GameRules.BuyResult.NO_WEAPON)
	assert_int(_tune(&"crowbar")).is_equal(GameRules.BuyResult.NO_WEAPON)
	assert_int(_tune(&"no_such_gun")).is_equal(GameRules.BuyResult.NO_WEAPON)
	assert_int(_rules.points_of(1)).is_equal(10200)


func test_without_the_points_nothing_is_sold() -> void:
	_begin(100)
	assert_int(_tune(&"pistol")).is_equal(GameRules.BuyResult.NOT_ENOUGH_POINTS)
	assert_array(_rules.players[1].upgraded).is_empty()


func test_the_tuned_weapons_survive_a_snapshot() -> void:
	_begin()
	_tune(&"smg")
	var copy := GameRules.new(RulesFixture.tuning(), 1)
	assert_str(copy.from_dict(_rules.to_dict())).is_equal("")
	assert_array(copy.players[1].upgraded).contains_exactly([&"smg"])
	var damaged := _rules.to_dict()
	damaged["players"][1]["upgraded"] = [7]
	assert_str(copy.from_dict(damaged)).is_not_equal("")


func test_the_buy_action_carries_the_weapon_only_when_given() -> void:
	assert_bool(RulesAction.buy(1, &"upgrade_weapon").has("weapon")).is_false()
	var action := RulesAction.buy(1, &"upgrade_weapon", -1, &"rifle")
	assert_dict(RulesAction.validate(action)).is_empty()
	action["weapon"] = 5
	assert_str(RulesAction.validate(action)["reason"]).is_equal("wrong_type")


func test_the_hearty_tonic_raises_the_most_health_and_the_health_with_it() -> void:
	_begin()
	var base := _rules.max_health_of(1)
	var bonus := _rules.tuning.economy.item(&"tonic_hearty").health_bonus
	assert_float(bonus).is_greater(0.0)
	_rules.apply(RulesAction.buy(1, &"tonic_hearty"))
	assert_float(_rules.max_health_of(1)).is_equal(base + bonus)
	assert_float(_rules.health_of(1)).is_equal(base + bonus)
	var healed := _log.of(&"player_healed")[0]
	assert_str(healed["reason"]).is_equal("tonic")
	assert_float(healed["max_health"]).is_equal(base + bonus)


func test_a_hurt_player_keeps_the_hurt_and_gets_the_room() -> void:
	_begin()
	_rules.apply(RulesAction.skip_break())
	_rules.apply(RulesAction.blow(1, 40.0))
	_rules.apply(RulesAction.buy(1, &"tonic_hearty"))
	var bonus := _rules.tuning.economy.item(&"tonic_hearty").health_bonus
	assert_float(_rules.health_of(1)).is_equal(60.0 + bonus)


func test_getting_up_after_a_down_restores_the_raised_most() -> void:
	_begin()
	_rules.apply(RulesAction.buy(1, &"tonic_hearty"))
	var most := _rules.max_health_of(1)
	_rules.apply(RulesAction.set_downed(1, true))
	_rules.apply(RulesAction.set_downed(1, false))
	assert_float(_rules.health_of(1)).is_equal(most)


func test_a_tonic_with_no_bonus_leaves_health_alone() -> void:
	_begin()
	var base := _rules.max_health_of(1)
	_rules.apply(RulesAction.buy(1, &"tonic_fleet"))
	assert_float(_rules.max_health_of(1)).is_equal(base)
