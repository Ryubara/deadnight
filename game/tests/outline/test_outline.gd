extends GdUnitTestSuite
## The universal outline: any mesh, skinned or static, wears it without a change to its model; the
## style (colour, thickness) is shared and tunable live; the enabled flag puts it on and takes
## it off; and a mesh that does not wear it draws nothing of it.


func _static_body() -> Node3D:
	var root := auto_free(Node3D.new()) as Node3D
	add_child(root)
	for i in 2:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		root.add_child(mesh)
	return root


func _outline_of(root: Node3D, style: OutlineStyle = null) -> Outline:
	var outline := Outline.new()
	outline.style = style
	root.add_child(outline)
	return outline


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		found.append(node as MeshInstance3D)
	return found


func test_it_is_off_until_enabled_and_the_model_is_not_edited() -> void:
	var root := _static_body()
	var outline := _outline_of(root)
	assert_int(outline.meshes().size()).is_equal(2)
	for mesh in _meshes(root):
		assert_object(mesh.material_overlay).is_null()
		assert_object(mesh.material_override).is_null()
	outline.enabled = true
	for mesh in _meshes(root):
		assert_object(mesh.material_overlay).is_not_null()
		assert_object(mesh.material_override).is_null()


func test_the_toggle_takes_it_off_again() -> void:
	var root := _static_body()
	var outline := _outline_of(root)
	outline.enabled = true
	outline.enabled = false
	for mesh in _meshes(root):
		assert_object(mesh.material_overlay).is_null()


func test_a_skinned_zombie_wears_it_on_both_its_meshes() -> void:
	var view := auto_free(ZombieView.new()) as ZombieView
	add_child(view)
	view.setup(ZombieModels.scene(), 1, 0.0, 0.7)
	var meshes := _meshes(view.model())
	assert_int(meshes.size()).is_equal(2)
	for mesh in meshes:
		assert_object(mesh.skin).is_not_null()
	view.set_outlined(true)
	for mesh in meshes:
		assert_object(mesh.material_overlay).is_not_null()


func test_every_mesh_that_wears_a_style_shares_its_materials() -> void:
	var style := OutlineStyle.new()
	var a := _static_body()
	var b := _static_body()
	_outline_of(a, style).enabled = true
	_outline_of(b, style).enabled = true
	assert_object(_meshes(a)[0].material_overlay).is_same(style.chain())
	assert_object(_meshes(b)[1].material_overlay).is_same(style.chain())


func test_the_chain_is_a_mask_then_a_ring_of_copies_that_read_the_scene_depth() -> void:
	var style := OutlineStyle.new()
	assert_int(style.pass_count()).is_equal(1 + OutlineStyle.DIRECTIONS)
	var materials := style.materials()
	assert_int(materials.size()).is_equal(style.pass_count())
	assert_object(materials[0].shader).is_same(OutlineStyle.MASK_SHADER)
	assert_str(OutlineStyle.MASK_SHADER.code).contains("depth_test_disabled")
	assert_str(OutlineStyle.LINE_SHADER.code).contains("depth_test_disabled")
	# The line is kept off the visible parts by comparing with the scene's depth, and has no halo.
	assert_str(OutlineStyle.LINE_SHADER.code).contains("hint_depth_texture")
	assert_str(OutlineStyle.MASK_SHADER.code).contains("stencil_mode write")
	# The passes are chained in the order they are drawn.
	var at: Material = style.chain()
	var chained := 0
	while at != null:
		chained += 1
		at = at.next_pass
	assert_int(chained).is_equal(style.pass_count())


func test_colour_and_thickness_reach_every_pass_live() -> void:
	var style := OutlineStyle.new()
	var root := _static_body()
	_outline_of(root, style).enabled = true
	style.color = Color(0.1, 0.9, 0.2, 1.0)
	style.thickness = 6.0
	var line := style.materials()[1]
	assert_that(line.get_shader_parameter(&"color")).is_equal(Color(0.1, 0.9, 0.2, 1.0))
	var radius: float = 6.0 / cos(PI / OutlineStyle.DIRECTIONS)
	assert_float(line.get_shader_parameter(&"reach")).is_equal_approx(radius, 0.001)


func test_the_copies_ring_the_body_in_even_directions() -> void:
	var style := OutlineStyle.new()
	var seen := {}
	for i in OutlineStyle.DIRECTIONS:
		var direction: Vector2 = style.materials()[1 + i].get_shader_parameter(&"direction")
		assert_float(direction.length()).is_equal_approx(1.0, 0.001)
		seen[snappedf(direction.angle(), 0.01)] = true
	assert_int(seen.size()).is_equal(OutlineStyle.DIRECTIONS)


func test_the_shipped_style_is_the_files() -> void:
	var file := load(Outline.DEFAULT_STYLE) as OutlineStyle
	assert_object(file).is_not_null()
	assert_float(file.thickness).is_greater(0.0)
	assert_float(file.color.a).is_greater(0.0)
	var root := _static_body()
	var outline := _outline_of(root)
	assert_object(outline.active_style()).is_same(file)
