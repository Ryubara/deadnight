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
		_spot(&"rack", &"grenades", Vector3(80.0, 0.0, 20.0)),
	]
	# One machine for every other tonic, further along the same row.
	var at := 70.0
	for tonic_id in PerkEffects.tonic_ids(_shop.economy):
		if tonic_id != &"tonic_hearty":
			_shop.spots.append(_spot(&"perk", tonic_id, Vector3(at, 0.0, 20.0)))
			at += 10.0


func _spot(kind: StringName, shop_id: StringName, at: Vector3, crane_spot := 0) -> Dictionary:
	return {"kind": kind, "shop_id": shop_id, "position": at, "crane_spot": crane_spot}


## A view of a bot with the pistol in hand and the crowbar, in a break of round 1, full reserve,
## the two grenades it starts with, every door open (a test about doors shuts them with
## `doors_open`).
## The re-cut's price in the shipped shop (5,000 flat, #909).
func _recut_price() -> int:
	return _shop.economy.item(&"upgrade_weapon").price


func _view(points: int, changes: Dictionary = {}) -> BotEconomy.View:
	var view := BotEconomy.View.new()
	view.points = points
	view.doors_open = ALL_DOORS.duplicate()
	view.arms = {PISTOL: [10, 80, 0], CROWBAR: [0, 0, 0]}
	view.held = PISTOL
	view.grenades = 2
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


func test_a_door_with_a_stand_a_flight_up_is_bought_from_the_stand_on_the_bots_floor() -> void:
	# A link set in a stair has a stand at its foot and one up the flight (the second map's): the
	# bot on the ground floor goes to the foot though the upper stand is flat-nearer, the bot on
	# the upper floor to the upper one.
	var foot := Vector3(0.0, 0.0, 0.0)
	var up := Vector3(3.0, 1.0, 0.0)
	_shop.door_stands[&"door_concession"] = [foot, up]
	var ground := _choose(_view(400, {"doors_open": [], "here": Vector3(4.0, 0.0, 0.0)}))
	assert_vector(ground.stand).is_equal(foot)
	var upstairs := _choose(_view(400, {"doors_open": [], "here": Vector3(9.0, 3.4, 0.0)}))
	assert_vector(upstairs.stand).is_equal(up)


func test_a_weapon_sold_on_two_floors_is_bought_on_the_bots_floor() -> void:
	# The second map sells the shotgun in the side room and upstairs. From the stair landing the two
	# are about the same flat metres away, and the flat nearest flipped with every step: the bot
	# walked to and fro on the landing and bought nothing (#811, #821). A metre of height counts.
	var side := Vector3(14.65, 0.0, -6.0)
	var upstairs := Vector3(5.0, 3.4, -6.5)
	_shop.spots = [
		_spot(&"wall", &"weapon_shotgun", side), _spot(&"wall", &"weapon_shotgun", upstairs)
	]
	for x in [8.9, 9.7, 10.3, 10.8]:
		var view := _view(900, {"here": Vector3(x, 3.4, 0.9)})
		var buy := _choose(view, _profile([&"weapon_shotgun"]))
		assert_vector(buy.stand).override_failure_message("from x %s" % x).is_equal(upstairs)
	var ground := _choose(
		_view(900, {"here": Vector3(9.0, 0.0, 0.9)}), _profile([&"weapon_shotgun"])
	)
	assert_vector(ground.stand).is_equal(side)


func test_the_stand_a_bot_is_walking_to_is_kept_against_a_second_seller() -> void:
	# Two stands on one floor, 1 m nearer for the other as the bot moves: it keeps its heading.
	var east := Vector3(10.0, 0.0, 0.0)
	var west := Vector3(-10.0, 0.0, 0.0)
	_shop.spots = [_spot(&"wall", &"weapon_shotgun", east), _spot(&"wall", &"weapon_shotgun", west)]
	var profile := _profile([&"weapon_shotgun"])
	var near_west := _view(900, {"here": Vector3(-1.0, 0.0, 0.0)})
	assert_vector(_choose(near_west, profile).stand).is_equal(west)
	near_west.heading = east
	assert_vector(_choose(near_west, profile).stand).is_equal(east)


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
	var enough := _view(_recut_price(), {"doors_open": [&"door_concession", &"door_booth"]})
	assert_str(String(_choose(enough, profile).item)).is_equal("upgrade_weapon")
	var no_saving := _profile([&"upgrade_weapon", &"door_back_lot"])
	assert_str(String(_choose(view, no_saving).item)).is_equal("door_back_lot")


func test_a_map_can_name_what_its_bots_save_for_over_the_profiles_list() -> void:
	# The second map's overlay (`bot_saves_for`): the first gun is not put off by a link that costs
	# less, so with 400 the bot waits for the shotgun (900) instead of buying the concession.
	var profile := _profile([&"weapon_shotgun", &"door_concession"])
	var view := _view(400, {"doors_open": []})
	assert_str(String(_choose(view, profile).item)).is_equal("door_concession")
	_shop.saves_for.assign([&"weapon_shotgun"])
	assert_bool(_choose(view, profile).is_none()).is_true()
	assert_str(String(_choose(_view(900, {"doors_open": []}), profile).item)).is_equal(
		"weapon_shotgun"
	)


func test_on_a_team_links_map_a_gun_in_reach_comes_before_the_links_after_it() -> void:
	# A bot with only its start gun that can pay for the shotgun is offered nothing after it (the
	# team link rule would buy the next door first, #910); a bot with a second gun still is.
	var profile := _profile([&"weapon_shotgun", &"door_booth"])
	var start_only := {WeaponCatalog.START_WEAPON: [10, 80, 0], CROWBAR: [0, 0, 0]}
	var view := _view(1300, {"doors_open": [&"door_concession"], "arms": start_only})
	assert_array(_items(BotEconomy.new(_shop, profile).candidates(view))).contains([&"door_booth"])
	_shop.team_links = true
	assert_array(_items(BotEconomy.new(_shop, profile).candidates(view))).is_equal(
		[&"weapon_shotgun"]
	)
	var armed := _view(1300, {"doors_open": [&"door_concession"], "arms": start_only.duplicate()})
	armed.arms[&"smg"] = [30, 120, 0]
	assert_array(_items(BotEconomy.new(_shop, profile).candidates(armed))).contains([&"door_booth"])


func _items(found: Array[BotEconomy.Buy]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for buy in found:
		ids.append(buy.item)
	return ids


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
	assert_str(String(_choose(_view(_recut_price()), profile).item)).is_equal("upgrade_weapon")
	var cut := _view(_recut_price(), {"arms": {PISTOL: [10, 80, 1], CROWBAR: [0, 0, 0]}})
	assert_bool(_choose(cut, profile).is_none()).is_true()
	var blade := _view(_recut_price(), {"held": CROWBAR})
	assert_bool(_choose(blade, profile).is_none()).is_true()
	var two := BotProfile.veteran()
	two.shopping.assign([&"upgrade_weapon"])
	var one_cut := _view(
		_recut_price(), {"arms": {PISTOL: [10, 80, 1], RIFLE: [8, 80, 0]}, "held": RIFLE}
	)
	assert_str(String(_choose(one_cut, two).item)).is_equal("upgrade_weapon")
	assert_bool(_choose(one_cut, profile).is_none()).is_true()


func test_a_bot_under_two_grenades_with_points_to_spare_buys_more() -> void:
	var item := _shop.economy.item(&"grenades")
	var buy := _choose(_view(1000, {"grenades": 1}), _profile([]))
	assert_str(String(buy.item)).is_equal("grenades")
	assert_str(String(buy.prompt)).is_equal("grenades")
	assert_int(buy.price).is_equal(item.price_at(1))
	assert_vector(buy.stand).is_equal(Vector3(80.0, 0.0, 20.0))
	# At two it has enough; with the points of nothing else to buy it buys nothing more.
	assert_bool(_choose(_view(1000, {"grenades": 2}), _profile([])).is_none()).is_true()
	# Short of the price, it waits.
	assert_bool(_choose(_view(item.price - 1, {"grenades": 0}), _profile([])).is_none()).is_true()


func test_grenades_wait_for_the_next_thing_on_the_list_and_for_a_calm_hour() -> void:
	var item := _shop.economy.item(&"grenades")
	var list := _profile([&"weapon_shotgun"], [&"weapon_shotgun"])
	# The shotgun is the next thing: the points that would buy a grenade and not the shotgun stay.
	assert_bool(_choose(_view(item.price + 50, {"grenades": 0}), list).is_none()).is_true()
	var spare := _view(900 + item.price, {"grenades": 0})
	# Nothing to buy first: the shotgun is bought, not grenades.
	assert_str(String(_choose(spare, list).item)).is_equal("weapon_shotgun")
	var busy := _view(1000, {"grenades": 0, "in_break": false, "remaining": 30})
	assert_bool(_choose(busy, _profile([])).is_none()).is_true()
	var never := _profile([])
	never.grenades_wanted = 0
	assert_bool(_choose(_view(1000, {"grenades": 0}), never).is_none()).is_true()


func test_a_pack_with_room_for_one_buys_one_at_its_share_of_the_price() -> void:
	var item := _shop.economy.item(&"grenades")
	var buy := _choose(_view(1000, {"grenades": 4}), _profile([]))
	assert_bool(buy.is_none()).is_true()
	var wants_more := _profile([])
	wants_more.grenades_wanted = 5
	buy = _choose(_view(1000, {"grenades": 4}), wants_more)
	assert_int(buy.price).is_equal(ceili(float(item.price_at(1)) / item.amount))


func test_a_tonic_is_bought_while_the_bot_lacks_it_and_a_lost_one_again() -> void:
	var order := PerkEffects.tonic_ids(_shop.economy)
	var hearty := 1 << order.find(&"tonic_hearty")
	var encore := 1 << order.find(&"tonic_swift_rescue")
	var rewind := 1 << order.find(&"tonic_quick_load")
	var arc := 1 << order.find(&"tonic_reload_shock")
	assert_str(String(_choose(_view(1000), _profile([&"tonic_hearty"])).item)).is_equal(
		"tonic_hearty"
	)
	# Had: not again. Lost on a down (the mask no longer has it): bought again.
	var had := _view(1000, {"perks": hearty})
	assert_bool(_choose(had, _profile([&"tonic_hearty"])).is_none()).is_true()
	var lost := _view(1000, {"perks": 0})
	assert_str(String(_choose(lost, _profile([&"tonic_hearty"])).item)).is_equal("tonic_hearty")
	# A perk with an effect other than health is a purchase too, at the price the table has.
	var revive := _choose(_view(1500, {"perks": hearty}), _profile([&"tonic_swift_rescue"]))
	assert_str(String(revive.item)).is_equal("tonic_swift_rescue")
	assert_int(revive.price).is_equal(_shop.economy.item(&"tonic_swift_rescue").price)
	# The limit: a bot that carries as many as the rules allow buys no more.
	var full := hearty | encore | rewind | arc
	var more := _choose(_view(5000, {"perks": full}), _profile([&"tonic_double_shot"]))
	assert_bool(more.is_none()).is_true()
	# On a night with the perk limit lifted (#913) the same bot buys the fifth and the sixth.
	_shop.perk_limit = MatchSettings.UNLIMITED_PERKS
	var fifth := _choose(_view(5000, {"perks": full}), _profile([&"tonic_double_shot"]))
	assert_str(String(fifth.item)).is_equal("tonic_double_shot")
	var five := full | (1 << order.find(&"tonic_double_shot"))
	var sixth := _choose(_view(5000, {"perks": five}), _profile([&"tonic_third_holster"]))
	assert_str(String(sixth.item)).is_equal("tonic_third_holster")
	# The shop built for a night reads the limit off the match settings.
	var unlimited := MatchSettings.new()
	unlimited.perk_limit = MatchSettings.PERKS_UNLIMITED
	assert_int(unlimited.tonic_limit(_shop.economy)).is_equal(MatchSettings.UNLIMITED_PERKS)
	_shop.perk_limit = 0
	assert_int(_shop.tonic_limit()).is_equal(_shop.economy.max_tonics)
