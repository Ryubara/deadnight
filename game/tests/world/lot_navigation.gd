class_name LotNavigation
extends RefCounted
## A navigation mesh baked over the greybox for one agent size, to ask where that agent can walk.
##
## The mesh is baked from the scene's own CSG boxes, so closed door slabs are walls and removed ones
## are not. The agent is a vertical capsule: the player (read from `PlayerTuning`), or the player
## plus the shoulder camera (0.9 m). `max_climb` is how high a step the agent takes: the default is
## walking, the player's jump height asks where a jump could land.

const CELL_SIZE := 0.05
const AGENT_HEIGHT := 1.8
## The server takes a new region in over a few map iterations, and links on the map count as
## iterations too, so the iteration id says nothing: `settle` waits until the map answers for the
## mesh's own first vertex, then a few frames more for the links to join. Give up after this many
## frames.
const SETTLE_FRAMES := 120
const LINK_FRAMES := 3
## More polygons than the lot's mesh has.
const SEARCH_POLYGONS := 1000000
## The lot is 124 m by 116 m; the outskirts slab is below y = -0.3 and left out.
const BAKE_BOX := AABB(Vector3(-66.0, -0.3, -56.0), Vector3(132.0, 9.0, 124.0))

const WALK_CLIMB := 0.3

var navmesh: NavigationMesh
var _map: RID


## Bakes `lot` (already in the tree, its CSG built) for an agent of `agent_radius` metres.
func _init(lot: Node3D, agent_radius: float, max_climb: float = WALK_CLIMB) -> void:
	var mesh := NavigationMesh.new()
	mesh.cell_size = CELL_SIZE
	mesh.cell_height = CELL_SIZE
	mesh.agent_radius = agent_radius
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_max_climb = max_climb
	mesh.agent_max_slope = 40.0
	mesh.filter_baking_aabb = BAKE_BOX
	var source := NavigationMeshSourceGeometryData3D.new()
	# The renderer is a dummy when the tests run headless, so the visual meshes are empty: take the
	# CSG shapes' faces.
	_add_csg_faces(source, lot)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	navmesh = mesh
	# A region in the lot's own world, so it is gone with the lot. The server applies it on the next
	# physics tick: the caller awaits `settle` before asking.
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	lot.add_child(region)
	_map = lot.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(_map, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(_map, CELL_SIZE)


## Waits until the navigation server has the new mesh. Call it once after `new`, before asking
## anything.
func settle(tree: SceneTree) -> void:
	var vertices := navmesh.get_vertices()
	for i in SETTLE_FRAMES:
		await tree.physics_frame
		if vertices.is_empty():
			return
		# A query before the map's first synchronisation is an engine error.
		if NavigationServer3D.map_get_iteration_id(_map) == 0:
			continue
		if (
			NavigationServer3D.map_get_closest_point(_map, vertices[0]).distance_to(vertices[0])
			< 0.5
		):
			break
	for i in LINK_FRAMES:
		await tree.physics_frame


## The polygon corners of the way from `from` to the nearest reachable point to `to`. The plain
## `map_get_path` stops its search after 4096 polygons, which a 0.05 m mesh of the whole lot exceeds
## when the target cannot be reached (an engine error, and a wrong answer): search without a limit.
## `shortest` pulls the way tight round the corners (the funnel), for measuring its length; the edge
## centres it goes through by default zigzag.
func path(from: Vector3, to: Vector3, shortest := false) -> PackedVector3Array:
	var query := NavigationPathQueryParameters3D.new()
	query.map = _map
	query.start_position = from
	query.target_position = to
	query.path_postprocessing = (
		NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL
		if shortest
		else NavigationPathQueryParameters3D.PATH_POSTPROCESSING_EDGECENTERED
	)
	query.path_search_max_polygons = SEARCH_POLYGONS
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	return result.path


## True when the agent can walk from `from` to within `within` metres of `to`.
func can_reach(from: Vector3, to: Vector3, within: float = 1.0) -> bool:
	var way := path(from, to)
	return not way.is_empty() and way[way.size() - 1].distance_to(to) <= within


## How close the agent gets to `to` starting at `from`, in metres.
func nearest_approach(from: Vector3, to: Vector3) -> float:
	var way := path(from, to)
	return INF if way.is_empty() else way[way.size() - 1].distance_to(to)


func _add_csg_faces(source: NavigationMeshSourceGeometryData3D, node: Node) -> void:
	if node is CSGShape3D and (node as CSGShape3D).is_root_shape():
		var csg := node as CSGShape3D
		source.add_faces(csg.bake_collision_shape().get_faces(), csg.global_transform)
	for child in node.get_children():
		_add_csg_faces(source, child)
