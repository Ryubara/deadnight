# The second map's zombie meshes, baked ahead for every set of sold links (eight: the three links
# have no prerequisite) and saved as `world/smallmap/smallmap_navmeshes.res` (`LotNavmeshes`,
# found by the key of the geometry). Fails when the greybox changed and the bake was not run:
#   godot --headless --path game -s res://tools/world/bake_lot_navmeshes.gd -- \
#     --scene=res://world/smallmap/smallmap_greybox.tscn \
#     --out=res://world/smallmap/smallmap_navmeshes.res
extends GdUnitTestSuite

const PATH := "res://world/smallmap/smallmap_navmeshes.res"
const RERUN := "the second map's geometry changed: bake its meshes again (this suite's header)"


func _map(sold: Array) -> Node3D:
	var lot := auto_free((load(SmallMapMeasure.SCENE) as PackedScene).instantiate()) as Node3D
	add_child(lot)
	for _i in 3:
		await get_tree().physics_frame
	var doors := lot.get_node("Doors") as LotDoors
	for id: StringName in sold:
		doors.open(id)
	await get_tree().physics_frame
	return lot


func _sets() -> Array[Array]:
	var lot := (load(SmallMapMeasure.SCENE) as PackedScene).instantiate()
	var sets := LotNavmeshes.door_sets(lot.get_node("Doors"))
	lot.free()
	return sets


func test_every_set_of_links_has_its_saved_mesh_and_no_stale_ones() -> void:
	var saved := load(PATH) as LotNavmeshes
	assert_object(saved).override_failure_message("%s missing" % PATH).is_not_null()
	var sets := _sets()
	assert_int(sets.size()).is_equal(8)
	for sold: Array in sets:
		var lot := await _map(sold)
		var mesh := saved.mesh_for(lot)
		assert_object(mesh).override_failure_message("links %s: %s" % [sold, RERUN]).is_not_null()
		if mesh != null:
			var baked := NavmeshBaker.bake(lot)
			(
				assert_bool(mesh.get_vertices() == baked.get_vertices())
				. override_failure_message(RERUN)
				. is_true()
			)
		lot.queue_free()
		await get_tree().process_frame
	assert_int(saved.meshes.size()).override_failure_message(RERUN).is_equal(sets.size())
