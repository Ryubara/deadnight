# Firing without aiming: the body turns to the view and the camera eases part of the way into the
# aim view, then lets go after a delay. Stepped by hand with fixed ticks (no wall time), like the
# shoulder camera suite.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _tuning: PlayerTuning


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_rig = _player.camera_rig
	_tuning = _player.tuning
	# The camera ease advances by the frame delta (wall time): step it by hand instead.
	_rig.set_process(false)
	_player.teleport(START)
	await _ticks(20)


func after_test() -> void:
	Input.action_release("fire")
	Input.action_release("aim")


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		_rig.step(TICK, 1.0)


func _seconds(seconds: float) -> void:
	await _ticks(roundi(seconds / TICK))


func _hip_zoom_fov() -> float:
	return lerpf(_tuning.fov, _tuning.fov_aim, _tuning.hip_fire_zoom)


func test_without_firing_the_body_does_not_follow_the_view() -> void:
	_rig.yaw = 1.2
	await _seconds(0.5)
	assert_float(_player.rotation.y).is_equal_approx(0.0, 0.01)
	assert_float(_rig.zoom_amount()).is_equal_approx(0.0, 0.001)


func test_firing_turns_the_body_to_the_view_within_a_few_ticks() -> void:
	_rig.yaw = 1.2
	_runner.simulate_action_press("fire")
	# 1.2 radians at the hip-fire turn speed: a handful of ticks, and not a snap.
	await _ticks(1)
	assert_float(_player.rotation.y).is_between(0.05, 1.19)
	var ticks_needed := ceili(1.2 / (_tuning.hip_fire_turn_speed * TICK)) + 2
	await _ticks(ticks_needed)
	assert_float(_player.rotation.y).is_equal_approx(1.2, 0.01)
	assert_bool(_player.is_aiming()).is_false()


func test_a_strafing_player_faces_the_view_while_firing_then_turns_back_after_the_hold() -> void:
	_runner.simulate_action_press("move_right")
	await _seconds(0.3)
	# Strafing right: the body turns toward the move direction (-90 degrees from the view).
	assert_float(_player.rotation.y).is_less(-1.0)
	_runner.simulate_action_press("fire")
	await _seconds(0.4)
	assert_float(_player.rotation.y).is_equal_approx(_rig.yaw, 0.02)
	_runner.simulate_action_release("fire")
	await _seconds(_tuning.hip_fire_hold - 0.2)
	assert_float(_player.rotation.y).is_equal_approx(_rig.yaw, 0.02)
	await _seconds(0.7)
	assert_float(_player.rotation.y).is_less(-1.0)
	_runner.simulate_action_release("move_right")


func test_firing_eases_the_camera_part_of_the_way_into_the_aim_view() -> void:
	var camera := _rig.camera()
	assert_float(camera.fov).is_equal_approx(_tuning.fov, 0.1)
	var hip_lens := _rig.lens_distance()
	_runner.simulate_action_press("fire")
	await _seconds(0.05)
	assert_float(camera.fov).is_between(_hip_zoom_fov() + 0.3, _tuning.fov - 0.05)  # mid-ease
	await _seconds(1.0)
	assert_float(_rig.zoom_amount()).is_equal_approx(_tuning.hip_fire_zoom, 0.01)
	assert_float(camera.fov).is_equal_approx(_hip_zoom_fov(), 0.1)
	# Part of the way: closer than the hip view, farther than the aim view.
	var aim_lens := Vector2(_tuning.shoulder_offset_aim, _tuning.arm_length_aim).length()
	assert_float(_rig.lens_distance()).is_less(hip_lens - 0.05)
	assert_float(_rig.lens_distance()).is_greater(aim_lens + 0.05)
	assert_bool(_rig.is_aim_zoomed()).is_false()


func test_the_zoom_holds_for_the_delay_after_the_last_shot_then_releases() -> void:
	var camera := _rig.camera()
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	_runner.simulate_action_release("fire")
	await _seconds(_tuning.hip_fire_zoom_delay - 0.2)
	assert_float(_rig.zoom_amount()).is_equal_approx(_tuning.hip_fire_zoom, 0.02)
	await _seconds(0.4)  # the delay is over: it starts to ease out
	assert_float(_rig.zoom_amount()).is_less(_tuning.hip_fire_zoom - 0.02)
	await _seconds(1.5)
	assert_float(_rig.zoom_amount()).is_equal_approx(0.0, 0.01)
	assert_float(camera.fov).is_equal_approx(_tuning.fov, 0.1)


func test_a_burst_with_short_gaps_keeps_the_zoom_in() -> void:
	# Taps closer than the delay never let the zoom go (the slowest weapon fires every 0.9 s).
	for i in 3:
		_runner.simulate_action_press("fire")
		await _ticks(3)
		_runner.simulate_action_release("fire")
		await _seconds(_tuning.hip_fire_zoom_delay - 0.1)
	assert_float(_rig.zoom_amount()).is_greater(_tuning.hip_fire_zoom * 0.9)


func test_aiming_still_uses_the_full_aim_zoom() -> void:
	var camera := _rig.camera()
	_runner.simulate_action_press("aim")
	_runner.simulate_action_press("fire")
	await _seconds(1.2)
	assert_float(_rig.aim_amount()).is_equal_approx(1.0, 0.01)
	assert_float(_rig.zoom_amount()).is_equal_approx(1.0, 0.01)
	assert_float(camera.fov).is_equal_approx(_tuning.fov_aim, 0.1)
	assert_float(_rig.hip_amount()).is_less(0.01)
	assert_bool(_rig.is_aim_zoomed()).is_true()
	_runner.simulate_action_release("aim")
	_runner.simulate_action_release("fire")
	await _seconds(2.0)
	assert_float(_rig.zoom_amount()).is_equal_approx(0.0, 0.01)


func test_the_hip_fire_zoom_does_not_slow_the_look() -> void:
	# The aim steadies the look; a burst from the hip does not.
	var before := _rig.yaw
	_rig.look_mouse(Vector2(100.0, 0.0))
	var plain := before - _rig.yaw
	_rig.yaw = before
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	before = _rig.yaw
	_rig.look_mouse(Vector2(100.0, 0.0))
	assert_float(before - _rig.yaw).is_equal_approx(plain, 0.0001)


func test_the_zoom_never_moves_the_aim_ray() -> void:
	# The shot follows the camera ray: its direction is the view's yaw and pitch, zoomed or not.
	_rig.yaw = 0.7
	_rig.pitch = 0.1
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	var forward := -_rig.camera().global_transform.basis.z
	var expected := Basis.from_euler(Vector3(_rig.pitch, _rig.yaw, 0.0)) * Vector3.FORWARD
	assert_float(forward.angle_to(expected)).is_less(0.001)


func test_the_command_carries_the_trigger() -> void:
	var command := PlayerCommand.new()
	command.fire = true
	assert_bool(PlayerCommand.from_bytes(command.to_bytes()).fire).is_true()
	assert_bool(PlayerCommand.from_dict({}).fire).is_false()


func test_the_same_commands_give_the_same_turn_and_trigger_age() -> void:
	# Hip fire is part of the simulated state, so a replay agrees with the server.
	_player.local_input = false
	var start := _player.state.duplicate_state()
	var commands: Array[PlayerCommand] = []
	for i in 90:
		var command := PlayerCommand.new()
		command.yaw = 0.9
		command.move = Vector2(1.0, 0.0)
		command.fire = i > 10 and i < 50
		commands.append(command)
	for command in commands:
		_player.submit_command(command)
		await get_tree().physics_frame
	var first := _player.state.duplicate_state()
	assert_float(first.fire_age).is_greater(0.5)
	_player.state.copy_from(start)
	_player.global_position = start.position
	for command in commands:
		_player.submit_command(command)
		await get_tree().physics_frame
	assert_float(_player.state.facing).is_equal_approx(first.facing, 0.0001)
	assert_float(_player.state.fire_age).is_equal_approx(first.fire_age, 0.0001)
