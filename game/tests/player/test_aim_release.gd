# Aim, shoot, let go of the aim (#428), and the zoom for the aim only (#464): a shot never holds the
# camera. Aim, shoot, release and hip fire, aim, release both let the view go the tick the button
# is let go and are back at 60 degrees within the aim's own blend time, with no extra hold. The
# hip-fire hold (`fire_age`, restarted only by a trigger pull made without the aim button) is the
# body's alone. Stepped by hand with fixed ticks.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## The aim's own blend time: back at the hip view within this after the button is let go.
const AIM_BLEND_TIME := 0.5

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _tuning: PlayerTuning


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	# The suite ticks the player by hand (PlayerHandStep), not at the physics clock's pace.
	_player.set_physics_process(false)
	_rig = _player.camera_rig
	_tuning = _player.tuning
	_rig.set_process(false)
	_player.teleport(START)
	# The physics server learns of the room's static bodies on its first step: take that one by
	# the clock, then tick by hand.
	await get_tree().physics_frame
	await _ticks(20)


func after_test() -> void:
	Input.action_release("fire")
	Input.action_release("aim")


func _ticks(count: int) -> void:
	for i in count:
		PlayerHandStep.tick(_player)
		_rig.step(TICK, 1.0)
	await get_tree().process_frame


func _seconds(seconds: float) -> void:
	await _ticks(roundi(seconds / TICK))


## The aim weight every tick for `count` ticks.
func _weights(count: int) -> Array[float]:
	var found: Array[float] = []
	for i in count:
		await _ticks(1)
		found.append(_rig.aim_amount())
	return found


## Ticks until the weight is under `limit` (-1 if it never is).
func _first_below(weights: Array[float], limit: float) -> int:
	for i in weights.size():
		if weights[i] < limit:
			return i
	return -1


## Aims for a second, taps the trigger once while aiming, and lets go of the aim after `gap`
## seconds; returns the weights from the release on, 120 ticks.
func _aim_shoot_release(gap: float) -> Array[float]:
	_runner.simulate_action_press("aim")
	await _seconds(1.0)
	_runner.simulate_action_press("fire")
	await _ticks(3)
	_runner.simulate_action_release("fire")
	await _seconds(gap)
	_runner.simulate_action_release("aim")
	return await _weights(120)


func test_a_shot_while_aiming_leaves_no_hold_after_the_release() -> void:
	var after_shot := await _aim_shoot_release(0.1)
	var plain_aim: Array[float] = []
	await _seconds(1.5)
	_runner.simulate_action_press("aim")
	await _seconds(1.0)
	_runner.simulate_action_release("aim")
	plain_aim = await _weights(120)
	# The weight starts falling on the release (inside a tick or two), and follows the release of
	# an aim nobody shot from.
	assert_int(_first_below(after_shot, 0.999)).is_less(3)
	assert_int(_first_below(plain_aim, 0.999)).is_less(3)
	for i in 120:
		assert_float(after_shot[i]).override_failure_message("tick %d" % i).is_equal_approx(
			plain_aim[i], 0.03
		)
	assert_float(after_shot[59]).is_less(0.01)
	assert_float(after_shot[-1]).is_equal_approx(0.0, 0.001)


func test_the_release_is_immediate_however_late_the_shot_was() -> void:
	# A shot the tick before the release: still no hold.
	_runner.simulate_action_press("aim")
	await _seconds(1.0)
	_runner.simulate_action_press("fire")
	await _ticks(2)
	_runner.simulate_action_release("fire")
	_runner.simulate_action_release("aim")
	var weights := await _weights(60)
	assert_int(_first_below(weights, 0.95)).is_less(10)
	assert_float(weights[40]).is_less(0.02)
	assert_float(_player.state.fire_age).is_greater(0.5)


## The field of view every tick for `count` ticks.
func _fovs(count: int) -> Array[float]:
	var found: Array[float] = []
	for i in count:
		await _ticks(1)
		found.append(_rig.camera().fov)
	return found


func _assert_hip_view(fovs: Array[float], label: String) -> void:
	for i in fovs.size():
		(
			assert_float(fovs[i])
			. override_failure_message("%s: tick %d fov %.3f" % [label, i, fovs[i]])
			. is_equal_approx(_tuning.fov, 0.0001)
		)


func test_aim_shoot_release_is_back_at_60_within_the_aim_blend_time() -> void:
	_runner.simulate_action_press("aim")
	await _seconds(1.0)
	assert_float(_rig.camera().fov).is_equal_approx(_tuning.fov_aim, 0.05)
	_runner.simulate_action_press("fire")
	await _ticks(3)
	_runner.simulate_action_release("fire")
	await _seconds(0.1)
	_runner.simulate_action_release("aim")
	var fovs := await _fovs(roundi(AIM_BLEND_TIME / TICK))
	# No hold: it starts to go the tick the button is let go, and is at 60 inside the blend time.
	assert_float(fovs[2]).is_greater(_tuning.fov_aim + 0.1)
	assert_float(fovs[2]).is_less(_tuning.fov - 1.0)
	assert_float(fovs[-1]).is_equal_approx(_tuning.fov, 0.1)
	var plain := await _plain_release_fovs(fovs.size())
	for i in fovs.size():
		assert_float(fovs[i]).override_failure_message("tick %d" % i).is_equal_approx(plain[i], 0.3)


## The fovs after a release of an aim nobody shot from: the reference curve.
func _plain_release_fovs(count: int) -> Array[float]:
	await _seconds(1.5)
	_runner.simulate_action_press("aim")
	await _seconds(1.0)
	_runner.simulate_action_release("aim")
	return await _fovs(count)


func test_hip_fire_aim_release_is_back_at_60_within_the_aim_blend_time() -> void:
	# A shot from the hip leaves no zoom; aiming inside its body hold zooms for the aim; letting go
	# of the aim returns to 60 at once, with nothing held over from the hip shot.
	_runner.simulate_action_press("fire")
	var before_aim := await _fovs(roundi(0.5 / TICK))
	_assert_hip_view(before_aim, "hip fire")
	_runner.simulate_action_release("fire")
	await _seconds(0.2)
	assert_bool(_player.state.holds_aim(_tuning.hip_fire_hold)).is_true()
	_runner.simulate_action_press("aim")
	await _seconds(1.0)
	assert_float(_rig.camera().fov).is_equal_approx(_tuning.fov_aim, 0.05)
	_runner.simulate_action_release("aim")
	var fovs := await _fovs(roundi(AIM_BLEND_TIME / TICK))
	assert_float(fovs[2]).is_greater(_tuning.fov_aim + 0.1)
	assert_float(fovs[-1]).is_equal_approx(_tuning.fov, 0.1)


func test_hip_fire_alone_never_zooms_and_holds_only_the_body() -> void:
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	_runner.simulate_action_release("fire")
	var fovs := await _fovs(120)
	_assert_hip_view(fovs, "after the trigger")
	assert_float(_rig.aim_amount()).is_equal_approx(0.0, 0.0001)
	# The body's hold is what stayed: it ended `hip_fire_hold` after the last shot.
	assert_float(_player.state.fire_age).is_greater(_tuning.hip_fire_hold)


func test_letting_go_of_the_aim_with_the_trigger_held_lets_the_zoom_go_at_once() -> void:
	_runner.simulate_action_press("aim")
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	assert_float(_rig.camera().fov).is_equal_approx(_tuning.fov_aim, 0.05)
	_runner.simulate_action_release("aim")
	var fovs := await _fovs(roundi(AIM_BLEND_TIME / TICK))
	assert_float(fovs[-1]).is_equal_approx(_tuning.fov, 0.1)
	assert_float(_rig.aim_amount()).is_less(0.01)
	# The trigger is still down: the body keeps facing the view (the hip-fire turn), the view stays.
	assert_bool(_player.is_aiming()).is_false()
	assert_bool(_player.state.holds_aim(_tuning.hip_fire_hold)).is_true()
	await _seconds(1.0)
	assert_float(_rig.camera().fov).is_equal_approx(_tuning.fov, 0.0001)
