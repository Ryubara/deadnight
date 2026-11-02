# The economy chooser of the bots (bots plan, phase 4), the second half of the table: rounds, the
# reserve kept back, refusals, the ping and the profiles. See `test_bot_economy.gd` for the first.
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


# --- Rounds ---


func test_a_reserve_under_a_magazine_buys_rounds_at_once_even_in_a_round() -> void:
	var low := _view(100, {"arms": {PISTOL: [4, 6, 0]}, "in_break": false, "remaining": 30})
	var buy := _choose(low)
	assert_str(String(buy.item)).is_equal("ammo_pistol")
	assert_str(String(buy.why)).is_equal("ammo_urgent")
	assert_str(String(buy.weapon)).is_equal("pistol")
	assert_vector(buy.stand).is_equal(Vector3(40.0, 0.0, 20.0))
	assert_int(buy.price).is_equal(_shop.economy.item(&"ammo_pistol").ammo_price(1, 20))


func test_a_short_reserve_is_filled_in_a_break_and_not_in_a_wave() -> void:
	# Three magazines for the regular bot, two for the rookie.
	var short := {"arms": {PISTOL: [10, 25, 0], CROWBAR: [0, 0, 0]}}
	assert_str(String(_choose(_view(100, short)).why)).is_equal("ammo_floor")
	assert_bool(_choose(_view(100, short), BotProfile.rookie()).is_none()).is_true()
	var wave := short.duplicate()
	wave["in_break"] = false
	wave["remaining"] = 30
	assert_bool(_choose(_view(100, wave)).is_none()).is_true()


func test_a_refill_that_would_fill_under_a_tenth_of_the_cap_is_not_bought() -> void:
	var def := WeaponCatalog.get_def(PISTOL)
	var nearly := def.reserve_max - int(float(def.reserve_max) * 0.05)
	var view := _view(500, {"arms": {PISTOL: [10, nearly, 0]}})
	assert_bool(_choose(view, _profile([])).is_none()).is_true()


func test_the_bot_tops_a_reserve_up_only_with_what_the_next_thing_on_its_list_leaves() -> void:
	var half := {"arms": {PISTOL: [10, 40, 0], CROWBAR: [0, 0, 0]}}
	var economy := BotEconomy.new(_shop, _profile([&"door_concession"]))
	half["doors_open"] = []
	# 360 points and the concession door at 350: the rounds (50) would take the door's money.
	var tight := economy.candidates(_view(360, half))
	assert_int(tight.size()).is_equal(1)
	assert_str(String(tight[0].item)).is_equal("door_concession")
	# With 400 there is the door's price and the rounds' too.
	var enough := economy.candidates(_view(400, half))
	assert_int(enough.size()).is_equal(2)
	assert_str(String(enough[1].why)).is_equal("top_off")
	# Nothing left on the list to save for: the rounds are bought.
	half["doors_open"] = ALL_DOORS.duplicate()
	var idle := BotEconomy.new(_shop, _profile([]))
	assert_str(String(idle.choose(_view(60, half)).why)).is_equal("top_off")


func test_a_slow_gun_that_is_no_use_is_not_fed() -> void:
	# The flare gun does a sliver of the pistol's damage a second: no rounds for it.
	var view := _view(500, {"arms": {PISTOL: [10, 80, 0], &"flare_gun": [1, 0, 0]}, "held": PISTOL})
	assert_bool(_choose(view, _profile([])).is_none()).is_true()


# --- Keeping back, refusing, the ping ---


func test_a_fuel_can_is_kept_back_from_round_three() -> void:
	var profile := _profile([&"door_concession"])
	var can := _shop.fuel_item.price_at(3)
	assert_int(can).is_greater(0)
	var shut := {"doors_open": []}
	(
		assert_bool(
			_choose(_view(350 + can - 1, shut.merged({"round_number": 3})), profile).is_none()
		)
		. is_true()
	)
	(
		assert_str(
			String(_choose(_view(350 + can, shut.merged({"round_number": 3})), profile).item)
		)
		. is_equal("door_concession")
	)
	(
		assert_str(String(_choose(_view(350, shut.merged({"round_number": 2})), profile).item))
		. is_equal("door_concession")
	)


func test_an_item_refused_lately_is_left_alone_until_the_back_off_is_over() -> void:
	var profile := _profile([&"door_concession", &"door_yard"])
	var view := _view(2000, {"doors_open": [], "now": 10.0, "denied": {&"door_concession": 40.0}})
	assert_bool(_choose(view, profile).item == &"door_concession").is_false()
	view.now = 40.5
	assert_str(String(_choose(view, profile).item)).is_equal("door_concession")


func test_a_door_the_etiquette_holds_back_from_is_passed_over() -> void:
	var profile := _profile([&"door_concession", &"door_yard"])
	var view := _view(2000, {"doors_open": [], "blocked": {&"door_concession": true}})
	assert_bool(_choose(view, profile).item == &"door_concession").is_false()


func test_a_door_a_person_pinged_comes_first_when_it_can_be_paid() -> void:
	var profile := _profile([&"upgrade_weapon", &"door_concession"], [&"upgrade_weapon"])
	var view := _view(520, {"doors_open": [&"door_concession"], "pinged": &"door_yard"})
	var buy := _choose(view, profile)
	assert_str(String(buy.item)).is_equal("door_yard")
	assert_str(String(buy.why)).is_equal("ping")
	var short := _view(499, {"doors_open": [&"door_concession"], "pinged": &"door_yard"})
	assert_bool(_choose(short, profile).is_none()).is_true()
	# The ping of a door that is locked, or that the etiquette holds, is no order.
	var locked := _view(5000, {"doors_open": [], "pinged": &"door_road"})
	assert_bool(_choose(locked, profile).item == &"door_road").is_false()


func test_a_door_is_bought_in_a_round_only_when_five_or_fewer_are_left() -> void:
	var profile := _profile([&"door_concession"])
	var wave := {"doors_open": [], "in_break": false}
	assert_bool(_choose(_view(400, wave.merged({"remaining": 6})), profile).is_none()).is_true()
	assert_str(String(_choose(_view(400, wave.merged({"remaining": 5})), profile).item)).is_equal(
		"door_concession"
	)


func test_the_next_price_is_the_first_thing_the_bot_wants_whether_or_not_it_can_pay() -> void:
	var economy := BotEconomy.new(_shop, BotProfile.regular())
	var view := _view(100, {"doors_open": []})
	assert_int(economy.next_price(view)).is_equal(900)
	view.doors_open = [&"door_concession"]
	view.arms = {SHOTGUN: [6, 60, 0], RIFLE: [8, 80, 0]}
	view.held = RIFLE
	assert_int(economy.next_price(view)).is_equal(750)


func test_the_phase_numbers_the_bots_read_are_the_rules() -> void:
	assert_int(BotErrands.BREAK_PHASE).is_equal(GameRules.Phase.BREAK)
	assert_int(BotErrands.ACTIVE_PHASE).is_equal(GameRules.Phase.ACTIVE)


func test_the_profiles_shop_as_the_simulators_matching_players_do() -> void:
	var pairs := {
		BotProfile.rookie(): SimSkill.named(SimSkill.WEAK),
		BotProfile.regular(): SimSkill.named(SimSkill.AVERAGE),
		BotProfile.veteran(): SimSkill.named(SimSkill.STRONG),
	}
	for profile: BotProfile in pairs:
		var skill: SimSkill = pairs[profile]
		assert_array(profile.shopping).override_failure_message(profile.title).is_equal(
			skill.shopping
		)
		assert_array(profile.saves_for).override_failure_message(profile.title).is_equal(
			skill.saves_for
		)
		assert_int(profile.ammo_floor_mags).override_failure_message(profile.title).is_equal(
			skill.ammo_floor_mags
		)
		assert_float(profile.ammo_topoff).override_failure_message(profile.title).is_equal(
			skill.ammo_topoff
		)
		assert_int(profile.re_cuts).override_failure_message(profile.title).is_equal(skill.re_cuts)
