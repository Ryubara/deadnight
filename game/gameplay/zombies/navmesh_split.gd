class_name NavmeshSplit
extends RefCounted
## Cuts the polygons that lie across a barricade out of the lot's navigation mesh, into a mesh of
## their own (`NavLayers`). The baked mesh is the dead's: the gap in a fence or a wall is the way
## they come in, and the boards across it are not part of the bake. A person is stopped by the
## boards, and a path over the whole mesh sent bots through them (#995). Two regions, the mesh
## but for the gaps (for everyone) and the gaps (for the dead alone), keep both true.
##
## A polygon belongs to a gap when it crosses a barricade's line: the barricade's local X is along
## the boards, Z across them (`Barricade`). Polygons are small (a metre or two), so a few at each
## barricade go, and the walking mesh stops at the boards' line on both sides.

## Half the metres across the barricade's line that count as on it (a polygon whose edge lies on
## the line has area on both sides of this).
const HALF_DEPTH := 0.1
## Metres above and below the barricade's feet that a polygon may be and still be across it (a
## second storey's floor is above that; the mesh lies a cell or two above the floor).
const ABOVE := 1.2
const BELOW := 0.3


## One barricade's line in the mesh's own space: its transform from there to its own (X along the
## boards, Z across), the metres of boards either side of its middle and the height of its feet.
class Strip:
	extends RefCounted
	var to_local: Transform3D
	var half: float
	var feet: float
	var box: Rect2

	func _init(p_to_local: Transform3D, p_half: float, p_feet: float, p_box: Rect2) -> void:
		to_local = p_to_local
		half = p_half
		feet = p_feet
		box = p_box


## The strips of the barricades under `lot`, in the space of `space` (the region the mesh goes to).
static func strips_of(lot: Node, space: Transform3D) -> Array[Strip]:
	var strips: Array[Strip] = []
	var from_world := space.affine_inverse()
	for node in lot.find_children("*", "Barricade", true, false):
		var barricade := node as Barricade
		var at := from_world * barricade.global_transform
		var corners := PackedVector2Array()
		for corner in [
			Vector3(barricade.board_half, 0.0, 0.5),
			Vector3(-barricade.board_half, 0.0, 0.5),
			Vector3(barricade.board_half, 0.0, -0.5),
			Vector3(-barricade.board_half, 0.0, -0.5)
		]:
			var p: Vector3 = at * corner
			corners.append(Vector2(p.x, p.z))
		var box := Rect2(corners[0], Vector2.ZERO)
		for corner in corners:
			box = box.expand(corner)
		strips.append(Strip.new(at.affine_inverse(), barricade.board_half, at.origin.y, box))
	return strips


## `[walking, gaps]`: `mesh` without the polygons across a strip, and those polygons alone. The
## gaps mesh is null when no polygon crosses one. `mesh` itself is left as it is.
static func split(mesh: NavigationMesh, strips: Array[Strip]) -> Array[NavigationMesh]:
	var out: Array[NavigationMesh] = [mesh, null]
	if strips.is_empty():
		return out
	var vertices := mesh.get_vertices()
	var gap_polygons: Array[PackedInt32Array] = []
	var kept: Array[PackedInt32Array] = []
	for i in mesh.get_polygon_count():
		var polygon := mesh.get_polygon(i)
		if _crosses_a_strip(polygon, vertices, strips):
			gap_polygons.append(polygon)
		else:
			kept.append(polygon)
	if gap_polygons.is_empty():
		return out
	out[0] = _made(mesh, vertices, kept)
	out[1] = _made(mesh, vertices, gap_polygons)
	return out


static func _crosses_a_strip(
	polygon: PackedInt32Array, vertices: PackedVector3Array, strips: Array[Strip]
) -> bool:
	var low := INF
	var high := -INF
	var area := Rect2(vertices[polygon[0]].x, vertices[polygon[0]].z, 0.0, 0.0)
	for index in polygon:
		var v := vertices[index]
		area = area.expand(Vector2(v.x, v.z))
		low = minf(low, v.y)
		high = maxf(high, v.y)
	for strip in strips:
		if not strip.box.intersects(area, true) or low > strip.feet + ABOVE:
			continue
		if high < strip.feet - BELOW:
			continue
		var across := PackedVector2Array()
		for index in polygon:
			var p := strip.to_local * vertices[index]
			across.append(Vector2(p.x, p.z))
		var line := PackedVector2Array(
			[
				Vector2(-strip.half, -HALF_DEPTH),
				Vector2(strip.half, -HALF_DEPTH),
				Vector2(strip.half, HALF_DEPTH),
				Vector2(-strip.half, HALF_DEPTH)
			]
		)
		if not Geometry2D.intersect_polygons(across, line).is_empty():
			return true
	return false


## A mesh like `like` (its sizes) that holds `polygons` of `vertices` and the vertices they use.
static func _made(
	like: NavigationMesh, vertices: PackedVector3Array, polygons: Array[PackedInt32Array]
) -> NavigationMesh:
	var made := NavigationMesh.new()
	made.cell_size = like.cell_size
	made.cell_height = like.cell_height
	made.agent_height = like.agent_height
	made.agent_radius = like.agent_radius
	made.agent_max_climb = like.agent_max_climb
	made.agent_max_slope = like.agent_max_slope
	made.edge_max_error = like.edge_max_error
	var used := PackedVector3Array()
	var renumbered: Dictionary[int, int] = {}
	for polygon in polygons:
		var indices := PackedInt32Array()
		for index in polygon:
			if not renumbered.has(index):
				renumbered[index] = used.size()
				used.append(vertices[index])
			indices.append(renumbered[index])
		made.add_polygon(indices)
	made.set_vertices(used)
	return made
