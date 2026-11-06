# The pieces of the walking mesh, on both maps (#1051). A path never leaves the piece it starts on,
# so a body on a piece joined to nothing is told every place is out of reach: a Rookie stood there
# for minutes (#1041). `NavmeshSplit` keeps such pieces off the walking mesh (they stay on the
# dead's).
#
# The check is the real capsule, not the rule that keeps them off. From every level of every piece
# but the map's own ground a body is flooded over the floor, the boards down, and it must not reach
# the ground the players start on, or a top reached from it, a climb of `CameraProbe.BODY_REACH` at
# most apart. It runs with every door open, the most ground; a shut room is the escape sweeps'. What
# is left on the walking mesh, each with why it is not a fault:
#
# - The ground outside the perimeter (below the lot's floor): no body gets there, `map_escape_probe`
#   and the escape sweeps hold that, so it is not walked here.
# - A pocket or a yard behind a barricade: the sill of the window (0.9 m) stops a walk even with the
#   boards torn, which the flood reads. A person who jumps a torn sill is out there and walks where
#   they like. A bot jumps only on the stuck ladder's third rung and then along its way, and the
#   walking mesh has no way across a barricade (`test_bot_breach_paths.gd`).
# - A roof or a top over the reach: the flood reads that too.
extends GdUnitTestSuite

const SMALL_MESHES := "res://world/smallmap/smallmap_navmeshes.res"
## The player's capsule (`player.tscn`), and how far off the floor it is held.
const BODY_RADIUS := 0.35
const BODY_HEIGHT := 1.8
const BODY_LIFT := 0.03
const WORLD_MASK := 1
## Metres between the spots a body is tried at.
const CELL := 0.125
## Metres past the edge of a piece a body's walk is followed: to the ground beyond a car's bonnet.
const STEP_OFF := 1.2
## The side of a bucket of the polygon lookup.
const BUCKET := 2.0
## Metres between the levels of one piece that are walked apart.
const LEVEL := 0.5
## Metres two paths may differ by and be the same path.
const SAME_PATH := 0.01
## The scrap the split used to leave at the west midway's boards (#1041).
const SCRAP := Rect2(-15.5, 30.5, 2.0, 2.0)

var _lot: Node3D
var _space: PhysicsDirectSpaceState3D
var _shape: CapsuleShape3D
var _maps: Array[RID] = []


func before_test() -> void:
	_shape = CapsuleShape3D.new()
	_shape.radius = BODY_RADIUS
	_shape.height = BODY_HEIGHT


func after_test() -> void:
	for map in _maps:
		NavigationServer3D.free_rid(map)
	_maps.clear()


## The map in the tree with every door open, and the mesh it then has.
func _opened(scene: String, saved: LotNavmeshes) -> NavigationMesh:
	_lot = auto_free((load(scene) as PackedScene).instantiate()) as Node3D
	add_child(_lot)
	for _i in NightWorld.SETTLE_FRAMES:
		await get_tree().physics_frame
	var doors := _lot.get_node("Doors") as LotDoors
	var sets := LotNavmeshes.door_sets(doors)
	for id: StringName in sets[sets.size() - 1]:
		doors.open(id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = _lot.get_world_3d().direct_space_state
	var mesh := saved.mesh_for(_lot)
	assert_object(mesh).override_failure_message("no saved mesh: bake again").is_not_null()
	return mesh


func _strips() -> Array[NavmeshSplit.Strip]:
	return NavmeshSplit.strips_of(_lot, Transform3D.IDENTITY)


func _start() -> Vector3:
	return MapLayout.new(_lot).player_markers()[0].global_position


# --- The flood ---


## The polygons of `walking` under each bucket of the ground plane, with their outlines.
class Ground:
	extends RefCounted
	var buckets: Dictionary[Vector2i, Array] = {}
	var outlines: Dictionary[int, PackedVector2Array] = {}
	var heights: Dictionary[int, float] = {}

	func _init(mesh: NavigationMesh, polygons: PackedInt32Array) -> void:
		var vertices := mesh.get_vertices()
		for index in polygons:
			var outline := PackedVector2Array()
			var box := Rect2()
			var high := -INF
			for i in mesh.get_polygon(index):
				var v := vertices[i]
				var at := Vector2(v.x, v.z)
				box = Rect2(at, Vector2.ZERO) if outline.is_empty() else box.expand(at)
				outline.append(at)
				high = maxf(high, v.y)
			outlines[index] = outline
			heights[index] = high
			var first := Vector2i((box.position / BUCKET).floor())
			var last := Vector2i((box.end / BUCKET).floor())
			for x in range(first.x, last.x + 1):
				for z in range(first.y, last.y + 1):
					var key := Vector2i(x, z)
					if not buckets.has(key):
						buckets[key] = []
					buckets[key].append(index)

	## The height of the polygon under `at` nearest `y`, or `INF` over none.
	func height_at(at: Vector2, y: float) -> float:
		var best := INF
		for index: int in buckets.get(Vector2i((at / BUCKET).floor()), []):
			if Geometry2D.is_point_in_polygon(at, outlines[index]):
				if absf(heights[index] - y) < absf(best - y):
					best = heights[index]
		return best


func _fits(at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.collision_mask = WORLD_MASK
	query.transform = Transform3D(Basis.IDENTITY, at)
	return _space.intersect_shape(query, 1).is_empty()


func _floor_under(at: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 0.3, at + Vector3.DOWN, WORLD_MASK
	)
	var hit := _space.intersect_ray(ray)
	return NAN if hit.is_empty() else float((hit["position"] as Vector3).y)


## True when a body at `start` walks (on its own level, within `limits`) over `ground` at a height
## it can climb to or from. Mesh heights are compared with mesh heights: `mesh_y` is the mesh under
## `start`.
func _walks_to(start: Vector3, mesh_y: float, limits: Rect2, ground: Ground) -> bool:
	var seen: Dictionary[Vector2i, bool] = {Vector2i.ZERO: true}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var at := Vector2(start.x + cell.x * CELL, start.z + cell.y * CELL)
		var height := ground.height_at(at, mesh_y)
		if height != INF and absf(height - mesh_y) <= CameraProbe.BODY_REACH:
			return true
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if seen.has(next):
				continue
			seen[next] = true
			var to := Vector3(start.x + next.x * CELL, start.y, start.z + next.y * CELL)
			if limits.has_point(Vector2(to.x, to.z)) and _fits(to):
				queue.append(next)
	return false


## Where a body on `piece` of `mesh` walks to `ground`: the spots, one a level. Empty for none.
func _ways_off(
	piece: NavmeshPieces.Piece, mesh: NavigationMesh, ground: Ground
) -> PackedVector3Array:
	var vertices := mesh.get_vertices()
	var limits := piece.box.grow(STEP_OFF)
	var levels: Dictionary[int, bool] = {}
	var ways := PackedVector3Array()
	for index in piece.polygons:
		var polygon := mesh.get_polygon(index)
		var middle := Vector3.ZERO
		for i in polygon:
			middle += vertices[i]
		middle /= polygon.size()
		var level := roundi(middle.y / LEVEL)
		if levels.has(level):
			continue
		var floor_y := _floor_under(middle)
		if is_nan(floor_y):
			continue
		var body := Vector3(middle.x, floor_y + BODY_HEIGHT * 0.5 + BODY_LIFT, middle.z)
		if not _fits(body):
			continue
		levels[level] = true
		if _walks_to(body, middle.y, limits, ground):
			ways.append(middle)
	return ways


## The spots on `walking`, on the map in the tree, a body gets to from the ground the players start
## on though no path joins them: a climb of the reach at most, and then from each such top to the
## next (a bonnet, then the roof).
func _faults(walking: NavigationMesh) -> PackedVector3Array:
	var pieces := NavmeshPieces.of(walking)
	var home := _piece_at(pieces, walking, _start())
	assert_object(home).override_failure_message("no piece at the players' start").is_not_null()
	var reached := PackedInt32Array(home.polygons)
	var left: Array[NavmeshPieces.Piece] = []
	for piece in pieces:
		if piece != home and piece.high > 0.0:
			left.append(piece)
	var faults := PackedVector3Array()
	var found := true
	while found:
		found = false
		var ground := Ground.new(walking, reached)
		for piece: NavmeshPieces.Piece in left.duplicate():
			var ways := _ways_off(piece, walking, ground)
			if not ways.is_empty():
				faults.append_array(ways)
				reached.append_array(piece.polygons)
				left.erase(piece)
				found = true
	return faults


func _piece_at(
	pieces: Array[NavmeshPieces.Piece], mesh: NavigationMesh, at: Vector3
) -> NavmeshPieces.Piece:
	var best: NavmeshPieces.Piece = null
	var vertices := mesh.get_vertices()
	var nearest := INF
	var flat := Vector2(at.x, at.z)
	for piece in pieces:
		for index in piece.polygons:
			var outline := PackedVector2Array()
			var low := INF
			for i in mesh.get_polygon(index):
				outline.append(Vector2(vertices[i].x, vertices[i].z))
				low = minf(low, vertices[i].y)
			if Geometry2D.is_point_in_polygon(flat, outline) and absf(low - at.y) < nearest:
				nearest = absf(low - at.y)
				best = piece
	return best


func _no_piece_a_body_walks_off(scene: String, saved: LotNavmeshes) -> void:
	var mesh := await _opened(scene, saved)
	var walking: NavigationMesh = NavmeshSplit.split(mesh, _strips())[0]
	var faults := _faults(walking)
	(
		assert_array(Array(faults))
		. override_failure_message("a body walks to the map's ground from %s" % [faults])
		. is_empty()
	)


func test_no_piece_a_body_walks_off_is_joined_to_nothing_on_the_lot() -> void:
	await _no_piece_a_body_walks_off(LotFixture.SCENE, LotNavmeshes.shared())


func test_no_piece_a_body_walks_off_is_joined_to_nothing_on_the_second_map() -> void:
	await _no_piece_a_body_walks_off(SmallMapMeasure.SCENE, load(SMALL_MESHES) as LotNavmeshes)


## The flood finds what it is for: the cut alone leaves the scrap, and the tops a body climbs to.
func test_the_check_finds_the_scrap_beside_the_west_midway_s_boards() -> void:
	var mesh := await _opened(LotFixture.SCENE, LotNavmeshes.shared())
	var walking: NavigationMesh = NavmeshSplit.split(mesh, _strips(), 0.0)[0]
	var faults := _faults(walking)
	var on_it := func(at: Vector3) -> bool: return SCRAP.has_point(Vector2(at.x, at.z))
	assert_int(Array(faults).filter(on_it).size()).is_equal(1)
	assert_int(faults.size()).is_greater(100)


# --- Every set of doors ---


func _no_scraps(scene: String, saved: LotNavmeshes) -> void:
	await _opened(scene, saved)
	var strips := _strips()
	assert_int(saved.meshes.size()).is_greater(7)
	for key: String in saved.meshes:
		var walking: NavigationMesh = NavmeshSplit.split(saved.meshes[key], strips)[0]
		var pieces := NavmeshPieces.of(walking)
		assert_float(pieces[pieces.size() - 1].area).is_greater_equal(NavmeshSplit.LEAST_PIECE)


func test_no_set_of_doors_leaves_a_scrap_on_the_lot() -> void:
	await _no_scraps(LotFixture.SCENE, LotNavmeshes.shared())


func test_no_set_of_doors_leaves_a_scrap_on_the_second_map() -> void:
	await _no_scraps(SmallMapMeasure.SCENE, load(SMALL_MESHES) as LotNavmeshes)


# --- What the mesh is made of stays ---


func _polygon_keys(mesh: NavigationMesh) -> Dictionary[String, bool]:
	var keys: Dictionary[String, bool] = {}
	var vertices := mesh.get_vertices()
	for i in mesh.get_polygon_count():
		var corners := PackedStringArray()
		for index in mesh.get_polygon(i):
			corners.append(str(vertices[index]))
		corners.sort()
		keys["|".join(corners)] = true
	return keys


## Nothing joins the walking mesh that the cut alone did not leave, and the two halves are the mesh.
func _only_leaves_the_walking_mesh(scene: String, saved: LotNavmeshes) -> void:
	var mesh := await _opened(scene, saved)
	var strips := _strips()
	var halves := NavmeshSplit.split(mesh, strips)
	var cut := _polygon_keys(NavmeshSplit.split(mesh, strips, 0.0)[0])
	var walking := _polygon_keys(halves[0])
	assert_int(walking.size()).is_less(cut.size())
	for key: String in walking:
		assert_bool(cut.has(key)).is_true()
	var gaps := _polygon_keys(halves[1])
	assert_int(walking.size() + gaps.size()).is_equal(_polygon_keys(mesh).size())


func test_polygons_only_leave_the_walking_mesh_on_the_lot() -> void:
	await _only_leaves_the_walking_mesh(LotFixture.SCENE, LotNavmeshes.shared())


func test_polygons_only_leave_the_walking_mesh_on_the_second_map() -> void:
	await _only_leaves_the_walking_mesh(SmallMapMeasure.SCENE, load(SMALL_MESHES) as LotNavmeshes)


func _navigation_of(halves: Array[NavigationMesh]) -> RID:
	var map := NavigationServer3D.map_create()
	_maps.append(map)
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_set_active(map, true)
	for i in halves.size():
		var region := NavigationServer3D.region_create()
		_maps.append(region)
		NavigationServer3D.region_set_map(region, map)
		NavigationServer3D.region_set_navigation_layers(
			region, NavLayers.WALK if i == 0 else NavLayers.GAP
		)
		NavigationServer3D.region_set_navigation_mesh(region, halves[i])
	return map


func _wait_for(map: RID, at: Vector3) -> void:
	for _i in 300:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			if NavigationServer3D.map_get_closest_point(map, at).distance_to(at) < 0.5:
				return
	fail("the map never took its mesh in")


## The dead's paths are the paths the cut alone gave.
func _paths_stay(scene: String, saved: LotNavmeshes) -> void:
	var mesh := await _opened(scene, saved)
	var strips := _strips()
	var vertices := mesh.get_vertices()
	var cut := _navigation_of(NavmeshSplit.split(mesh, strips, 0.0))
	var kept := _navigation_of(NavmeshSplit.split(mesh, strips))
	await _wait_for(cut, vertices[0])
	await _wait_for(kept, vertices[0])
	var compared := 0
	var starts := mesh.get_polygon_count()
	for i in range(0, starts, 7):
		var from := vertices[mesh.get_polygon(i)[0]]
		var to := vertices[mesh.get_polygon((i * 31 + 11) % starts)[0]]
		var before := NavigationServer3D.map_get_path(cut, from, to, true, NavLayers.DEAD)
		var after := NavigationServer3D.map_get_path(kept, from, to, true, NavLayers.DEAD)
		# A start on a scrap (an island the bake leaves between props: 207 pieces on the lot, the
		# small ones 0.2 to 25 m2) has no way in the cut alone, which is what the split fixes by giving
		# scraps to the gaps' mesh: the dead's way from there is new, not kept. Which polygons the
		# every-seventh sample lands on moves with the mesh (#1334 added 16), so the sample leaves
		# such starts out.
		if _length(before) <= 0.0:
			continue
		(
			assert_float(_length(after))
			. override_failure_message(
				"from %s to %s: %.3f m, was %.3f" % [from, to, _length(after), _length(before)]
			)
			. is_equal_approx(_length(before), SAME_PATH)
		)
		compared += 1
	assert_int(compared).is_greater(30)


func _length(path: PackedVector3Array) -> float:
	var metres := 0.0
	for i in range(1, path.size()):
		metres += path[i - 1].distance_to(path[i])
	return metres


func test_the_dead_keep_their_paths_on_the_lot() -> void:
	await _paths_stay(LotFixture.SCENE, LotNavmeshes.shared())


func test_the_dead_keep_their_paths_on_the_second_map() -> void:
	await _paths_stay(SmallMapMeasure.SCENE, load(SMALL_MESHES) as LotNavmeshes)
