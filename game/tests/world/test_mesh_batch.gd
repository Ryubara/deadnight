# What a batch of meshes keeps and what it refuses (#728): the picture is the same, drawn with fewer
# calls.
extends GdUnitTestSuite

const CELL := 10.0

var _holder: Node3D


func before_test() -> void:
	_holder = auto_free(Node3D.new()) as Node3D
	add_child(_holder)


func _box(size: Vector3 = Vector3.ONE) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _paint(colour: Color, rough := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = rough
	return material


func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		total += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


func test_pieces_of_one_material_in_one_cell_are_one_surface() -> void:
	var batch := MeshBatch.new(CELL)
	var mesh := _box()
	var paint := _paint(Color.RED)
	for i in 5:
		(
			assert_bool(batch.add(mesh, 0, Transform3D(Basis.IDENTITY, Vector3(i, 0, 0)), paint))
			. is_true()
		)
	assert_int(batch.cell_count()).is_equal(1)
	assert_int(batch.surface_count()).is_equal(1)
	var made := batch.build(_holder)
	assert_int(made.size()).is_equal(1)
	assert_int(made[0].mesh.get_surface_count()).is_equal(1)
	assert_int(_triangles(made[0].mesh)).is_equal(5 * _triangles(mesh))


func test_two_materials_with_the_same_look_are_one_and_two_that_differ_are_two() -> void:
	var batch := MeshBatch.new(CELL)
	var mesh := _box()
	# Two resources that read the same (two models that wear one palette), and a third that does
	# not.
	batch.add(mesh, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), _paint(Color.RED))
	batch.add(mesh, 0, Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), _paint(Color.RED))
	batch.add(mesh, 0, Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)), _paint(Color.BLUE))
	batch.add(mesh, 0, Transform3D(Basis.IDENTITY, Vector3(6, 0, 0)), _paint(Color.RED, 0.5))
	assert_int(batch.surface_count()).is_equal(3)


func test_pieces_in_far_cells_are_not_one_mesh() -> void:
	var batch := MeshBatch.new(CELL)
	var mesh := _box()
	var paint := _paint(Color.RED)
	batch.add(mesh, 0, Transform3D(Basis.IDENTITY, Vector3(1, 0, 1)), paint)
	batch.add(mesh, 0, Transform3D(Basis.IDENTITY, Vector3(41, 0, 1)), paint)
	assert_int(batch.cell_count()).is_equal(2)
	assert_int(batch.build(_holder).size()).is_equal(2)


func test_a_built_mesh_stands_where_the_pieces_stood() -> void:
	var batch := MeshBatch.new(CELL)
	var mesh := _box()
	var paint := _paint(Color.RED)
	var turned := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 1, 4))
	batch.add(mesh, 0, turned, paint)
	batch.add(mesh, 0, Transform3D(Basis.IDENTITY, Vector3(6, 1, 2)), paint)
	var made := batch.build(_holder)
	var drawn := made[0].global_transform * made[0].get_aabb()
	var wanted := (turned * mesh.get_aabb()).merge(
		Transform3D(Basis.IDENTITY, Vector3(6, 1, 2)) * mesh.get_aabb()
	)
	assert_vector(drawn.position).is_equal_approx(wanted.position, Vector3.ONE * 0.001)
	assert_vector(drawn.size).is_equal_approx(wanted.size, Vector3.ONE * 0.001)


func test_what_would_draw_wrong_is_refused() -> void:
	var batch := MeshBatch.new(CELL)
	var mesh := _box()
	var mirrored := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
	assert_bool(batch.add(mesh, 0, mirrored, _paint(Color.RED))).is_false()
	var glass := _paint(Color(1, 1, 1, 0.5))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	assert_bool(batch.add(mesh, 0, Transform3D.IDENTITY, glass)).is_false()
	var chained := _paint(Color.RED)
	chained.next_pass = _paint(Color.BLUE)
	assert_bool(batch.add(mesh, 0, Transform3D.IDENTITY, chained)).is_false()
	var shaded := ShaderMaterial.new()
	shaded.shader = Shader.new()
	assert_bool(batch.add(mesh, 0, Transform3D.IDENTITY, shaded)).is_false()
	assert_bool(batch.add(mesh, 0, Transform3D.IDENTITY, null)).is_false()
	assert_int(batch.surface_count()).is_equal(0)


func test_the_lots_surface_shader_may_be_batched_and_another_may_not() -> void:
	var lot := ShaderMaterial.new()
	lot.shader = load("res://assets/lot/lot_surface.gdshader")
	assert_bool(MeshBatch.can_batch(lot)).is_true()
	var other := ShaderMaterial.new()
	other.shader = load("res://world/drive_in/glow.gdshader")
	assert_bool(MeshBatch.can_batch(other)).is_false()


func test_a_cell_that_too_many_lights_reach_is_split() -> void:
	var lights: Array[Light3D] = []
	for i in 4:
		var lamp := OmniLight3D.new()
		lamp.omni_range = 3.0
		_holder.add_child(lamp)
		lamp.global_position = Vector3(i * 2.0, 2, 0)
		lights.append(lamp)
	var mesh := _box()
	var paint := _paint(Color.RED)
	# Eight boxes in a row along x (0 to 14): all four lamps reach the row, but a box only a lamp or
	# two.
	var whole := MeshBatch.new(40.0)
	var cut := MeshBatch.new(40.0, lights, 2)
	for i in 8:
		var at := Transform3D(Basis.IDENTITY, Vector3(i * 2.0, 0.5, 0))
		whole.add(mesh, 0, at, paint)
		cut.add(mesh, 0, at, paint)
	assert_int(whole.cell_count()).is_equal(1)
	assert_int(cut.cell_count()).is_greater(1)
	for instance in cut.build(_holder):
		var box := instance.global_transform * instance.get_aabb()
		var reached := LightReach.count(lights, box)
		var pieces := _triangles(instance.mesh) / _triangles(mesh)
		(
			assert_bool(reached <= 2 or pieces == 1)
			. override_failure_message(
				"a mesh of %d pieces is reached by %d lights" % [pieces, reached]
			)
			. is_true()
		)


func test_a_lone_piece_over_the_budget_is_kept_whole() -> void:
	var lamp := OmniLight3D.new()
	lamp.omni_range = 50.0
	_holder.add_child(lamp)
	var lights: Array[Light3D] = [lamp, lamp, lamp]
	var batch := MeshBatch.new(CELL, lights, 1)
	batch.add(_box(), 0, Transform3D.IDENTITY, _paint(Color.RED))
	assert_int(batch.cell_count()).is_equal(1)


func test_the_same_pieces_build_the_same_batch_each_time() -> void:
	var names: Array[String] = []
	for _run in 2:
		var batch := MeshBatch.new(CELL)
		var mesh := _box()
		for i in 12:
			batch.add(
				mesh,
				0,
				Transform3D(Basis.IDENTITY, Vector3(i * 7.0, 0, (i % 3) * 9.0)),
				_paint(Color.RED)
			)
		var host := auto_free(Node3D.new()) as Node3D
		add_child(host)
		var line := ""
		for instance in batch.build(host):
			line += "%s@%s;" % [instance.name, instance.position]
		names.append(line)
	assert_str(names[1]).is_equal(names[0])
