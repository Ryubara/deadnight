# Refuelling the generator (docs/design/rounds.md, Fuel): what the shop offers for the tank as it
# stands, and what a can does to a tank that has run dry.
extends GdUnitTestSuite

const CAN := &"fuel_can"

var _rules: GameRules
var _log: RulesFixture


func before_test() -> void:
	_rules = RulesFixture.make_rules(1)
	_log = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)
	_rules.apply(RulesAction.grant_points(1, 1000))


func _can() -> ShopItem:
	return _rules.tuning.economy.item(CAN)


## What the can sells for the tank as it stands, in the round it is.
func _offer() -> Dictionary:
	return _can().fuel_offer(_rules.round_number, _rules.generator.space())


func test_the_offer_is_a_whole_can_at_the_price_of_the_round() -> void:
	_rules.generator.fuel = 40.0
	var offer := _offer()
	assert_float(offer["units"]).is_equal(_can().amount)
	assert_int(offer["price"]).is_equal(_rules.price_of(CAN))
	assert_int(offer["price"]).is_equal(_can().price_at(1))


func test_the_offer_rises_with_the_round() -> void:
	_rules.generator.fuel = 40.0
	var round_one: int = _offer()["price"]
	_rules.round_number = 6
	var round_six: int = _offer()["price"]
	assert_int(round_six - round_one).is_equal(5 * _can().price_per_round)


func test_the_offer_for_a_nearly_full_tank_is_the_room_and_its_share_of_the_price() -> void:
	_rules.generator.fuel = 90.0
	var offer := _offer()
	assert_float(offer["units"]).is_equal(10.0)
	assert_int(offer["price"]).is_equal(ceili(float(_can().price_at(1)) * 10.0 / _can().amount))
	# The rules charge exactly the quote.
	var before := _rules.points_of(1)
	RulesFixture.buy(_rules, 1, CAN)
	assert_int(before - _rules.points_of(1)).is_equal(offer["price"])


func test_a_full_tank_offers_nothing() -> void:
	var offer := _offer()
	assert_float(offer["units"]).is_equal(0.0)
	assert_int(offer["price"]).is_equal(0)
	# A tank within a unit of full counts as full: no one pays for a sliver.
	_rules.generator.fuel = 99.5
	assert_float(_offer()["units"]).is_equal(0.0)


func test_an_item_that_is_no_fuel_offers_nothing() -> void:
	_rules.generator.fuel = 10.0
	assert_float(_rules.tuning.economy.item(&"grenades").fuel_offer(1, 10.0)["units"]).is_equal(0.0)


func test_a_can_brings_a_dry_tank_back_and_the_lights_with_it() -> void:
	_rules.generator.fuel = 0.5
	RulesFixture.run(_rules, 30.0)
	assert_float(_rules.generator.fuel).is_equal(0.0)
	assert_bool(_rules.generator.is_powered()).is_false()
	assert_int(_log.count(&"fuel_empty")).is_equal(1)
	assert_bool(_rules.generator.is_lit(&"screen_lot")).is_false()
	assert_int(RulesFixture.buy(_rules, 1, CAN)).is_equal(GameRules.BuyResult.OK)
	assert_float(_rules.generator.fuel).is_equal_approx(_can().amount, 0.05)
	assert_bool(_rules.generator.is_powered()).is_true()
	assert_int(_log.count(&"fuel_restored")).is_equal(1)
	assert_bool(_rules.generator.is_lit(&"screen_lot")).is_true()
	# The refill is announced as fuel gained, which is what shows the generator's card.
	var changes := _log.of(&"fuel_changed")
	assert_float(changes.back()["delta"]).is_greater(0.0)


func test_a_player_who_cannot_pay_is_refused_and_the_tank_stays_dry() -> void:
	var poor := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(poor)
	poor.round_number = 7
	poor.generator.fuel = 0.0
	assert_int(poor.price_of(CAN)).is_greater(poor.points_of(1))
	assert_int(RulesFixture.buy(poor, 1, CAN)).is_equal(GameRules.BuyResult.NOT_ENOUGH_POINTS)
	assert_float(poor.generator.fuel).is_equal(0.0)


func test_a_can_costs_what_the_offer_said() -> void:
	_rules.generator.fuel = 0.0
	var offer := _offer()
	var before := _rules.points_of(1)
	RulesFixture.buy(_rules, 1, CAN)
	assert_int(before - _rules.points_of(1)).is_equal(offer["price"])
