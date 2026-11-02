# The touch controls driving the real player: a drag on the right turns the camera, the stick
# walks the player. Its own suite because the scene runner changes how input is delivered.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"

var _fixture: TouchFixture


func before_test() -> void:
	# A screen an earlier suite left on the router (a main menu, say) takes the mouse motion the
	# touch look sends before the player's `_unhandled_input` sees it, and the drag turns nothing.
	await RouterFixture.clear(get_tree())
	_fixture = TouchFixture.make(self)


func after_test() -> void:
	_fixture.free_all()


func test_a_drag_turns_the_player_through_the_real_input_path() -> void:
	var runner := scene_runner("res://world/test_room.tscn")
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var rig := player.camera_rig
	var yaw := rig.yaw
	await _fixture.touch(0, Vector2(1700.0, 300.0))
	await _fixture.drag(0, Vector2(1800.0, 300.0), Vector2(100.0, 0.0))
	await _fixture.lift(0)
	# Dragging right turns the view right (mouse convention): the yaw falls. A drag of 100 units
	# on a 1080 unit tall canvas turns 100 / 1080 of the full-height swipe, at sensitivity 1.
	var turned := angle_difference(yaw, rig.yaw)
	assert_float(turned).is_equal_approx(-TouchLook.RADIANS_PER_HEIGHT * 100.0 / 1080.0, 0.02)


func test_a_100_unit_drag_turns_about_8_degrees_in_small_steps_at_the_default_sensitivity() -> void:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var rig := player.camera_rig
	await _fixture.touch(0, Vector2(1700.0, 300.0))
	var biggest := 0.0
	var start := rig.yaw
	for step in 10:
		var before := rig.yaw
		await _fixture.drag(0, Vector2(1700.0 + 10.0 * (step + 1), 300.0), Vector2(10.0, 0.0))
		biggest = maxf(biggest, absf(angle_difference(before, rig.yaw)))
	await _fixture.lift(0)
	# 1.6 rad per full height at sensitivity 1: 100 of 1080 units is 0.148 rad, 8.5 degrees. The
	# first design turned twice that and a phone flew round.
	assert_float(rad_to_deg(absf(angle_difference(start, rig.yaw)))).is_equal_approx(8.5, 0.3)
	assert_float(rad_to_deg(biggest)).is_less(1.0)


func test_a_drag_turns_once_when_the_browser_also_reports_it_as_mouse_motion() -> void:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var yaw := player.camera_rig.yaw
	await _fixture.touch(0, Vector2(1700.0, 300.0))
	await _fixture.drag(0, Vector2(1800.0, 300.0), Vector2(100.0, 0.0))
	await _fixture.stray_mouse_motion(Vector2(100.0, 0.0))
	await _fixture.lift(0)
	var turned := angle_difference(yaw, player.camera_rig.yaw)
	assert_float(turned).is_equal_approx(-TouchLook.RADIANS_PER_HEIGHT * 100.0 / 1080.0, 0.02)


func test_the_move_stick_turns_nothing_when_the_browser_reports_the_finger_as_mouse_motion(
) -> void:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var yaw := player.camera_rig.yaw
	await _fixture.touch(0, Vector2(300.0, 800.0))
	for step in 5:
		var at := Vector2(300.0 + 30.0 * (step + 1), 800.0)
		await _fixture.drag(0, at, Vector2(30.0, 0.0))
		await _fixture.stray_mouse_motion(Vector2(30.0, 0.0))
	await _fixture.lift(0)
	assert_float(player.camera_rig.yaw).is_equal(yaw)


func test_a_mouse_turns_the_view_once_it_was_the_last_input() -> void:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	UIInputMode.touch = false
	var yaw := player.camera_rig.yaw
	await _fixture.stray_mouse_motion(Vector2(100.0, 0.0))
	assert_float(absf(angle_difference(yaw, player.camera_rig.yaw))).is_greater(0.05)


func test_the_look_gain_slows_a_drag_as_the_aim_assist_does_near_a_zombie() -> void:
	var runner := scene_runner("res://world/test_room.tscn")
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	_fixture.controls.look_gain = func() -> float: return 0.5
	var yaw := player.camera_rig.yaw
	await _fixture.touch(0, Vector2(1700.0, 300.0))
	await _fixture.drag(0, Vector2(1800.0, 300.0), Vector2(100.0, 0.0))
	await _fixture.lift(0)
	var turned := angle_difference(yaw, player.camera_rig.yaw)
	assert_float(turned).is_equal_approx(-TouchLook.RADIANS_PER_HEIGHT * 100.0 / 1080.0 * 0.5, 0.02)


func test_the_side_button_moves_the_camera_to_the_other_shoulder() -> void:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var before := player.state.shoulder_side
	await _fixture.touch(0, _fixture.at(TouchLayout.SHOULDER))
	await runner.simulate_frames(6)
	await _fixture.lift(0)
	assert_float(player.state.shoulder_side).is_equal(-before)
	# A second tap swaps back (once the first press has been let go: a press lasts 90 ms at least).
	await await_millis(250)
	await _fixture.touch(0, _fixture.at(TouchLayout.SHOULDER))
	await runner.simulate_frames(6)
	await _fixture.lift(0)
	assert_float(player.state.shoulder_side).is_equal(before)
