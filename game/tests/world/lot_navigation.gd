class_name LotNavigation
extends RefCounted
## A navigation mesh baked over the greybox for one agent size, to ask where that agent can walk.
##
## The mesh is baked from the scene's own CSG boxes, so closed door slabs are walls and removed ones
## are not. The agent is a vertical capsule: the player (0.35 m), or the player plus the shoulder
## camera (0.9 m).

const CELL_SIZE := 0.05
const AGENT_HEIGHT := 1.8
## The server takes a new region in over two map iterations, a few physics ticks each; give up after
## this many.
const SETTLE_FRAMES := 120
## The lot is 124 m by 116 m; the outskirts slab is below y = -0.3 and left out.
const BAKE_BOX := AABB(Vector3(-66.0, -0.3, -56.0), Vector3(132.0, 9.0, 124.0))

var navmesh: NavigationMesh
var _map: RID
var _first_iteration := 0


## Bakes `lot` (already in the tree, its CSG built) for an agent of `agent_radius` metres.
func _init(lot: Node3D, agent_radius: float) -> void:
	var mesh := NavigationMesh.new()
	mesh.cell_size = CELL_SIZE
	mesh.cell_height = CELL_SIZE
	mesh.agent_radius = agent_radius
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_max_climb = 0.3
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
	_first_iteration = NavigationServer3D.map_get_iteration_id(_map)


## Waits until the navigation server has the new mesh. Call it once after `new`, before asking
## anything.
func settle(tree: SceneTree) -> void:
	for i in SETTLE_FRAMES:
		await tree.physics_frame
		if NavigationServer3D.map_get_iteration_id(_map) >= _first_iteration + 2:
			return


## True when the agent can walk from `from` to within `within` metres of `to`.
func can_reach(from: Vector3, to: Vector3, within: float = 1.0) -> bool:
	var path := NavigationServer3D.map_get_path(_map, from, to, false)
	return not path.is_empty() and path[path.size() - 1].distance_to(to) <= within


## How close the agent gets to `to` starting at `from`, in metres.
func nearest_approach(from: Vector3, to: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(_map, from, to, false)
	return INF if path.is_empty() else path[path.size() - 1].distance_to(to)


func _add_csg_faces(source: NavigationMeshSourceGeometryData3D, node: Node) -> void:
	if node is CSGShape3D and (node as CSGShape3D).is_root_shape():
		var csg := node as CSGShape3D
		source.add_faces(csg.bake_collision_shape().get_faces(), csg.global_transform)
	for child in node.get_children():
		_add_csg_faces(source, child)
