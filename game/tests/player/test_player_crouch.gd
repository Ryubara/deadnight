extends OmniHarness
## Crouching: a lower capsule, a slower walk, no sprint or jump, a stand-up that waits for
## room under a low beam, a lower camera and the Duck pose (docs/research/player-controller.md).

## The beam's south face, across the player's way north (-z) from START.
const FACE_Z := 7.0
const BEAM_DEPTH := 6.0
## Lower than the standing body (1.8 m), higher than the crouched one (1.2 m).
const BEAM_BOTTOM := 1.45

var _jumps := 0
var _animation: PlayerAnimation


func before_test() -> void:
	await super.before_test()
	_jumps = 0
	_player.jumped.connect(func() -> void: _jumps += 1)
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# The state machine leaves Start on the first landing; the harness's player settled with the
	# tree off, so start it by hand.
	_animation._playback.start(PlayerAnimation.STATE_LOCOMOTION)


func _add_beam(bottom := BEAM_BOTTOM) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 0.4, BEAM_DEPTH)
	shape.shape = box
	body.add_child(shape)
	_player.get_parent().add_child(body)
	body.global_position = Vector3(START.x, bottom + 0.2, FACE_Z - BEAM_DEPTH * 0.5)
	return body


## Feeds a command each tick for `ticks`, stepping the camera and the animation by hand.
func _crouch_run(
	move: Vector2, ticks: int, crouch := true, sprint := false, aim := false, jump_first := false
) -> void:
	for i in ticks:
		var command := PlayerCommand.new()
		command.move = move
		command.yaw = _yaw
		command.crouch = crouch
		command.sprint = sprint
		command.aim = aim
		command.jump = jump_first and i == 0
		_step(command)
		_player.camera_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)


func _capsule() -> CapsuleShape3D:
	return (_player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D


func _shape_node() -> CollisionShape3D:
	return _player.get_node("CollisionShape3D") as CollisionShape3D


# --- the body ---


func test_crouching_lowers_the_capsule_from_the_feet() -> void:
	assert_float(_capsule().height).is_equal_approx(_tuning.height, 0.001)
	await _crouch_run(Vector2.ZERO, 6)
	assert_bool(_player.state.crouching).is_true()
	assert_float(_capsule().height).is_equal_approx(_tuning.crouch_height, 0.001)
	assert_float(_shape_node().position.y).is_equal_approx(_tuning.crouch_height * 0.5, 0.001)
	assert_float(_player.state.position.y).is_less(0.02)  # the feet did not move


func test_letting_go_stands_up_when_there_is_room() -> void:
	await _crouch_run(Vector2.ZERO, 6)
	await _crouch_run(Vector2.ZERO, 3, false)
	assert_bool(_player.state.crouching).is_false()
	assert_float(_capsule().height).is_equal_approx(_tuning.height, 0.001)
	assert_float(_shape_node().position.y).is_equal_approx(_tuning.height * 0.5, 0.001)


func test_standing_up_beside_a_wall_is_not_blocked_by_it() -> void:
	# A pillar next to the body, closer than the radius of a sprint's stride: only what is overhead
	# keeps a crouch.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 3.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	_player.get_parent().add_child(wall)
	wall.global_position = _player.global_position + Vector3(0.35 + 0.2 + 0.03, 1.5, 0.0)
	await _flush_physics()
	await _crouch_run(Vector2.ZERO, 6)
	await _crouch_run(Vector2.ZERO, 3, false)
	assert_bool(_player.state.crouching).is_false()


func test_crouch_does_not_start_in_the_air() -> void:
	_player.teleport(Vector3(START.x, 6.0, START.z))
	await _crouch_run(Vector2.ZERO, 8)
	assert_bool(_player.state.on_floor).is_false()
	assert_bool(_player.state.crouching).is_false()


# --- speed, sprint, jump ---


func test_a_crouched_walk_goes_at_the_crouch_speed() -> void:
	await _crouch_run(Vector2(0.0, -1.0), 60)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.crouch_speed, 0.05)


func test_a_crouched_aim_walk_is_slower_by_the_same_share() -> void:
	await _crouch_run(Vector2(0.0, -1.0), 60, true, false, true)
	var expected := _tuning.aim_speed * _tuning.crouch_speed / _tuning.run_speed
	assert_float(_player.ground_speed()).is_equal_approx(expected, 0.05)


func test_sprint_is_ignored_while_crouched() -> void:
	await _crouch_run(Vector2(0.0, -1.0), 60, true, true)
	assert_bool(_player.is_sprinting()).is_false()
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.crouch_speed, 0.05)


func test_jump_is_ignored_while_crouched() -> void:
	await _crouch_run(Vector2.ZERO, 6)
	await _crouch_run(Vector2.ZERO, 20, true, false, false, true)
	assert_int(_jumps).is_equal(0)
	assert_float(_player.state.position.y).is_less(0.02)


# --- under a beam ---


func test_a_standing_player_is_stopped_by_a_beam_a_crouched_one_walks_under() -> void:
	_add_beam()
	await _flush_physics()
	await _run(Vector2(0.0, -1.0), 120)
	assert_float(_player.state.position.z).is_greater(FACE_Z)  # stopped at the beam's face
	_player.teleport(START)
	await _run(Vector2.ZERO, 20)
	await _crouch_run(Vector2(0.0, -1.0), 200)
	assert_float(_player.state.position.z).is_less(FACE_Z - 1.0)  # under it


func test_standing_up_under_a_beam_waits_for_the_way_out() -> void:
	_add_beam()
	await _flush_physics()
	await _crouch_run(Vector2(0.0, -1.0), 130)  # under the beam, crouched
	assert_float(_player.state.position.z).is_less(FACE_Z - 0.5)
	await _crouch_run(Vector2.ZERO, 10, false)  # key let go: no room
	assert_bool(_player.state.crouching).is_true()
	assert_float(_capsule().height).is_equal_approx(_tuning.crouch_height, 0.001)
	# Walk on out of the far end with the key up: stands once clear.
	await _crouch_run(Vector2(0.0, -1.0), 200, false)
	assert_float(_player.state.position.z).is_less(FACE_Z - BEAM_DEPTH - 0.5)
	assert_bool(_player.state.crouching).is_false()
	assert_float(_capsule().height).is_equal_approx(_tuning.height, 0.001)


func test_the_crouch_under_a_beam_slows_the_walk_even_with_the_key_up() -> void:
	_add_beam()
	await _flush_physics()
	await _crouch_run(Vector2(0.0, -1.0), 130)
	await _crouch_run(Vector2(0.0, -1.0), 30, false)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.crouch_speed, 0.05)


# --- the network boundary ---


func test_a_replay_crouches_and_stands_the_same() -> void:
	# Recorded in one physics callback, replayed from a standing start in a later one: the stance, the
	# capsule and the position come out the same, with a beam that holds one crouch. (The idle frame
	# of a message handler is the reconcile suite's: replayed in one, this test missed by 0.2 to 6 mm
	# in one run of six, depending on that frame's wall-time delta, which the simulation rescales.)
	_add_beam()
	await _flush_physics()
	var recorded: Array[PackedByteArray] = []
	var start := _player.state.duplicate_state()
	for i in 260:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -1.0) if i < 230 else Vector2(1.0, 0.0)
		command.yaw = 0.0
		command.crouch = i > 20 and i < 150 or i > 200
		command.sprint = i % 70 > 40
		command.jump = i == 15 or i == 160
		recorded.append(command.to_bytes())
		_step(command)
	var first_end := _player.state.duplicate_state()
	var first_height := _capsule().height
	await _flush_physics()  # the replay is a later physics callback; see the note above
	_player.state.copy_from(start)
	_player.global_position = start.position
	_player.velocity = start.velocity
	_capsule().height = _tuning.crouch_height  # the body's shape is not where the start state says
	for bytes in recorded:
		PlayerSimulation.simulate(
			_player, _player.state, PlayerCommand.from_bytes(bytes), _tuning, TICK
		)
	assert_bool(_player.state.crouching).is_equal(first_end.crouching)
	assert_float(_capsule().height).is_equal(first_height)
	assert_float(_player.state.position.distance_to(first_end.position)).is_less(0.001)
	assert_float(_player.state.velocity.distance_to(first_end.velocity)).is_less(0.001)


func test_a_rewind_to_a_crouch_restores_the_crouched_shape() -> void:
	await _crouch_run(Vector2.ZERO, 6)
	var crouched := _player.state.duplicate_state()
	await _crouch_run(Vector2.ZERO, 6, false)
	assert_float(_capsule().height).is_equal_approx(_tuning.height, 0.001)
	_player.state.copy_from(crouched)
	PlayerSimulation.simulate(_player, _player.state, _command(true), _tuning, TICK)
	assert_float(_capsule().height).is_equal_approx(_tuning.crouch_height, 0.001)


func _command(crouch: bool) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.crouch = crouch
	return command


# --- what is seen ---


func test_the_camera_pivot_sits_lower_while_crouched() -> void:
	await _crouch_run(Vector2.ZERO, 90, false)
	var standing := _player.camera_rig.pivot_position().y - _player.state.position.y
	await _crouch_run(Vector2.ZERO, 120)
	var crouched := _player.camera_rig.pivot_position().y - _player.state.position.y
	assert_float(standing).is_equal_approx(_tuning.pivot_height, 0.1)
	assert_float(crouched).is_equal_approx(_tuning.crouch_pivot_height, 0.1)
	assert_float(crouched).is_less(standing - 0.3)


func test_the_crouch_pose_plays_and_the_stand_returns() -> void:
	await _crouch_run(Vector2.ZERO, 30)
	assert_str(str(_animation.current_state())).is_equal("crouch")
	await _crouch_run(Vector2.ZERO, 30, false)
	assert_str(str(_animation.current_state())).is_equal("locomotion")


func test_a_crouched_walk_steps_under_the_held_pose() -> void:
	await _crouch_run(Vector2(0.0, -1.0), 40)
	var mix: float = _animation.get(PlayerAnimation.CROUCH_MIX_PARAMETER)
	assert_float(mix).is_equal_approx(_tuning.crouch_walk_blend, 0.05)
	await _crouch_run(Vector2.ZERO, 40)
	assert_float(_animation.get(PlayerAnimation.CROUCH_MIX_PARAMETER)).is_less(0.05)
