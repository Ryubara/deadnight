extends GdUnitTestSuite
## A dressed Soldier holds what it wears and nothing else: the file holds every part of the
## catalogue, four bodies and four HUD portraits are alive in a night, and a hidden mesh still
## counts against `mesh_instances` (tools/perf/budget.json). A later look brings its parts back.

## The most meshes a dressed Soldier may hold, near and far: nine parts and eight far levels, with
## one spare. It does not grow with the catalogue, which is the point.
const MOST_MESHES := 18


func _looks() -> Array[CharacterLook]:
	var out: Array[CharacterLook] = []
	for i in SoldierLook.presets().size():
		for body: String in ["male", "female"]:
			var look := CharacterLook.from_preset(i)
			look.parts[&"body"] = StringName(body)
			out.append(look)
	return out


func _assemble(look: CharacterLook) -> Node3D:
	var model := CharacterAssembler.assemble(look, 0)
	add_child(model)
	auto_free(model)
	return model


func _held(model: Node) -> Array[String]:
	var out: Array[String] = []
	out.assign(SoldierLook.part_meshes(model).keys())
	out.sort()
	return out


func _worn(look: CharacterLook) -> Array[String]:
	var out := SoldierLook.visible_meshes(look.to_soldier_look())
	out.sort()
	return out


func test_a_dressed_soldier_holds_only_what_it_wears() -> void:
	for look in _looks():
		var model := _assemble(look)
		assert_array(_held(model)).is_equal(_worn(look))
		var far := SoldierLook.far_meshes(model)
		for mesh_name: String in far:
			assert_array(_worn(look)).contains([mesh_name])
		assert_int(_held(model).size() + far.size()).is_less_equal(MOST_MESHES)


func test_a_trimmed_soldier_changes_its_look_in_place() -> void:
	# Every look follows several others, without the cost of every pair.
	var looks := _looks()
	var model := _assemble(looks[0])
	for stride in [1, 5, 7]:
		for i in looks.size():
			var to := looks[(i * stride) % looks.size()]
			CharacterAssembler.dress(model, to, 0)
			assert_array(_held(model)).is_equal(_worn(to))


func test_a_part_that_comes_back_is_skinned_and_keeps_its_far_swap() -> void:
	var from := CharacterLook.from_preset(0)
	var to := CharacterLook.from_preset(1)
	var model := _assemble(from)
	var skeleton := model.find_child("Skeleton3D", true, false)
	CharacterAssembler.dress(model, to, 0)
	var near := SoldierLook.part_meshes(model)
	var far := SoldierLook.far_meshes(model)
	for mesh_name: String in near:
		var mi: MeshInstance3D = near[mesh_name]
		assert_object(mi.skin).is_not_null()
		assert_object(mi.get_node(mi.skeleton)).is_same(skeleton)
		assert_bool(mi.visible).is_true()
		assert_object(mi.material_override).is_not_null()
		if far.has(mesh_name):
			var fi: MeshInstance3D = far[mesh_name]
			assert_object(fi.get_node(fi.skeleton)).is_same(skeleton)
			assert_bool(fi.visible).is_true()
			assert_float(mi.visibility_range_end).is_equal(SoldierLook.FAR_FROM)
			assert_float(fi.visibility_range_begin).is_equal(SoldierLook.FAR_FROM)


func test_a_look_counts_the_same_on_a_trimmed_soldier_and_a_new_one() -> void:
	var look := CharacterLook.from_preset(1)
	var worn := look.to_soldier_look()
	var model := _assemble(CharacterLook.from_preset(0))
	var fresh := SoldierLook.instantiate()
	auto_free(fresh)
	assert_int(SoldierLook.apply(model, worn)).is_equal(SoldierLook.apply(fresh, worn))
	assert_int(SoldierLook.far_triangles(model)).is_equal(SoldierLook.far_triangles(fresh))


func test_changing_looks_leaves_no_node_behind() -> void:
	var model := _assemble(CharacterLook.from_preset(0))
	CharacterAssembler.dress(model, CharacterLook.from_preset(1), 0)
	await get_tree().process_frame
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 8:
		CharacterAssembler.dress(model, CharacterLook.from_preset(i), 0)
	await get_tree().process_frame
	var after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	assert_int(after).is_less_equal(before)
