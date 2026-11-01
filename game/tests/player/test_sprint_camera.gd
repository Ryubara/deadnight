# The sprint pull-back of the shoulder camera, and that it follows a sprint in every direction
# (docs/research/character-controller.md). Stepped by hand with fixed time steps, like
# test_shoulder_camera.gd.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(4.0, 0.05, 10.0)

var _player: Player
var _rig: ThirdPersonCamera
var _tuning: PlayerTuning


func before_test() -> void:
	var runner := scene_runner(TEST_ROOM)
	_player = runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_player.set_physics_process(false)
	_player.set_process(false)
	_rig = _player.camera_rig
	_rig.set_process(false)
	_tuning = _player.tuning
	_player.teleport(START)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _render(seconds: float) -> void:
	for i in roundi(seconds / TICK):
		_rig.step(TICK, 1.0)


func test_the_sprint_pull_back_is_half_as_far_and_one_and_a_half_times_as_fast() -> void:
	# Was 0.3 m out at 9 rad/s (95 percent in 0.53 s); now 0.15 m at 13.5 rad/s (0.35 s).
	assert_float(_tuning.sprint_arm_extra).is_equal_approx(0.15, 0.001)
	assert_float(_tuning.sprint_frequency).is_equal_approx(13.5, 0.001)
	var rest := _rig.lens_distance()
	_rig.sprinting = true
	_render(0.2)
	assert_float(_rig.sprint_amount()).is_less(0.95)
	_render(0.17)  # 0.37 s in: past 4.75 / 13.5 = 0.352 s
	assert_float(_rig.sprint_amount()).is_greater(0.95)
	assert_float(_rig.lens_distance() - rest).is_equal_approx(_tuning.sprint_arm_extra, 0.02)
	# The old spring (9 rad/s) would still be short of 95 percent at that moment.
	var old := DampedSpring.new()
	for i in roundi(0.37 / TICK):
		old.step(1.0, 9.0, TICK)
	assert_float(old.value).is_less(0.95)


func test_the_camera_pulls_back_when_sprinting_in_every_direction() -> void:
	for i in 8:
		var angle := TAU * i / 8.0
		var move := Vector2(sin(angle), -cos(angle)).snappedf(0.0001)
		_player.teleport(START)
		await get_tree().physics_frame
		var rest := _rig.lens_distance()
		for tick in 60:
			var command := PlayerCommand.new()
			command.move = move
			command.sprint = true
			_player.tick(command)
			_rig.step(TICK, 1.0)
		var label := "direction %s" % move
		assert_bool(_player.camera_rig.sprinting).override_failure_message(label).is_true()
		assert_float(_rig.sprint_amount()).override_failure_message(label).is_greater(0.95)
		assert_float(_player.ground_speed()).override_failure_message(label).is_greater(
			_tuning.run_speed + 1.0
		)
		assert_float(_rig.lens_distance()).override_failure_message(label).is_greater(rest)
