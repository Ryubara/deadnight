# The measures of the second map's formula suite, on shapes whose answer is known: each fails where
# it should, so a pass of `test_smallmap_formula.gd` means something.
extends GdUnitTestSuite


func _world(boxes: Array) -> Node3D:
	var world := auto_free(Node3D.new()) as Node3D
	add_child(world)
	for spec: Array in boxes:
		var box := CSGBox3D.new()
		box.use_collision = true
		box.size = spec[0]
		box.position = spec[1]
		world.add_child(box)
	await get_tree().process_frame
	for _i in 3:
		await get_tree().physics_frame
	return world


func test_the_floor_mesh_measures_a_10_by_10_room_as_100_square_metres() -> void:
	var walls := [
		[Vector3(10.6, 0.4, 10.6), Vector3(0, -0.2, 0)],
		[Vector3(0.3, 3, 10.6), Vector3(-5.15, 1.5, 0)],
		[Vector3(0.3, 3, 10.6), Vector3(5.15, 1.5, 0)],
		[Vector3(10.6, 3, 0.3), Vector3(0, 1.5, -5.15)],
		[Vector3(10.6, 3, 0.3), Vector3(0, 1.5, 5.15)],
		# A block in the middle a body cannot climb: its top is not floor anyone reaches.
		[Vector3(2, 1.2, 2), Vector3(2, 0.6, 2)],
	]
	var world := await _world(walls)
	var nav := SmallMapNavigation.new(
		world, SmallMapNavigation.floor_mesh(AABB(Vector3(-6, -1, -6), Vector3(12, 5, 12)))
	)
	var area := 0.0
	for i in nav.connected_polygons(Vector3(-3, 0.2, -3)):
		area += nav.polygon_area(i)
	nav.free_map()
	assert_float(area).is_between(94.0, 97.0)


func test_a_narrow_passage_reads_its_width() -> void:
	var world := await _world(
		[
			[Vector3(8, 0.4, 8), Vector3(0, -0.2, 0)],
			[Vector3(1, 3, 6), Vector3(-1.2, 1.5, 0)],
			[Vector3(1, 3, 6), Vector3(1.2, 1.5, 0)],
		]
	)
	var probe := Marker3D.new()
	world.add_child(probe)
	await get_tree().physics_frame
	var width := SmallMapMeasure.passage_width(world.get_world_3d().direct_space_state, probe)
	assert_float(width).is_equal_approx(1.4, 0.02)


func test_the_sweep_sees_a_corridor_squeeze_the_shoulder_camera() -> void:
	# A 1.2 m corridor is narrower than the shoulder camera's reach (0.6 m out and a 0.25 m sphere):
	# the rig slides the lens in, and the sweep counts it; a 4 m hall leaves the shoulder alone.
	for gap: float in [1.2, 4.0]:
		var world := await _world(
			[
				[Vector3(10, 0.4, 14), Vector3(0, -0.2, 0)],
				[Vector3(1, 3, 14), Vector3(-gap / 2 - 0.5, 1.5, 0)],
				[Vector3(1, 3, 14), Vector3(gap / 2 + 0.5, 1.5, 0)],
			]
		)
		var probe := Marker3D.new()
		world.add_child(probe)
		await get_tree().physics_frame
		var result := SmallMapMeasure.sweep(world.get_world_3d().direct_space_state, probe)
		assert_int(result["samples"]).is_greater(0)
		assert_array(result["failures"]).is_empty()
		if gap < 1.8:
			assert_int(result["squeezed"]).is_greater(0)
		else:
			assert_int(result["squeezed"]).is_equal(0)
		world.queue_free()
		await get_tree().process_frame


func test_the_longest_clear_line_ignores_a_line_through_a_wall() -> void:
	# A wall down the middle of a hall: the two longest pairs (29.7 and 28.6 m) cross it and are not
	# lines of sight; the longest clear one stays on one side of it (28.3 m).
	var world := await _world(
		[
			[Vector3(30, 0.4, 12), Vector3(0, -0.2, 0)],
			[Vector3(26, 3, 0.3), Vector3(2, 1.5, 0)],
		]
	)
	var points: Array[Vector3] = [
		Vector3(-14, 1.55, -5), Vector3(14, 1.55, 5), Vector3(14, 1.55, -5), Vector3(-14, 1.55, -1)
	]
	var measure := SmallMapMeasure.new()
	var longest := measure.longest_clear(world.get_world_3d().direct_space_state, points)
	assert_float(longest["length"]).is_equal_approx(28.28, 0.05)


func test_the_setting_check_skips_an_engine_made_name_and_reads_authored_ones() -> void:
	# An unnamed child gets an engine name such as `@MeshInstance3D@31945`: a counter, not ours.
	var parent := auto_free(Node3D.new()) as Node3D
	var made := MeshInstance3D.new()
	parent.add_child(made)
	assert_str(String(made.name)).starts_with("@")
	assert_str(SmallMapMeasure.setting_words(made)).is_empty()
	var authored := auto_free(Node3D.new()) as Node3D
	authored.name = "Bunker1945"
	assert_bool(SmallMapMeasure.setting_words(authored).contains("1945")).is_true()
	var sign := auto_free(Label3D.new()) as Label3D
	sign.name = "@Label3D@2"
	sign.text = "HELP"
	assert_bool(SmallMapMeasure.setting_words(sign).contains("help")).is_true()
