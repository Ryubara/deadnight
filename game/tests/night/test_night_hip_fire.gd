# The server turns a firing player to the view (the facing it uses for the muzzle) and the shot
# still lands where the camera ray is.
extends GdUnitTestSuite


func test_a_fire_command_turns_the_body_to_the_view_and_the_shot_still_hits() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var zombie_id := NightFixture.first_zombie(night)
	assert_int(zombie_id).is_greater(0)
	var body: ZombieBody = night.server.sim.zombies[zombie_id]
	var player := night.player()
	# The zombie stands to the east and the view is turned to it; the body has not been.
	var spot := night.state.position() + Vector3(6.0, 0.0, 0.0)
	var east := -PI / 2.0
	assert_float(absf(angle_difference(player.state.facing, east))).is_greater(1.0)
	var damaged := {"count": 0}
	night.state.event_received.connect(
		func(e: Dictionary) -> void: damaged["count"] += 1 if e["type"] == &"damage_dealt" else 0
	)
	var command := NightFixture.shoot_at(night, spot)
	command.motion.yaw = east
	# 90 degrees at the aim turn speed (8 rad/s) is 12 ticks.
	for _i in 16:
		body.position = spot
		body.velocity = Vector3.ZERO
		NightFixture.run(night, 1, command)
	assert_float(absf(angle_difference(player.state.facing, east))).is_less(0.02)
	assert_float(player.state.fire_age).is_less(0.2)
	assert_int(damaged["count"]).is_greater(0)
	# Hip fire in the real night leaves the view alone: 60 degrees, no zoom (#464).
	assert_float(player.camera_rig.camera().fov).is_equal_approx(player.tuning.fov, 0.0001)
	assert_float(player.camera_rig.aim_amount()).is_equal_approx(0.0, 0.0001)
	# The trigger let go: the body keeps the view for the hold, whatever it walks to afterwards.
	var idle := NightCommand.new()
	idle.motion.yaw = east
	idle.motion.move = Vector2(0.0, 1.0)  # walking backward: the body would turn the other way
	NightFixture.run(night, 20, idle)
	assert_float(absf(angle_difference(player.state.facing, east))).is_less(0.1)
	night.queue_free()


func test_a_downed_player_does_not_turn_to_fire() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	night.server.rules.apply(RulesAction.set_downed(1, true))
	NightFixture.run(night, 3)
	var player := night.player()
	var facing := player.state.facing
	var command := NightCommand.new()
	command.fire = true
	command.motion.yaw = facing + 1.5
	NightFixture.run(night, 20, command)
	assert_float(player.state.facing).is_equal_approx(facing, 0.001)
	night.queue_free()
