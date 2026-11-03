# The small map's cover and clutter props (issue #635, `tools/blender/build_smallmap_props.py`):
# every fixture holds its model on the kit's atlas, stands on its origin (the middle of its
# footprint, on the floor), keeps to the triangle budget the build wrote, and has hidden collision
# unless it is walk-over dressing.
extends GdUnitTestSuite

const FIXTURES := "res://world/smallmap/fixtures/%s.tscn"
const REPORT := "res://assets/smallmap/smallmap_props.json"
const PALETTE := "res://assets/smallmap/smallmap_palette.png"
const PIECES := [
	"sandbags_2m",
	"sandbags_1m",
	"table",
	"table_tipped",
	"chair",
	"filing_cabinet",
	"shelf_rack",
	"tall_cabinet",
	"rubble_a",
	"rubble_b",
	"rubble_c",
	"rubble_d",
	"rubble_cone",
	"radio",
	"lantern",
	"helmet",
]
## Walk-over dressing, with no collision, as the lot's papers and debris: a player steps over it
## (step 0.3 m).
const DRESSING := ["rubble_a", "rubble_b", "radio", "lantern", "helmet"]
## Built around its own footprint, with a part outside it (the filing cabinet's pulled-out drawer).
const OFF_CENTRE := ["filing_cabinet"]


func _report() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(REPORT)) as Dictionary


func _fixture(name: String) -> Node3D:
	return auto_free((load(FIXTURES % name) as PackedScene).instantiate()) as Node3D


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(node as MeshInstance3D)
	return out


## The node's transform relative to `root`, without the tree (the fixture is never added to it).
func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var at := node
	while at != root and at != null:
		xform = at.transform * xform
		at = at.get_parent() as Node3D
	return xform


func _model_box(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in _meshes(root):
		var b := _to_root(mesh, root) * mesh.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _blockers(root: Node3D) -> Array[CSGShape3D]:
	var out: Array[CSGShape3D] = []
	for node in root.get_children():
		if node is CSGShape3D and (node as CSGShape3D).use_collision:
			out.append(node as CSGShape3D)
	return out


func test_every_piece_has_a_fixture_and_a_line_in_the_report() -> void:
	var report := _report()
	for name in PIECES:
		assert_bool(ResourceLoader.exists(FIXTURES % name)).override_failure_message(name).is_true()
		assert_bool(report.has(name)).override_failure_message(name).is_true()
	assert_int(report.size()).is_equal(PIECES.size())


func test_each_model_keeps_to_its_budget_and_the_build_report() -> void:
	var report := _report()
	for name in PIECES:
		var tris := 0
		for mesh in _meshes(_fixture(name)):
			for s in mesh.mesh.get_surface_count():
				tris += (
					(mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
					/ 3
				)
		var row := report[name] as Dictionary
		assert_int(tris).override_failure_message("%s: %d tris" % [name, tris]).is_equal(
			int(row["tris"])
		)
		assert_int(tris).override_failure_message(name).is_less_equal(int(row["budget"]))


func test_each_model_is_one_material_on_the_kit_atlas() -> void:
	for name in PIECES:
		var meshes := _meshes(_fixture(name))
		assert_int(meshes.size()).override_failure_message(name).is_equal(1)
		var mesh := meshes[0].mesh
		assert_int(mesh.get_surface_count()).override_failure_message(name).is_equal(1)
		var material := mesh.surface_get_material(0) as BaseMaterial3D
		assert_str(material.albedo_texture.resource_path).override_failure_message(name).is_equal(
			PALETTE
		)
		assert_float(material.metallic).is_equal(0.0)
		assert_float(material.roughness).is_equal_approx(0.415, 0.001)


func test_each_piece_stands_on_the_floor_in_the_middle_of_its_footprint() -> void:
	for name in PIECES:
		var box := _model_box(_fixture(name))
		var centre := box.get_center()
		assert_float(box.position.y).override_failure_message(name).is_equal_approx(0.0, 0.005)
		if name in OFF_CENTRE:
			continue
		assert_float(centre.x).override_failure_message(name).is_equal_approx(0.0, 0.01)
		assert_float(centre.z).override_failure_message(name).is_equal_approx(0.0, 0.01)


func test_cover_and_furniture_block_and_dressing_does_not() -> void:
	for name in PIECES:
		var root := _fixture(name)
		var blockers := _blockers(root)
		if name in DRESSING:
			assert_int(blockers.size()).override_failure_message(name).is_equal(0)
			assert_float(_model_box(root).size.y).override_failure_message(name).is_less(0.36)
			continue
		assert_int(blockers.size()).override_failure_message(name).is_greater(0)
		var model := _model_box(root)
		var top := 0.0
		for blocker in blockers:
			assert_bool(blocker.visible).override_failure_message(name).is_false()
			top = maxf(top, blocker.transform.origin.y * 2.0)  # every blocker stands on the floor
		# The collision reaches the model's top (within 5 cm): nothing is shot or walked through above.
		assert_float(top).override_failure_message(name).is_equal_approx(model.end.y, 0.05)


func test_the_tall_cabinet_has_room_for_a_wall_buy_plaque_on_end() -> void:
	var root := _fixture("tall_cabinet")
	var slot := root.get_node("PlaqueSlot") as Marker3D
	# The lot's plaque (1.7 x 0.9 x 0.12 m) under the slot, on end: inside the model, off the floor.
	var plaque := slot.transform * AABB(Vector3(-0.85, -0.45, -0.06), Vector3(1.7, 0.9, 0.12))
	var model := _model_box(root)
	assert_bool(model.encloses(plaque)).is_true()
	assert_float(plaque.size.y).is_equal_approx(1.7, 0.001)
	assert_float(plaque.position.y).is_greater(0.12)
