# The touch controls driving the real player: a drag on the right turns the camera, the stick
# walks the player. Its own suite because the scene runner changes how input is delivered.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
## A steady drag: how long, how fast (canvas units a second) and the stretch at each end left out.
const DRAG_SECONDS := 1.6
const DRAG_UNITS_PER_SECOND := 40.0
const DRAG_TRIM_SECONDS := 0.4

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
	await _fixture.settle_look()
	# Dragging right turns the view right (mouse convention): the yaw falls. A drag of 100 units
	# on a 1080 unit tall canvas turns 100 / 1080 of the full-height swipe, at sensitivity 1.
	var turned := angle_difference(yaw, rig.yaw)
	assert_float(turned).is_equal_approx(
		-TouchLook.tuning.radians_per_height * 100.0 / 1080.0, 0.02
	)


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
	await _fixture.settle_look()
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
	await _fixture.settle_look()
	var turned := angle_difference(yaw, player.camera_rig.yaw)
	assert_float(turned).is_equal_approx(
		-TouchLook.tuning.radians_per_height * 100.0 / 1080.0, 0.02
	)


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
	await _fixture.settle_look()
	var turned := angle_difference(yaw, player.camera_rig.yaw)
	assert_float(turned).is_equal_approx(
		-TouchLook.tuning.radians_per_height * 100.0 / 1080.0 * 0.5, 0.02
	)


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


## What a browser's web runtime reports for the first drag of each finger while another is down: its
## `relative` is measured from somewhere else (the origin for the look finger, the other finger's
## press for the stick finger), not from the finger's own last position (#497, found by logging
## every touch event in headless Chrome with two fingers).
func test_two_thumbs_turn_the_view_by_the_look_drag_alone_whatever_the_first_drag_reports() -> void:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var rig := player.camera_rig
	var stick_at := Vector2(300.0, 800.0)
	var look_at := Vector2(1700.0, 300.0)
	var yaw := rig.yaw
	await _fixture.touch(0, stick_at)
	await _fixture.touch(1, look_at)
	var biggest := 0.0
	for step in 10:
		stick_at += Vector2(8.0, -3.0)
		look_at += Vector2(10.0, 0.0)
		var stick_step := Vector2(8.0, -3.0)
		var look_step := Vector2(10.0, 0.0)
		if step == 0:
			# The runtime's mistakes: the stick finger's step is measured from the look finger's press,
			# the look finger's from the origin.
			stick_step = stick_at - Vector2(1700.0, 300.0)
			look_step = look_at
		var before := rig.yaw
		await _fixture.drag(0, stick_at, stick_step)
		await _fixture.drag(1, look_at, look_step)
		biggest = maxf(biggest, absf(angle_difference(before, rig.yaw)))
	await _fixture.lift(0)
	await _fixture.lift(1)
	await _fixture.settle_look()
	# The flick gain follows the frame timing the engine measures, so the turn is between the slow-drag
	# design and the fastest gain; the bogus first drags turned the view by a whole screen.
	var designed := TouchLook.tuning.radians_per_height * 100.0 / 1080.0
	var turned := -angle_difference(yaw, rig.yaw)
	assert_float(turned).is_between(designed * 0.98, designed * TouchLook.tuning.max_gain * 1.02)
	assert_float(rad_to_deg(biggest)).is_less(2.0)


func test_a_drag_from_the_aim_button_turns_the_view_and_keeps_aiming() -> void:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var rig := player.camera_rig
	var aim := _fixture.at(TouchLayout.AIM)
	var yaw := rig.yaw
	await _fixture.touch(0, aim)
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	await _fixture.drag(0, aim + Vector2(100.0, 0.0), Vector2(100.0, 0.0))
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	await _fixture.lift(0)
	await _fixture.settle_look()
	# The aim button also steadies the look: the rig scales the turn by `aim_sensitivity_scale` in
	# proportion to how far its spring (stepped by the measured frame time) has eased into the aim
	# when the drag lands, so the turn is anywhere between the hip turn and the fully steadied one
	# (#576: 0.112 to 0.148 rad on different runs). A drag that turns nothing, or too much, is outside.
	var hip_turn := TouchLook.tuning.radians_per_height * 100.0 / 1080.0
	var steady_turn := hip_turn * player.tuning.aim_sensitivity_scale
	var turned := -angle_difference(yaw, rig.yaw)
	assert_float(turned).is_between(steady_turn * 0.98, hip_turn * 1.02)


## A steady slow drag through the real input path, sampled every third frame as a 60 Hz finger is
## on a page drawn at 180 Hz (#598): the yaw of every frame in the middle of the drag, without the
## first and last 0.4 s, and the clock of each. The finger's speed is steady in time whatever the
## frames take.
func _steady_drag(rig: ThirdPersonCamera, frames_per_sample: int) -> Dictionary:
	var yaws: Array[float] = []
	var clocks: Array[float] = []
	var began := Time.get_ticks_usec() / 1000000.0
	var last_sample := began
	var at := Vector2(1700.0, 300.0)
	await _fixture.touch(0, at)
	var frame := 0
	while Time.get_ticks_usec() / 1000000.0 - began < DRAG_SECONDS:
		var now := Time.get_ticks_usec() / 1000000.0
		if frame % frames_per_sample == 0:
			var step := Vector2(DRAG_UNITS_PER_SECOND * (now - last_sample), 0.0)
			at += step
			last_sample = now
			await _fixture.drag(0, at, step)
		else:
			await get_tree().process_frame
		frame += 1
		var elapsed := now - began
		if elapsed > DRAG_TRIM_SECONDS and elapsed < DRAG_SECONDS - DRAG_TRIM_SECONDS:
			yaws.append(rig.yaw)
			clocks.append(now)
	await _fixture.lift(0)
	return {"yaws": yaws, "clocks": clocks}


## The turn of each frame of a drag, and the turn per second.
func _frame_turns(drag: Dictionary) -> Dictionary:
	var steps: Array[float] = []
	var rates: Array[float] = []
	for i in range(1, drag["yaws"].size()):
		var step := angle_difference(drag["yaws"][i - 1], drag["yaws"][i])
		steps.append(step)
		rates.append(step / maxf(drag["clocks"][i] - drag["clocks"][i - 1], 0.000001))
	return {"steps": steps, "rates": rates}


func _variation(values: Array[float]) -> float:
	var mean := 0.0
	for value in values:
		mean += value
	mean /= values.size()
	var variance := 0.0
	for value in values:
		variance += (value - mean) * (value - mean)
	return sqrt(variance / values.size()) / absf(mean)


func test_a_steady_slow_drag_turns_the_view_every_frame_without_a_step_back() -> void:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var drag := await _steady_drag(player.camera_rig, 3)
	var turns := _frame_turns(drag)
	var steps: Array[float] = turns["steps"]
	assert_int(steps.size()).is_greater(30)
	# Dragging right turns the yaw down: every frame moves that way, none stands still or goes back.
	assert_int(steps.filter(func(step: float) -> bool: return step >= 0.0).size()).is_equal(0)
	assert_float(_variation(turns["rates"])).is_less(0.35)


func test_the_same_drag_stood_still_in_most_frames_without_the_smoothing() -> void:
	# What the smoothing replaces: the same steady drag, the view turned the moment a sample came.
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	_fixture.controls.tuning = TouchTuning.shipped()
	_fixture.controls.tuning.look_smoothing = 0.0
	var drag := await _steady_drag(player.camera_rig, 3)
	var turns := _frame_turns(drag)
	var steps: Array[float] = turns["steps"]
	(
		assert_int(steps.filter(func(step: float) -> bool: return step == 0.0).size())
		. is_greater(steps.size() / 3)
	)
	assert_float(_variation(turns["rates"])).is_greater(0.8)
