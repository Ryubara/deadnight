# The weapon's pose weight (#300, #464): the aim button and a shot from the hip both raise the
# weapon and turn the body, and the pose eases in and out at the same speed and never jumps. Only
# the aim button moves the camera (the zoom is for the aim, #464). Stepped by hand with fixed ticks
# (no wall time).
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## The view is turned this far from the body before the aim is held, in radians (75 degrees: the
## body is side-on, which was the worst case of the old pose).
const LOOK_AWAY := 1.31
## The most the grip may move in one tick, in metres, and the barrel turn, in degrees, while the
## pose eases between the hip and the aim (on main the aim button moved it 0.47 m and 78 degrees
## in one tick, a shot from the hip 0.16 m and 21 degrees).
const MAX_HAND_STEP := 0.15
const MAX_BARREL_TURN_DEG := 25.0
## Pose of the held aim, hip fire against the aim button.
const PLACE_TOLERANCE := 0.01
const POSE_TOLERANCE := 0.01
const WEIGHT_TOLERANCE := 0.03

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _tuning: PlayerTuning


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_rig = _player.camera_rig
	_tuning = _player.tuning
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.teleport(START)
	# The starting pistol has no shouldered hold: the rifle shows the pose.
	_animation.equip(&"rifle")
	await _ticks(60)


func after_test() -> void:
	Input.action_release("fire")
	Input.action_release("aim")


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	# The skeleton's modifiers run on the idle frame.
	await get_tree().process_frame


func _seconds(seconds: float) -> void:
	await _ticks(roundi(seconds / TICK))


## The weapon's place and the barrel's direction, without the recoil kick (one frame by design).
func _pose() -> Dictionary:
	var hands := _animation.hands()
	var kick := hands.recoil
	hands.recoil = 0.0
	var target := hands.weapon_target()
	hands.recoil = kick
	return {"grip": target.origin, "barrel": -target.basis.x}


## What the player sees now: the lens, the field of view, the weapon, relative to the body.
func _view() -> Dictionary:
	var camera := _rig.camera()
	var pose := _pose()
	var body := _player.global_position
	return {
		"weight": _animation.aim_weight(),
		"camera_weight": _rig.aim_amount(),
		"fov": camera.fov,
		"lens_distance": _rig.lens_distance(),
		"lens": camera.global_position - body,
		"grip": pose["grip"] - body,
		"barrel": pose["barrel"],
	}


func _turn_view_away() -> void:
	_rig.yaw = _player.rotation.y + LOOK_AWAY


## Presses `action`, samples a view every tick for `seconds`, releases it and returns the samples.
func _sample_view_after(action: String, seconds: float) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	_runner.simulate_action_press(action)
	for i in roundi(seconds / TICK):
		await _ticks(1)
		samples.append(_view())
	return samples


func test_hip_fire_raises_the_weapon_like_the_aim_and_leaves_the_camera_alone() -> void:
	_turn_view_away()
	await _ticks(2)
	var rest := _view()
	var aimed := await _sample_view_after("aim", 1.5)
	_runner.simulate_action_release("aim")
	await _seconds(_tuning.hip_fire_hold + 1.5)
	assert_float(_animation.aim_weight()).is_equal_approx(0.0, 0.01)
	var fired := await _sample_view_after("fire", 1.5)
	var want: Dictionary = aimed.back()
	var got: Dictionary = fired.back()
	# The weapon and the body: the same pose as the aim.
	assert_float(got["weight"]).is_equal_approx(want["weight"], 0.005)
	assert_vector(got["grip"]).override_failure_message("grip").is_equal_approx(
		want["grip"], Vector3.ONE * POSE_TOLERANCE
	)
	assert_vector(got["barrel"]).override_failure_message("barrel").is_equal_approx(
		want["barrel"], Vector3.ONE * POSE_TOLERANCE
	)
	# The camera: where it was at the hip, tick after tick; the aim's zoom was another.
	assert_float(want["fov"]).is_equal_approx(_tuning.fov_aim, 0.05)
	for view: Dictionary in fired:
		assert_float(view["camera_weight"]).is_equal_approx(0.0, 0.0001)
		assert_float(view["fov"]).is_equal_approx(_tuning.fov, 0.0001)
		assert_float(view["lens_distance"]).is_equal_approx(rest["lens_distance"], 0.0001)


func test_the_weapon_pose_eases_in_without_a_jump_for_hip_fire_and_for_aim() -> void:
	for action in ["fire", "aim"]:
		_runner.simulate_action_release("fire")
		_runner.simulate_action_release("aim")
		await _seconds(_tuning.hip_fire_hold + 1.5)
		_turn_view_away()
		await _ticks(2)
		var before := _view()
		var samples := await _sample_view_after(action, 1.5)
		samples.push_front(before)
		_assert_smooth(samples, action + " in")
		samples = await _sample_after_release(action, 1.5)
		_assert_smooth(samples, action + " out")


## Releases `action` and samples a view every tick for `seconds`.
func _sample_after_release(action: String, seconds: float) -> Array[Dictionary]:
	var samples: Array[Dictionary] = [_view()]
	_runner.simulate_action_release(action)
	for i in roundi(seconds / TICK):
		await _ticks(1)
		samples.append(_view())
	return samples


func _assert_smooth(samples: Array[Dictionary], label: String) -> void:
	var hand := 0.0
	var turn := 0.0
	for i in range(1, samples.size()):
		hand = maxf(hand, (samples[i]["grip"] as Vector3).distance_to(samples[i - 1]["grip"]))
		turn = maxf(
			turn, rad_to_deg((samples[i]["barrel"] as Vector3).angle_to(samples[i - 1]["barrel"]))
		)
	assert_float(hand).override_failure_message("%s: hand step %.3f m" % [label, hand]).is_less(
		MAX_HAND_STEP
	)
	assert_float(turn).override_failure_message("%s: barrel turn %.1f deg" % [label, turn]).is_less(
		MAX_BARREL_TURN_DEG
	)


func test_the_pose_lets_go_after_the_last_shot_as_it_does_after_the_aim_button() -> void:
	# Release the aim: the weight falls at once. Release the trigger: it falls after the hold, along
	# the same curve.
	var aim_out: Array[float] = []
	_runner.simulate_action_press("aim")
	await _seconds(1.5)
	_runner.simulate_action_release("aim")
	for i in 90:
		await _ticks(1)
		aim_out.append(_animation.aim_weight())
	await _seconds(1.0)
	var fire_out: Array[float] = []
	_runner.simulate_action_press("fire")
	await _seconds(1.5)
	_runner.simulate_action_release("fire")
	for i in 90 + ceili(_tuning.hip_fire_hold / TICK) + 1:
		await _ticks(1)
		fire_out.append(_animation.aim_weight())
	# Where the weight first drops below 95 percent: the same curve, `hold` later.
	var aim_at := _first_below(aim_out, 0.95)
	var fire_at := _first_below(fire_out, 0.95)
	assert_int(aim_at).is_greater(-1)
	assert_int(fire_at).is_greater(-1)
	var delay := (fire_at - aim_at) * TICK
	assert_float(delay).override_failure_message("delay %.3f s" % delay).is_equal_approx(
		_tuning.hip_fire_hold, 2.5 * TICK
	)
	var offset := fire_at - aim_at
	for i in 60:
		assert_float(fire_out[i + offset]).is_equal_approx(aim_out[i], WEIGHT_TOLERANCE)


func _first_below(weights: Array[float], limit: float) -> int:
	for i in weights.size():
		if weights[i] < limit:
			return i
	return -1


func test_pressing_the_aim_button_during_a_burst_does_not_slow_the_pose_and_zooms_the_view(
) -> void:
	_turn_view_away()
	_runner.simulate_action_press("fire")
	await _seconds(0.1)
	var weight := _animation.aim_weight()
	assert_float(weight).is_between(0.05, 0.95)
	assert_float(_rig.camera().fov).is_equal_approx(_tuning.fov, 0.0001)
	_runner.simulate_action_press("aim")
	for i in 20:
		await _ticks(1)
		assert_float(_animation.aim_weight()).is_greater_equal(weight - 0.0001)
		weight = _animation.aim_weight()
	assert_float(weight).is_equal_approx(1.0, 0.01)
	# The button's zoom starts at the press, from 60, and reaches 40.
	assert_float(_rig.camera().fov).is_between(_tuning.fov_aim, _tuning.fov)
	await _seconds(0.5)
	assert_float(_rig.camera().fov).is_equal_approx(_tuning.fov_aim, 0.05)
	# The trigger lets go; the button keeps the aim: pose and view both stay.
	_runner.simulate_action_release("fire")
	await _seconds(_tuning.hip_fire_hold + 0.5)
	assert_float(_animation.aim_weight()).is_equal_approx(1.0, 0.001)
	assert_float(_rig.camera().fov).is_equal_approx(_tuning.fov_aim, 0.05)


func test_the_look_steadiness_follows_only_the_aim_button() -> void:
	_runner.simulate_action_press("fire")
	await _seconds(1.0)
	assert_float(_animation.aim_weight()).is_equal_approx(1.0, 0.01)
	assert_float(_rig.aim_amount()).is_equal_approx(0.0, 0.001)
	assert_float(_rig.steady_amount()).is_equal_approx(0.0, 0.001)
	_runner.simulate_action_press("aim")
	await _seconds(1.0)
	assert_float(_rig.steady_amount()).is_equal_approx(1.0, 0.01)
