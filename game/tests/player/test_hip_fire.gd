# Firing without aiming: the body turns to the view and holds it for a moment, and the camera does
# nothing at all (#464: the zoom is for the aim button only). Stepped by hand with fixed ticks (no
# wall time), like the shoulder camera suite. The weapon's pose: test_aim_weight.gd.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## The aim's own blend time: a view that was zoomed is back at the hip within this after the aim
## button is let go (the spring settles in about 0.3 s).
const AIM_BLEND_TIME := 0.5

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


func test_without_firing_the_body_does_not_follow_the_view() -> void:
	_rig.yaw = 1.2
	await _seconds(0.5)
	assert_float(_player.rotation.y).is_equal_approx(0.0, 0.01)
	assert_float(_rig.aim_amount()).is_equal_approx(0.0, 0.001)


func test_firing_turns_the_body_to_the_view_within_a_few_ticks() -> void:
	_rig.yaw = 1.2
	_runner.simulate_action_press("fire")
	# 1.2 radians at the hip-fire turn speed: a handful of ticks, and not a snap.
	await _ticks(1)
	assert_float(_player.rotation.y).is_between(0.05, 1.19)
	var ticks_needed := ceili(1.2 / (_tuning.aim_turn_speed * TICK)) + 2
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
	_runner.simulate_action_release("move_back")


## What the player sees of the camera: the field of view and where the lens is.
func _framing() -> Dictionary:
	var camera := _rig.camera()
	return {
		"fov": camera.fov,
		"lens": camera.global_position,
		"distance": _rig.lens_distance(),
		"weight": _rig.aim_amount(),
	}


func _assert_framing_is(base: Dictionary, label: String) -> void:
	var now := _framing()
	(
		assert_float(now["fov"])
		. override_failure_message("%s: fov %.3f" % [label, now["fov"]])
		. is_equal_approx(base["fov"], 0.0001)
	)
	assert_vector(now["lens"]).override_failure_message(label + ": lens").is_equal_approx(
		base["lens"], Vector3.ONE * 0.0001
	)
	assert_float(now["distance"]).override_failure_message(label + ": distance").is_equal_approx(
		base["distance"], 0.0001
	)
	assert_float(now["weight"]).override_failure_message(label + ": weight").is_equal_approx(
		0.0, 0.0001
	)


func test_hip_fire_never_moves_the_fov_or_the_framing() -> void:
	# Held for a second and a half, then let go and watched through the hold and well past it: every
	# tick has the same field of view (60) and the same lens as before the first shot (the pivot
	# settles onto the floor for a second after the teleport: that is not the aim).
	await _seconds(1.5)
	var base := _framing()
	assert_float(base["fov"]).is_equal_approx(_tuning.fov, 0.0001)
	_runner.simulate_action_press("fire")
	for i in roundi(1.5 / TICK):
		await _ticks(1)
		_assert_framing_is(base, "firing, tick %d" % i)
	_runner.simulate_action_release("fire")
	for i in roundi((_tuning.hip_fire_hold + 1.5) / TICK):
		await _ticks(1)
		_assert_framing_is(base, "after the trigger, tick %d" % i)
	assert_bool(_rig.is_aim_zoomed()).is_false()


func test_hip_fire_does_not_move_the_framing_while_moving_or_sprinting() -> void:
	# The sprint pull-back and sway used to ease out for a shot from the hip: that was a framing
	# change from hip fire too. Sprint, then fire: the sprint's field of view stays.
	_runner.simulate_action_press("sprint")
	_runner.simulate_action_press("move_forward")
	await _seconds(1.5)
	var base := _framing()
	assert_float(base["fov"]).is_greater(_tuning.fov + 1.0)
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	_runner.simulate_action_release("fire")
	await _seconds(_tuning.hip_fire_hold + 0.5)
	assert_float(_rig.camera().fov).is_equal_approx(base["fov"], 0.2)
	assert_float(_rig.aim_amount()).is_equal_approx(0.0, 0.0001)
	_runner.simulate_action_release("sprint")
	_runner.simulate_action_release("move_forward")


func test_the_body_keeps_facing_the_view_for_the_hold_with_no_zoom() -> void:
	# What stayed from the hip-fire hold: the body turns to the view and keeps it for `hip_fire_hold`.
	_rig.yaw = 1.2
	_runner.simulate_action_press("fire")
	await _seconds(0.5)
	_runner.simulate_action_release("fire")
	assert_bool(_player.state.holds_aim(_tuning.hip_fire_hold)).is_true()
	await _seconds(_tuning.hip_fire_hold - 0.2)
	assert_bool(_player.state.holds_aim(_tuning.hip_fire_hold)).is_true()
	assert_float(_player.rotation.y).is_equal_approx(1.2, 0.01)
	assert_float(_rig.aim_amount()).is_equal_approx(0.0, 0.0001)
	await _seconds(0.4)
	assert_bool(_player.state.holds_aim(_tuning.hip_fire_hold)).is_false()


func test_a_burst_with_short_gaps_leaves_the_framing_alone() -> void:
	# Taps closer than the hold (the slowest weapon fires every 0.9 s): the view never moves.
	await _seconds(1.5)
	var base := _framing()
	for i in 3:
		_runner.simulate_action_press("fire")
		await _ticks(3)
		_runner.simulate_action_release("fire")
		for j in roundi((_tuning.hip_fire_hold - 0.1) / TICK):
			await _ticks(1)
			_assert_framing_is(base, "burst %d, tick %d" % [i, j])


func test_aiming_and_firing_together_zoom_for_the_aim_and_release_with_it() -> void:
	var camera := _rig.camera()
	_runner.simulate_action_press("aim")
	_runner.simulate_action_press("fire")
	await _seconds(1.2)
	assert_float(_rig.aim_amount()).is_equal_approx(1.0, 0.01)
	assert_float(camera.fov).is_equal_approx(_tuning.fov_aim, 0.1)
	assert_bool(_rig.is_aim_zoomed()).is_true()
	_runner.simulate_action_release("aim")
	_runner.simulate_action_release("fire")
	await _seconds(AIM_BLEND_TIME)
	assert_float(camera.fov).is_equal_approx(_tuning.fov, 0.1)
	assert_float(_rig.aim_amount()).is_equal_approx(0.0, 0.01)


func test_a_burst_from_the_hip_does_not_slow_the_look() -> void:
	# The aim button steadies the look; a burst from the hip does not.
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


func test_firing_while_backing_away_keeps_the_run_speed() -> void:
	# The body faces the view while firing, so backing away is a turn of 180 degrees from its
	# heading: the pivot rules (a slow walk until the body faces the way) must not apply to it.
	_runner.simulate_action_press("fire")
	_runner.simulate_action_press("move_back")
	await _seconds(1.0)
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	assert_float(speed).is_greater(_tuning.run_speed * 0.9)
	_runner.simulate_action_release("move_back")
