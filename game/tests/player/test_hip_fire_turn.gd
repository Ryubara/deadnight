# The shot waits for the body (#477), the client's side: a predicting client runs the very
# simulation the server does, so from the same commands it knows the tick the shot leaves
# (`shot_ready`), keeps a tap made during the turn, and a replay from an older state agrees. The
# server's own shot, once per press: tests/night/test_night_hip_fire_turn.gd. Stepped by hand with
# fixed ticks (no wall time).
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)

var _runner: GdUnitSceneRunner
var _player: Player
var _tuning: PlayerTuning


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_tuning = _player.tuning
	_player.teleport(START)
	for i in 20:
		await get_tree().physics_frame


func _tolerance() -> float:
	return deg_to_rad(_tuning.hip_fire_align_degrees)


func _command(yaw: float, fire: bool, aim: bool = false) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = yaw
	command.fire = fire
	command.aim = aim
	return command


## Runs `commands` one physics tick each and returns the state after each.
func _run(commands: Array[PlayerCommand]) -> Array[PlayerMotionState]:
	var states: Array[PlayerMotionState] = []
	for command in commands:
		_player.submit_command(command)
		await get_tree().physics_frame
		states.append(_player.state.duplicate_state())
	return states


func _ready_ticks(states: Array[PlayerMotionState]) -> Array[int]:
	var ticks: Array[int] = []
	for i in states.size():
		if states[i].shot_ready:
			ticks.append(i)
	return ticks


func _repeat(command: PlayerCommand, count: int) -> Array[PlayerCommand]:
	var list: Array[PlayerCommand] = []
	for i in count:
		list.append(command)
	return list


func test_facing_the_view_the_shot_is_ready_on_the_press() -> void:
	var states := await _run(_repeat(_command(_player.state.facing, true), 5))
	assert_array(_ready_ticks(states)).is_equal([0, 1, 2, 3, 4])


func test_facing_away_the_shot_is_not_ready_until_the_body_has_turned() -> void:
	var back := _player.state.facing + PI
	var states := await _run(_repeat(_command(back, true), 60))
	var ready := _ready_ticks(states)
	assert_int(ready.size()).is_greater(0)
	# From the first ready tick on it stays ready (a held trigger), and never before.
	assert_int(ready[0]).is_greater_equal(
		ceili((PI - _tolerance()) / (_tuning.aim_turn_speed * TICK)) - 1
	)
	assert_int(ready.size()).is_equal(60 - ready[0])
	for i in states.size():
		if i < ready[0]:
			assert_float(states[i].view_error).is_greater(_tolerance())
		else:
			assert_float(states[i].view_error).is_less_equal(_tolerance() + 0.001)


func test_a_tap_made_during_the_turn_is_ready_once_when_the_body_is_there() -> void:
	var back := _player.state.facing + PI
	var commands := _repeat(_command(back, true), 3)
	commands.append_array(_repeat(_command(back, false), 70))
	var states := await _run(commands)
	var ready := _ready_ticks(states)
	assert_int(ready.size()).is_equal(1)
	assert_float(states[ready[0]].view_error).is_less_equal(_tolerance() + 0.001)
	assert_float(states[ready[0]].shot_buffer).is_equal(0.0)


func test_a_tap_that_the_turn_outlasts_is_dropped_when_its_buffer_runs_out() -> void:
	# A press is kept for `hip_fire_buffer`; a turn that takes longer (a short buffer here, a half
	# circle needs 23 ticks) leaves nothing behind: the spent tap is not ready late.
	var kept := _tuning.hip_fire_buffer
	_tuning.hip_fire_buffer = 0.1
	var back := _player.state.facing + PI
	var commands := _repeat(_command(back, true), 3)
	commands.append_array(_repeat(_command(back, false), 70))
	var states := await _run(commands)
	_tuning.hip_fire_buffer = kept
	assert_array(_ready_ticks(states)).is_empty()


func test_a_view_still_turning_keeps_the_shot_waiting() -> void:
	var yaw := _player.state.facing
	var commands: Array[PlayerCommand] = []
	for i in 5:
		yaw += 0.2  # the view runs ahead of the body (no trigger: the body stays)
		commands.append(_command(yaw, false))
	for i in 12:
		yaw += 0.2  # 11.5 degrees a tick: faster than the body's 7.6
		commands.append(_command(yaw, true))
	for i in 30:
		commands.append(_command(yaw, true))
	var states := await _run(commands)
	var ready := _ready_ticks(states)
	assert_int(ready.size()).is_greater(0)
	assert_int(ready[0]).is_greater_equal(17)


func test_the_aim_button_needs_no_turn() -> void:
	var states := await _run(_repeat(_command(_player.state.facing + PI, true, true), 3))
	assert_array(_ready_ticks(states)).is_equal([0, 1, 2])


func test_a_replay_from_an_older_state_is_ready_on_the_same_ticks() -> void:
	var back := _player.state.facing + PI
	var commands := _repeat(_command(back, true), 3)
	commands.append_array(_repeat(_command(back, false), 60))
	var start := _player.state.duplicate_state()
	var first := await _run(commands)
	# The server's answer arrives and the client plays its commands again from the state it names.
	_player.state.copy_from(start)
	_player.global_position = start.position
	var again := await _run(commands)
	assert_array(_ready_ticks(again)).is_equal(_ready_ticks(first))
	for i in first.size():
		assert_float(again[i].shot_buffer).is_equal_approx(first[i].shot_buffer, 0.0001)
		assert_float(again[i].facing).is_equal_approx(first[i].facing, 0.0001)
