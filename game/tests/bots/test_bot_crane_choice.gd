# What a bot decides about the crane (#1322) as a table: the chance of a prize it would take, the
# play it does not pay for, and the round it passes. No night, no server: `BotEconomy` is a pure
# function of its view. The suite of the same bots on a real server step is
# `tests/night/test_bot_crane.gd`.
extends GdUnitTestSuite

const PISTOL := &"pistol"
const RIFLE := &"rifle"
const SHOTGUN := &"shotgun"
const ALL_DOORS: Array = [
	&"door_concession", &"door_booth", &"door_back_lot", &"door_yard", &"door_road"
]

var _shop: BotShop


func before_test() -> void:
	_shop = BotShop.new()
	_shop.economy = RulesFixture.tuning().economy
	_shop.fuel = RulesFixture.tuning().fuel
	_shop.spots = [
		{
			"kind": &"crane",
			"shop_id": &"crane_play",
			"position": Vector3(20.0, 0.0, 20.0),
			"crane_spot": 0,
		},
		{
			"kind": &"crane",
			"shop_id": &"crane_play",
			"position": Vector3(30.0, 0.0, 20.0),
			"crane_spot": 1,
		},
	]


func _view(points: int, changes: Dictionary = {}) -> BotEconomy.View:
	var view := BotEconomy.View.new()
	view.points = points
	view.doors_open = ALL_DOORS.duplicate()
	view.arms = {PISTOL: [10, 80, 0]}
	view.held = PISTOL
	view.grenades = 2
	for key: String in changes:
		view.set(key, changes[key])
	return view


func _choose(view: BotEconomy.View, profile: BotProfile) -> BotEconomy.Buy:
	return BotEconomy.new(_shop, profile).choose(view)


func _profile() -> BotProfile:
	var profile := BotProfile.regular()
	profile.shopping.assign([&"crane_play"])
	profile.saves_for.clear()
	return profile


func test_the_crane_is_not_played_for_a_slim_chance_of_a_prize_worth_taking() -> void:
	# Against round 12's dead (192 health) a pair of a rifle and a shotgun is beaten, by 1.5 times, by
	# two prizes of seventeen less what it carries: the 50 caliber and the ray gun (#1322).
	var profile := _profile()
	var item := _shop.economy.item(&"crane_play")
	var arms := {RIFLE: [8, 80, 0], SHOTGUN: [6, 60, 0]}
	var tough := _view(5000, {"arms": arms, "held": RIFLE, "zombie_health": 192.0})
	var odds := BotEconomy.crane_odds(tough, item)
	assert_float(odds).is_greater(0.0)
	assert_float(odds).is_less(profile.crane_min_odds)
	assert_bool(_choose(tough, profile).is_none()).is_true()
	# A bot that plays for any chance (`crane_min_odds` 0) still does, as it did.
	profile.crane_min_odds = 0.0
	assert_str(String(_choose(tough, profile).item)).is_equal("crane_play")


func test_the_odds_of_the_crane_are_the_weight_of_the_prizes_a_bot_would_take() -> void:
	var item := _shop.economy.item(&"crane_play")
	# Not weighing by the round, a free hand takes anything it does not carry: every prize.
	var free := _view(900, {"arms": {PISTOL: [10, 80, 0]}})
	assert_float(BotEconomy.crane_odds(free, item)).is_equal(1.0)
	# A bot that carries every prize has no chance of one.
	var every: Dictionary = {}
	for prize in item.pool:
		every[WeaponCatalog.catalog_id(prize)] = [1, 1, 0]
	assert_float(BotEconomy.crane_odds(_view(900, {"arms": every}), item)).is_equal(0.0)


func test_a_bot_that_left_the_prize_on_the_glass_does_not_play_again_until_something_changed(
) -> void:
	var profile := _profile()
	var passed := _view(600, {"crane_spot": 1, "crane_passed": true})
	assert_bool(_choose(passed, profile).is_none()).is_true()
	assert_str(String(_choose(_view(600, {"crane_spot": 1}), profile).item)).is_equal("crane_play")
	# The belief holds for the round and the weapons it was formed with, no longer.
	var beliefs := BotBeliefs.new()
	var carried := {PISTOL: [10, 80, 0]}
	beliefs.pass_crane(3, carried)
	assert_bool(beliefs.passed_crane(3, carried)).is_true()
	assert_bool(beliefs.passed_crane(4, carried)).is_false()
	assert_bool(beliefs.passed_crane(3, {PISTOL: [0, 0, 0], SHOTGUN: [6, 60, 0]})).is_false()
	assert_bool(beliefs.passed_crane(3, {PISTOL: [3, 7, 1]})).is_true()
