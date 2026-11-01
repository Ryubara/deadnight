class_name NavmeshBaker
extends RefCounted
## Bakes a navigation mesh from a scene built of CSG boxes (the greybox lot). The standard parser
## ignores CSG nodes, so their meshes are handed to the baker directly. The world owner should
## bake once in the editor and ship the saved mesh; this is for greybox scenes and tests.

## A multiple of the cell sizes (the baker warns and disconnects regions otherwise).
const CELL_SIZE := 0.25
const AGENT_HEIGHT := 1.75
const AGENT_RADIUS := 0.5
const AGENT_MAX_CLIMB := 0.25
const AGENT_MAX_SLOPE := 45.0


static func bake(root: Node3D) -> NavigationMesh:
	var navmesh := new_navmesh()
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source_data(root))
	return navmesh


## Bakes on the server's worker threads, from the scene as it is now (the geometry is read before
## this returns, so the scene may change at once). `done` is called on the main thread with the
## finished mesh. One bake of the lot takes about a second.
static func bake_async(root: Node3D, done: Callable) -> void:
	var navmesh := new_navmesh()
	NavigationServer3D.bake_from_source_geometry_data_async(
		navmesh, source_data(root), func() -> void: done.call(navmesh)
	)


## The collision boxes of `root`'s CSG shapes, as the baker's input.
static func source_data(root: Node3D) -> NavigationMeshSourceGeometryData3D:
	var data := NavigationMeshSourceGeometryData3D.new()
	for node in root.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if shape.use_collision:
			data.add_faces(_box_faces(_size_of(shape)), shape.global_transform)
	return data


static func new_navmesh() -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = CELL_SIZE
	navmesh.cell_height = CELL_SIZE
	navmesh.agent_height = AGENT_HEIGHT
	navmesh.agent_radius = AGENT_RADIUS
	navmesh.agent_max_climb = AGENT_MAX_CLIMB
	navmesh.agent_max_slope = AGENT_MAX_SLOPE
	return navmesh


## Every collision shape in the greybox is a box or a cylinder; a cylinder is baked as the box
## around it, which is slightly wider for an obstacle.
static func _size_of(shape: CSGShape3D) -> Vector3:
	if shape is CSGBox3D:
		return (shape as CSGBox3D).size
	if shape is CSGCylinder3D:
		var cylinder := shape as CSGCylinder3D
		return Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
	return Vector3.ZERO


static func _box_faces(size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(
			Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		)
	# Two triangles a face, wound outward; the indices are corners of the cube by bit (x, y, z).
	var quads := [
		[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]
	]
	var faces := PackedVector3Array()
	for quad in quads:
		for index in [0, 1, 2, 0, 2, 3]:
			faces.append(corners[quad[index]])
	return faces
