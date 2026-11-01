extends GdUnitTestSuite
## The camera probe takes the rig's numbers from the player's tuning, so the passage tests in
## `test_drive_in_camera` keep judging the camera the player really has.

var _tuning: PlayerTuning
var _saved := {}


func before_test() -> void:
	_tuning = CameraProbe.tuning()
	for property in ["pivot_height", "shoulder_offset", "arm_length", "arm_margin"]:
		_saved[property] = _tuning.get(property)


func after_test() -> void:
	for property: String in _saved:
		_tuning.set(property, _saved[property])


func test_the_probe_reads_the_rig_values_from_the_tuning() -> void:
	assert_float(CameraProbe.pivot_height()).is_equal(_tuning.pivot_height)
	assert_float(CameraProbe.shoulder_offset()).is_equal(_tuning.shoulder_offset)
	assert_float(CameraProbe.arm_length()).is_equal(_tuning.arm_length)
	assert_float(CameraProbe.arm_margin()).is_equal(_tuning.arm_margin)


func test_the_rig_in_open_air_follows_a_changed_tuning() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var feet := Vector3(4.0, 0.0, -2.0)
	var before := CameraProbe.rig(space, feet, 0.0, 1.0)
	_tuning.pivot_height += 0.5
	_tuning.arm_length += 1.0
	_tuning.shoulder_offset += 0.25
	var after := CameraProbe.rig(space, feet, 0.0, 1.0)
	# Yaw 0 looks down -Z, so the arm runs back along +Z and the right shoulder is +X.
	assert_vector(after["pivot"] - before["pivot"]).is_equal_approx(
		Vector3(0.0, 0.5, 0.0), Vector3.ONE * 0.001
	)
	assert_float(after["arm"] - before["arm"]).is_equal_approx(1.0, 0.001)
	assert_float(after["camera"].x - before["camera"].x).is_equal_approx(0.25, 0.001)
	assert_float(after["camera"].z - before["camera"].z).is_equal_approx(1.0, 0.001)
