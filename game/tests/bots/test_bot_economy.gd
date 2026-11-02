# The economy chooser of the bots (bots plan, phase 4) as a table: the points, the prices and what
# the bot carries go in, the purchase comes out. No night, no server: `BotEconomy` is a pure
# function of its view, so every rule is a row here.
extends GdUnitTestSuite

const PISTOL := &"pistol"
const CROWBAR := &"crowbar"
const RIFLE := &"rifle"
const SHOTGUN := &"shotgun"
const NONE := &""
const ALL_DOORS: Array = [
	&"door_concession", &"door_booth", &"door_back_lot", &"door_yard", &"door_road"
]

var _shop: BotShop


func before_test() -> void:
	_shop = BotShop.new()
	_shop.economy = RulesFixture.tuning().economy
	_shop.fuel = RulesFixture.tuning().fuel
	for item in _shop.economy.items:
		match item.kind:
			ShopItem.Kind.DOOR:
				_shop.doors.append(item.id)
				_shop.door_stands[item.id] = [Vector3(float(_shop.doors.size()) * 10.0, 0.0, 0.0)]
			ShopItem.Kind.FUEL:
				_shop.fuel_item = item
	_shop.spots = [
		_spot(&"wall", &"weapon_shotgun", Vector3(0.0, 0.0, 20.0)),
		_spot(&"wall", &"weapon_rifle", Vector3(10.0, 0.0, 20.0)),
		_spot(&"crane", &"crane_play", Vector3(20.0, 0.0, 20.0), 0),
		_spot(&"crane", &"crane_play", Vector3(30.0, 0.0, 20.0), 1),
		_spot(&"ammo", &"", Vector3(40.0, 0.0, 20.0)),
		_spot(&"upgrade", &"upgrade_weapon", Vector3(50.0, 0.0, 20.0)),
		_spot(&"perk", &"tonic_hearty", Vector3(60.0, 0.0, 20.0)),
		_spot(&"perk", &"tonic_second_wind", Vector3(70.0, 0.0, 20.0)),
	]


func _spot(kind: StringName, shop_id: StringName, at: Vector3, crane_spot := 0) -> Dictionary:
	return {"kind": kind, "shop_id": shop_id, "position": at, "crane_spot": crane_spot}


## A view of a bot with the pistol in hand and the crowbar, in a break of round 1, full reserve,
## every door open (a test about doors shuts them with `doors_open`).
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


func _profile(list: Array[StringName], saves: Array[StringName] = []) -> BotProfile:
	var profile := BotProfile.regular()
	profile.shopping.assign(list)
	profile.saves_for.assign(saves)
	return profile


# --- Which purchase, from what the bot holds ---


func test_a_bot_with_only_its_start_points_and_full_reserves_buys_nothing() -> void:
	assert_bool(_choose(_view(200, {"doors_open": []})).is_none()).is_true()


func test_the_first_door_in_the_plan_is_bought_when_it_can_be_paid() -> void:
	assert_bool(_choose(_view(349, {"doors_open": []})).is_none()).is_true()
	var buy := _choose(_view(350, {"doors_open": []}))
	assert_str(String(buy.item)).is_equal("door_concession")
	assert_str(String(buy.prompt)).is_equal("door")
	assert_vector(buy.stand).is_equal(_shop.door_stands[&"door_concession"][0])


func test_the_weak_bot_plan_buys_in_its_own_order() -> void:
	# The weak player's list begins with the concession door, then a crane play, then the shotgun.
	var rookie := BotProfile.rookie()
	var view := _view(900, {"doors_open": [&"door_concession"], "crane_spot": 1})
	assert_str(String(_choose(view, rookie).item)).is_equal("crane_play")
	assert_vector(_choose(view, rookie).stand).is_equal(Vector3(30.0, 0.0, 20.0))


func test_an_unaffordable_item_is_passed_over_and_the_next_that_can_be_paid_is_bought() -> void:
	# The regular list starts with the shotgun (900); with 400 the concession door (350) is next.
	assert_str(String(_choose(_view(400, {"doors_open": []})).item)).is_equal("door_concession")


func test_an_item_the_bot_saves_for_stops_the_list_there() -> void:
	var profile := _profile([&"upgrade_weapon", &"door_back_lot"], [&"upgrade_weapon"])
	var view := _view(1300, {"doors_open": [&"door_concession", &"door_booth"]})
	assert_bool(_choose(view, profile).is_none()).is_true()
	var enough := _view(1500, {"doors_open": [&"door_concession", &"door_booth"]})
	assert_str(String(_choose(enough, profile).item)).is_equal("upgrade_weapon")
	var no_saving := _profile([&"upgrade_weapon", &"door_back_lot"])
	assert_str(String(_choose(view, no_saving).item)).is_equal("door_back_lot")


func test_a_door_is_bought_only_when_the_one_before_it_is_open() -> void:
	var profile := _profile([&"door_booth"])
	assert_bool(_choose(_view(5000, {"doors_open": []}), profile).item == &"door_booth").is_false()
	var view := _view(5000, {"doors_open": [&"door_concession"]})
	assert_str(String(_choose(view, profile).item)).is_equal("door_booth")


func test_doors_the_list_lacks_come_after_it_in_the_table_order() -> void:
	var economy := BotEconomy.new(_shop, _profile([&"door_booth"]))
	var order := economy.plan()
	assert_str(String(order[0])).is_equal("door_booth")
	assert_array(order.slice(1)).is_equal(
		[&"door_concession", &"door_back_lot", &"door_yard", &"door_road"]
	)


func test_a_wall_weapon_is_bought_only_when_it_beats_the_weakest_weapon_carried() -> void:
	var profile := _profile([&"weapon_shotgun"])
	var carried := _view(900)
	assert_str(String(_choose(carried, profile).item)).is_equal("weapon_shotgun")
	# Full hands: the weapon must be worth 1.5 times the weakest carried (not the one in hand).
	var strong := {RIFLE: [8, 80, 0], &"smg": [30, 180, 0]}
	var weakest := BotEconomy.weakest_of(strong)
	var wanted := WeaponWorth.beats(WeaponCatalog.get_def(SHOTGUN), WeaponCatalog.get_def(weakest))
	var full := _view(900, {"arms": strong, "held": RIFLE})
	assert_bool(_choose(full, profile).is_none()).is_equal(not wanted)
	var pistol_and_rifle := {RIFLE: [8, 80, 0], PISTOL: [10, 80, 0]}
	assert_str(String(BotEconomy.weakest_of(pistol_and_rifle))).is_equal("pistol")
	var rifle := _view(900, {"arms": pistol_and_rifle, "held": RIFLE})
	assert_bool(BotEconomy.worth_taking(rifle, SHOTGUN)).is_equal(
		WeaponWorth.beats(WeaponCatalog.get_def(SHOTGUN), WeaponCatalog.get_def(PISTOL))
	)
	# The flare gun is worth less than a rifle: nobody gives a rifle for it.
	(
		assert_bool(
			BotEconomy.worth_taking(_view(900, {"arms": strong, "held": RIFLE}), &"flare_gun")
		)
		. is_false()
	)
	# A free hand takes anything it does not already have.
	var free := _view(900, {"arms": {PISTOL: [10, 80, 0]}})
	assert_str(String(_choose(free, profile).item)).is_equal("weapon_shotgun")
	var owned := _view(900, {"arms": {SHOTGUN: [6, 60, 0], PISTOL: [10, 80, 0]}})
	assert_bool(_choose(owned, profile).is_none()).is_true()


func test_the_crane_is_played_only_where_it_stands_and_only_for_a_prize_worth_taking() -> void:
	var profile := _profile([&"crane_play"])
	var view := _view(600, {"crane_spot": 1})
	var buy := _choose(view, profile)
	assert_str(String(buy.item)).is_equal("crane_play")
	assert_vector(buy.stand).is_equal(Vector3(30.0, 0.0, 20.0))
	(
		assert_bool(_choose(_view(600, {"crane_spot": 1, "crane_ready": false}), profile).is_none())
		. is_true()
	)


func test_the_re_cut_is_for_a_firearm_in_hand_that_has_not_been_cut() -> void:
	var profile := _profile([&"upgrade_weapon"])
	assert_str(String(_choose(_view(1500), profile).item)).is_equal("upgrade_weapon")
	var cut := _view(1500, {"arms": {PISTOL: [10, 80, 1], CROWBAR: [0, 0, 0]}})
	assert_bool(_choose(cut, profile).is_none()).is_true()
	var blade := _view(1500, {"held": CROWBAR})
	assert_bool(_choose(blade, profile).is_none()).is_true()
	var two := BotProfile.veteran()
	two.shopping.assign([&"upgrade_weapon"])
	var one_cut := _view(1500, {"arms": {PISTOL: [10, 80, 1], RIFLE: [8, 80, 0]}, "held": RIFLE})
	assert_str(String(_choose(one_cut, two).item)).is_equal("upgrade_weapon")
	assert_bool(_choose(one_cut, profile).is_none()).is_true()


func test_only_a_tonic_that_does_something_is_bought_and_only_once() -> void:
	assert_str(String(_choose(_view(1000), _profile([&"tonic_hearty"])).item)).is_equal(
		"tonic_hearty"
	)
	(
		assert_bool(
			_choose(_view(1500), _profile([&"tonic_second_wind", &"tonic_fleet"])).is_none()
		)
		. is_true()
	)
	var had := _view(1000, {"bought": {&"tonic_hearty": 1}})
	assert_bool(_choose(had, _profile([&"tonic_hearty"])).is_none()).is_true()
