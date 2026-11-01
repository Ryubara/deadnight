# The Usher's trouser stripe is one straight band (#140): the stripe is cut into the trouser
# mesh between two planes, so every vertex of its faces lies between them. Painted on whole faces
# by their centre, the band's faces reached past both edges in sawtooth teeth.
extends GdUnitTestSuite

const PART := "legs__striped"
## The band's width at kit scale: 2 x 45 mm (`STRIPE_HALF` in tools/blender/build_soldier_parts.py),
## and what a vertex may stray past it (float precision of the cut).
const WIDTH := 0.09
const SLACK := 0.004


## The accent faces' vertices of the striped trousers, in the part's own space.
func _band_vertices() -> PackedVector3Array:
	var model := SoldierLook.instantiate()
	add_child(auto_free(model))
	var mesh_instance := model.find_child(PART, true, false) as MeshInstance3D
	assert_object(mesh_instance).is_not_null()
	var catalog := SoldierLook.catalog()
	var atlas: Dictionary = catalog["atlas"]
	var cell: Array = atlas["cells"]["accent"]
	var size: Array = atlas["size"]
	var px: float = atlas["swatch_px"]
	var centre := Vector2(
		(cell[0] + 0.5) * px / float(size[0]), (cell[1] + 0.5) * px / float(size[1])
	)
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var half := Vector2(0.5 * px / float(size[0]), 0.5 * px / float(size[1]))
	var band := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		var uv := uvs[indices[i]]
		# The atlas is read with V either way up; a face is accent when its UV is in the cell.
		var in_cell := absf(uv.x - centre.x) < half.x
		in_cell = (
			in_cell and (absf(uv.y - centre.y) < half.y or absf(1.0 - uv.y - centre.y) < half.y)
		)
		if in_cell:
			for k in 3:
				band.append(vertices[indices[i + k]])
	return band


func test_the_stripe_is_a_straight_band_on_each_leg() -> void:
	var band := _band_vertices()
	assert_int(band.size()).is_greater(0)
	for side in [-1.0, 1.0]:
		var low := INF
		var high := -INF
		for v in band:
			if v.x * side > 0.0:
				low = minf(low, v.z)
				high = maxf(high, v.z)
		# Front to back (glTF Z is the kit's Y), the band is exactly as wide as the cut.
		(
			assert_float(high - low)
			. override_failure_message(
				(
					"the %s leg's stripe spans %.3f m front to back"
					% ["left" if side > 0 else "right", high - low]
				)
			)
			. is_less_equal(WIDTH + SLACK)
		)
		assert_float(high - low).is_greater(WIDTH * 0.8)
