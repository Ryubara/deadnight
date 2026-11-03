# The second map's economy and placement against rows 20 to 26 of
# docs/research/maps/small-map-formula.md ("Economy and placement targets"): one price for the three
# links that opens one at round 3, two at round 4 and three at round 5; the box in one place in the
# side room that never moves; the wall weapons 2 / 2 / 4 and a cabinet at prices that climb;
# the lot's machines (#792); at most 24 dead at once. Each test fails outside its tolerance,
# and the map's tuning
# (`smallmap_tuning.tres`) and the scene's markers must name the same things.
extends GdUnitTestSuite

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const TUNING := "res://world/smallmap/smallmap_tuning.tres"

## Row 21's count, the method of `test_door_affordability.gd`: a player earns this per zombie on
## average, a half of it goes on doors, no starting points and no round bonus.
const POINTS_PER_ZOMBIE := 85.0
const DOOR_SHARE := 0.5
const LAST_ROUND := 60
## Row 24: each price within this share of its ratio of the link price.
const PRICE_TOLERANCE := 0.10

## Row 24: the ratio of the link price each wall weapon sells at, by room: the start room's two, the
## side room's two, and the upstairs' range (the four and the cabinet).
const START_RATIOS: Array[float] = [0.2, 0.6]
const SIDE_RATIO := 1.2
const UPSTAIRS_RATIO_FROM := 1.2
const UPSTAIRS_RATIO_TO := 1.8

## The three walls of the second batch of firearms (#793): the pump in the side room, the MP5
## and the M4A1 upstairs, at the ratios of docs/design/weapons.md (0.9, 1.7 and 2.1 of the link
## price). Rows 23 and 24 are about the formula's eight walls and count these apart.
const NEW_WALLS := {&"weapon_pump_870": 0.9, &"weapon_mp5": 1.7, &"weapon_m4a1": 2.1}

var _map: MapTuning
var _rules: RulesTuning
var _lot: Node3D
var _spots: Array[Dictionary] = []


func before_test() -> void:
	_map = load(TUNING) as MapTuning
	_rules = _map.apply(RulesFixture.tuning())
	_lot = auto_free((load(SCENE) as PackedScene).instantiate()) as Node3D
	add_child(_lot)
	_spots.clear()
	for marker in _lot.get_node("ShopSpots").get_children():
		(
			_spots
			. append(
				{
					"name": marker.name,
					"kind": StringName(marker.get_meta("kind")),
					"shop_id": StringName(marker.get_meta("shop_id")),
					"room": String(marker.get_meta("room")),
					"position": (marker as Node3D).global_position,
					"cabinet": marker.has_meta("cabinet"),
					"crane_spot": int(marker.get_meta("crane_spot", -1)),
				}
			)
		)


func _price(item_id: StringName) -> int:
	return _rules.economy.item(item_id).price


func _link_price() -> int:
	return _map.link_price()


## The first round at whose end `total` points have been earned for doors (-1 for never).
func _first_affordable_round(total: int) -> int:
	var points := 0.0
	for round_number in range(1, LAST_ROUND + 1):
		points += POINTS_PER_ZOMBIE * _rules.rounds.zombies_for_round(round_number, 1)
		if points * DOOR_SHARE >= total:
			return round_number
	return -1


## The formula's walls in a room: the new firearms' are counted apart (`NEW_WALLS`).
func _walls_in(room: String) -> Array[Dictionary]:
	return _spots.filter(
		func(spot: Dictionary) -> bool:
			return (
				spot["kind"] == &"wall"
				and spot["room"] == room
				and not NEW_WALLS.has(spot["shop_id"])
			)
	)


# --- Row 20: every link costs the same price P ---


func test_row_20_the_three_links_cost_one_price_in_the_tuning_and_in_the_scene() -> void:
	var links := _map.link_ids()
	assert_array(links).is_equal(
		[&"door_side", &"door_stairs_start", &"door_stairs_side"] as Array[StringName]
	)
	assert_int(_link_price()).override_failure_message("the links differ in price").is_greater(0)
	for id in links:
		assert_int(_price(id)).is_equal(_link_price())
		assert_object(_rules.economy.item(id).requires).is_equal(&"")
	var doors := _lot.get_node("Doors")
	assert_int(doors.get_child_count()).is_equal(3)
	for door in doors.get_children():
		assert_array(links).contains([StringName(door.get_meta("shop_id"))])
		assert_int(int(door.get_meta("cost"))).is_equal(_link_price())
		assert_str(String(door.get_meta("requires"))).is_empty()


# --- Row 21: P opens one link at round 3, two at round 4, three at round 5 ---


func test_row_21_the_price_opens_one_link_at_round_3_two_at_4_and_three_at_5() -> void:
	var wanted := [3, 4, 5]
	for count in 3:
		var round_number := _first_affordable_round(_link_price() * (count + 1))
		(
			assert_int(absi(round_number - wanted[count]))
			. override_failure_message(
				(
					"%d link(s) at P=%d: round %d, wanted %d (one round either way)"
					% [count + 1, _link_price(), round_number, wanted[count]]
				)
			)
			. is_less_equal(1)
		)


func test_row_21_the_price_is_what_the_formula_page_works_out_and_a_bad_one_fails() -> void:
	# The page: P from 400 to 475 opens one link at round 3, two at 4, three at 5 exactly.
	assert_int(_link_price()).is_between(400, 475)
	for count in 3:
		assert_int(_first_affordable_round(_link_price() * (count + 1))).is_equal(3 + count)
	# The row is sensitive: prices outside the band put a link more than a round off.
	assert_bool(_row_21_holds(_link_price())).is_true()
	assert_bool(_row_21_holds(1000)).is_false()
	assert_bool(_row_21_holds(150)).is_false()


## Whether a link price P opens one link at round 3, two at 4 and three at 5, each within a round.
func _row_21_holds(price: int) -> bool:
	for count in 3:
		if absi(_first_affordable_round(price * (count + 1)) - (3 + count)) > 1:
			return false
	return true


# --- Row 22: the box, one place, never moves, in the side room ---


func test_row_22_the_box_has_one_place_in_the_side_room_and_never_moves() -> void:
	var boxes := _spots.filter(func(spot: Dictionary) -> bool: return spot["kind"] == &"crane")
	assert_int(boxes.size()).is_equal(1)
	assert_int(_rules.crane.spot_count()).is_equal(1)
	assert_int(boxes[0]["crane_spot"]).is_equal(0)
	assert_str(boxes[0]["room"]).is_equal("side")
	assert_object(boxes[0]["shop_id"]).is_equal(&"crane_play")
	var side := _lot.get_node("Side").get_meta("rect") as Rect2
	var at: Vector3 = boxes[0]["position"]
	assert_bool(side.has_point(Vector2(at.x, at.z))).is_true()
	# It never breaks down and hops: no play at any count leaves.
	for plays in 200:
		assert_float(_rules.crane.leave_chance(plays)).is_equal(0.0)


func test_row_22_the_box_costs_085_to_105_of_the_link_price() -> void:
	var share := float(_price(&"crane_play")) / float(_link_price())
	assert_float(share).is_between(0.85, 1.05)


# --- Row 23: wall weapons 2 / 2 / 4 and a cabinet ---


func test_row_23_wall_weapons_are_two_two_and_four_with_a_cabinet() -> void:
	assert_int(_walls_in("start").size()).is_equal(2)
	assert_int(_walls_in("side").size()).is_equal(2)
	var upstairs := _walls_in("upstairs")
	var cabinets := upstairs.filter(func(spot: Dictionary) -> bool: return spot["cabinet"])
	assert_int(cabinets.size()).is_equal(1)
	assert_int(upstairs.size() - cabinets.size()).is_equal(4)
	for spot in _spots:
		if spot["cabinet"]:
			assert_str(spot["room"]).is_equal("upstairs")


func test_the_new_firearms_walls_sell_at_their_ratios_in_the_rooms_beyond_the_formulas() -> void:
	var found := {}
	for spot in _spots:
		if spot["kind"] == &"wall" and NEW_WALLS.has(spot["shop_id"]):
			found[spot["shop_id"]] = spot["room"]
			var ratio := float(_price(spot["shop_id"])) / _link_price()
			assert_float(ratio).override_failure_message(String(spot["name"])).is_equal_approx(
				NEW_WALLS[spot["shop_id"]], NEW_WALLS[spot["shop_id"]] * PRICE_TOLERANCE
			)
	assert_dict(found).is_equal(
		{&"weapon_pump_870": "side", &"weapon_mp5": "upstairs", &"weapon_m4a1": "upstairs"}
	)
	# The other three of the six are the box's alone on this map.
	var pool := _rules.economy.item(&"crane_play").pool
	for id in [&"ppsh", &"m249", &"fifty_cal", &"pump_870", &"mp5", &"m4a1"]:
		assert_array(pool).contains([StringName("weapon_" + String(id))])
	for id: StringName in [&"weapon_ppsh", &"weapon_m249", &"weapon_fifty_cal"]:
		for spot in _spots:
			assert_bool(spot["shop_id"] == id).is_false()


func test_row_23_every_wall_spot_sells_a_weapon_the_tuning_prices() -> void:
	for spot in _spots:
		if spot["kind"] != &"wall":
			continue
		var item := _rules.economy.item(spot["shop_id"])
		assert_object(item).override_failure_message(String(spot["name"])).is_not_null()
		assert_int(item.kind).is_equal(ShopItem.Kind.WEAPON)
		assert_object(WeaponCatalog.get_def(WeaponCatalog.catalog_id(item.id))).is_not_null()


# --- Row 24: wall prices climb with the distance from the start ---


func test_row_24_the_start_room_sells_at_a_fifth_and_three_fifths_of_a_link() -> void:
	var prices: Array[float] = []
	for spot in _walls_in("start"):
		prices.append(float(_price(spot["shop_id"])) / _link_price())
	prices.sort()
	for i in START_RATIOS.size():
		assert_float(prices[i]).is_equal_approx(START_RATIOS[i], START_RATIOS[i] * PRICE_TOLERANCE)


func test_row_24_the_side_room_sells_at_one_and_a_fifth_links() -> void:
	for spot in _walls_in("side"):
		var ratio := float(_price(spot["shop_id"])) / _link_price()
		assert_float(ratio).is_equal_approx(SIDE_RATIO, SIDE_RATIO * PRICE_TOLERANCE)


func test_row_24_the_upstairs_sells_from_1_2_to_1_8_links() -> void:
	var low := INF
	var high := 0.0
	for spot in _walls_in("upstairs"):
		var ratio := float(_price(spot["shop_id"])) / _link_price()
		assert_float(ratio).is_between(
			UPSTAIRS_RATIO_FROM * (1.0 - PRICE_TOLERANCE),
			UPSTAIRS_RATIO_TO * (1.0 + PRICE_TOLERANCE)
		)
		low = minf(low, ratio)
		high = maxf(high, ratio)
	assert_float(low).is_less_equal(UPSTAIRS_RATIO_FROM * (1.0 + PRICE_TOLERANCE))
	assert_float(high).is_greater_equal(UPSTAIRS_RATIO_TO * 0.8)


func test_row_24_the_prices_climb_room_by_room() -> void:
	var start_top := 0
	var side_low := 1000000
	var side_top := 0
	var upstairs_low := 1000000
	for spot in _walls_in("start"):
		start_top = maxi(start_top, _price(spot["shop_id"]))
	for spot in _walls_in("side"):
		side_low = mini(side_low, _price(spot["shop_id"]))
		side_top = maxi(side_top, _price(spot["shop_id"]))
	for spot in _walls_in("upstairs"):
		upstairs_low = mini(upstairs_low, _price(spot["shop_id"]))
	assert_int(start_top).is_less(side_low)
	assert_int(side_top).is_less_equal(upstairs_low)
	# The cabinet is the rifle, the best gun of the map, in the dearest room.
	var cabinet := _spots.filter(func(spot: Dictionary) -> bool: return spot["cabinet"])
	assert_object(cabinet[0]["shop_id"]).is_equal(&"weapon_rifle")


# --- Row 25: the shop. The formula's default was links, weapons, the box and ammunition only;
# #792 brings the lot's machines (the six tonics and the re-cut) at the shared table's prices. ---


func test_row_25_the_shop_sells_links_weapons_the_box_ammunition_and_the_lots_machines() -> void:
	var allowed := [
		ShopItem.Kind.DOOR,
		ShopItem.Kind.WEAPON,
		ShopItem.Kind.CRANE,
		ShopItem.Kind.AMMO,
		ShopItem.Kind.TONIC,
		ShopItem.Kind.UPGRADE
	]
	for item in _rules.economy.items:
		assert_array(allowed).override_failure_message(String(item.id)).contains([item.kind])
	for spot in _spots:
		assert_array([&"wall", &"crane", &"ammo", &"perk", &"upgrade"]).contains([spot["kind"]])


func test_row_25_every_tonic_and_the_re_cut_the_table_sells_has_its_machine_and_spot() -> void:
	var tonics: Array[String] = []
	var upgrades: Array[String] = []
	for item in _rules.economy.items:
		if item.kind == ShopItem.Kind.TONIC:
			tonics.append(String(item.id))
		elif item.kind == ShopItem.Kind.UPGRADE:
			upgrades.append(String(item.id))
	var perk_spots: Array[String] = []
	var upgrade_spots: Array[String] = []
	for spot in _spots:
		if spot["kind"] == &"perk":
			perk_spots.append(String(spot["shop_id"]))
		elif spot["kind"] == &"upgrade":
			upgrade_spots.append(String(spot["shop_id"]))
	tonics.sort()
	perk_spots.sort()
	assert_array(tonics).is_equal(perk_spots)
	assert_int(tonics.size()).is_equal(6)
	assert_array(upgrades).is_equal(upgrade_spots)
	# One machine drawn for each: five perk coolers, the fountain, the re-cut bench.
	assert_int(_lot.find_children("*", "PerkMachine", true, false).size()).is_equal(5)
	assert_int(_lot.find_children("*", "SodaFountain", true, false).size()).is_equal(1)
	assert_int(_lot.find_children("*", "RecutMachine", true, false).size()).is_equal(1)
	# Each machine's spot is in front of it, close (the marker a player buys from).
	for machine in _lot.find_children("*", "Node3D", true, false):
		if not (machine is PerkMachine or machine is SodaFountain or machine is RecutMachine):
			continue
		var nearest := INF
		for marker in _lot.get_node("ShopSpots").get_children():
			if marker.get_meta(&"kind") in [&"perk", &"upgrade"]:
				nearest = minf(
					nearest,
					(
						Vector2(
							(
								(machine as Node3D).global_position.x
								- (marker as Node3D).global_position.x
							),
							(
								(machine as Node3D).global_position.z
								- (marker as Node3D).global_position.z
							)
						)
						. length()
					)
				)
		assert_float(nearest).override_failure_message(str(machine.name)).is_between(0.9, 2.6)


func test_row_25_the_map_has_no_breaker_post_and_no_fuel_can() -> void:
	assert_int(_lot.find_children("*", "CircuitSwitch", true, false).size()).is_equal(0)
	assert_bool(_lot.has_node("FuelSpots")).is_false()
	assert_int(_rules.fuel.circuit_drain.size()).is_equal(0)
	assert_float(_rules.fuel.idle_drain).is_equal(0.0)
	assert_float(_rules.fuel.round_strain).is_equal(0.0)


# --- Row 26: at most 24 dead at once ---


func test_row_26_no_round_and_no_party_stands_more_than_24_dead_at_once() -> void:
	assert_int(_map.alive_cap).is_equal(24)
	assert_int(_rules.rounds.ceiling_for(false)).is_equal(24)
	assert_int(_rules.rounds.ceiling_for(true)).is_equal(24)
	var most := 0
	for round_number in range(1, LAST_ROUND + 1):
		for players in range(1, 5):
			most = maxi(most, _rules.rounds.alive_cap(round_number, players))
	assert_int(most).is_equal(24)


# --- The tuning and the scene agree ---


func test_the_windows_the_rules_list_are_the_boards_in_the_scene() -> void:
	var in_scene: Array[StringName] = []
	for node in _lot.find_children("*", "Barricade", true, false):
		in_scene.append(StringName((node as Barricade).get_meta("barricade_id")))
	in_scene.sort()
	var listed := _rules.barricades.ids.duplicate()
	listed.sort()
	assert_array(in_scene).is_equal(listed)
	assert_int(listed.size()).is_equal(12)


func test_every_spot_and_door_in_the_scene_names_an_item_the_rules_sell() -> void:
	for spot in _spots:
		if spot["kind"] == &"ammo":
			assert_str(String(spot["shop_id"])).is_empty()
			continue
		assert_object(_rules.economy.item(spot["shop_id"])).is_not_null()
	for door in _lot.get_node("Doors").get_children():
		assert_object(_rules.economy.item(StringName(door.get_meta("shop_id")))).is_not_null()


func test_the_overlay_leaves_the_shared_table_alone() -> void:
	var shared := RulesFixture.tuning()
	var fingerprint := shared.fingerprint()
	var applied := _map.apply(shared)
	assert_str(shared.fingerprint()).is_equal(fingerprint)
	assert_str(applied.fingerprint()).is_not_equal(fingerprint)
	# What the maps share is the shared table's: rounds, points, health, the zombie types, ammunition.
	assert_float(applied.rounds.count_base).is_equal(shared.rounds.count_base)
	assert_int(applied.economy.start_points).is_equal(shared.economy.start_points)
	assert_int(applied.roster.types.size()).is_equal(shared.roster.types.size())
	for weapon in [&"pistol", &"smg", &"shotgun", &"rifle", &"flare_gun"]:
		assert_object(applied.economy.ammo_item_for(weapon)).is_not_null()
