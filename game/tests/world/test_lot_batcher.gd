# The drive-in lot drawn as a few meshes (#728): fewer draws, the same picture, and nothing a script
# or the rules reach is touched. The pictures are compared by `tools/lot/batch_capture.gd`
# (attached to the pull request).
extends GdUnitTestSuite

var _lot: Node3D
var _before := {}
var _stats := {}
var _solid_before := {}


func before_test() -> void:
	_lot = await LotFixture.make_lot(self)
	auto_free(_lot.get_parent())
	_before = _drawn(_lot)
	_solid_before = _solid_boxes(_lot)
	_stats = LotBatcher.batch(_lot)
	await get_tree().process_frame


## The surfaces and triangles the lot asks the renderer for: the meshes seen and the roots of the
## seen CSG boxes.
func _drawn(lot: Node3D) -> Dictionary:
	var surfaces := 0
	var triangles := 0
	for node in lot.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
			continue
		for surface in mesh_node.mesh.get_surface_count():
			surfaces += 1
			triangles += _triangles(mesh_node.mesh, surface)
	for node in lot.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if shape.get_parent() is CSGShape3D or not shape.is_visible_in_tree():
			continue
		var built := shape.get_meshes()
		if built.size() < 2 or not (built[1] is Mesh):
			continue
		for surface in (built[1] as Mesh).get_surface_count():
			surfaces += 1
			triangles += _triangles(built[1], surface)
	return {"surfaces": surfaces, "triangles": triangles}


func _triangles(mesh: Mesh, surface: int) -> int:
	var indices: Variant = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
	return (indices as PackedInt32Array).size() / 3 if indices != null else 0


func test_the_lot_is_drawn_with_far_fewer_surfaces_and_not_a_triangle_less() -> void:
	var after := _drawn(_lot)
	assert_int(_stats["pieces"]).is_greater(600)
	assert_int(after["surfaces"]).is_less(int(_before["surfaces"] * 0.75))
	assert_int(after["triangles"]).is_equal(_before["triangles"])


func test_every_prop_and_car_is_in_a_batch() -> void:
	var left: Array[String] = []
	for node in _lot.find_children("*", "MeshInstance3D", true, false):
		var at := node as Node
		while at != null and at != _lot:
			var path := at.scene_file_path
			if (
				path.begins_with("res://world/drive_in/props/")
				or path == "res://world/drive_in/car.tscn"
			):
				left.append(str(_lot.get_path_to(node)))
				break
			at = at.get_parent()
	assert_array(left).is_empty()
	assert_object(_lot.get_node(LotBatcher.BATCH_NODE)).is_not_null()


func test_what_the_rules_and_the_scripts_reach_is_left_alone() -> void:
	# A door's slabs, a barricade's boards, a lamp's bulb and the machines are still there, drawn as
	# they were.
	var doors := _lot.get_node("Doors")
	assert_int(doors.get_child_count()).is_greater(0)
	for door in doors.get_children():
		assert_int(door.get_child_count()).override_failure_message(door.name).is_greater(0)
	for node in _lot.find_children("*", "Barricade", true, false):
		(
			assert_object(node.get_node_or_null("Board1/Mesh"))
			. override_failure_message(str(node.name))
			. is_not_null()
		)
	var heads := 0
	for node in _lot.find_children("Head", "CSGBox3D", true, false):
		assert_bool((node as CSGShape3D).visible).is_true()
		heads += 1
	assert_int(heads).is_greater(20)
	assert_int(_lot.find_children("*", "PerkMachine", true, false).size()).is_equal(5)
	for machine in _lot.find_children("*", "PerkMachine", true, false):
		# The emblem, the flap, the falling bottle and the glass are its own.
		assert_int(machine.find_children("*", "MeshInstance3D", true, false).size()).is_between(
			4, 16
		)


func test_a_wall_that_was_drawn_still_blocks() -> void:
	# The batch hides the box and draws its mesh; the box stays the wall (`use_collision`): every
	# box a ray hit before is hit now.
	var after := _solid_boxes(_lot)
	assert_int(_solid_before.size()).is_greater(300)
	var lost: Array[String] = []
	for path in _solid_before:
		if not after.has(path):
			lost.append(path)
	assert_array(lost).is_empty()


## The solid boxes of the map (by path) a ray from above reaches the middle of.
func _solid_boxes(lot: Node3D) -> Dictionary:
	var space := lot.get_world_3d().direct_space_state
	var found := {}
	for node in lot.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if shape.get_parent() is CSGShape3D or not shape.use_collision:
			continue
		var query := PhysicsRayQueryParameters3D.create(
			shape.global_position + Vector3.UP * 60.0, shape.global_position
		)
		if not space.intersect_ray(query).is_empty():
			found[str(lot.get_path_to(shape))] = true
	return found


func test_a_batched_mesh_is_reached_by_no_more_lights_than_the_map_allows_a_mesh() -> void:
	# The lot keeps each mesh to the cap less the room a fight needs (test_lot_light_cap.gd).
	var lights: Array[Light3D] = []
	for light in _lot.find_children("*", "Light3D", true, false):
		lights.append(light)
	var allowed := LightReach.limit() - LotBatcher.DYNAMIC_LIGHTS
	var over: Array[String] = []
	for instance in _lot.get_node(LotBatcher.BATCH_NODE).get_children():
		var box := (
			(instance as MeshInstance3D).global_transform * (instance as MeshInstance3D).get_aabb()
		)
		var reached := LightReach.count(lights, box)
		# A mesh that is one piece was that piece's own before: the map's own test holds it to its
		# own cap.
		if reached > allowed and instance.get_meta(MeshBatch.PIECES_META) > 1:
			over.append(
				(
					"%s: %d lights, %d pieces, box %s"
					% [instance.name, reached, instance.get_meta(MeshBatch.PIECES_META), box]
				)
			)
	assert_array(over).is_empty()


func test_a_night_batches_the_map_that_asks_and_not_a_server() -> void:
	var asks := MapInfo.new()
	asks.batch_still = true
	var silent := MapInfo.new()
	assert_bool(LotBatcher.wanted(asks, false)).is_true()
	assert_bool(LotBatcher.wanted(silent, false)).is_false()
	assert_bool(LotBatcher.wanted(asks, true)).is_false()
	assert_bool(LotBatcher.wanted(null, false)).is_false()
	LotBatcher.enabled = false
	assert_bool(LotBatcher.wanted(asks, false)).is_false()
	LotBatcher.enabled = true
	assert_bool((load("res://world/maps/drive_in.tres") as MapInfo).batch_still).is_true()
	assert_bool((load("res://world/maps/small_indoor.tres") as MapInfo).batch_still).is_false()


func test_the_small_props_can_be_left_out_beyond_a_distance() -> void:
	var lot := auto_free(load(LotFixture.SCENE).instantiate()) as Node3D
	add_child(lot)
	await get_tree().process_frame
	await get_tree().physics_frame
	LotBatcher.batch(lot, MeshBatch.DEFAULT_CELL, 50.0)
	var ranged := 0
	for instance in lot.get_node(LotBatcher.BATCH_NODE).get_children():
		var small: bool = instance.get_meta(MeshBatch.GROUP_META) == LotBatcher.GROUP_SMALL
		assert_bool((instance as GeometryInstance3D).visibility_range_end > 0.0).is_equal(small)
		ranged += 1 if small else 0
	assert_int(ranged).is_greater(5)
