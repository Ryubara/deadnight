# The lot's fuel can spots (docs/design/map.md, The fuel cans): one in the stand and one by the
# generator, each selling the shop's fuel item, each in an area behind its door, clear of the
# doors' and the breaker posts' prompts, on ground a player can walk to.
extends GdUnitTestSuite

const NOWHERE := Vector3(0.0, 0.0, -20.0)
## Which area's ground each spot's door opens.
const AREA_OF_DOOR := {&"door_concession": "Concession", &"door_yard": "GeneratorYard"}

var _lot: Node3D
var _fuel: LotFuel
var _rules: GameRules
var _tuning := NightTuning.shipped()


func before_test() -> void:
	_lot = await LotFixture.make_lot(self)
	auto_free(_lot.get_parent())
	_rules = _lot.get_meta(&"rules")
	_fuel = LotFuel.new(_lot)


func test_there_is_a_spot_in_the_stand_and_one_in_the_yard() -> void:
	var found: Array = _fuel.ids()
	assert_array(found).contains_exactly_in_any_order([&"SpotStand", &"SpotYard"])
	assert_str(_fuel.door_of(&"SpotStand")).is_equal("door_concession")
	assert_str(_fuel.door_of(&"SpotYard")).is_equal("door_yard")


func test_each_spot_sells_a_fuel_item_of_the_shop_and_its_door_is_a_shop_door() -> void:
	for id in _fuel.ids():
		var item := _rules.tuning.economy.item(_fuel.item_of(id))
		assert_bool(item != null and item.kind == ShopItem.Kind.FUEL).is_true()
		var door := _rules.tuning.economy.item(_fuel.door_of(id))
		assert_bool(door != null and door.kind == ShopItem.Kind.DOOR).is_true()


func test_each_spot_stands_on_the_ground_of_the_area_its_door_opens() -> void:
	for id in _fuel.ids():
		var area: String = AREA_OF_DOOR[_fuel.door_of(id)]
		var rects := LotFixture.footprint(_lot, area)
		assert_bool(LotFixture.inside(rects, _fuel.standing_point(id), 1.0)).is_true()


func test_a_spot_stands_clear_of_every_door_slab_and_breaker_post() -> void:
	# A door in reach wins the prompt, and a post wins over a spot: neither may shadow a spot, and a
	# spot may not be bought from at a door.
	var doors := _lot.get_node("Doors") as LotDoors
	var posts := LotSwitches.new(_lot)
	for id in _fuel.ids():
		var stand := _fuel.standing_point(id)
		for door in doors.get_children():
			for slab in door.get_children():
				if slab is CSGShape3D and (slab as CSGShape3D).use_collision:
					var at := (slab as Node3D).global_position
					(
						assert_float(Vector2(stand.x, stand.z).distance_to(Vector2(at.x, at.z)))
						. override_failure_message("%s near %s" % [id, slab.get_path()])
						. is_greater(_tuning.use_reach + _tuning.fuel_reach)
					)
		assert_object(posts.within_reach(stand, _tuning.use_reach + _tuning.fuel_reach)).is_null()


func test_the_spots_are_far_enough_apart_not_to_share_a_prompt() -> void:
	var a := _fuel.standing_point(&"SpotStand")
	var b := _fuel.standing_point(&"SpotYard")
	assert_float(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))).is_greater(
		_tuning.fuel_reach * 2.0
	)


func test_a_spot_is_reached_from_where_it_is_stood_at_and_not_from_afar() -> void:
	for id in _fuel.ids():
		var stand := _fuel.standing_point(id)
		assert_str(_fuel.within_reach(stand, _tuning.fuel_reach)).is_equal(id)
		assert_str(_fuel.within_reach(stand + Vector3(1.0, 0.0, 0.0), _tuning.fuel_reach)).is_equal(
			id
		)
		(
			assert_str(_fuel.within_reach(stand + Vector3(30.0, 0.0, 0.0), _tuning.fuel_reach))
			. is_equal("")
		)
	assert_str(_fuel.within_reach(NOWHERE, _tuning.fuel_reach)).is_equal("")


func test_a_spot_is_on_walkable_ground_with_every_door_open() -> void:
	var sold: Array = LotFixture.door_table().keys()
	var lot := await LotFixture.make_lot(self, sold)
	auto_free(lot.get_parent())
	var nav := LotNavigation.new(lot, CameraProbe.body_radius())
	await nav.settle(get_tree())
	for id in _fuel.ids():
		var stand := _fuel.standing_point(id)
		assert_bool(nav.can_reach(LotFixture.START, stand, LotFixture.REACHED)).is_true()


func test_a_crate_of_cans_is_solid_and_no_lamp_of_the_lot() -> void:
	var props := _lot.get_node("FuelProps")
	var solid := props.get_node("Stand") as CSGBox3D
	assert_bool(solid.use_collision).is_true()
	var lamps := _lot.get_tree().get_nodes_in_group(&"powered_light")
	for lamp in lamps:
		assert_bool(props.is_ancestor_of(lamp)).is_false()
