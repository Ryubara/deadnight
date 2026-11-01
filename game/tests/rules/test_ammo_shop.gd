extends GdUnitTestSuite
## Ammunition in the shop: priced by the rounds that fit, refused when none do, and described to
## the combat server in the purchase's detail.

var _rules: GameRules
var _log: RulesFixture


func _begin() -> void:
	_rules = RulesFixture.make_rules(1)
	_log = RulesFixture.record(_rules)
	_rules.apply(RulesAction.start())
	_rules.apply(RulesAction.grant_points(1, 10000))


func _buy(item_id: StringName, rounds: int = -1) -> int:
	for event in _rules.apply(RulesAction.buy(1, item_id, rounds)):
		if event["type"] == &"purchase_denied":
			return event["result"]
	return GameRules.BuyResult.OK


func test_every_weapon_that_uses_ammunition_has_an_ammunition_item() -> void:
	var tuning := RulesFixture.tuning()
	var sold: Array[StringName] = []
	for item in tuning.economy.items:
		if item.kind == ShopItem.Kind.AMMO:
			sold.append(item.weapon)
			assert_float(item.amount).is_greater(0.0)
			assert_int(item.price).is_greater(0)
	for def in WeaponCatalog.all():
		assert_bool(sold.has(def.id)).is_equal(not def.is_melee())


func test_a_whole_purchase_costs_the_price_and_names_the_rounds() -> void:
	_begin()
	var item := _rules.tuning.economy.item(&"ammo_rifle")
	assert_int(_buy(&"ammo_rifle")).is_equal(GameRules.BuyResult.OK)
	assert_int(_rules.points_of(1)).is_equal(10200 - item.price)
	var made := _log.of(&"purchase_made")[0]
	assert_str(made["detail"]["ammo"]).is_equal("rifle")
	assert_int(made["detail"]["rounds"]).is_equal(int(item.amount))
	assert_int(made["price"]).is_equal(item.price)


func test_rounds_that_fit_are_all_that_is_paid_for() -> void:
	_begin()
	var item := _rules.tuning.economy.item(&"ammo_pistol")
	var half := int(item.amount) / 2
	assert_int(_buy(&"ammo_pistol", half)).is_equal(GameRules.BuyResult.OK)
	assert_int(10200 - _rules.points_of(1)).is_equal(ceili(float(item.price) * 0.5))
	assert_int(_log.of(&"purchase_made")[0]["detail"]["rounds"]).is_equal(half)


func test_more_room_than_a_purchase_holds_buys_one_purchase() -> void:
	_begin()
	var item := _rules.tuning.economy.item(&"ammo_smg")
	assert_int(_buy(&"ammo_smg", 500)).is_equal(GameRules.BuyResult.OK)
	assert_int(10200 - _rules.points_of(1)).is_equal(item.price)
	assert_int(_log.of(&"purchase_made")[0]["detail"]["rounds"]).is_equal(int(item.amount))


func test_a_full_reserve_refuses_and_takes_nothing() -> void:
	_begin()
	assert_int(_buy(&"ammo_pistol", 0)).is_equal(GameRules.BuyResult.AMMO_FULL)
	assert_int(_rules.points_of(1)).is_equal(10200)
	assert_int(_log.count(&"purchase_made")).is_equal(0)


func test_ammunition_can_be_bought_again_and_again() -> void:
	_begin()
	for _i in 5:
		assert_int(_buy(&"ammo_shotgun")).is_equal(GameRules.BuyResult.OK)
	assert_int(_log.count(&"purchase_made")).is_equal(5)


func test_too_few_points_refuses_ammunition_too() -> void:
	_rules = RulesFixture.make_rules(1)
	_rules.apply(RulesAction.start())
	_rules.players[1].points = _rules.price_of(&"ammo_flare_gun") - 1
	assert_int(RulesFixture.buy(_rules, 1, &"ammo_flare_gun")).is_equal(
		GameRules.BuyResult.NOT_ENOUGH_POINTS
	)


func test_a_rounds_field_that_is_not_a_count_is_rejected() -> void:
	_begin()
	for bad: Variant in [-1, RulesAction.MAX_ROUNDS + 1, 2.5, "ten", null]:
		var action := RulesAction.buy(1, &"ammo_pistol")
		action["rounds"] = bad
		var events := _rules.apply(action)
		assert_str(events[0]["type"]).is_equal("action_rejected")
		assert_str(events[0]["field"]).is_equal("rounds")
	assert_int(_rules.points_of(1)).is_equal(10200)


func test_the_plain_buy_action_is_unchanged_without_rounds() -> void:
	assert_bool(RulesAction.buy(1, &"door_concession").has("rounds")).is_false()
	assert_int(RulesAction.buy(1, &"ammo_pistol", 7)["rounds"]).is_equal(7)
