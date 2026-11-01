# A door bought in the night: the lot's own `LotDoors` and `DoorNavigation` carry it out, so
# the whole door goes (slabs and price label) and the server tick that sells it does not stall
# on a bake.
extends GdUnitTestSuite

const DOOR := &"door_concession"
## A tick that sells a door must stay far below the bake the night used to wait for (420 ms).
const TICK_BUDGET_MS := 60.0


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	night.player().teleport(night.world.door_points(DOOR)[0] + Vector3(0.0, 0.1, -2.0))
	night.state.apply_events(night.server.rules.apply(RulesAction.grant_points(1, 400)))
	NightFixture.run(night, 3)
	return night


func _door_node(night: Night) -> Node:
	for door in night.world.doors.get_children():
		if door.get_meta(&"shop_id", "") == String(DOOR):
			return door
	return null


func test_a_bought_door_loses_its_slabs_and_its_price_label() -> void:
	var night := await _start()
	var door := _door_node(night)
	assert_array(door.find_children("*", "Label3D", true, false)).is_not_empty()
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)
	assert_bool(night.server.rules.is_door_open(DOOR)).is_true()
	assert_int(door.get_child_count()).is_equal(0)
	assert_array(door.find_children("*", "Label3D", true, false)).is_empty()
	night.queue_free()


func test_the_tick_that_sells_a_door_does_not_wait_for_the_bake() -> void:
	var night := await _start()
	var command := NightCommand.new()
	command.use = true
	night.link.send(command.to_dict())
	var worst := 0.0
	for _i in 5:
		var began := Time.get_ticks_usec()
		night.tick()
		worst = maxf(worst, (Time.get_ticks_usec() - began) / 1000.0)
	assert_bool(night.server.rules.is_door_open(DOOR)).is_true()
	assert_float(worst).is_less(TICK_BUDGET_MS)
	night.queue_free()


func test_the_mesh_follows_the_door_a_moment_later() -> void:
	var night := await _start()
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	assert_bool(night.world.navigation.is_busy()).is_true()
	for _i in 1800:
		await get_tree().physics_frame
		if not night.world.navigation.is_busy():
			break
	assert_bool(night.world.navigation.is_busy()).is_false()
	assert_int(night.world.navigation.bake_count).is_equal(2)
	night.queue_free()
