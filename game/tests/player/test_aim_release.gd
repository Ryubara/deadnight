# Aim, shoot, let go of the aim (#428): a shot fired while aiming starts no hip-fire hold, so the
# aim weight falls the tick the button is let go, along the aim's own release. The rule:
# `holds_aim = aiming or fire_age < hip_fire_hold`, and `fire_age` restarts only for a trigger
# pull made without the aim button. Stepped by hand with fixed ticks.
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


func test_hip_fire_alone_still_holds_for_the_hold() -> void:
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	_runner.simulate_action_release("fire")
	var weights := await _weights(120)
	var first := _first_below(weights, 0.95)
	assert_float(first * TICK).is_equal_approx(_tuning.hip_fire_hold, 0.1)


func test_an_aim_inside_a_hip_hold_gives_only_what_hip_fire_gives() -> void:
	# Hip shot, aim during its hold, let go of the aim inside the hold: the hold the hip shot
	# started runs out as it would have (no restart from the aim, no second hold).
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	_runner.simulate_action_release("fire")
	await _seconds(0.2)
	_runner.simulate_action_press("aim")
	await _seconds(0.2)
	_runner.simulate_action_release("aim")
	# 0.4 s into the hold: the rest of it runs out as it would have, 0.4 s later.
	var weights := await _weights(120)
	var falls_in := _first_below(weights, 0.95) * TICK
	assert_float(falls_in).is_equal_approx(_tuning.hip_fire_hold - 0.4, 0.1)
	# Aimed late in the hold and let go after it ran out: immediate.
	await _seconds(2.0)
	_runner.simulate_action_press("fire")
	await _ticks(3)
	_runner.simulate_action_release("fire")
	await _seconds(_tuning.hip_fire_hold - 0.2)
	_runner.simulate_action_press("aim")
	await _seconds(0.5)
	_runner.simulate_action_release("aim")
	var late := await _weights(60)
	assert_int(_first_below(late, 0.95)).is_less(10)


func test_letting_go_of_the_aim_with_the_trigger_held_is_hip_fire() -> void:
	_runner.simulate_action_press("aim")
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	_runner.simulate_action_release("aim")
	await _seconds(0.5)
	assert_float(_rig.aim_amount()).is_greater(0.99)
	_runner.simulate_action_release("fire")
	await _seconds(_tuning.hip_fire_hold - 0.2)
	assert_float(_rig.aim_amount()).is_greater(0.98)
	await _seconds(1.0)
	assert_float(_rig.aim_amount()).is_less(0.01)
