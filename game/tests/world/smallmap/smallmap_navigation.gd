class_name SmallMapNavigation
extends RefCounted
## A navigation mesh baked over the second map's greybox (or any scene of CSG boxes), on a map of
## its own, to measure it: paths and their lengths, what is reachable, and the floor's area.
##
## Two kinds are baked: the zombies' mesh (`NavmeshBaker`'s sizes, what the night walks on) and
## the floor mesh (no agent radius, fine cells: the floor a body can stand on, the formula's "floor
## inside the walls"). The scene must be in the tree with its CSG built.

## More polygons than any mesh of the map has (`map_get_path` stops at 4096).
const SEARCH_POLYGONS := 1000000
const SETTLE_FRAMES := 240
const LINK_FRAMES := 3

var navmesh: NavigationMesh
var _map: RID
var _region: RID


## Bakes `root` with `mesh`'s settings and puts it on a navigation map of its own.
func _init(root: Node3D, mesh: NavigationMesh) -> void:
	navmesh = mesh
	NavigationServer3D.bake_from_source_geometry_data(mesh, NavmeshBaker.source_data(root))
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(_map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(_map, mesh.cell_height)
	NavigationServer3D.map_set_active(_map, true)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _map)
	NavigationServer3D.region_set_navigation_mesh(_region, mesh)


## The navigation map the mesh is on (for a `NavmeshPathing`).
func map() -> RID:
	return _map


## The zombies' mesh: the sizes the night bakes with.
static func zombie_mesh() -> NavigationMesh:
	return NavmeshBaker.new_navmesh()


## The floor a body stands on: no radius, 0.05 m cells, inside `box`.
static func floor_mesh(box: AABB) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = 0.05
	mesh.cell_height = 0.05
	mesh.agent_radius = 0.0
	mesh.agent_height = NavmeshBaker.AGENT_HEIGHT
	mesh.agent_max_climb = NavmeshBaker.AGENT_MAX_CLIMB
	mesh.agent_max_slope = NavmeshBaker.AGENT_MAX_SLOPE
	mesh.filter_baking_aabb = box
	return mesh


## Waits until the server has the mesh (a query on the map answers for one of its own vertices).
func settle(tree: SceneTree) -> void:
	var vertices := navmesh.get_vertices()
	for i in SETTLE_FRAMES:
		await tree.physics_frame
		if vertices.is_empty():
			return
		if NavigationServer3D.map_get_iteration_id(_map) == 0:
			continue
		if (
			NavigationServer3D.map_get_closest_point(_map, vertices[0]).distance_to(vertices[0])
			< 0.5
		):
			break
	for i in LINK_FRAMES:
		await tree.physics_frame


func free_map() -> void:
	NavigationServer3D.free_rid(_region)
	NavigationServer3D.free_rid(_map)


func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var query := NavigationPathQueryParameters3D.new()
	query.map = _map
	query.start_position = from
	query.target_position = to
	query.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL
	query.path_search_max_polygons = SEARCH_POLYGONS
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	return result.path


## True when the walk from `from` ends within `within` metres of `to` (in 3D: a floor right below
## the goal is not the goal).
func can_reach(from: Vector3, to: Vector3, within: float = 1.0) -> bool:
	var way := path(from, to)
	return not way.is_empty() and way[way.size() - 1].distance_to(to) <= within


## The length of the walk from `from` to `to` (metres, along the path), or INF when it ends more
## than a metre short.
func walk_length(from: Vector3, to: Vector3) -> float:
	var way := path(from, to)
	if way.is_empty() or way[way.size() - 1].distance_to(to) > 1.0:
		return INF
	var length := 0.0
	for i in range(1, way.size()):
		length += way[i - 1].distance_to(way[i])
	return length


## The closest the walk from `from` to `to` passes to `point` on the ground plane.
func passes_within(from: Vector3, to: Vector3, point: Vector3) -> float:
	var way := path(from, to)
	var best := INF
	for i in range(1, way.size()):
		var a := Vector2(way[i - 1].x, way[i - 1].z)
		var b := Vector2(way[i].x, way[i].z)
		var p := Vector2(point.x, point.z)
		var ab := b - a
		var t := (
			0.0
			if ab.length_squared() < 1e-6
			else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		)
		best = minf(best, (a + ab * t).distance_to(p))
	return best


## The polygons joined to the one nearest `from` (by shared edges), as indices.
func connected_polygons(from: Vector3) -> Array[int]:
	var vertices := navmesh.get_vertices()
	var count := navmesh.get_polygon_count()
	var by_edge := {}
	var nearest := -1
	var nearest_distance := INF
	for i in count:
		var polygon := navmesh.get_polygon(i)
		var centre := Vector3.ZERO
		for k in polygon.size():
			centre += vertices[polygon[k]]
			var a: int = polygon[k]
			var b: int = polygon[(k + 1) % polygon.size()]
			var edge := Vector2i(mini(a, b), maxi(a, b))
			if not by_edge.has(edge):
				by_edge[edge] = []
			by_edge[edge].append(i)
		centre /= polygon.size()
		var distance := centre.distance_to(from)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = i
	var seen := {nearest: true}
	var queue: Array[int] = [nearest]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		var polygon := navmesh.get_polygon(i)
		for k in polygon.size():
			var a: int = polygon[k]
			var b: int = polygon[(k + 1) % polygon.size()]
			for j: int in by_edge[Vector2i(mini(a, b), maxi(a, b))]:
				if not seen.has(j):
					seen[j] = true
					queue.append(j)
	var found: Array[int] = []
	for i: int in seen:
		found.append(i)
	return found


## A polygon's area on the ground plane (square metres) and its middle.
func polygon_area(index: int) -> float:
	var vertices := navmesh.get_vertices()
	var polygon := navmesh.get_polygon(index)
	var twice := 0.0
	for k in polygon.size():
		var a := vertices[polygon[k]]
		var b := vertices[polygon[(k + 1) % polygon.size()]]
		twice += a.x * b.z - b.x * a.z
	return absf(twice) * 0.5


func polygon_centre(index: int) -> Vector3:
	var vertices := navmesh.get_vertices()
	var polygon := navmesh.get_polygon(index)
	var centre := Vector3.ZERO
	for k in polygon.size():
		centre += vertices[polygon[k]]
	return centre / polygon.size()


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
