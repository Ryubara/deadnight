# Rewinding a predicting body to an older state and replaying commands from it (a client that takes
# the server's answer and plays its unanswered commands again): the replay must follow the run it
# replaces, from the ground on a slope and from mid-air, whatever contact the body had last.
extends GdUnitTestSuite

const TICK := SlopeWorld.TICK

var _player: Player


func _world() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	_player = await SlopeWorld.build(root)


## Up the ramp, then back down it at a sprint; optionally one jump.
func _command(tick: int, jump_at: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(1, 0) if tick < 120 else Vector2(-1, 0)
	command.sprint = true
	command.jump = tick == jump_at
	return command


func _run(from: int, to: int, jump_at: int) -> Array[PlayerMotionState]:
	var states: Array[PlayerMotionState] = []
	for tick in range(from, to):
		_player.tick(_command(tick, jump_at))
		states.append(_player.state.duplicate_state())
	return states


## The furthest the replay from tick `start` strays from `reference` (metres).
func _replay_error(
	reference: Array[PlayerMotionState], start: int, length: int, jump_at: int, restore: bool
) -> float:
	var from := reference[start]
	_player.state.copy_from(from)
	if restore:
		PlayerSimulation.restore(_player, from, TICK)
	else:
		_player.global_position = from.position
		_player.velocity = from.velocity
	var replay := _run(start + 1, length, jump_at)
	var worst := 0.0
	for i in replay.size():
		worst = maxf(worst, replay[i].position.distance_to(reference[start + 1 + i].position))
	return worst


## The first tick after `after` where `wanted` holds for the state.
func _find(reference: Array[PlayerMotionState], after: int, wanted: Callable) -> int:
	for tick in range(after, reference.size()):
		if wanted.call(reference[tick]):
			return tick
	return -1


func test_a_replay_from_the_ground_on_the_slope_follows_the_run() -> void:
	await _world()
	# The run ends in the air (a jump on the last ticks), so the body's own last contact says "no
	# floor" while the state to replay from stands on the ramp.
	var reference := _run(0, 262, 258)
	var start := _find(reference, 130, func(s: PlayerMotionState) -> bool: return s.on_floor)
	assert_int(start).is_greater(0)
	assert_float(reference[start].position.y).is_greater(0.5)
	assert_float(_replay_error(reference, start, 262, 258, true)).is_less(0.01)


func test_without_restore_a_replay_from_the_slope_strays() -> void:
	await _world()
	# Why `restore` exists: the same replay with the body only moved by hand leaves the ramp by the
	# contact it remembers (measured 0.2 m).
	var reference := _run(0, 262, 258)
	var start := _find(reference, 130, func(s: PlayerMotionState) -> bool: return s.on_floor)
	assert_float(_replay_error(reference, start, 262, 258, false)).is_greater(0.1)


func test_a_replay_from_mid_air_over_the_slope_follows_the_run() -> void:
	await _world()
	# A jump on the way down; the run ends on the ground, so the body remembers a floor while the
	# state to replay from is in the air.
	var reference := _run(0, 400, 150)
	var start := _find(
		reference,
		151,
		func(s: PlayerMotionState) -> bool: return not s.on_floor and s.position.y > 0.4
	)
	assert_int(start).is_greater(0)
	assert_bool(reference[start].on_floor).is_false()
	assert_float(_replay_error(reference, start, 400, 150, true)).is_less(0.01)


func test_every_state_of_a_run_replays_to_the_same_end() -> void:
	await _world()
	var reference := _run(0, 330, 150)
	for start in range(5, 320, 13):
		(
			assert_float(_replay_error(reference, start, 330, 150, true))
			. override_failure_message("from tick %d" % start)
			. is_less(0.01)
		)
