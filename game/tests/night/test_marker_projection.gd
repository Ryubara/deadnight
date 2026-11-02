# Where a point of the world falls on a camera's screen, for the HUD's markers.
extends GdUnitTestSuite

const UNIT := Rect2(0.0, 0.0, 1.0, 1.0)

var _camera: Camera3D


func before_test() -> void:
	_camera = auto_free(Camera3D.new())
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)


func test_a_point_straight_ahead_is_the_middle_of_the_screen() -> void:
	var found := MarkerProjection.project(_camera, Vector3(0.0, 0.0, -10.0))
	assert_bool(found["behind"]).is_false()
	assert_vector(found["screen"]).is_equal_approx(Vector2(0.5, 0.5), Vector2(0.001, 0.001))


func test_it_agrees_with_the_cameras_own_projection_as_a_share_of_the_screen() -> void:
	var point := Vector3(2.0, 1.0, -9.0)
	var found := MarkerProjection.project(_camera, point)
	var size := _camera.get_viewport().get_visible_rect().size
	var expected := _camera.unproject_position(point) / size
	assert_vector(found["screen"]).is_equal_approx(expected, Vector2(0.0001, 0.0001))


func test_a_point_to_a_side_is_on_that_side_and_off_the_screen_when_far_enough() -> void:
	var left := MarkerProjection.project(_camera, Vector3(-30.0, 0.0, -10.0))
	assert_bool(left["behind"]).is_false()
	assert_float(left["screen"].x).is_less(0.0)
	var right := MarkerProjection.project(_camera, Vector3(30.0, 0.0, -10.0))
	assert_float(right["screen"].x).is_greater(1.0)


func test_a_point_straight_behind_is_below_the_screen() -> void:
	var found := MarkerProjection.project(_camera, Vector3(0.0, 0.0, 12.0))
	assert_bool(found["behind"]).is_true()
	assert_float(found["screen"].y).is_greater(1.0)
	assert_float(found["screen"].x).is_equal_approx(0.5, 0.01)


func test_a_point_behind_goes_to_its_own_side_not_where_the_mirror_lands() -> void:
	var left := MarkerProjection.project(_camera, Vector3(-8.0, 0.0, 3.0))
	assert_bool(left["behind"]).is_true()
	assert_float(left["screen"].x).is_less(0.5)
	var right := MarkerProjection.project(_camera, Vector3(8.0, 0.0, 3.0))
	assert_float(right["screen"].x).is_greater(0.5)
	# Either way it is off the screen, so the HUD pins it.
	assert_bool(UNIT.has_point(left["screen"])).is_false()
	assert_bool(UNIT.has_point(right["screen"])).is_false()


func test_it_follows_the_camera_when_it_turns() -> void:
	var point := Vector3(0.0, 0.0, -10.0)
	_camera.rotation.y = deg_to_rad(15.0)
	# Turned to the left, a point that was ahead is now to the right.
	assert_float(MarkerProjection.project(_camera, point)["screen"].x).is_greater(0.5)
	_camera.rotation.y = deg_to_rad(180.0)
	assert_bool(MarkerProjection.project(_camera, point)["behind"]).is_true()
