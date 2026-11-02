# Every purchase door can be reached and bought the way a bot or a person does it (#590). The
# walking mesh is cut back from a wall on both sides alike, so a goal in the middle of a slab
# snapped to the shut area behind the booth's door and the path stopped 6.75 m short, and no bot
# ever bought it. The stands (`NightWorld.door_stands`, a point in front of each slab on the open
# ground) are what to walk to: the doors are bought here one after the other, in the order the shop
# sells them, with only the doors before each one open, from the stands, with real use presses.
extends GdUnitTestSuite

## Where a night's people start: the field below the screen.
const FIELD := Vector3(0.0, 0.0, -34.0)
## Metres a path may end from a stand and still have reached it: what a bot allows (`BotPath`), and
## what the issue asks of the walking mesh.
const REACHED := BotPath.REACHED_SHORT
## Metres at which the mesh has surely taken a bought door in: the stand itself is on it.
const ON_MESH := 0.5
## Physics frames a bought door's mesh gets to reach the map (3 to 12 ticks were measured).
const MAP_FRAMES := 600


func _shop_doors(night: Night) -> Array[StringName]:
	var found: Array[StringName] = []
	for item in night.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			found.append(item.id)
	return found


## How far the walking mesh's path from the field ends from `point`.
func _gap(night: Night, point: Vector3) -> float:
	var way := NavigationServer3D.map_get_path(night.world.map(), FIELD, point, true)
	return INF if way.is_empty() else way[way.size() - 1].distance_to(point)


## Waits until the map answers for every stand of `door_id` (a bought door's mesh reaches it a few
## ticks late).
func _map_reaches(night: Night, door_id: StringName) -> void:
	for _i in MAP_FRAMES:
		if night.world.door_stands(door_id).all(
			func(stand: Vector3) -> bool: return _gap(night, stand) < ON_MESH
		):
			return
		await get_tree().physics_frame


func test_every_door_has_a_stand_for_each_slab_within_reach() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	var reach := night.server.tuning.use_reach
	for door_id in _shop_doors(night):
		var slabs := night.world.door_points(door_id)
		var stands := night.world.door_stands(door_id)
		assert_int(stands.size()).override_failure_message(String(door_id)).is_equal(slabs.size())
		for i in stands.size():
			var apart := Vector2(stands[i].x - slabs[i].x, stands[i].z - slabs[i].z).length()
			assert_float(apart).override_failure_message(String(door_id)).is_less(reach)
	night.queue_free()


func test_the_doors_are_bought_from_their_stands_in_the_shops_order() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	night.server.rules.apply(RulesAction.grant_points(1, 20000))
	var order := _shop_doors(night)
	assert_array(order).is_not_empty()
	for door_id in order:
		await _map_reaches(night, door_id)
		var stands := night.world.door_stands(door_id)
		for stand in stands:
			# The walking mesh ends at the stand, not short of it.
			(
				assert_float(_gap(night, stand))
				. override_failure_message(
					"%s: the path from the field ends short of %s" % [door_id, stand]
				)
				. is_less(REACHED)
			)
			# And a person standing there is offered the door (the body stands on the ground).
			night.player().teleport(stand + Vector3(0.0, 0.1, 0.0))
			NightFixture.run(night, 6)
			(
				assert_str(String(night.state.me()["prompt"].get("id", "")))
				. override_failure_message("%s: no door offered at %s" % [door_id, stand])
				. is_equal(String(door_id))
			)
		var command := NightCommand.new()
		command.use = true
		NightFixture.run(night, 1, command)
		NightFixture.run(night, 3)
		(
			assert_bool(night.server.rules.is_door_open(door_id))
			. override_failure_message("%s was not bought from its stand" % door_id)
			. is_true()
		)
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_a_bought_door_has_no_stands_left() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var door_id := &"door_concession"
	assert_array(night.world.door_stands(door_id)).is_not_empty()
	night.server.rules.apply(RulesAction.grant_points(1, 20000))
	night.player().teleport(night.world.door_stands(door_id)[0] + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 6)
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)
	assert_array(night.world.door_stands(door_id)).is_empty()
	await NightFixture.settle_bake(night)
	night.queue_free()
