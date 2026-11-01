# The dead follow the doors (docs/research/zombies.md "Doors"): the zombie navigation mesh is baked
# with the slabs as they stand and again after each door is bought (`DoorNavigation`), so after each
# set of doors the shop can have sold a zombie from the field walks to a player in every open area
# and not into a closed one.
extends GdUnitTestSuite

## Metres between the points that judge a closed area.
const GRID_STEP := 4.0
## Seconds a zombie gets to walk to a player; the longest way (the road) is about 150 m.
const WALK_SECONDS := 90.0
## A blow lands within this distance.
const CLOSE := 1.6

const BAKE_FRAMES := 1800


## The lot with `sold` bought through the rules, then given its zombie navigation: baked from the
## lot as it stands and kept in step with its doors from here on. The suite is about the bake, so
## the saved meshes (`LotNavmeshes`, tested in test_lot_navmeshes.gd) are left out.
func _zombie_lot(sold: Array) -> Node3D:
	var lot := await LotFixture.make_lot(self, sold)
	auto_free(lot.get_parent())
	var navigation := DoorNavigation.new()
	navigation.name = "DoorNavigation"
	navigation.saved = null
	lot.add_child(navigation)
	navigation.setup(lot, lot.get_node("Doors"))
	await _map_ready(lot)
	return lot


## Waits until the navigation map answers a query across the field: the iteration id is no sign
## (links and regions both change it), the answer is.
func _map_ready(lot: Node3D) -> void:
	var map := lot.get_world_3d().navigation_map
	for i in BAKE_FRAMES:
		await get_tree().physics_frame
		if not (
			NavigationServer3D
			. map_get_path(map, LotFixture.START, Vector3(0, 0, -30), true)
			. is_empty()
		):
			break
	for i in 3:
		await get_tree().physics_frame


## Buys `item` through the rules and waits until the zombie navigation has caught up: the bake is
## done and the map answers for `expect`, the points the new mesh opens.
func _buy_and_wait(lot: Node3D, item: StringName, expect: Array[Vector3]) -> void:
	var navigation := lot.get_node("DoorNavigation") as DoorNavigation
	assert_int(RulesFixture.buy(lot.get_meta(&"rules"), 1, item)).is_equal(GameRules.BuyResult.OK)
	assert_bool(navigation.is_busy()).is_true()
	await _bake_done(navigation)
	await _map_current(lot, expect)


func _bake_done(navigation: DoorNavigation) -> void:
	for i in BAKE_FRAMES:
		if not navigation.is_busy():
			return
		await get_tree().physics_frame


## Waits until the map answers for every point of `expect`. A finished bake is in the region at
## once but reaches the map over the next physics ticks: the server iterates the map on a thread,
## and 3 to 12 ticks were measured under load. A fixed few frames after the bake raced the
## machine's speed (#192); the answer the test is about is what it waits for. A mesh that never
## lands ends the wait at `BAKE_FRAMES` and the test's own assertions then fail with their message.
func _map_current(lot: Node3D, expect: Array[Vector3]) -> void:
	var pathing := _pathing(lot)
	var from := _spawn_point(lot)
	for i in BAKE_FRAMES:
		if expect.all(
			func(point: Vector3) -> bool: return _gap(pathing, from, point) < LotFixture.REACHED
		):
			return
		await get_tree().physics_frame


## The sample points of every area the doors in `sold` open.
func _open_points(sold: Array) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for area: String in LotFixture.AREA_POINTS:
		if LotFixture.is_open(area, sold):
			points.append_array(LotFixture.AREA_POINTS[area])
	return points


func _pathing(lot: Node3D) -> NavmeshPathing:
	return NavmeshPathing.new(lot.get_world_3d().navigation_map)


func _spawn_point(lot: Node3D) -> Vector3:
	return (lot.get_node("Field/ZombieSpawns").get_child(0) as Marker3D).global_position


## The end of the way a zombie would walk from the spawn to `to`, and how close it ends.
func _gap(pathing: NavmeshPathing, from: Vector3, to: Vector3) -> float:
	var way := pathing.find_path(from, to)
	return INF if way.is_empty() else way[way.size() - 1].distance_to(to)


func test_after_each_set_of_doors_zombies_reach_the_open_areas_and_not_the_closed() -> void:
	for sold: Array in LotFixture.sold_sets():
		var lot := await _zombie_lot(sold)
		var pathing := _pathing(lot)
		var from := _spawn_point(lot)
		for area: String in LotFixture.AREA_POINTS:
			if LotFixture.is_open(area, sold):
				for point: Vector3 in LotFixture.AREA_POINTS[area]:
					(
						assert_float(_gap(pathing, from, point))
						. override_failure_message("sold %s, area %s at %s" % [sold, area, point])
						. is_less(LotFixture.REACHED)
					)
			else:
				var leak := _leak(pathing, lot, area, from)
				assert_str(leak).override_failure_message("sold %s: %s" % [sold, leak]).is_empty()
		lot.get_parent().queue_free()
		await get_tree().process_frame


func test_a_zombie_walks_to_a_player_in_each_area_once_every_door_is_open() -> void:
	var sold: Array = LotFixture.door_table().keys()
	for area: String in LotFixture.AREA_POINTS:
		var lot := await _zombie_lot(sold)
		var target: Vector3 = LotFixture.AREA_POINTS[area][0]
		var closest := _walk(lot, target, WALK_SECONDS)
		assert_float(closest).override_failure_message(area).is_less(CLOSE)
		lot.get_parent().queue_free()
		await get_tree().process_frame


func test_each_bought_door_lets_the_dead_into_its_area_and_no_further() -> void:
	# The game's own order of events: the lot is baked closed, then each door is bought through the
	# rules and the mesh follows.
	var lot := await _zombie_lot([])
	var from := _spawn_point(lot)
	var sold: Array = []
	for item: StringName in [
		&"door_concession", &"door_booth", &"door_yard", &"door_back_lot", &"door_road"
	]:
		sold.append(String(item))
		await _buy_and_wait(lot, item, _open_points(sold))
		var pathing := _pathing(lot)
		for area: String in LotFixture.AREA_POINTS:
			if LotFixture.is_open(area, sold):
				for point: Vector3 in LotFixture.AREA_POINTS[area]:
					(
						assert_float(_gap(pathing, from, point))
						. override_failure_message("after %s, area %s at %s" % [item, area, point])
						. is_less(LotFixture.REACHED)
					)
			else:
				var leak := _leak(pathing, lot, area, from)
				assert_str(leak).override_failure_message("after %s: %s" % [item, leak]).is_empty()


func test_a_zombie_on_its_way_gets_in_once_the_door_is_bought() -> void:
	var lot := await _zombie_lot(["door_concession"])
	var booth: Vector3 = LotFixture.AREA_POINTS["ProjectionBooth"][0]
	var sim := ZombieFixture.sim()
	sim.pathing = _pathing(lot)
	ZombieFixture.standing(sim, 1, _spawn_point(lot), 3.0)
	var footprint := LotFixture.footprint(lot, "ProjectionBooth")
	for _i in ceili(WALK_SECONDS / ZombieSim.STEP):
		sim.tick(ZombieSim.STEP, {1: booth})
		assert_bool(LotFixture.inside(footprint, sim.zombies[1].position)).is_false()
	assert_float(sim.zombies[1].position.distance_to(booth)).is_greater(CLOSE)
	await _buy_and_wait(lot, &"door_booth", [booth])
	var closest := INF
	for _i in ceili(WALK_SECONDS / ZombieSim.STEP):
		sim.tick(ZombieSim.STEP, {1: booth})
		closest = minf(closest, sim.zombies[1].position.distance_to(booth))
	assert_float(closest).is_less(CLOSE)


func test_doors_bought_in_quick_succession_end_with_the_last_one_in_the_mesh() -> void:
	var lot := await _zombie_lot([])
	var navigation := lot.get_node("DoorNavigation") as DoorNavigation
	var rules: GameRules = lot.get_meta(&"rules")
	for item: StringName in [&"door_concession", &"door_booth", &"door_back_lot", &"door_road"]:
		RulesFixture.buy(rules, 1, item)
	assert_bool(navigation.is_busy()).is_true()
	await _bake_done(navigation)
	await _map_current(lot, [LotFixture.AREA_POINTS["Road"][0]])
	# One bake for the first door, one more for all the others that arrived while it ran.
	assert_int(navigation.bake_count).is_equal(3)
	var road: Vector3 = LotFixture.AREA_POINTS["Road"][0]
	assert_float(_gap(_pathing(lot), _spawn_point(lot), road)).is_less(LotFixture.REACHED)


func test_a_night_that_ends_during_a_bake_ends_cleanly() -> void:
	# A door bought in the last second of a night: the bake lands after the navigation is gone.
	var lot := await _zombie_lot([])
	RulesFixture.buy(lot.get_meta(&"rules"), 1, &"door_concession")
	assert_bool((lot.get_node("DoorNavigation") as DoorNavigation).is_busy()).is_true()
	(lot.get_node("DoorNavigation") as DoorNavigation).free()
	for i in BAKE_FRAMES:
		await get_tree().physics_frame
		if i > 180:
			break


func test_a_door_opened_without_a_rebake_leaves_the_dead_outside() -> void:
	# Why the mesh is rebaked: the slab goes, the baked mesh does not change, and the zombie stops at
	# the old wall.
	var lot := await _zombie_lot([])
	(lot.get_node("DoorNavigation") as DoorNavigation).free()
	(lot.get_node("Doors") as LotDoors).open(&"door_concession")
	for i in 30:
		await get_tree().physics_frame
	var gap := _gap(_pathing(lot), _spawn_point(lot), LotFixture.AREA_POINTS["Concession"][0])
	assert_float(gap).is_greater(5.0)


## Walks a zombie from the spawn towards `target`; returns the closest it came.
func _walk(lot: Node3D, target: Vector3, seconds: float) -> float:
	var sim := ZombieFixture.sim()
	sim.pathing = _pathing(lot)
	ZombieFixture.standing(sim, 1, _spawn_point(lot), 3.0)
	var closest := INF
	for _i in ceili(seconds / ZombieSim.STEP):
		sim.tick(ZombieSim.STEP, {1: target})
		closest = minf(closest, sim.zombies[1].position.distance_to(target))
		if closest < CLOSE:
			break
	return closest


## A description of the first way into `area`'s footprint, or "" when there is none.
func _leak(pathing: NavmeshPathing, lot: Node3D, area: String, from: Vector3) -> String:
	var footprint := LotFixture.footprint(lot, area)
	var targets := LotFixture.grid(footprint, GRID_STEP)
	targets.append_array(LotFixture.AREA_POINTS[area])
	for target in targets:
		for point in LotFixture.along(pathing.find_path(from, target)):
			if LotFixture.inside(footprint, point):
				return "a way towards %s enters %s at %s" % [target, area, point]
	return ""
