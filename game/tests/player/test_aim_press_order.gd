# Every order the aim button and the trigger can be pressed in, with gaps of 0, 50 and 100 ms
# (#478: "right click and immediately tap left click maybe 50 ms after: the aim is held for a second
# and then unzooms, even when not aiming anymore"). The rule is the button's, never the aim weight:
# a shot made while the aim button is down is an aimed shot and leaves no hip-fire hold behind; the
# camera zooms for the button only (#464), so in every order it is back at 60 degrees within the
# aim's own blend time of the button being let go, and no shot ever zooms the view. Stepped by hand
# with fixed ticks, with the real input actions.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## The aim's own blend time: back at the hip view within this after the button is let go.
const AIM_BLEND_TIME := 0.5
## A tap of the trigger, as a finger makes it.
const TAP := 0.06
const GAPS := [0.0, 0.05, 0.1]

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


func _tap() -> void:
	_runner.simulate_action_press("fire")
	await _seconds(TAP)
	_runner.simulate_action_release("fire")


## The field of view of every tick for `seconds`.
func _fovs(seconds: float) -> Array[float]:
	var found: Array[float] = []
	for i in roundi(seconds / TICK):
		await _ticks(1)
		found.append(_rig.camera().fov)
	return found


func _assert_back_at_the_hip(fovs: Array[float], label: String) -> void:
	var needed := roundi(AIM_BLEND_TIME / TICK)
	(
		assert_float(fovs[needed - 1])
		. override_failure_message("%s: fov %.2f after the blend time" % [label, fovs[needed - 1]])
		. is_equal_approx(_tuning.fov, 0.1)
	)
	assert_float(fovs[-1]).is_equal_approx(_tuning.fov, 0.0001)
	assert_float(_rig.aim_amount()).is_less(0.001)


func test_aim_then_tap_then_release_aim_lets_the_zoom_go_at_once() -> void:
	for gap: float in GAPS:
		_runner.simulate_action_press("aim")
		await _seconds(gap)
		await _tap()
		await _seconds(0.3)
		(
			assert_float(_rig.aim_amount())
			. override_failure_message("gap %.2f: not zoomed" % gap)
			. is_greater(0.9)
		)
		# An aimed shot starts no hold: the button's release is the end of everything.
		assert_float(_player.state.fire_age).is_greater(_tuning.hip_fire_hold)
		_runner.simulate_action_release("aim")
		await _ticks(1)
		(
			assert_bool(_player.state.holds_aim(_tuning.hip_fire_hold))
			. override_failure_message("gap %.2f: a hold outlived the button" % gap)
			. is_false()
		)
		var fovs := await _fovs(1.0)
		_assert_back_at_the_hip(fovs, "aim, tap, release (gap %.2f)" % gap)
		await _seconds(1.0)


func test_a_trigger_pressed_with_the_aim_in_the_same_tick_is_an_aimed_shot() -> void:
	# Gap 0: both buttons land in one physics tick, in either order of the two calls.
	for aim_first in [true, false]:
		if aim_first:
			_runner.simulate_action_press("aim")
			_runner.simulate_action_press("fire")
		else:
			_runner.simulate_action_press("fire")
			_runner.simulate_action_press("aim")
		await _seconds(TAP)
		_runner.simulate_action_release("fire")
		await _seconds(0.3)
		assert_float(_player.state.fire_age).is_greater(_tuning.hip_fire_hold)
		_runner.simulate_action_release("aim")
		var fovs := await _fovs(1.0)
		_assert_back_at_the_hip(fovs, "same tick, aim first: %s" % aim_first)
		await _seconds(1.0)


func test_tap_then_aim_then_release_aim_lets_the_zoom_go_at_once() -> void:
	# A shot from the hip, then the aim button inside its hold: the button zooms from 60 and its
	# release is back at 60 within the blend time, whatever the hip shot's hold has left (the body's).
	for gap: float in GAPS:
		await _tap()
		await _seconds(gap)
		_runner.simulate_action_press("aim")
		await _seconds(0.5)
		(
			assert_float(_rig.aim_amount())
			. override_failure_message("gap %.2f: not zoomed" % gap)
			. is_greater(0.9)
		)
		_runner.simulate_action_release("aim")
		var fovs := await _fovs(1.0)
		_assert_back_at_the_hip(fovs, "tap, aim, release (gap %.2f)" % gap)
		await _seconds(1.0)


func test_aim_then_release_then_tap_never_zooms() -> void:
	for gap: float in GAPS:
		_runner.simulate_action_press("aim")
		await _seconds(0.5)
		_runner.simulate_action_release("aim")
		await _seconds(gap)
		await _tap()
		var fovs := await _fovs(0.5)
		# The release's own ease may still be running at gap 0; the tap adds nothing to it.
		for i in fovs.size():
			assert_float(fovs[i]).is_less_equal(_tuning.fov + 0.0001)
		assert_float(fovs[-1]).is_equal_approx(_tuning.fov, 0.01)
		await _seconds(1.0)


func test_a_tap_in_the_first_frames_of_the_aim_press_is_not_a_hip_shot() -> void:
	# The aim weight is still near zero 1 to 3 ticks after the press: a rule that read it would
	# take the shot for a hip shot and hold the pose for 0.8 s after the release.
	for ticks in [1, 2, 3]:
		_runner.simulate_action_press("aim")
		await _ticks(ticks)
		assert_float(_rig.aim_amount()).is_less(0.5)
		await _tap()
		await _seconds(0.3)
		_runner.simulate_action_release("aim")
		await _ticks(1)
		(
			assert_float(_player.state.fire_age)
			. override_failure_message("%d ticks after the press: a hip hold started" % ticks)
			. is_greater(_tuning.hip_fire_hold)
		)
		assert_bool(_player.state.holds_aim(_tuning.hip_fire_hold)).is_false()
		await _seconds(1.0)
