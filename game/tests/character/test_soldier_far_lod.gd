# The modular Soldier's far level of detail (#139): every preset dressed by SoldierLook shows each
# part's far mesh past FAR_FROM, with the same material, within the far budget the catalog states.
extends GdUnitTestSuite


func test_every_preset_has_a_far_look_within_the_budget() -> void:
	var cat := SoldierLook.catalog()
	for p: Dictionary in SoldierLook.presets():
		var model := SoldierLook.instantiate()
		add_child(auto_free(model))
		var near_tris := SoldierLook.apply(model, p)
		var far_tris := SoldierLook.far_triangles(model)
		assert_int(far_tris).override_failure_message(p.id).is_equal(int(p.tris_far))
		assert_int(far_tris).is_less_equal(int(cat.far_budget))
		assert_int(far_tris).is_less(near_tris / 2)
		var far := SoldierLook.far_meshes(model)
		for mesh_name: String in SoldierLook.part_meshes(model):
			var near: MeshInstance3D = SoldierLook.part_meshes(model)[mesh_name]
			var fi: MeshInstance3D = far[mesh_name]
			assert_bool(fi.visible).is_equal(near.visible)
			if near.visible:
				assert_object(fi.material_override).is_same(near.material_override)
				assert_float(near.visibility_range_end).is_equal(SoldierLook.FAR_FROM)
				assert_float(fi.visibility_range_begin).is_equal(SoldierLook.FAR_FROM)
				assert_object(fi.skin).is_not_null()


func test_an_undressed_model_shows_nothing_far_away() -> void:
	var model := SoldierLook.instantiate()
	add_child(auto_free(model))
	assert_int(SoldierLook.far_triangles(model)).is_equal(0)
