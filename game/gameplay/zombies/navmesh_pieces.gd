class_name NavmeshPieces
extends RefCounted
## The pieces of a navigation mesh: polygons joined by a shared edge, the way a path can go. A path
## never leaves the piece it starts on, so a body on a piece apart from the rest has nowhere to go
## (`NavmeshSplit`, #1051).


## One piece: its polygons (indices into the list it was found in), the ground it covers and where.
class Piece:
	extends RefCounted
	var polygons := PackedInt32Array()
	## Square metres on the ground plane.
	var area := 0.0
	## The height of its vertices, lowest and highest.
	var low := INF
	var high := -INF
	## Where it lies on the ground plane (x, z).
	var box := Rect2()


## The pieces of `mesh`, the largest first.
static func of(mesh: NavigationMesh) -> Array[Piece]:
	var polygons: Array[PackedInt32Array] = []
	for i in mesh.get_polygon_count():
		polygons.append(mesh.get_polygon(i))
	return among(polygons, mesh.get_vertices())


## The pieces of `polygons` (lists of indices into `vertices`), the largest first.
static func among(polygons: Array[PackedInt32Array], vertices: PackedVector3Array) -> Array[Piece]:
	var parents := PackedInt32Array()
	parents.resize(polygons.size())
	for i in polygons.size():
		parents[i] = i
	var by_edge: Dictionary[Vector2i, int] = {}
	for i in polygons.size():
		var polygon := polygons[i]
		for j in polygon.size():
			var a := polygon[j]
			var b := polygon[(j + 1) % polygon.size()]
			var edge := Vector2i(mini(a, b), maxi(a, b))
			if by_edge.has(edge):
				parents[_root(parents, i)] = _root(parents, by_edge[edge])
			else:
				by_edge[edge] = i
	var found: Dictionary[int, Piece] = {}
	for i in polygons.size():
		var root := _root(parents, i)
		if not found.has(root):
			found[root] = Piece.new()
		_add(found[root], i, polygons[i], vertices)
	var pieces: Array[Piece] = []
	pieces.assign(found.values())
	pieces.sort_custom(func(a: Piece, b: Piece) -> bool: return a.area > b.area)
	return pieces


static func _add(
	piece: Piece, index: int, polygon: PackedInt32Array, vertices: PackedVector3Array
) -> void:
	var first := vertices[polygon[0]]
	if piece.polygons.is_empty():
		piece.box = Rect2(first.x, first.z, 0.0, 0.0)
	piece.polygons.append(index)
	for j in polygon.size():
		var v := vertices[polygon[j]]
		piece.box = piece.box.expand(Vector2(v.x, v.z))
		piece.low = minf(piece.low, v.y)
		piece.high = maxf(piece.high, v.y)
		if j >= 1 and j < polygon.size() - 1:
			var next := vertices[polygon[j + 1]]
			var u := Vector2(v.x - first.x, v.z - first.z)
			var w := Vector2(next.x - first.x, next.z - first.z)
			piece.area += absf(u.cross(w)) * 0.5


static func _root(parents: PackedInt32Array, i: int) -> int:
	while parents[i] != i:
		parents[i] = parents[parents[i]]
		i = parents[i]
	return i
