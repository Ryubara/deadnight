# The dead rise only where the walking map takes them out (#591). A door bought opens its area at
# once, but the navigation server takes the new mesh in over the next physics ticks (and a night
# stepped by hand, with no physics frame between its ticks, never does): a dead one risen in the
# area meanwhile walks to the nearest point of the island it stands on, the wall of the door's
# room, and stays there. Three to six did, at (-2, -3) and (9, -3) beside the concession door, so
# a round of the shopping soak never ended. The area's spawn points join when the map walks to them.
extends GdUnitTestSuite

## Physics frames a bought door's mesh gets to reach the map (3 to 12 ticks were measured).
const MAP_FRAMES := 600

const FIRST_DOOR := &"door_concession"


func _markers(night: Night, area: String) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var group := night.world.greybox.get_node_or_null(area + "/ZombieSpawns")
	if group != null:
		for marker in group.get_children():
			found.append((marker as Marker3D).global_position)
	return found


func _holds_all(points: Array[Vector3], wanted: Array[Vector3]) -> bool:
	return wanted.all(func(point: Vector3) -> bool: return points.has(point))


func _holds_any(points: Array[Vector3], wanted: Array[Vector3]) -> bool:
	return wanted.any(func(point: Vector3) -> bool: return points.has(point))


## Buys `door_id` as a player at its first slab would: points, then a use press.
func _buy(night: Night, door_id: StringName) -> void:
	night.server.rules.apply(RulesAction.grant_points(1, 20000))
	night.player().teleport(night.world.door_points(door_id)[0] + Vector3(0.0, 0.1, -2.0))
	NightFixture.run(night, 6)
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)
	assert_bool(night.server.rules.is_door_open(door_id)).is_true()


## Ticks the night one by one with a physics frame between, until the director has `wanted`.
func _until_taken_in(night: Night, wanted: Array[Vector3]) -> bool:
	for _i in MAP_FRAMES:
		if _holds_all(night.server.director.spawn_points, wanted):
			return true
		await get_tree().physics_frame
		NightFixture.run(night, 1)
	return _holds_all(night.server.director.spawn_points, wanted)


func test_a_door_bought_does_not_open_its_spawns_before_the_map_has_the_room() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var midway := _markers(night, "Midway")
	assert_array(midway).is_not_empty()
	_buy(night, FIRST_DOOR)
	# No physics frame yet: the server has not taken the door's mesh in.
	assert_bool(_holds_any(night.server.director.spawn_points, midway)).is_false()
	assert_bool(_holds_any(night.world.spawn_points(), midway)).is_false()
	# And a night stepped by hand with no frames never rises a dead one there.
	NightFixture.run(night, 600)
	assert_bool(_holds_any(night.server.director.spawn_points, midway)).is_false()
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_the_spawns_join_once_the_map_walks_to_them() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var midway := _markers(night, "Midway")
	_buy(night, FIRST_DOOR)
	(
		assert_bool(await _until_taken_in(night, midway))
		. override_failure_message("the midway's spawns never joined")
		. is_true()
	)
	# The field's are never left.
	assert_bool(_holds_all(night.server.director.spawn_points, _markers(night, "Field"))).is_true()
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_every_door_in_the_shops_order_gives_its_spawns_to_the_dead() -> void:
	# The wait must never keep an area shut for good: each area's every marker is on the map's
	# ground from the field once its door has been taken in.
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var opened: Dictionary[StringName, Array] = {
		&"door_concession": ["Midway"],
		&"door_booth": ["ProjectionBooth"],
		&"door_back_lot": ["BackLot"],
		&"door_yard": ["GeneratorYard"],
		&"door_road": ["Road"],
	}
	for door_id: StringName in [
		&"door_concession", &"door_booth", &"door_back_lot", &"door_yard", &"door_road"
	]:
		_buy(night, door_id)
		for area: String in opened[door_id]:
			var wanted := _markers(night, area)
			if wanted.is_empty():
				continue  # the booth has no spawns of its own
			(
				assert_bool(await _until_taken_in(night, wanted))
				. override_failure_message("%s: the spawns of %s never joined" % [door_id, area])
				. is_true()
			)
	await NightFixture.settle_bake(night)
	night.queue_free()
