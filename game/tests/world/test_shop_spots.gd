# The lot's shop spots (docs/design/map.md): wall weapons, the prize crane, ammunition lockers,
# the machines and the grenade rack are markers the night reads; each names a real shop item,
# stands on ground a player can reach and sits clear of every door and of the other spots, so one
# press never means two things.
extends GdUnitTestSuite

const KINDS: Array[StringName] = [&"wall", &"crane", &"ammo", &"upgrade", &"perk", &"rack"]
## The night's reach for a use (NightTuning.use_reach): spots of different kinds must be farther
## apart than twice this, so no place is in reach of two of them.
const REACH := 3.2

var _world: NightWorld
var _spots: Array[Dictionary]


func before_test() -> void:
	_world = NightWorld.new()
	add_child(_world)
	_world.greybox = load(LotFixture.SCENE).instantiate() as Node3D
	_world.add_child(_world.greybox)
	_spots = _world.shop_spots()


func after_test() -> void:
	_world.queue_free()


func test_the_lot_has_two_wall_weapons_a_crane_lockers_three_machines_and_a_grenade_rack() -> void:
	var kinds := {}
	for spot in _spots:
		kinds[spot["kind"]] = kinds.get(spot["kind"], 0) + 1
	assert_int(kinds[&"wall"]).is_equal(2)
	assert_int(kinds[&"crane"]).is_equal(CraneTuning.new().spot_count())
	assert_int(kinds[&"ammo"]).is_greater_equal(4)
	assert_int(kinds[&"upgrade"]).is_equal(1)
	# The soda fountain and the five other perk machines, one to a tonic of the shop.
	assert_int(kinds[&"perk"]).is_equal(PerkEffects.tonic_ids(RulesFixture.tuning().economy).size())
	assert_int(kinds[&"rack"]).is_equal(1)


func test_every_spot_has_a_known_kind_and_wall_and_crane_name_shop_items() -> void:
	var economy := RulesFixture.tuning().economy
	for spot in _spots:
		assert_bool(KINDS.has(spot["kind"])).is_true()
		if spot["kind"] == &"ammo":
			assert_str(String(spot["shop_id"])).is_empty()
			continue
		var item := economy.item(spot["shop_id"])
		assert_object(item).override_failure_message(String(spot["shop_id"])).is_not_null()
		var expected: Dictionary = {
			&"wall": ShopItem.Kind.WEAPON,
			&"crane": ShopItem.Kind.CRANE,
			&"upgrade": ShopItem.Kind.UPGRADE,
			&"perk": ShopItem.Kind.TONIC,
			&"rack": ShopItem.Kind.GRENADES,
		}
		assert_int(item.kind).is_equal(expected[spot["kind"]])


func test_every_place_the_crane_can_stand_has_one_marker() -> void:
	var seen: Array[int] = []
	for spot in _spots:
		if spot["kind"] == &"crane":
			seen.append(spot["crane_spot"])
	seen.sort()
	var count := RulesFixture.tuning().crane.spot_count()
	var all: Array[int] = []
	for index in count:
		all.append(index)
	assert_array(seen).is_equal(all)


func test_every_weapon_the_shop_sells_by_the_wall_hangs_on_one() -> void:
	var on_walls: Array[StringName] = []
	for spot in _spots:
		if spot["kind"] == &"wall":
			on_walls.append(spot["shop_id"])
	for item in RulesFixture.tuning().economy.items:
		if item.kind == ShopItem.Kind.WEAPON:
			assert_array(on_walls).contains([item.id])


func test_no_spot_is_within_reach_of_a_door_slab_or_of_another_kind_of_spot() -> void:
	var doors := _world.greybox.get_node("Doors")
	for spot in _spots:
		var at: Vector3 = spot["position"]
		for door in doors.get_children():
			for slab in door.get_children():
				if slab is CSGShape3D and (slab as CSGShape3D).use_collision:
					var apart := _flat(at, (slab as Node3D).global_position)
					(
						assert_float(apart)
						. override_failure_message(
							"%s is %.1f m from %s" % [spot["shop_id"], apart, door.name]
						)
						. is_greater(REACH)
					)
		for other in _spots:
			if other["kind"] != spot["kind"]:
				assert_float(_flat(at, other["position"])).is_greater(REACH)


func test_every_spot_stands_inside_the_lot() -> void:
	for spot in _spots:
		var at: Vector3 = spot["position"]
		assert_float(absf(at.x)).is_less(62.0)
		assert_float(at.z).is_between(-52.0, 58.0)
		assert_float(at.y).is_equal(0.0)


func test_the_wall_weapons_hang_in_the_two_places_the_design_gives_them() -> void:
	# The shotgun in the open before any door; the rifle past the concession, on the booth's wall.
	for spot in _spots:
		if spot["shop_id"] == &"weapon_shotgun":
			assert_float(spot["position"].z).is_less(-4.0)
		if spot["shop_id"] == &"weapon_rifle":
			assert_float(spot["position"].z).is_between(8.0, 22.0)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_the_machines_stand_in_the_booth_the_stand_and_the_ticket_plaza_over_their_blocks(
) -> void:
	# The re-cut bench is in the projection booth, the soda fountain in the concession stand and the
	# road door's perk machine against the south wall of the ticket plaza (docs/design/map.md), each
	# drawn over the hidden block that holds its place in the walking mesh.
	var perks := 0
	for spot in _spots:
		if spot["kind"] == &"upgrade":
			assert_float(spot["position"].z).is_between(22.0, 32.0)
			assert_float(spot["position"].x).is_between(-6.0, 6.0)
		if spot["kind"] == &"perk":
			perks += 1
		if spot["shop_id"] == &"tonic_hearty":
			assert_float(spot["position"].z).is_between(-4.0, 8.0)
			assert_float(spot["position"].x).is_between(-10.0, 10.0)
		if spot["shop_id"] == &"tonic_third_holster":
			assert_float(spot["position"].z).is_between(38.0, 58.0)
			assert_float(spot["position"].x).is_between(-16.0, 16.0)
	assert_int(perks).is_equal(PerkEffects.tonic_ids(RulesFixture.tuning().economy).size())
	var greybox := _world.greybox
	var blocks := ["ProjectionBooth/ReCutMachine", "Concession/SodaFountain", "Road/PerkMachine"]
	for path: String in blocks:
		var block := greybox.get_node(path) as CSGBox3D
		assert_bool(block.visible).is_false()
		assert_bool(block.use_collision).is_true()
	assert_bool(greybox.get_node("ShopProps/ReCut") is RecutMachine).is_true()
	assert_bool(greybox.get_node("ShopProps/Soda") is SodaFountain).is_true()
	assert_bool(greybox.get_node("ShopProps/PlazaPerk") is PerkMachine).is_true()


func test_the_five_other_perk_machines_stand_one_to_an_area_over_their_blocks() -> void:
	# Each sells its own tonic, faces its spot, has a hidden block and a look of its own.
	var areas := {
		&"tonic_swift_rescue": [-16.0, 16.0, 8.0, 38.0],
		&"tonic_quick_load": [-6.0, 6.0, 22.0, 32.0],
		&"tonic_double_shot": [16.0, 62.0, -4.0, 38.0],
		&"tonic_reload_shock": [-62.0, -16.0, -4.0, 38.0],
		&"tonic_third_holster": [-16.0, 16.0, 38.0, 58.0],
	}
	var seen := {}
	for machine in _world.greybox.find_children("*", "PerkMachine", true, false):
		var perk_machine := machine as PerkMachine
		var item := perk_machine.item_id()
		assert_bool(areas.has(item)).override_failure_message(String(item)).is_true()
		var box: Array = areas[item]
		assert_float(perk_machine.position.x).is_between(box[0], box[1])
		assert_float(perk_machine.position.z).is_between(box[2], box[3])
		# The plaza's machine stands over the road area's own block, the rest over one of their own.
		var block_path := (
			"Road/PerkMachine"
			if perk_machine.name == &"PlazaPerk"
			else "ShopProps/%sBlock" % perk_machine.name
		)
		var block := _world.greybox.get_node(block_path) as CSGBox3D
		assert_bool(block.visible).is_false()
		assert_bool(block.use_collision).is_true()
		seen[item] = true
		var found := false
		for spot in _spots:
			found = found or spot["shop_id"] == item
		assert_bool(found).override_failure_message(String(item)).is_true()
	assert_int(seen.size()).is_equal(areas.size())
