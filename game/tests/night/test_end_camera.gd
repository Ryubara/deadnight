extends GdUnitTestSuite
## The camera of the end of a night (`EndCamera`): it starts on the player's own lens, eases out
## without a jerk, never goes through a wall on the way, then cuts between the map's angles on the
## clock, and is the same at any frame rate because its time is a number.

var _tuning: EndTuning


func before_test() -> void:
	_tuning = EndTuning.shipped()


## A player's lens: a camera `behind` metres south of `at`, `up` high, looking at `at`.
func _lens(at: Vector3, behind := 4.0, up := 2.0) -> Camera3D:
	var lens: Camera3D = auto_free(Camera3D.new())
	add_child(lens)
	lens.fov = 74.0
	var place := at + Vector3(0.0, up, behind)
	lens.global_transform = Transform3D(EndShot.facing(at - place), place)
	return lens


func _shot(from: Vector3, to: Vector3, look: Vector3, fov := 55.0) -> EndShot:
	var shot := EndShot.new()
	shot.lens_from = from
	shot.lens_to = to
	shot.look_from = look
	shot.look_to = look
	shot.fov = fov
	return shot


func _shots() -> Array[EndShot]:
	var list: Array[EndShot] = [
		_shot(Vector3(20, 10, 0), Vector3(20, 10, 10), Vector3.ZERO),
		_shot(Vector3(-20, 12, 0), Vector3(-20, 12, 10), Vector3.ZERO),
		_shot(Vector3(0, 30, 30), Vector3(0, 30, 20), Vector3.ZERO),
	]
	return list


func _camera(lens: Camera3D, at: Vector3, shots: Array[EndShot]) -> EndCamera:
	var camera: EndCamera = auto_free(EndCamera.new())
	add_child(camera)
	camera.begin(lens, at, shots, _tuning)
	return camera


func _wall(centre: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = PhysicsLayers.WORLD
	add_child(body)
	body.global_position = centre


func test_it_starts_on_the_players_own_lens_and_takes_the_view() -> void:
	var lens := _lens(Vector3.ZERO)
	var camera := _camera(lens, Vector3.ZERO, _shots())
	assert_vector(camera.global_position).is_equal_approx(lens.global_position, Vector3.ONE * 0.001)
	assert_float(camera.fov).is_equal_approx(lens.fov, 0.001)
	assert_object(camera.get_viewport().get_camera_3d()).is_same(camera)
	# The direction is the lens's too: the same way along the view.
	assert_vector(-camera.global_basis.z).is_equal_approx(-lens.global_basis.z, Vector3.ONE * 0.001)


func test_the_pull_back_eases_out_and_ends_high_behind_the_player_looking_at_them() -> void:
	var lens := _lens(Vector3.ZERO)
	var camera := _camera(lens, Vector3.ZERO, _shots())
	var start := camera.global_position
	camera.seek(0.1)
	# It begins gently: after a tenth of a second it has hardly moved.
	assert_float(camera.global_position.distance_to(start)).is_less(0.1)
	var last := 0.0
	var t := 0.0
	while t < _tuning.pullback_seconds:
		camera.seek(t)
		var gone := camera.global_position.distance_to(start)
		assert_float(gone).is_greater_equal(last - 0.0001)
		last = gone
		t += 0.1
	camera.seek(_tuning.pullback_seconds - 0.001)
	var end := camera.global_position
	assert_float(end.y).is_greater(_tuning.pullback_height * 0.9)
	assert_float(Vector2(end.x, end.z).length()).is_greater(_tuning.pullback_distance * 0.9)
	# It looks at the player's chest at the end of it.
	var to_player := (Vector3.UP * _tuning.look_lift - end).normalized()
	assert_float((-camera.global_basis.z).dot(to_player)).is_greater(0.99)
	assert_float(camera.fov).is_equal_approx(_tuning.pullback_fov, 0.05)


func test_the_pull_back_never_goes_through_a_wall() -> void:
	var lens := _lens(Vector3.ZERO)
	# A wall across the way back and up: 1 m thick, 30 m wide, reaching 9 m, 5 m south of the player.
	_wall(Vector3(0.0, 4.5, 6.0), Vector3(30.0, 9.0, 1.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var camera := _camera(lens, Vector3.ZERO, _shots())
	var space := camera.get_world_3d().direct_space_state
	var wall_face_z := 5.5
	var t := 0.0
	while t <= _tuning.pullback_seconds:
		camera.seek(t)
		var lens_at := camera.global_position
		# Never in the wall's volume, never farther south than its near face less the margin.
		var inside := lens_at.z > wall_face_z - _tuning.margin * 0.5 and lens_at.y < 9.0
		(
			assert_bool(inside)
			. override_failure_message("the lens at %s is in the wall" % lens_at)
			. is_false()
		)
		t += 0.1
	var from := lens.global_position
	var fraction := CameraPlacement.sweep(
		space, [], EndCamera.WALL_MASK, from, camera.global_position - from, 0.05
	)
	assert_float(fraction).is_equal_approx(1.0, 0.001)


func test_the_angles_cut_on_the_clock_and_wrap_after_the_last() -> void:
	var lens := _lens(Vector3.ZERO)
	var shots := _shots()
	var camera := _camera(lens, Vector3.ZERO, shots)
	var cuts: Array[int] = []
	camera.cut.connect(func(number: int) -> void: cuts.append(number))
	var first := _tuning.pullback_seconds
	camera.seek(first - 0.01)
	assert_int(camera.shot_number).is_equal(-1)
	assert_array(cuts).is_empty()
	camera.seek(first + 0.01)
	assert_int(camera.shot_number).is_equal(0)
	assert_vector(camera.global_position).is_equal_approx(shots[0].lens_from, Vector3.ONE * 0.1)
	assert_float(camera.fov).is_equal_approx(55.0, 0.001)
	camera.seek(first + _tuning.shot_seconds * 0.5)
	# A drift: half way along the first shot's way (10 m in z, so 5).
	assert_float(camera.global_position.z).is_equal_approx(5.0, 0.2)
	camera.seek(first + _tuning.shot_seconds + 0.01)
	assert_int(camera.shot_number).is_equal(1)
	assert_vector(camera.global_position).is_equal_approx(shots[1].lens_from, Vector3.ONE * 0.1)
	camera.seek(first + _tuning.shot_seconds * 3.0 + 0.01)
	assert_int(camera.shot_number).is_equal(3)
	assert_vector(camera.global_position).is_equal_approx(shots[0].lens_from, Vector3.ONE * 0.1)
	assert_array(cuts).is_equal([0, 1, 3])


func test_every_angle_looks_at_its_point() -> void:
	var lens := _lens(Vector3.ZERO)
	var camera := _camera(lens, Vector3.ZERO, _shots())
	for t in [5.0, 6.0, 9.7, 12.3, 20.0]:
		camera.seek(t + _tuning.pullback_seconds)
		var to_point := (Vector3.ZERO - camera.global_position).normalized()
		assert_float((-camera.global_basis.z).dot(to_point)).is_greater(0.999)


func test_it_is_the_same_at_any_frame_rate() -> void:
	var lens := _lens(Vector3.ZERO)
	var slow := _camera(lens, Vector3.ZERO, _shots())
	var fast := _camera(lens, Vector3.ZERO, _shots())
	for i in 100:
		slow.advance(0.1)
	for i in 1440:
		fast.advance(1.0 / 144.0)
	assert_vector(slow.global_position).is_equal_approx(fast.global_position, Vector3.ONE * 0.01)
	assert_int(slow.shot_number).is_equal(fast.shot_number)


func test_a_map_with_no_angles_holds_the_end_of_the_pull_back() -> void:
	var lens := _lens(Vector3.ZERO)
	var empty: Array[EndShot] = []
	var camera := _camera(lens, Vector3.ZERO, empty)
	camera.seek(_tuning.pullback_seconds + 30.0)
	var held := camera.global_position
	camera.seek(_tuning.pullback_seconds + 60.0)
	assert_vector(camera.global_position).is_equal_approx(held, Vector3.ONE * 0.0001)
	assert_float(held.y).is_greater(_tuning.pullback_height * 0.9)


func test_a_look_straight_down_has_a_basis() -> void:
	var down := EndShot.facing(Vector3.DOWN)
	assert_float((-down.z).dot(Vector3.DOWN)).is_greater(0.999)
	assert_bool(down.is_finite()).is_true()
