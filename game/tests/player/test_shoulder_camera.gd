# The shoulder camera's damping, interpolation and clearance, stepped by hand with fixed time steps:
# no wall time, no frame delta, so the same numbers come out on any machine.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## Where a run along +x starts: 12 m of open floor to the east at 3 m/s for 4 s.
const LANE := Vector3(-6.0, 0.05, 10.0)

var _player: Player
var _rig: ThirdPersonCamera
var _tuning: PlayerTuning


func before_test() -> void:
	var runner := scene_runner(TEST_ROOM)
	_player = runner.find_child("Player") as Player
	_player.capture_mouse = false
	# Nothing runs by itself: the test places the body and steps the rig.
	_player.set_physics_process(false)
	_player.set_process(false)
	_rig = _player.camera_rig
	_rig.set_process(false)
	_tuning = _player.tuning
	_put(START)
	await get_tree().physics_frame
	await get_tree().physics_frame


## Put the body at `position` (the physics server gets it too) and the camera at rest there.
func _put(position: Vector3) -> void:
	_player.global_position = position
	_player.state.position = position
	_rig.snap_to(position)


## Run `seconds` of rendering at `fps`, the body already at its position (no physics ticks).
func _render(seconds: float, fps := 60.0, fraction := 1.0) -> void:
	for i in roundi(seconds * fps):
		_rig.step(1.0 / fps, fraction)


func test_a_critically_damped_spring_is_exact_for_any_step_and_never_overshoots() -> void:
	var one_big := DampedSpring.new()
	one_big.step(1.0, 12.0, 0.5)
	var many_small := DampedSpring.new()
	var highest := 0.0
	for i in 300:
		many_small.step(1.0, 12.0, 0.5 / 300.0)
		highest = maxf(highest, many_small.value)
	assert_float(many_small.value).is_equal_approx(one_big.value, 0.0001)
	assert_float(many_small.velocity).is_equal_approx(one_big.velocity, 0.001)
	assert_float(highest).is_less_equal(1.0)


func test_a_spring_closes_95_percent_in_its_settle_time() -> void:
	for frequency: float in [6.0, 16.0, 24.0]:
		var spring := DampedSpring.new()
		spring.step(1.0, frequency, DampedSpring.settle_time(frequency))
		assert_float(spring.value).is_equal_approx(0.95, 0.005)


func test_the_aim_zoom_eases_with_no_kink_and_lands_on_the_aim_numbers() -> void:
	var camera := _rig.camera()
	_render(0.5)
	assert_float(camera.fov).is_equal_approx(_tuning.fov, 0.01)
	_rig.aiming = true
	var fovs: Array[float] = [camera.fov]
	for i in 30:
		_rig.step(TICK, 1.0)
		fovs.append(camera.fov)
	var steps: Array[float] = []
	for i in range(1, fovs.size()):
		steps.append(fovs[i - 1] - fovs[i])
	for step in steps:
		assert_float(step).is_greater_equal(0.0)  # never turns back
	# A kink would be a first frame as fast as the fastest one (an exponential ease is): this
	# ease starts from rest, so its first frame is under half of its fastest.
	assert_float(steps[0]).is_less(steps.max() * 0.5)
	assert_float(camera.fov).is_equal_approx(_tuning.fov_aim, 0.05)
	assert_float(_rig.aim_amount()).is_equal_approx(1.0, 0.01)


func test_releasing_aim_halfway_keeps_the_velocity_and_does_not_snap_back() -> void:
	_rig.aiming = true
	_render(0.07)
	var fov_before := _rig.camera().fov
	_rig.aiming = false
	_rig.step(TICK, 1.0)
	# Still closing in for a moment (its velocity carries on), then it opens: no jump in either.
	# No jump: a tick moves it less than a tenth of the way between the hip and the aim view.
	assert_float(absf(_rig.camera().fov - fov_before)).is_less(
		(_tuning.fov - _tuning.fov_aim) * 0.1
	)
	_render(0.8)
	assert_float(_rig.camera().fov).is_equal_approx(_tuning.fov, 0.05)


func test_sprinting_widens_the_view_and_lets_the_camera_out_then_settles_back() -> void:
	var camera := _rig.camera()
	var rest := _rig.lens_distance()
	_rig.sprinting = true
	_render(1.0)
	assert_float(camera.fov).is_equal_approx(_tuning.fov + _tuning.sprint_fov_kick, 0.05)
	assert_float(_rig.lens_distance() - rest).is_greater(_tuning.sprint_arm_extra * 0.5)
	_rig.sprinting = false
	_render(1.5)
	assert_float(camera.fov).is_equal_approx(_tuning.fov, 0.05)


func test_aim_cancels_the_sprint_pull_back() -> void:
	_rig.sprinting = true
	_rig.aiming = true
	_render(1.0)
	assert_float(_rig.sprint_amount()).is_less(0.01)
	assert_float(_rig.camera().fov).is_equal_approx(_tuning.fov_aim, 0.05)


func test_the_camera_trails_a_moving_body_by_twice_its_speed_over_the_frequency() -> void:
	var speed := 4.0
	var x := 0.0
	for tick in 180:  # three seconds of steady running along +x, rendered with the exact blend
		x += speed * TICK
		_rig.track(START + Vector3(x, 0.0, 0.0))
		_rig.step(TICK, 1.0)
	var lag := (START.x + x) - _rig.pivot_position().x
	# A critically damped spring tracking a ramp trails it by 2 v / w.
	assert_float(lag).is_equal_approx(2.0 * speed / _tuning.follow_frequency, 0.05)


func test_the_camera_catches_up_when_the_body_stops() -> void:
	for tick in 60:
		_rig.track(START + Vector3(0.1 * (tick + 1), 0.0, 0.0))
		_rig.step(TICK, 1.0)
	_render(1.0)
	var stopped := START + Vector3(6.0, 0.0, 0.0)
	assert_float(_rig.pivot_position().x).is_equal_approx(stopped.x, 0.01)


## The lens x after every rendered frame while the body runs along +x at `speed`, ticked at
## 60 Hz and drawn at `fps`, with the blend of the time since the last tick (or always 1.0 when
## `interpolate` is false).
func _lens_path(fps: float, speed: float, interpolate: bool) -> Array[float]:
	_put(LANE)
	var path: Array[float] = []
	var since_tick := 0.0
	var x := 0.0
	var frame := 1.0 / fps
	# Warm up to the steady state, then record.
	for n in roundi(fps * 4.0):
		since_tick += frame
		while since_tick >= TICK:
			since_tick -= TICK
			x += speed * TICK
			_rig.track(LANE + Vector3(x, 0.0, 0.0))
		_rig.step(frame, since_tick / TICK if interpolate else 1.0)
		if n >= roundi(fps * 2.0):
			path.append(_rig.camera().global_position.x)
	return path


## Largest departure of one frame's travel from the average travel, as a fraction of the average.
func _unevenness(path: Array[float]) -> float:
	var travel: Array[float] = []
	for i in range(1, path.size()):
		travel.append(path[i] - path[i - 1])
	var mean := (path[-1] - path[0]) / travel.size()
	var worst := 0.0
	for step in travel:
		worst = maxf(worst, absf(step - mean))
	return worst / mean


func test_the_view_moves_evenly_at_144_hz_with_physics_at_60() -> void:
	var path := _lens_path(144.0, 3.0, true)
	assert_float(_unevenness(path)).is_less(0.05)


func test_the_view_moves_evenly_at_other_frame_rates() -> void:
	for fps: float in [30.0, 75.0, 240.0]:
		var path := _lens_path(fps, 3.0, true)
		assert_float(_unevenness(path)).override_failure_message("%d fps" % fps).is_less(0.08)


func test_without_the_blend_the_same_camera_would_still_stutter_a_little() -> void:
	# Negative control: drawing the newest tick at every frame (no interpolation) moves the body
	# in jumps once per tick at 144 Hz. The spring already hides most of it; the blend removes it.
	var unblended := _unevenness(_lens_path(144.0, 3.0, false))
	var blended := _unevenness(_lens_path(144.0, 3.0, true))
	assert_float(unblended).is_greater(0.015)
	assert_float(blended).is_less(0.001)


func test_a_body_that_jumps_far_in_one_tick_is_snapped_to_not_eased_to() -> void:
	_rig.track(START + Vector3(40.0, 0.0, 0.0))
	_rig.step(TICK, 1.0)
	assert_float(_rig.pivot_position().x).is_equal_approx(40.0, 0.5)


func test_the_lens_stays_in_the_room_beside_a_wall_on_the_shoulder_side() -> void:
	# The east wall's inner face is at x = 15.0; the right shoulder is toward it at yaw 0.
	_put(Vector3(14.4, 0.05, 0.0))
	_render(0.5)
	assert_float(_rig.camera().global_position.x).is_less(15.0 - 0.1)
	assert_bool(_rig.is_body_hidden()).is_false()  # slid in behind the player, not into the head
	# Aiming too, and on the other shoulder against the west wall.
	_rig.aiming = true
	_render(0.5)
	assert_float(_rig.camera().global_position.x).is_less(15.0 - 0.1)
	_rig.aiming = false
	_rig.side = -1.0
	_put(Vector3(-14.4, 0.05, 0.0))
	_render(0.5)
	assert_float(_rig.camera().global_position.x).is_greater(-15.0 + 0.1)


func test_the_body_hides_with_the_lens_at_the_head_and_returns_with_a_margin() -> void:
	var changes: Array[bool] = []
	_rig.body_hidden_changed.connect(func(hidden: bool) -> void: changes.append(hidden))
	_put(Vector3(0.0, 0.05, 19.4))  # the south wall is right behind the camera
	_render(0.3)
	assert_bool(_rig.is_body_hidden()).is_true()
	assert_float(_rig.lens_distance()).is_less(_tuning.hide_body_distance)
	_put(Vector3(0.0, 0.05, 10.0))
	_render(2.0)
	assert_bool(_rig.is_body_hidden()).is_false()
	assert_array(changes).is_equal([true, false])


func test_the_lens_comes_out_of_a_wall_gradually() -> void:
	_put(Vector3(0.0, 0.05, 19.4))
	_render(0.3)
	var z := 19.4
	var previous := _rig.lens_distance()
	var largest := 0.0
	for i in 40:  # walk away from the wall at 5 m/s
		z -= 5.0 * TICK
		_rig.track(Vector3(0.0, 0.05, z))
		_rig.step(TICK, 1.0)
		largest = maxf(largest, _rig.lens_distance() - previous)
		previous = _rig.lens_distance()
	_render(2.0)
	assert_float(largest).is_less(0.1)  # no pop: the arm is let out over a second or so
	assert_float(_rig.lens_distance()).is_equal_approx(
		Vector2(_tuning.shoulder_offset, _tuning.arm_length).length(), 0.05
	)


func test_the_aim_reticle_is_clear_of_the_body() -> void:
	_rig.aiming = true
	_render(1.0)
	var camera := _rig.camera()
	var axis := Vector2(_player.global_position.x, _player.global_position.z)
	var ray_at := Vector2(camera.global_position.x, camera.global_position.z)
	var forward := Vector2(-camera.global_transform.basis.z.x, -camera.global_transform.basis.z.z)
	# Distance from the body's vertical axis to the line through the screen centre.
	var distance := absf((axis - ray_at).cross(forward.normalized()))
	assert_float(distance).is_greater(_tuning.radius + 0.2)


func test_the_character_sits_in_the_lower_left_third_over_the_right_shoulder() -> void:
	_render(0.5)
	var camera := _rig.camera()
	var head := _player.global_position + Vector3(0.0, _tuning.pivot_height, 0.0)
	var screen := camera.unproject_position(head)
	var size := get_viewport().get_visible_rect().size
	assert_float(screen.x / size.x).is_between(0.25, 0.45)
	assert_float(screen.y / size.y).is_between(0.3, 0.6)


func test_the_first_steer_sets_the_heading_and_later_ones_ease_to_it() -> void:
	_rig.yaw = 2.5
	_rig.steer(-1.0, 0.1)
	assert_float(_rig.yaw).is_equal_approx(-1.0, 0.0001)
	_rig.steer(-0.5, 0.1)
	_rig.step(TICK, 1.0)
	assert_float(_rig.yaw).is_between(-1.0, -0.9)
	_rig.stop_steering()


func test_a_steered_view_turns_to_the_heading_without_overshooting() -> void:
	_rig.yaw = 0.0
	_rig.steer(0.0, 0.0)  # the first call places the view; the next ones ease
	_rig.steer(1.0, 0.2)
	var highest := 0.0
	var first_step := 0.0
	var biggest_step := 0.0
	for i in 90:
		var before := _rig.yaw
		_rig.step(TICK, 1.0)
		highest = maxf(highest, _rig.yaw)
		var step := _rig.yaw - before
		if i == 0:
			first_step = step
		biggest_step = maxf(biggest_step, step)
	assert_float(highest).is_less_equal(1.0 + 0.001)
	assert_float(_rig.yaw).is_equal_approx(1.0, 0.01)
	assert_float(_rig.pitch).is_equal_approx(0.2, 0.01)
	assert_float(first_step).is_less(biggest_step * 0.5)  # starts from rest, no jerk
	_rig.stop_steering()
