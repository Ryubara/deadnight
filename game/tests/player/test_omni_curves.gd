extends OmniHarness
## The acceleration curves, the strafe while aiming, and the replay of omni commands
## (docs/research/character-controller.md).

# --- acceleration ---


func test_a_sprint_builds_up_instead_of_starting_at_once() -> void:
	await _run(Vector2(0.0, -1.0), 12, true)  # 0.2 s: the run speed, and part of the way on
	assert_float(_player.ground_speed()).is_between(_tuning.run_speed, _tuning.sprint_speed - 0.3)
	await _seconds(Vector2(0.0, -1.0), 0.5, true)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.sprint_speed, 0.05)


func test_a_sprint_carries_on_after_the_keys_are_let_go() -> void:
	await _seconds(Vector2(0.0, -1.0), 1.0, true)
	var before := _player.global_position
	await _seconds(Vector2.ZERO, 0.6)
	assert_float(_player.ground_speed()).is_less(0.01)
	var slid := before.distance_to(_player.global_position)
	# Sprint friction down to the run speed, then the run's friction to a stop.
	var run := _tuning.run_speed
	var expected := (
		(_tuning.sprint_speed * _tuning.sprint_speed - run * run) / (2.0 * _tuning.sprint_friction)
		+ run * run / (2.0 * _tuning.ground_friction)
	)
	assert_float(slid).is_between(expected - 0.15, expected + 0.15)


func test_a_run_stops_sooner_than_a_sprint() -> void:
	await _seconds(Vector2(0.0, -1.0), 1.0)
	var before := _player.global_position
	await _seconds(Vector2.ZERO, 0.5)
	var run_slide := before.distance_to(_player.global_position)
	var expected := _tuning.run_speed * _tuning.run_speed / (2.0 * _tuning.ground_friction)
	assert_float(run_slide).is_between(expected - 0.1, expected + 0.1)


func test_letting_the_sprint_go_eases_down_to_the_run() -> void:
	await _seconds(Vector2(0.0, -1.0), 1.0, true)
	await _run(Vector2(0.0, -1.0), 2)
	assert_float(_player.ground_speed()).is_between(_tuning.run_speed + 0.5, _tuning.sprint_speed)
	await _seconds(Vector2(0.0, -1.0), 0.5)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.run_speed, 0.05)


# --- aiming: strafe ---


func test_aiming_strafes_with_the_body_facing_the_view() -> void:
	_yaw = 0.8
	await _seconds(Vector2(1.0, 0.0), 1.0, false, true)
	assert_float(absf(angle_difference(_player.state.facing, _yaw))).is_less(0.02)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.aim_speed, 0.05)
	# Sideways to the view: the heading is the view's right.
	var right := Basis(Vector3.UP, _yaw) * Vector3.RIGHT
	assert_float(_player.state.velocity.normalized().dot(right)).is_greater(0.99)


func test_backing_away_while_aiming_is_slower_than_stepping_forward() -> void:
	await _seconds(Vector2(0.0, 1.0), 1.0, false, true)
	assert_float(_player.ground_speed()).is_equal_approx(
		_tuning.aim_speed * _tuning.aim_backpedal_scale, 0.05
	)
	assert_float(absf(angle_difference(_player.state.facing, _yaw))).is_less(0.02)


func test_aiming_from_a_sprint_slows_down_over_a_moment_and_turns_to_the_view() -> void:
	await _seconds(Vector2(1.0, 0.0), 1.0, true)
	assert_float(absf(angle_difference(_player.state.facing, _facing_for(Vector2.RIGHT)))).is_less(
		0.02
	)
	await _run(Vector2(1.0, 0.0), 2, true, true)
	assert_bool(_player.is_sprinting()).is_false()
	assert_float(_player.ground_speed()).is_greater(_tuning.aim_speed + 1.0)
	await _seconds(Vector2(1.0, 0.0), 0.5, true, true)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.aim_speed, 0.05)
	assert_float(absf(angle_difference(_player.state.facing, _yaw))).is_less(0.02)


func test_sprinting_again_after_aiming_cancels_the_aim_speed() -> void:
	await _seconds(Vector2(0.0, -1.0), 0.8, true, true)
	await _seconds(Vector2(0.0, -1.0), 1.0, true)
	assert_bool(_player.is_sprinting()).is_true()
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.sprint_speed, 0.05)


# --- the network boundary ---


func test_replaying_omni_commands_gives_the_same_result() -> void:
	# What prediction and the server's replay rely on: sprints in every direction, a reversal, an
	# aim and a jump, recorded as bytes and played again from the same state.
	var recorded: Array[PackedByteArray] = []
	var start := _player.state.duplicate_state()
	var directions := _directions()
	for i in 480:
		var command := PlayerCommand.new()
		command.move = directions[(i / 30) % 8]
		command.yaw = 0.3 + 0.002 * i
		command.sprint = (i / 30) % 3 != 2
		command.aim = (i / 30) % 5 == 4
		command.jump = i % 97 == 0
		recorded.append(command.to_bytes())
		_player.submit_command(command)
		await get_tree().physics_frame
	var first_end := _player.state.duplicate_state()
	_player.state.copy_from(start)
	_player.global_position = start.position
	for bytes in recorded:
		_player.submit_command(PlayerCommand.from_bytes(bytes))
		await get_tree().physics_frame
	var replay_end := _player.state
	assert_vector(replay_end.position).is_equal_approx(first_end.position, Vector3.ONE * 0.001)
	assert_vector(replay_end.velocity).is_equal_approx(first_end.velocity, Vector3.ONE * 0.001)
	assert_float(replay_end.facing).is_equal_approx(first_end.facing, 0.001)
	assert_bool(replay_end.sprinting).is_equal(first_end.sprinting)
