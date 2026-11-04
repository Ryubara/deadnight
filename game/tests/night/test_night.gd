# One night on the drive-in lot, driven by hand: joining, moving, shooting, buying, pausing, dying.
extends GdUnitTestSuite

const STEP := Night.STEP


func test_a_night_starts_with_the_player_holding_the_house_pistol() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	var me := night.state.me()
	assert_str(String(me["weapon"])).is_equal("house_pistol")
	assert_int(me["ammo"]).is_equal(15)
	assert_int(me["points"]).is_equal(200)
	assert_int(night.state.phase()).is_equal(GameRules.Phase.BREAK)
	night.queue_free()


func test_a_move_command_walks_the_player() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var start := night.state.position()
	var command := NightCommand.new()
	command.motion.move = Vector2(0.0, -1.0)
	NightFixture.run(night, 60, command)
	assert_float(night.state.position().distance_to(start)).is_greater(2.0)
	night.queue_free()


func test_a_fire_command_wounds_and_pays() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var zombie_id := NightFixture.first_zombie(night)
	assert_int(zombie_id).is_greater(0)
	var body: ZombieBody = night.server.sim.zombies[zombie_id]
	var spot := night.state.position() + Vector3(0.0, 0.0, -6.0)
	var heard: Array[StringName] = []
	night.state.event_received.connect(func(e: Dictionary) -> void: heard.append(e["type"]))
	var before := night.state.points()
	for _i in 12:
		body.position = spot
		body.velocity = Vector3.ZERO
		NightFixture.run(night, 1, NightFixture.shoot_at(night, spot))
	NightFixture.run(night, 5)
	assert_bool(heard.has(&"shot_fired")).is_true()
	assert_bool(heard.has(&"damage_dealt")).is_true()
	assert_int(night.state.points()).is_greater(before)
	night.queue_free()


func test_use_buys_the_door_in_reach() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var door := &"door_concession"
	var slab := night.world.door_points(door)[0]
	night.player().teleport(slab + Vector3(0.0, 0.1, -2.0))
	night.server.rules.apply(RulesAction.grant_points(1, 400))
	NightFixture.run(night, 3)
	assert_str(String(night.state.me()["prompt"].get("id", ""))).is_equal("door_concession")
	var before := night.state.points()
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)
	assert_bool(night.server.rules.is_door_open(door)).is_true()
	assert_bool(night.world.door_points(door).is_empty()).is_true()
	assert_int(night.state.points()).is_equal(before - 350)
	assert_int(night.state.doors_bought).is_equal(1)
	night.queue_free()


func test_the_clock_stops_while_paused() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	night.set_paused(true)
	var ticks := night.server.tick_count
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(night.server.tick_count).is_equal(ticks)
	night.set_paused(false)
	assert_bool(night.running).is_true()
	night.queue_free()


func test_a_player_left_to_the_dead_ends_the_night() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var zombie_id := NightFixture.first_zombie(night)
	var body: ZombieBody = night.server.sim.zombies[zombie_id]
	for _i in 900:
		body.position = night.state.position() + Vector3(0.0, 0.0, 0.8)
		night.tick()
		if night.state.over:
			break
	assert_bool(night.state.over).is_true()
	assert_float(night.state.damage_taken).is_greater_equal(100.0)
	assert_bool(night.running).is_false()
	night.queue_free()
