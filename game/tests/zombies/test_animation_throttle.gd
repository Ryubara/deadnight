extends GdUnitTestSuite
## The animation throttle's tiers: how often a zombie's tree is advanced by where it stands against
## the camera, and that a zombie out of view is not advanced at all but is back at once when it is
## seen (Deadnight #949).

const STEP := 1.0 / 60.0

var _camera: Camera3D
var _throttle: AnimationThrottle


func before_test() -> void:
	_camera = auto_free(Camera3D.new()) as Camera3D
	add_child(_camera)
	# Looking down -z from the origin, as a Camera3D does by default.
	_throttle = auto_free(AnimationThrottle.new()) as AnimationThrottle
	_throttle.camera = _camera
	add_child(_throttle)
	_throttle.set_process(false)


func _view_at(position: Vector3) -> ZombieView:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(), 1, 0.0, 0.7)
	view.position = position
	_throttle.add_view(view)
	return view


## Runs `frames` frames and returns the animations advanced in them.
func _run(frames: int) -> int:
	var advanced := 0
	for i in frames:
		_throttle._process(STEP)
		advanced += _throttle.advanced_last_frame
	return advanced


func test_the_period_follows_the_distance_in_front_of_the_camera() -> void:
	var cases := {
		5.0: AnimationThrottle.PERIOD_NEAR,
		20.0: AnimationThrottle.PERIOD_MID,
		30.0: AnimationThrottle.PERIOD_FAR,
		60.0: AnimationThrottle.PERIOD_DISTANT,
	}
	for distance: float in cases:
		var view := _view_at(Vector3(0, -1.0, -distance))
		(
			assert_int(_throttle._period_for(view))
			. override_failure_message("%s m ahead" % distance)
			. is_equal(cases[distance])
		)


func test_a_zombie_out_of_view_is_not_advanced() -> void:
	var behind := _view_at(Vector3(0, -1.0, 6.0))
	var aside := _view_at(Vector3(40.0, -1.0, -5.0))
	assert_int(_throttle._period_for(behind)).is_equal(AnimationThrottle.PERIOD_UNSEEN)
	assert_int(_throttle._period_for(aside)).is_equal(AnimationThrottle.PERIOD_UNSEEN)
	# Its first RETIER_EVERY frames it is still going (a new view starts at every frame), then it
	# stops: over a long run it is advanced only in that start.
	_run(AnimationThrottle.RETIER_EVERY)
	assert_int(behind.period).is_equal(AnimationThrottle.PERIOD_UNSEEN)
	assert_int(_run(120)).is_equal(0)


func test_a_zombie_that_comes_into_view_is_advanced_the_frame_it_is_seen() -> void:
	var view := _view_at(Vector3(0, -1.0, 6.0))
	_run(AnimationThrottle.RETIER_EVERY)
	assert_int(view.period).is_equal(AnimationThrottle.PERIOD_UNSEEN)
	view.position = Vector3(0, -1.0, -6.0)
	# Looked at every RETIER_UNSEEN_EVERY frames, and advanced in the frame it is found.
	var first := -1
	for frame in AnimationThrottle.RETIER_UNSEEN_EVERY:
		_throttle._process(STEP)
		if _throttle.advanced_last_frame > 0:
			first = frame
			break
	assert_int(first).is_greater_equal(0)
	assert_int(view.period).is_equal(AnimationThrottle.PERIOD_NEAR)


func test_the_time_kept_out_of_view_is_bounded_and_a_starting_phase_is_kept() -> void:
	var view := _view_at(Vector3(0, -1.0, 6.0))
	_run(AnimationThrottle.RETIER_EVERY)
	view.accumulated = 0.0
	_run(600)
	assert_float(view.accumulated).is_equal_approx(AnimationThrottle.MAX_CATCH_UP, 0.001)
	view.accumulated = 1.2
	_run(60)
	assert_float(view.accumulated).is_equal(1.2)


func test_a_zombie_with_only_its_head_in_view_still_moves() -> void:
	# Ten metres ahead the view is about 7.7 m above and below the axis: stand it so that its feet
	# are under the bottom edge and its head above it.
	var feet := Vector3(0, -8.0, -10.0)
	var view := _view_at(feet)
	assert_bool(_camera.is_position_in_frustum(feet)).is_false()
	assert_bool(_camera.is_position_in_frustum(feet + Vector3(0, 2.2, 0))).is_true()
	assert_int(_throttle._period_for(view)).is_not_equal(AnimationThrottle.PERIOD_UNSEEN)
