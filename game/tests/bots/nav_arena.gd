class_name NavArena
extends RefCounted
## A small walking mesh built from squares of ground, in a navigation map of its own, for the unit
## tests of the bots' movement: a room, an L, a corridor, a ledge. A square is `CELL` metres; the
## squares share their corners, so neighbours are joined. `sight` answers the way the bots'
## level does (metres to the first wall, -1 when clear) by treating everything off the ground as
## wall, so a heading that leaves the ground is stopped like one that meets a wall.

const CELL := 2.0

var map: RID
var region: RID
var cells: Dictionary = {}

var _vertices := PackedVector3Array()
var _index: Dictionary = {}


## `shape` is rows of text from the north (smaller z) down, '#' is ground, anything else is not.
## The first column, first row starts at the origin.
static func from_rows(rows: Array[String]) -> NavArena:
	var arena := NavArena.new()
	for z in rows.size():
		for x in rows[z].length():
			if rows[z][x] == "#":
				arena.cells[Vector2i(x, z)] = true
	arena._build()
	return arena


## The level a bot is given in this arena.
func level() -> BotLevel:
	var made := BotLevel.new(Callable(self, &"sight"), Callable(self, &"is_lit"), null, map)
	return made


func is_lit(_point: Vector3) -> bool:
	return true


## The centre of square (`x`, `z`) on the ground.
func centre(x: int, z: int) -> Vector3:
	return Vector3((float(x) + 0.5) * CELL, 0.0, (float(z) + 0.5) * CELL)


func on_ground(point: Vector3) -> bool:
	return cells.has(Vector2i(floori(point.x / CELL), floori(point.z / CELL)))


## Metres to the first point of the segment that is off the ground, or -1.
func sight(from: Vector3, to: Vector3) -> float:
	var length := Vector2(to.x - from.x, to.z - from.z).length()
	var steps := maxi(ceili(length / 0.1), 1)
	for i in range(1, steps + 1):
		var at := from.lerp(to, float(i) / float(steps))
		if not on_ground(at):
			return length * float(i) / float(steps)
	return -1.0


## Waits until the map answers for the mesh (a new region is taken in over a few frames).
func settle(tree: SceneTree) -> void:
	var first := centre(cells.keys()[0].x, cells.keys()[0].y)
	for _i in 60:
		await tree.physics_frame
		if NavigationServer3D.map_get_iteration_id(map) < 1:
			continue
		if NavigationServer3D.map_get_closest_point(map, first).distance_to(first) < 0.5:
			return


## Frees the map and the region.
func dispose() -> void:
	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)


func _build() -> void:
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, 0.25)
	NavigationServer3D.map_set_active(map, true)
	region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	swap_in()
	NavigationServer3D.map_force_update(map)


## Puts a fresh mesh of the same ground into the region, as a door opening does in the lot (the
## map takes it in over its next iteration).
func swap_in() -> void:
	var mesh := NavigationMesh.new()
	_vertices = PackedVector3Array()
	_index = {}
	var keys := cells.keys()
	keys.sort()
	for key: Vector2i in keys:
		# Clockwise seen from above, as the engine wants.
		(
			mesh
			. add_polygon(
				PackedInt32Array(
					[
						_corner(key.x, key.y),
						_corner(key.x + 1, key.y),
						_corner(key.x + 1, key.y + 1),
						_corner(key.x, key.y + 1),
					]
				)
			)
		)
	mesh.vertices = _vertices
	NavigationServer3D.region_set_navigation_mesh(region, mesh)


## The index of the corner at grid point (`x`, `z`), added on first use.
func _corner(x: int, z: int) -> int:
	var key := Vector2i(x, z)
	if not _index.has(key):
		_index[key] = _vertices.size()
		_vertices.append(Vector3(float(x) * CELL, 0.0, float(z) * CELL))
	return _index[key]
