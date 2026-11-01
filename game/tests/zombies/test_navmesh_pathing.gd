extends GdUnitTestSuite
## Paths through a baked navigation mesh, with no zombie nodes: the wall in the way is walked
## around, and a zombie in a sim follows that path.

var _root: Node3D
var _iteration_before := 0


func before_test() -> void:
	_root = auto_free(Node3D.new())
	_root.add_child(_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40)))  # ground, top at y = 0
	_root.add_child(_box(Vector3(0, 1.5, 0), Vector3(1, 3, 20)))  # a wall across x = 0
	add_child(_root)
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	_root = null


func _box(at: Vector3, size: Vector3) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.use_collision = true
	box.size = size
	box.position = at
	return box


func _pathing() -> NavmeshPathing:
	var region := NavigationRegion3D.new()
	region.navigation_mesh = NavmeshBaker.bake(_root)
	var map := _root.get_world_3d().navigation_map
	_iteration_before = NavigationServer3D.map_get_iteration_id(map)
	_root.add_child(region)
	return NavmeshPathing.new(map)


func test_the_baked_mesh_has_ground_to_walk_on() -> void:
	var navmesh := NavmeshBaker.bake(_root)
	assert_int(navmesh.get_polygon_count()).is_greater(0)


func test_a_path_goes_around_a_wall_not_through_it() -> void:
	var pathing := _pathing()
	await _map_ready(pathing.map)
	var path := pathing.find_path(Vector3(-10, 0, 0), Vector3(10, 0, 0))
	assert_int(path.size()).is_greater(2)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	# Straight is 20 m; round the wall's end at z = 10 is about 28 m.
	assert_float(length).is_greater(26.0)
	for point in path:
		assert_bool(absf(point.x) < 0.5 and absf(point.z) < 10.0).is_false()


func test_a_zombie_follows_the_path_round_the_wall() -> void:
	var pathing := _pathing()
	await _map_ready(pathing.map)
	var sim := ZombieFixture.sim()
	sim.pathing = pathing
	ZombieFixture.standing(sim, 1, Vector3(-10, 0, 0), 3.0)
	var crossed_wall_line_inside_wall := false
	for _i in 300:
		sim.tick(ZombieSim.STEP, {1: Vector3(10, 0, 0)})
		var p := sim.zombies[1].position
		if absf(p.x) < 0.4 and absf(p.z) < 9.5:
			crossed_wall_line_inside_wall = true
	assert_bool(crossed_wall_line_inside_wall).is_false()
	assert_float(sim.zombies[1].position.x).is_greater(2.0)


## A region added to a map shows in its queries only after a few physics frames (the map updates
## in iterations): wait for the second after the region joined.
func _map_ready(map: RID) -> void:
	for _i in 20:
		if NavigationServer3D.map_get_iteration_id(map) >= _iteration_before + 2:
			return
		await get_tree().physics_frame
