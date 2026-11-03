extends SceneTree
## What `LotBatcher` does to the drive-in lot (#728): the surfaces and triangles drawn before and
## after, the cells, the time it takes, and which parts of the lot it leaves alone.
##
## godot --headless --path game -s res://tools/lot/batch_report.gd -- [--cell=24] [--small=0]

const GREYBOX := preload("res://world/drive_in_greybox.tscn")


func _init() -> void:
	var args := NetArgs.new()
	var lot := GREYBOX.instantiate()
	root.add_child(lot)
	for _i in 6:
		await physics_frame
	var before := _count(lot)
	var stats := LotBatcher.batch(
		lot, args.get_float("cell", MeshBatch.DEFAULT_CELL), args.get_float("small", 0.0)
	)
	await process_frame
	var after := _count(lot)
	print("before: ", before)
	print("after:  ", after)
	print("batcher: ", stats)
	var left := {}
	for node in lot.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.is_visible_in_tree() and not _in_batch(mesh_node):
			var key := _scene_of(mesh_node, lot)
			left[key] = int(left.get(key, 0)) + mesh_node.mesh.get_surface_count()
	print("mesh surfaces left as they were, by scene: ", left)
	quit()


func _in_batch(node: Node) -> bool:
	return node.get_parent() != null and node.get_parent().name == LotBatcher.BATCH_NODE


func _scene_of(node: Node, lot: Node) -> String:
	var at := node
	while at != null and at != lot:
		if at.scene_file_path.get_extension() == "tscn":
			return at.scene_file_path.get_file().get_basename()
		at = at.get_parent()
	return "(lot)"


## Surfaces and triangles the renderer is asked for: the meshes seen, and the roots of the seen CSG
## boxes.
func _count(lot: Node) -> Dictionary:
	var surfaces := 0
	var triangles := 0
	var csg_surfaces := 0
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
		var mesh := built[1] as Mesh
		for surface in mesh.get_surface_count():
			csg_surfaces += 1
			triangles += _triangles(mesh, surface)
	return {"mesh_surfaces": surfaces, "csg_surfaces": csg_surfaces, "triangles": triangles}


func _triangles(mesh: Mesh, surface: int) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.is_empty():
		return 0
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices != null and (indices as PackedInt32Array).size() > 0:
		return (indices as PackedInt32Array).size() / 3
	var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
	return (vertices as PackedVector3Array).size() / 3 if vertices != null else 0
