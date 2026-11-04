# The two places the bots' shopping followed the simulator's players late (#767): a rookie fills up
# for the special round the marquee announces, and weighs a weapon by the health of the round's dead
# as the model does, so a first boss night is met with the kit the model's weak player has. The
# chooser is a pure function of its view (`test_bot_economy.gd`).
extends GdUnitTestSuite

const PISTOL := &"pistol"
const CROWBAR := &"crowbar"
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
			"kind": &"ammo",
			"shop_id": &"",
			"position": Vector3(40.0, 0.0, 20.0),
			"crane_spot": 0,
		},
	]


func _view(points: int, changes: Dictionary = {}) -> BotEconomy.View:
	var view := BotEconomy.View.new()
	view.points = points
	view.doors_open = ALL_DOORS.duplicate()
	view.arms = {PISTOL: [10, 80, 0], CROWBAR: [0, 0, 0]}
	view.held = PISTOL
	for key: String in changes:
		view.set(key, changes[key])
	return view


func _choose(view: BotEconomy.View, profile: BotProfile = null) -> BotEconomy.Buy:
	var economy := BotEconomy.new(_shop, profile if profile != null else BotProfile.regular())
	return economy.choose(view)


func test_a_rookie_fills_up_for_a_special_round_and_a_regular_does_not() -> void:
	# Four magazines of 10 (the pistol's), a full reserve being 80: above the rookie's floor of two
	# magazines, under the six it keeps once the marquee has announced a special round.
	var arms := {"arms": {PISTOL: [10, 40, 0], CROWBAR: [0, 0, 0]}}
	assert_bool(_choose(_view(100, arms), BotProfile.rookie()).is_none()).is_true()
	var announced := arms.merged({"prepared": true})
	var buy := _choose(_view(100, announced), BotProfile.rookie())
	assert_str(String(buy.why)).is_equal("ammo_floor")
	assert_str(String(buy.item)).is_equal("ammo_pistol")
	# Past that floor it tops the reserve up to the limit, whatever its usual share.
	var most := {"arms": {PISTOL: [10, 70, 0], CROWBAR: [0, 0, 0]}}
	assert_bool(_tops_up(_view(2000, most), BotProfile.rookie())).is_false()
	most["prepared"] = true
	assert_bool(_tops_up(_view(2000, most), BotProfile.rookie())).is_true()
	var regular := BotProfile.regular()
	assert_int(regular.prepared_mags).is_equal(0)
	assert_str(String(_choose(_view(100, announced), regular).why)).is_not_equal("ammo_floor")


func _tops_up(view: BotEconomy.View, profile: BotProfile) -> bool:
	for buy in BotEconomy.new(_shop, profile).candidates(view):
		if buy.why == &"top_off":
			return true
	return false


func test_a_rookie_leaves_a_shotgun_to_the_thin_dead_of_the_early_rounds() -> void:
	var tuning := RulesFixture.tuning()
	var carried := {PISTOL: [10, 80, 0]}
	var early := tuning.rounds.health_for_round(1)
	# A free hand takes anything in the old rule, and what beats the quick melee when it weighs.
	assert_bool(BotEconomy.worth_taking(_view(900, {"arms": carried}), SHOTGUN)).is_true()
	var thin := _view(900, {"arms": carried, "zombie_health": early})
	assert_bool(BotEconomy.worth_taking(thin, SHOTGUN)).is_false()
	# On round 1 the quick melee kills in one blow (83 health a second), so no gun beats it by half;
	# from round 2 (two blows, 48) the rifle does.
	assert_bool(BotEconomy.worth_taking(thin, RIFLE)).is_false()
	var round_two := _view(
		900, {"arms": carried, "zombie_health": tuning.rounds.health_for_round(2)}
	)
	assert_bool(BotEconomy.worth_taking(round_two, RIFLE)).is_true()
	# Only the rookie weighs so, and the simulator's weak player is the one it follows.
	assert_bool(BotProfile.rookie().weighs_by_round).is_true()
	assert_bool(BotProfile.regular().weighs_by_round).is_false()
	for weapon in [SHOTGUN, RIFLE, &"smg", &"baseball_bat", &"flare_gun", &"crowbar"]:
		for round_number in [1, 3, 5, 8]:
			var health := tuning.rounds.health_for_round(round_number)
			var bot := BotEconomy.worth_taking(
				_view(900, {"arms": carried, "zombie_health": health}), weapon
			)
			var model := WeaponWorth.beats(
				WeaponCatalog.get_def(weapon), WeaponCatalog.quick_melee(), health
			)
			(
				assert_bool(bot)
				. override_failure_message("%s round %d" % [weapon, round_number])
				. is_equal(model)
			)


func test_the_rookie_prepares_for_a_special_round_as_the_simulators_players_do() -> void:
	assert_int(BotProfile.rookie().prepared_mags).is_equal(NightSim.PREPARED_MAGS)
