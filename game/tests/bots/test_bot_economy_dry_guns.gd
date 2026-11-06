# The shopping chooser with two dry guns, the one worth the rounds not in hand (#1346): the soak
# found two nights of a hundred where a lone bot stood a boss round out holding 1 780 and 235 points
# and the start pistol and the freeze gun, both empty. `test_bot_economy_rounds.gd` has the table.
extends GdUnitTestSuite

const PISTOL := &"pistol"
const RIFLE := &"rifle"
## The locker of the shop, where rounds are sold.
const NEAR_LOCKER := Vector3(40.0, 0.0, 20.0)
const ALL_DOORS: Array = [
	&"door_concession", &"door_booth", &"door_back_lot", &"door_yard", &"door_road"
]
const HOUSE_PISTOL := &"house_pistol"
const FREEZE_GUN := &"freeze_gun"

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
		_spot(&"ammo", &"", NEAR_LOCKER),
	]


func _spot(kind: StringName, shop_id: StringName, at: Vector3) -> Dictionary:
	return {"kind": kind, "shop_id": shop_id, "position": at, "crane_spot": 0}


## A view of a bot in a break of round 1 with every door open (so the doors are not what it wants).
func _view(points: int, changes: Dictionary = {}) -> BotEconomy.View:
	var view := BotEconomy.View.new()
	view.points = points
	view.doors_open = ALL_DOORS.duplicate()
	view.arms = {PISTOL: [10, 80, 0]}
	view.held = PISTOL
	for key: String in changes:
		view.set(key, changes[key])
	return view


func _choose(view: BotEconomy.View) -> BotEconomy.Buy:
	return BotEconomy.new(_shop, BotProfile.regular()).choose(view)


## A bot holding the empty start pistol with the crane's freeze gun empty in the pack: the freeze
## gun is the only gun worth rounds (`BotEconomy.useful`), the shop has no wall for it, and the
## locker sells for the weapon in hand. The soak found two nights of 100 where such a bot stood
## the last round out, holding 1 780 points.
func _two_dry_guns(changes: Dictionary = {}) -> BotEconomy.View:
	return _view(
		1780,
		(
			{
				"arms": {HOUSE_PISTOL: [0, 0, 0], FREEZE_GUN: [0, 0, 0]},
				"held": HOUSE_PISTOL,
				"doors_open": ALL_DOORS.duplicate()
			}
			. merged(changes, true)
		)
	)


func test_a_bot_holding_a_dry_start_pistol_buys_rounds_for_the_dry_gun_worth_them() -> void:
	(
		assert_array(BotEconomy.useful({HOUSE_PISTOL: [0, 0, 0], FREEZE_GUN: [0, 0, 0]}))
		. contains_exactly([FREEZE_GUN])
	)
	var buy := _choose(_two_dry_guns())
	assert_str(String(buy.item)).is_equal("ammo_freeze_gun")
	assert_vector(buy.stand).is_equal(NEAR_LOCKER)
	# It is not calm (the headliner is out), and the rounds are still the first thing it wants.
	var in_the_fight := _choose(_two_dry_guns({"in_break": false, "remaining": 1}))
	assert_str(String(in_the_fight.item)).is_equal("ammo_freeze_gun")


func test_the_locker_still_sells_for_the_weapon_in_hand_while_it_has_rounds() -> void:
	# The rifle in hand has rounds; the dry freeze gun in the pack waits for the rifle to run out.
	var view := _two_dry_guns({"arms": {RIFLE: [8, 80, 0], FREEZE_GUN: [0, 0, 0]}, "held": RIFLE})
	assert_bool(_choose(view).item == &"ammo_freeze_gun").is_false()


func test_a_bot_with_no_round_and_too_few_points_for_the_dry_gun_buys_the_start_pistols_rounds(
) -> void:
	# The freeze gun's three rounds cost 150 and the start pistol's thirty cost 40: a bot with 100
	# points and nothing to fire (the nightly's seed 55, 105 points, crowbar in hand) took neither
	# and stood the boss round out, earning nothing.
	var broke := _choose(_two_dry_guns({"points": 100}))
	assert_str(String(broke.item)).is_equal("ammo_house_pistol")
	assert_str(String(broke.why)).is_equal("ammo_urgent")
	assert_vector(broke.stand).is_equal(NEAR_LOCKER)
	# With the points for the gun worth the rounds and the pistol's after them, those come first;
	# a bot that spent the 40 would have nothing to fire and nothing to earn with again.
	assert_str(String(_choose(_two_dry_guns({"points": 190})).item)).is_equal("ammo_freeze_gun")
	assert_str(String(_choose(_two_dry_guns({"points": 180})).item)).is_equal("ammo_house_pistol")


func test_a_bot_with_a_loaded_gun_does_not_buy_rounds_for_the_gun_not_worth_them() -> void:
	var view := _two_dry_guns({"arms": {HOUSE_PISTOL: [0, 0, 0], FREEZE_GUN: [6, 0, 0]}})
	view.points = 100
	assert_bool(_choose(view).item == &"ammo_house_pistol").is_false()
