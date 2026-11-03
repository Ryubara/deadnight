# The second map's three paid links, each bought the way a person does it: walk to its stand, see
# the offer with its price, press use. A link opens on purchase (its slab goes, the walking mesh
# takes the way in, the dead of the rooms it opens may rise), is refused without the points, is not
# offered across a floor, and the three together close the ring.
extends GdUnitTestSuite

const LINKS: Array[StringName] = [&"door_side", &"door_stairs_start", &"door_stairs_side"]
## The rooms whose dead may rise once a link is open (`metadata/opens`, read by `MapLayout`).
const OPENS := {
	&"door_side": ["side"],
	&"door_stairs_start": ["upstairs"],
	&"door_stairs_side": ["side", "upstairs"],
}
## A point in the room a link leads to, on its floor (feet), inside its walking mesh.
const SIDE_ROOM := Vector3(5.0, 0.0, -2.0)
const UPSTAIRS_A := Vector3(11.0, 3.4, 2.3)
const UPSTAIRS_B := Vector3(5.0, 3.4, -4.0)

var _night: Night


func after_test() -> void:
	if _night != null:
		_night.queue_free()
		_night = null


func _start() -> Night:
	_night = await SmallMapNight.start(self)
	SmallMapNight.run(_night, 30)
	return _night


func _price() -> int:
	return _night.server.rules.tuning.economy.item(&"door_side").price


func test_each_link_is_offered_at_its_stands_with_the_price_and_bought_with_use() -> void:
	await _start()
	_night.server.rules.apply(RulesAction.grant_points(1, 20000))
	for id in LINKS:
		var stands := _night.world.door_stands(id)
		assert_int(stands.size()).override_failure_message(String(id)).is_equal(2)
		for stand in stands:
			# The stand a person reaches from the open side is the one offered first; both offer.
			if not await SmallMapNight.map_reaches(_night, stand):
				continue
			SmallMapNight.stand_at(_night, stand)
			var prompt: Dictionary = _night.state.me()["prompt"]
			(
				assert_str(String(prompt.get("id", "")))
				. override_failure_message("%s at %s: %s" % [id, stand, prompt])
				. is_equal(String(id))
			)
			assert_int(int(prompt.get("price", 0))).is_equal(_price())
			break
		assert_bool(_night.server.rules.is_door_open(id)).is_false()
		SmallMapNight.press_use(_night)
		(
			assert_bool(_night.server.rules.is_door_open(id))
			. override_failure_message("%s was not bought from its stand" % id)
			. is_true()
		)
		await get_tree().physics_frame
	assert_int(_night.world.doors.closed_doors().size()).is_equal(0)


func test_a_link_is_refused_without_the_points_and_stays_shut() -> void:
	await _start()
	var rules := _night.server.rules
	assert_int(rules.points_of(1)).is_less(_price())
	SmallMapNight.stand_at(_night, _night.world.door_stands(&"door_side")[0])
	SmallMapNight.press_use(_night)
	assert_bool(rules.is_door_open(&"door_side")).is_false()
	assert_int(_night.world.doors.closed_doors().size()).is_equal(3)
	assert_int(rules.points_of(1)).is_less(_price())


func test_buying_a_link_takes_its_price_and_removes_its_slab() -> void:
	await _start()
	var rules := _night.server.rules
	rules.apply(RulesAction.grant_points(1, _price()))
	var before := rules.points_of(1)
	SmallMapNight.stand_at(_night, _night.world.door_stands(&"door_side")[0])
	SmallMapNight.press_use(_night)
	assert_int(before - rules.points_of(1)).is_equal(_price())
	assert_bool(_night.world.doors.closed_doors().has(&"door_side")).is_false()
	assert_int(_night.world.door_points(&"door_side").size()).is_equal(0)
	# The other two are still shut.
	assert_int(_night.world.doors.closed_doors().size()).is_equal(2)


func test_the_side_room_is_walled_off_until_its_door_is_bought() -> void:
	await _start()
	assert_bool(await _reaches(SIDE_ROOM)).is_false()
	_night.server.rules.apply(RulesAction.grant_points(1, _price()))
	RulesFixture.buy(_night.server.rules, 1, &"door_side")
	assert_bool(await SmallMapNight.map_reaches(_night, SIDE_ROOM)).is_true()


func test_the_upstairs_is_walled_off_until_a_stair_is_bought() -> void:
	await _start()
	assert_bool(await _reaches(UPSTAIRS_A)).is_false()
	_night.server.rules.apply(RulesAction.grant_points(1, _price()))
	RulesFixture.buy(_night.server.rules, 1, &"door_stairs_start")
	assert_bool(await SmallMapNight.map_reaches(_night, UPSTAIRS_A)).is_true()
	# The far half is through the opening with no door.
	assert_bool(await SmallMapNight.map_reaches(_night, UPSTAIRS_B)).is_true()


func test_the_third_link_is_a_short_cut_that_closes_the_ring() -> void:
	await _start()
	var rules := _night.server.rules
	rules.apply(RulesAction.grant_points(1, _price() * 3))
	var side_foot := Vector3(-4.5, 0.0, -6.8)
	var upstairs := Vector3(5.0, 3.4, -4.0)
	RulesFixture.buy(rules, 1, &"door_side")
	RulesFixture.buy(rules, 1, &"door_stairs_start")
	await SmallMapNight.map_reaches(_night, upstairs)
	assert_bool(await SmallMapNight.map_reaches(_night, side_foot)).is_true()
	# Two links leave a chain: from the side room to the upstairs is the whole way round the ring
	# (door, hall, the first stair, the opening).
	var round_the_ring := _path_length(side_foot, upstairs)
	assert_float(round_the_ring).is_greater(40.0)
	RulesFixture.buy(rules, 1, &"door_stairs_side")
	for _i in SmallMapNight.MAP_FRAMES:
		await get_tree().physics_frame
		if _path_length(side_foot, upstairs) < round_the_ring - 10.0:
			break
	# The third link is the stair itself: a walk of a few metres up it.
	assert_float(_path_length(side_foot, upstairs)).is_between(6.0, 20.0)


func test_a_player_upstairs_is_not_offered_the_link_below_him() -> void:
	await _start()
	var rules := _night.server.rules
	rules.apply(RulesAction.grant_points(1, _price() * 3))
	RulesFixture.buy(rules, 1, &"door_stairs_start")
	await SmallMapNight.map_reaches(_night, UPSTAIRS_A)
	# Directly over the side door's slab, a floor above it.
	var slab: Vector3 = _night.world.door_points(&"door_side")[0]
	SmallMapNight.stand_at(_night, Vector3(slab.x, 3.4, slab.z + 1.0))
	var prompt: Dictionary = _night.state.me()["prompt"]
	assert_str(String(prompt.get("kind", ""))).is_not_equal("door")
	assert_bool(rules.is_door_open(&"door_side")).is_false()
	SmallMapNight.press_use(_night)
	assert_bool(rules.is_door_open(&"door_side")).is_false()


func test_the_dead_of_a_room_rise_only_once_a_link_to_it_is_open() -> void:
	await _start()
	var rules := _night.server.rules
	var world := _night.world
	# At the start only the hall's windows are open for the dead.
	assert_array(world.open_areas()).is_equal(["start"] as Array[String])
	assert_int(world.spawn_points().size()).is_equal(5)
	rules.apply(RulesAction.grant_points(1, _price() * 3))
	for id in LINKS:
		RulesFixture.buy(rules, 1, id)
		for area: String in OPENS[id]:
			assert_array(world.open_areas()).contains([area])
		# The mesh takes the new rooms in a few frames later; then their spawns join the pool.
		for _i in SmallMapNight.MAP_FRAMES:
			await get_tree().physics_frame
			if world.spawn_points().size() >= _spawns_after(id):
				break
		assert_int(world.spawn_points().size()).override_failure_message(String(id)).is_equal(
			_spawns_after(id)
		)


## The spawn points in the pool once the links up to and including `id` (in `LINKS` order) are open:
## the hall's five, the side room's three (a door, or the stair that joins it) and the upstairs'
## four.
func _spawns_after(id: StringName) -> int:
	match id:
		&"door_side":
			return 8
		&"door_stairs_start":
			return 12
	return 12


func test_every_link_has_one_slab_and_a_stand_on_each_side_within_reach_on_the_mesh() -> void:
	await _start()
	var reach := _night.server.tuning.use_reach
	for id in LINKS:
		assert_int(_night.world.door_points(id).size()).is_equal(1)
		var slab: Vector3 = _night.world.door_points(id)[0]
		for stand in _night.world.door_stands(id):
			var apart := Vector2(stand.x - slab.x, stand.z - slab.z).length()
			assert_float(apart).override_failure_message(String(id)).is_less(reach)
			var on_mesh := NavigationServer3D.map_get_closest_point(_night.world.map(), stand)
			(
				assert_float(on_mesh.distance_to(stand))
				. override_failure_message(
					"%s: stand %s is %.2f m off the mesh" % [id, stand, on_mesh.distance_to(stand)]
				)
				. is_less(0.6)
			)


## Whether the map as it is takes a path from the players' start to `point` (no waiting).
func _reaches(point: Vector3) -> bool:
	await get_tree().physics_frame
	var way := NavigationServer3D.map_get_path(
		_night.world.map(), _night.world.player_spawn(0), point, true
	)
	return not way.is_empty() and way[way.size() - 1].distance_to(point) < 0.5


func _path_length(from: Vector3, to: Vector3) -> float:
	var way := NavigationServer3D.map_get_path(_night.world.map(), from, to, true)
	var length := 0.0
	for i in range(1, way.size()):
		length += way[i - 1].distance_to(way[i])
	return length
