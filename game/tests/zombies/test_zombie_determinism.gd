extends GdUnitTestSuite
## The sim on a real navigation mesh is a pure function of its seed and its inputs: the same
## seed gives the same state on every tick, another seed does not, and the way the caller slices
## time does not matter. A wall across the lot makes the paths bend, so the paths, the repath
## phases and the pushing all take part.

const TICKS := 600  # 20 s
const WALL_HALF_WIDTH := 0.5
const WALL_HALF_LENGTH := 10.0

var _root: Node3D
var _pathing: NavmeshPathing


func before_test() -> void:
	_root = auto_free(Node3D.new())
	_root.add_child(_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40)))  # ground, top at y = 0
	_root.add_child(_box(Vector3(0, 1.5, 0), Vector3(1, 3, 20)))  # a wall across x = 0
	add_child(_root)
	await await_idle_frame()
	await await_idle_frame()
	var region := NavigationRegion3D.new()
	region.navigation_mesh = NavmeshBaker.bake(_root)
	var map := _root.get_world_3d().navigation_map
	var iteration_before := NavigationServer3D.map_get_iteration_id(map)
	_root.add_child(region)
	_pathing = NavmeshPathing.new(map)
	# A region added to a map shows in its queries after the map's second iteration.
	for _i in 20:
		if NavigationServer3D.map_get_iteration_id(map) >= iteration_before + 2:
			break
		await get_tree().physics_frame


func after_test() -> void:
	_root = null


func _box(at: Vector3, size: Vector3) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.use_collision = true
	box.size = size
	box.position = at
	return box


func _world(p_seed: int) -> ZombieSim:
	var sim := ZombieSim.new(ZombieTuning.new(), p_seed)
	sim.pathing = _pathing
	for i in 16:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * (6.0 + i % 5), 0.0, -12.0 + 1.5 * i)
		sim.spawn(i + 1, 1.2 + 0.1 * i, at).enter(ZombieBody.Mode.CHASE)
	return sim


## The running state hash after each tick; `slices` cuts each fixed step into that many caller
## deltas.
func _trace(p_seed: int, slices: int = 1) -> Array[int]:
	var sim := _world(p_seed)
	var targets := {1: Vector3(-12, 0, 0), 2: Vector3(12, 0, 8)}
	var hashes: Array[int] = []
	var running := 0
	for _i in TICKS:
		for _s in slices:
			sim.tick(ZombieSim.STEP / slices, targets)
		running = ZombieFixture.state_hash(sim, running)
		hashes.append(running)
	_assert_clear_of_the_wall(sim)
	return hashes


func _assert_clear_of_the_wall(sim: ZombieSim) -> void:
	for zombie: ZombieBody in sim.zombies.values():
		var p := zombie.position
		assert_bool(absf(p.x) < WALL_HALF_WIDTH and absf(p.z) < WALL_HALF_LENGTH).is_false()


func test_the_same_seed_gives_the_same_state_on_every_tick() -> void:
	assert_array(_trace(21)).is_equal(_trace(21))


func test_another_seed_gives_another_run() -> void:
	assert_array(_trace(21)).is_not_equal(_trace(22))


func test_slicing_the_time_finer_does_not_change_the_run() -> void:
	var reference := _trace(21)
	assert_array(_trace(21, 2)).is_equal(reference)
	assert_array(_trace(21, 4)).is_equal(reference)
