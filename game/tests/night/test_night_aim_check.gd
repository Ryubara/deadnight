# A shot goes where its own view points (bots plan, gap 1): the server refuses a command whose `dir`
# disagrees with its `motion.yaw` and `pitch`. A person's shot is the camera's forward, so it
# always agrees; a client that shoots at one zombie while looking at another is turned away.
extends GdUnitTestSuite

const SETTLE := 30


func _start() -> Night:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(night, SETTLE)
	night.server.rules.apply(RulesAction.skip_break())
	NightFixture.run(night, SETTLE)
	return night


func _shot(yaw: float, pitch: float, off_by_degrees := 0.0) -> NightCommand:
	var command := NightCommand.new()
	command.motion.yaw = yaw
	command.motion.pitch = pitch
	command.fire = true
	command.dir = NightServer.view_dir(yaw + deg_to_rad(off_by_degrees), pitch)
	return command


func test_the_view_dir_follows_the_camera_convention() -> void:
	assert_vector(NightServer.view_dir(0.0, 0.0)).is_equal_approx(
		Vector3(0, 0, -1), Vector3.ONE * 0.001
	)
	assert_vector(NightServer.view_dir(PI / 2.0, 0.0)).is_equal_approx(
		Vector3(-1, 0, 0), Vector3.ONE * 0.001
	)
	assert_float(NightServer.view_dir(0.0, 0.5).y).is_greater(0.4)


func test_a_shot_along_the_view_is_taken_and_one_across_it_is_refused() -> void:
	var night := await _start()
	var shots: Array[Dictionary] = []
	var refused: Array[Dictionary] = []
	night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == &"shot_fired":
				shots.append(event)
			elif event["type"] == &"fire_rejected" and event["reason"] == &"aim_mismatch":
				refused.append(event)
	)
	NightFixture.run(night, 1, _shot(0.3, 0.1))
	NightFixture.run(night, 30, NightCommand.new())
	assert_int(shots.size()).is_equal(1)
	assert_int(refused.size()).is_equal(0)
	# Ninety degrees off: the muzzle never fires.
	NightFixture.run(night, 1, _shot(0.3, 0.1, 90.0))
	NightFixture.run(night, 30, NightCommand.new())
	assert_int(shots.size()).is_equal(1)
	assert_int(refused.size()).is_equal(1)
	night.queue_free()


func test_the_slack_is_a_few_degrees_not_zero() -> void:
	var night := await _start()
	var tuning := night.server.tuning
	(
		assert_bool(night.server.aims_with_view(_shot(1.0, 0.0, tuning.aim_slack_degrees - 1.0)))
		. is_true()
	)
	(
		assert_bool(night.server.aims_with_view(_shot(1.0, 0.0, tuning.aim_slack_degrees + 1.0)))
		. is_false()
	)
	night.queue_free()


func test_a_direction_that_is_not_one_is_refused() -> void:
	var night := await _start()
	var command := _shot(0.0, 0.0)
	command.dir = Vector3.ZERO
	assert_bool(night.server.aims_with_view(command)).is_false()
	command.dir = Vector3(INF, 0.0, 0.0)
	assert_bool(night.server.aims_with_view(command)).is_false()
	night.queue_free()


func test_a_persons_camera_always_agrees_with_its_own_yaw_and_pitch() -> void:
	var night := await _start()
	var rig := night.player().camera_rig
	var human := HumanController.new()
	var worst := 0.0
	for yaw in [-3.0, -1.2, 0.0, 0.7, 2.9]:
		for pitch in [-0.5, 0.0, 0.4]:
			rig.yaw = yaw
			rig.pitch = pitch
			await get_tree().process_frame
			await get_tree().process_frame
			var command := human.command(night.player(), 1)
			var apart := rad_to_deg(
				NightServer.view_dir(command.motion.yaw, command.motion.pitch).angle_to(command.dir)
			)
			worst = maxf(worst, apart)
			assert_bool(night.server.aims_with_view(command)).is_true()
	assert_float(worst).is_less(1.0)
	night.queue_free()
