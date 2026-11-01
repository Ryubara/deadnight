extends OmniHarness
## Sprint in every direction when not aiming, and a body that turns toward its travel at the tuned
## rate, arcs, and pivots on a reversal (docs/research/character-controller.md).

# --- sprint in every direction ---


func test_sprint_works_in_all_eight_directions_when_not_aiming() -> void:
	for move in _directions():
		_player.teleport(START)
		await _run(Vector2.ZERO, 20)
		await _seconds(move, 1.2, true)
		var label := "direction %s" % move
		assert_bool(_player.is_sprinting()).override_failure_message(label).is_true()
		assert_bool(_player.camera_rig.sprinting).override_failure_message(label).is_true()
		assert_float(_player.ground_speed()).override_failure_message(label).is_equal_approx(
			_tuning.sprint_speed, 0.05
		)


func test_the_body_faces_the_way_it_sprints_in_every_direction() -> void:
	for move in _directions():
		_player.teleport(START)
		_player.state.facing = 0.0
		await _run(Vector2.ZERO, 20)
		await _seconds(move, 1.2, true)
		var off := absf(angle_difference(_player.state.facing, _facing_for(move)))
		(
			assert_float(off)
			. override_failure_message("direction %s faces %.1f deg off" % [move, rad_to_deg(off)])
			. is_less(0.02)
		)
		# The body goes where it faces: no skating.
		var heading := absf(angle_difference(deg_to_rad(_heading_degrees()), _player.state.facing))
		assert_float(heading).is_less(0.03)


func test_sprint_works_the_same_with_the_view_turned() -> void:
	_yaw = 2.0
	for move in [Vector2(0.0, -1.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0)]:
		_player.teleport(START)
		await _run(Vector2.ZERO, 20)
		await _seconds(move, 0.8, true)
		assert_bool(_player.is_sprinting()).is_true()
		assert_float(absf(angle_difference(_player.state.facing, _facing_for(move)))).is_less(0.02)


func test_sprint_never_works_while_aiming() -> void:
	for move in _directions():
		_player.teleport(START)
		await _run(Vector2.ZERO, 20)
		await _seconds(move, 1.0, true, true)
		var label := "direction %s" % move
		assert_bool(_player.is_sprinting()).override_failure_message(label).is_false()
		assert_bool(_player.camera_rig.sprinting).override_failure_message(label).is_false()
		assert_float(_player.ground_speed()).override_failure_message(label).is_less_equal(
			_tuning.aim_speed + 0.05
		)


func test_a_nudge_of_the_stick_does_not_start_a_sprint() -> void:
	await _seconds(Vector2(0.0, -_tuning.sprint_min_input * 0.5), 0.6, true)
	assert_bool(_player.is_sprinting()).is_false()
	await _seconds(Vector2(0.0, -_tuning.sprint_min_input), 0.3, true)
	assert_bool(_player.is_sprinting()).is_true()


func test_sprinting_with_no_input_is_not_a_sprint() -> void:
	await _seconds(Vector2.ZERO, 0.5, true)
	assert_bool(_player.is_sprinting()).is_false()


func test_a_jump_from_a_sprint_keeps_the_sprint_in_the_air() -> void:
	await _seconds(Vector2(0.0, 1.0), 0.8, true)
	await _run(Vector2(0.0, 1.0), 1, true, false, true)
	await _run(Vector2(0.0, 1.0), 6, true)
	assert_bool(_player.state.on_floor).is_false()
	assert_bool(_player.is_sprinting()).is_true()
	# Letting the sprint key go in the air ends it.
	await _run(Vector2(0.0, 1.0), 2, false)
	assert_bool(_player.is_sprinting()).is_false()


# --- turning ---


func test_the_body_turns_toward_travel_at_the_tuned_rate() -> void:
	# A quarter turn is below the pivot angle, so the run's turn speed applies.
	assert_float(_tuning.pivot_angle_degrees).is_greater(90.0)
	var start := _player.state.facing
	await _run(Vector2(1.0, 0.0), 5)
	var turned := absf(angle_difference(start, _player.state.facing))
	assert_float(turned).is_equal_approx(_tuning.turn_speed * 5.0 * TICK, 0.001)


func test_a_sprint_turns_slower_than_a_run() -> void:
	var start := _player.state.facing
	await _run(Vector2(1.0, 0.0), 5, true)
	var turned := absf(angle_difference(start, _player.state.facing))
	assert_float(turned).is_equal_approx(_tuning.sprint_turn_speed * 5.0 * TICK, 0.001)


func test_the_velocity_turns_with_the_body_in_an_arc() -> void:
	await _seconds(Vector2(0.0, -1.0), 1.0)
	await _run(Vector2(1.0, 0.0), 3)
	# Three ticks into the turn the heading has moved at the turn rate, with the speed kept.
	var heading := absf(angle_difference(deg_to_rad(_heading_degrees()), 0.0))
	assert_float(heading).is_equal_approx(_tuning.turn_speed * 3.0 * TICK, 0.02)
	assert_float(_player.ground_speed()).is_greater(_tuning.run_speed - 0.2)


func test_a_reversal_pivots_quickly_and_goes_the_other_way() -> void:
	await _seconds(Vector2(0.0, -1.0), 1.0, true)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.sprint_speed, 0.05)
	# Four ticks into the reversal the body has turned at the pivot rate, faster than a run turn.
	await _run(Vector2(0.0, 1.0), 4, true)
	var turned := absf(angle_difference(0.0, _player.state.facing))
	assert_float(turned).is_equal_approx(_tuning.pivot_turn_speed * 4.0 * TICK, 0.05)
	assert_float(turned).is_greater(_tuning.turn_speed * 4.0 * TICK + 0.2)
	# The speed is being shed along the old heading, not turned into an arc.
	assert_float(_player.state.velocity.z).is_less(0.0)
	assert_float(_player.ground_speed()).is_less(_tuning.sprint_speed - 1.0)
	await _seconds(Vector2(0.0, 1.0), 0.15, true)
	# Planted: nearly stopped or already coming back.
	assert_float(_player.ground_speed()).is_less(3.5)
	await _seconds(Vector2(0.0, 1.0), 1.0, true)
	assert_bool(_player.is_sprinting()).is_true()
	assert_float(_player.state.velocity.z).is_greater(_tuning.sprint_speed - 0.1)
	assert_float(absf(angle_difference(_player.state.facing, PI))).is_less(0.02)


func test_the_whole_reversal_takes_a_fraction_of_a_second() -> void:
	await _seconds(Vector2(0.0, -1.0), 1.0)
	var ticks := 0
	while _player.state.velocity.z < _tuning.run_speed - 0.2 and ticks < 120:
		await _run(Vector2(0.0, 1.0), 1)
		ticks += 1
	assert_float(ticks * TICK).is_less(0.35)


func test_the_body_does_not_moonwalk_out_of_a_turn_on_the_spot() -> void:
	# From a standstill, asking for the way behind: the body turns first (0.14 s at the pivot rate).
	await _run(Vector2(0.0, 1.0), 3)
	assert_float(_player.ground_speed()).is_less_equal(_tuning.pivot_walk_speed + 0.1)
	await _seconds(Vector2(0.0, 1.0), 0.8)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.run_speed, 0.05)
