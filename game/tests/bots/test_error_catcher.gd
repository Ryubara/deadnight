# The error catcher the movement tests use to say "nothing was printed": it must see what the
# engine prints, or an empty list means nothing.
extends GdUnitTestSuite


func test_it_catches_the_error_a_query_on_an_unsynchronised_map_prints() -> void:
	var catcher := ErrorCatcher.new()
	catcher.start()
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array(
		[
			Vector3(0.0, 0.0, 0.0),
			Vector3(2.0, 0.0, 0.0),
			Vector3(2.0, 0.0, 2.0),
			Vector3(0.0, 0.0, 2.0)
		]
	)
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	# The map has not taken its first mesh in: this prints an engine error.
	NavigationServer3D.map_get_closest_point(map, Vector3(1.0, 0.0, 1.0))
	catcher.stop()
	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)
	assert_int(catcher.lines.size()).is_equal(1)
	assert_str(catcher.lines[0]).contains("before first map synchronization")


func test_it_catches_nothing_when_nothing_is_printed() -> void:
	var catcher := ErrorCatcher.new()
	catcher.start()
	var total := 1 + 1
	assert_int(total).is_equal(2)
	catcher.stop()
	assert_array(catcher.lines).is_empty()
