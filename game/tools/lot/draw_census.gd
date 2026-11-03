extends SceneTree
## Counts what the drive-in lot asks the renderer to draw (#728): the mesh surfaces (one draw call
## each, before any merging), the triangles, the distinct meshes and materials, per area and per
## kind of prop, so a cut goes to where the calls are.
##
## godot --headless --path game -s res://tools/lot/draw_census.gd
##
## Meshes of the lot only (no crowd, no weapons); a surface counts when it and every parent is
## visible.

const GREYBOX := preload("res://world/drive_in_greybox.tscn")


func _init() -> void:
	var lot := GREYBOX.instantiate()
	root.add_child(lot)
	await process_frame
	await process_frame
	var by_area := {}
	var by_kind := {}
	var meshes := {}
	var materials := {}
	var total_surfaces := 0
	var total_tris := 0
	var instances := 0
	for node in lot.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		instances += 1
		var area := _area_of(lot, mi)
		var kind := _kind_of(lot, mi)
		meshes[mi.mesh] = true
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			materials[mat] = true
			var tris := _tris(mi.mesh, s)
			total_surfaces += 1
			total_tris += tris
			_add(by_area, area, tris)
			_add(by_kind, kind, tris)
	print(
		(
			"lot mesh instances: %d, surfaces: %d, triangles: %d"
			% [instances, total_surfaces, total_tris]
		)
	)
	print("distinct meshes: %d, distinct materials: %d" % [meshes.size(), materials.size()])
	print("\nBy area (surfaces, triangles)")
	_print_sorted(by_area)
	print("\nBy kind (surfaces, triangles)")
	_print_sorted(by_kind)
	var roots := {}
	var csg_hidden := 0
	for node in lot.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if not shape.is_visible_in_tree():
			csg_hidden += 1
		elif not (shape.get_parent() is CSGShape3D):
			_add(roots, _kind_of(lot, shape), 0)
	var root_count := 0
	for k: String in roots:
		root_count += roots[k][0]
	print("\nCSG roots drawn (one mesh each): %d, hidden shapes: %d" % [root_count, csg_hidden])
	_print_sorted(roots)
	var lights := lot.find_children("*", "Light3D", true, false).size()
	print("lights: %d" % lights)
	quit()


func _tris(mesh: Mesh, surface: int) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.is_empty():
		return 0
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	if idx != null and (idx as PackedInt32Array).size() > 0:
		return (idx as PackedInt32Array).size() / 3
	var v: Variant = arrays[Mesh.ARRAY_VERTEX]
	return (v as PackedVector3Array).size() / 3 if v != null else 0


func _area_of(lot: Node, node: Node) -> String:
	var n := node
	while n.get_parent() != null and n.get_parent() != lot:
		n = n.get_parent()
	return String(n.name)


func _kind_of(lot: Node, node: Node) -> String:
	# The scene file the nearest instanced ancestor came from; a node of the lot's own file is
	# "(lot)".
	var n := node
	while n != null and n != lot:
		if n.scene_file_path != "" and n.scene_file_path.get_extension() == "tscn":
			return n.scene_file_path.get_file().get_basename()
		n = n.get_parent()
	return "(lot)"


func _add(into: Dictionary, key: String, tris: int) -> void:
	var row: Array = into.get(key, [0, 0])
	row[0] += 1
	row[1] += tris
	into[key] = row


func _print_sorted(rows: Dictionary) -> void:
	var keys := rows.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return rows[a][0] > rows[b][0])
	for k: String in keys:
		print("  %-28s %4d %8d" % [k, rows[k][0], rows[k][1]])
