extends OmniHarness
## The reconciliation shape (docs/research/player-controller.md): a client rewinds to the server's
## state and re-runs every unacknowledged command inside ONE callback, which on the network is a
## message handler in an idle frame. The first run is one command per physics frame, as it is
## played; the replay must land where it landed, from the air, from a slope, in either frame kind.

## Where the ramp's foot is (x 6, rising toward -z): the player starts above its middle.
const RAMP_MIDDLE := Vector3(6.0, 0.0, -8.0)
const COMMANDS := 150
## Millimetre, the issue's bar.
const MILLIMETRE := 0.001


## A varied run: runs, a sprint, jumps, an aim, a turn, so every branch of the rules is replayed.
func _commands(yaw_start: float, forward_ticks: int) -> Array[PackedByteArray]:
	var recorded: Array[PackedByteArray] = []
	for i in COMMANDS:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -1.0) if i < forward_ticks else Vector2(1.0, 0.0)
		command.yaw = yaw_start + 0.004 * i
		command.sprint = i > 30 and i < 80
		command.jump = i == 60 or i == 110
		command.aim = i > 120
		command.fire = i > 40 and i < 90
		recorded.append(command.to_bytes())
	return recorded


func _play_one_per_physics_frame(recorded: Array[PackedByteArray]) -> void:
	for bytes in recorded:
		_player.submit_command(PlayerCommand.from_bytes(bytes))
		await get_tree().physics_frame


## The whole batch inside the calling callback, without `tick` (no camera, no signals).
func _replay_in_this_callback(recorded: Array[PackedByteArray]) -> void:
	for bytes in recorded:
		PlayerSimulation.simulate(
			_player,
			_player.state,
			PlayerCommand.from_bytes(bytes),
			_tuning,
			get_tree().root.get_physics_process_delta_time()
		)


func _rewind(start: PlayerMotionState) -> void:
	_player.state.copy_from(start)
	_player.global_position = start.position
	_player.velocity = start.velocity


func _assert_same_end(replayed: PlayerMotionState, first: PlayerMotionState) -> void:
	assert_float(replayed.position.distance_to(first.position)).is_less(MILLIMETRE)
	assert_float(replayed.velocity.distance_to(first.velocity)).is_less(MILLIMETRE)
	assert_float(absf(angle_difference(replayed.facing, first.facing))).is_less(0.001)
	assert_bool(replayed.on_floor).is_equal(first.on_floor)


## Starts in the air above the ramp's middle, falls onto it and runs up and across.
func _start_in_the_air() -> PlayerMotionState:
	_player.teleport(RAMP_MIDDLE + Vector3(0.0, 2.5, 0.0))
	return _player.state.duplicate_state()


## Starts standing on the ramp (settled), so the floor is a slope from the first tick.
func _start_on_the_slope() -> PlayerMotionState:
	_player.teleport(RAMP_MIDDLE + Vector3(0.0, 2.5, 0.0))
	await _run(Vector2.ZERO, 60)
	assert_bool(_player.state.on_floor).is_true()
	assert_float(_player.state.position.y).is_greater(0.4)  # on the ramp, not the floor
	return _player.state.duplicate_state()


func test_a_batch_replayed_in_one_physics_callback_matches_from_the_air() -> void:
	var start := _start_in_the_air()
	var recorded := _commands(0.0, 100)
	await _play_one_per_physics_frame(recorded)
	var first_end := _player.state.duplicate_state()
	assert_float(first_end.position.distance_to(start.position)).is_greater(5.0)
	await get_tree().physics_frame
	_rewind(start)
	_replay_in_this_callback(recorded)
	_assert_same_end(_player.state, first_end)


func test_a_batch_replayed_in_one_physics_callback_matches_on_a_slope() -> void:
	var start: PlayerMotionState = await _start_on_the_slope()
	var recorded := _commands(PI, 100)  # yaw PI faces +z: the first leg runs down the ramp
	await _play_one_per_physics_frame(recorded)
	var first_end := _player.state.duplicate_state()
	assert_float(first_end.position.distance_to(start.position)).is_greater(5.0)
	await get_tree().physics_frame
	_rewind(start)
	_replay_in_this_callback(recorded)
	_assert_same_end(_player.state, first_end)


func test_a_batch_replayed_in_an_idle_frame_matches_from_the_air() -> void:
	var start := _start_in_the_air()
	var recorded := _commands(0.0, 100)
	await _play_one_per_physics_frame(recorded)
	var first_end := _player.state.duplicate_state()
	# What a SceneMultiplayer message handler sees: a process frame, not a physics frame.
	await get_tree().process_frame
	assert_bool(Engine.is_in_physics_frame()).is_false()
	_rewind(start)
	_replay_in_this_callback(recorded)
	_assert_same_end(_player.state, first_end)


func test_a_batch_replayed_in_an_idle_frame_matches_on_a_slope() -> void:
	var start: PlayerMotionState = await _start_on_the_slope()
	var recorded := _commands(PI, 100)
	await _play_one_per_physics_frame(recorded)
	var first_end := _player.state.duplicate_state()
	await get_tree().process_frame
	assert_bool(Engine.is_in_physics_frame()).is_false()
	_rewind(start)
	_replay_in_this_callback(recorded)
	_assert_same_end(_player.state, first_end)


func test_an_idle_frame_with_a_slow_frame_time_still_matches() -> void:
	# The frame delta is wall time; make it very different from the physics tick.
	var start := _start_in_the_air()
	var recorded := _commands(0.0, 100)
	await _play_one_per_physics_frame(recorded)
	var first_end := _player.state.duplicate_state()
	OS.delay_msec(120)  # the next idle frame's delta is long
	await get_tree().process_frame
	await get_tree().process_frame
	_rewind(start)
	_replay_in_this_callback(recorded)
	_assert_same_end(_player.state, first_end)


func test_the_delta_argument_is_the_step_taken_in_either_kind_of_frame() -> void:
	# In the air with no input the horizontal velocity is untouched, so the step is exactly
	# velocity * delta: twice the tick moves twice as far, in a physics frame and in an idle one.
	_player.teleport(Vector3(START.x, 20.0, START.z))
	var start := _player.state.duplicate_state()
	start.velocity = Vector3(4.0, 0.0, 0.0)
	for idle in [false, true]:
		if idle:
			await get_tree().process_frame
		else:
			await get_tree().physics_frame
		for ticks in [1.0, 2.0, 0.5]:
			_rewind(start)
			var command := PlayerCommand.new()
			PlayerSimulation.simulate(_player, _player.state, command, _tuning, TICK * ticks)
			var moved := _player.state.position.x - start.position.x
			assert_float(moved).is_equal_approx(4.0 * TICK * ticks, MILLIMETRE)
