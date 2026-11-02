extends GdUnitTestSuite
## How often a zombie asks for its path (issue #156: path queries were a third of the server's time
## in a crowd, and most of the crowd stood swinging at the players or far across the lot).


## Counts the paths asked for, answering with the straight line.
class CountingPathing:
	extends ZombiePathing

	var calls := 0

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		calls += 1
		return PackedVector3Array([from, to])


func _sim() -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.pathing = CountingPathing.new()
	return sim


func _calls(sim: ZombieSim) -> int:
	return (sim.pathing as CountingPathing).calls


func test_a_zombie_near_its_target_asks_every_repath_interval() -> void:
	var sim := _sim()
	ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	var seconds := 5.0
	ZombieFixture.run(sim, seconds, {1: Vector3(8, 0, 0)})
	var expected := seconds / sim.tuning.repath_interval
	assert_float(float(_calls(sim))).is_between(expected - 2.0, expected + 2.0)


func test_a_zombie_far_from_its_target_asks_less_often() -> void:
	var sim := _sim()
	ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	var seconds := 5.0
	ZombieFixture.run(sim, seconds, {1: Vector3(sim.tuning.repath_far_distance + 10.0, 0, 0)})
	var expected := seconds / (sim.tuning.repath_interval * sim.tuning.repath_far_factor)
	assert_float(float(_calls(sim))).is_between(expected - 2.0, expected + 2.0)


func test_a_zombie_that_is_swinging_asks_for_no_path_and_asks_when_it_walks_again() -> void:
	var sim := _sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	# Right at the target: it swings, again and again, and has no use for a way there.
	ZombieFixture.run(sim, 0.3, {1: Vector3(0.5, 0, 0)})
	var before := _calls(sim)
	var swung := 0
	for _i in ceili(4.0 / ZombieFixture.STEP):
		sim.tick(ZombieFixture.STEP, {1: Vector3(0.5, 0, 0)})
		if zombie.mode == ZombieBody.Mode.ATTACK:
			swung += 1
	assert_int(swung).is_greater(20)
	assert_int(_calls(sim)).is_less_equal(before + 4)
	# The player runs off: the first tick it chases again it asks, before it walks.
	var asked := _calls(sim)
	var guard := 0
	while zombie.mode != ZombieBody.Mode.CHASE and guard < 200:
		sim.tick(ZombieFixture.STEP, {1: Vector3(12, 0, 0)})
		guard += 1
	sim.tick(ZombieFixture.STEP, {1: Vector3(12, 0, 0)})
	assert_int(_calls(sim)).is_greater(asked)
	assert_float(zombie.path[zombie.path.size() - 1].x).is_equal_approx(12.0, 0.01)


func test_a_zombie_that_is_still_rising_asks_for_nothing() -> void:
	var sim := _sim()
	sim.spawn(1, 2.0, Vector3.ZERO)
	ZombieFixture.run(sim, 0.4, {1: Vector3(10, 0, 0)})
	assert_int(_calls(sim)).is_equal(0)
