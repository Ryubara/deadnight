extends GdUnitTestSuite
## The dead stand on the floor their path runs on (Deadnight #681): they rise with a ramp, a floor
## over their heads is not within a swing, and a zombie on a ramp does not shove one on the floor
## under it. A stand-in for the navigation mesh answers a straight ramp, lying `OFFSET` over it as
## the baked mesh does.

## How far above the floor the stand-in's path lies.
const OFFSET := 0.4
## The ramp climbs 1 m in 4 along x, to a floor 3 m up.
const RUN := 12.0
const RISE := 3.0


## A path along the ramp: from where the zombie stands to the top and the floor beyond it, all
## `OFFSET` high.
class RampPathing:
	extends ZombiePathing

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		var path := PackedVector3Array()
		path.append(Vector3(from.x, clampf(from.x / RUN, 0.0, 1.0) * RISE + OFFSET, from.z))
		if from.x < 0.0:
			path.append(Vector3(0.0, OFFSET, 0.0))
		if from.x < RUN:
			path.append(Vector3(RUN, RISE + OFFSET, 0.0))
		path.append(Vector3(to.x, RISE + OFFSET, to.z))
		return path

	func ground_offset() -> float:
		return OFFSET


func _sim() -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.pathing = RampPathing.new()
	return sim


func test_a_zombie_rises_with_the_ramp_and_stands_on_the_floor_at_its_top() -> void:
	var sim := _sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3(-1.0, 0.0, 0.0), 2.0)
	var highest_step := 0.0
	var last_y := zombie.position.y
	for _i in 30 * 14:
		sim.tick(ZombieFixture.STEP, {1: Vector3(RUN + 6.0, RISE, 0.0)})
		highest_step = maxf(highest_step, absf(zombie.position.y - last_y))
		last_y = zombie.position.y
	assert_float(zombie.position.y).is_equal_approx(RISE, 0.1)
	assert_float(zombie.position.x).is_greater(RUN)
	# It follows the slope, with no jump at the foot or the top.
	assert_float(highest_step).is_less(0.1)


func test_a_zombie_halfway_up_stands_halfway_up() -> void:
	var sim := _sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3(-1.0, 0.0, 0.0), 2.0)
	while zombie.position.x < RUN * 0.5:
		sim.tick(ZombieFixture.STEP, {1: Vector3(RUN + 6.0, RISE, 0.0)})
	assert_float(zombie.position.y).is_equal_approx(RISE * 0.5, 0.25)


func test_a_straight_line_path_keeps_the_height_a_zombie_has() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3(0.0, 0.7, 0.0), 2.0)
	ZombieFixture.run(sim, 3.0, {1: Vector3(8.0, 0.0, 0.0)})
	assert_float(zombie.position.y).is_equal_approx(0.7, 0.0001)


func test_a_zombie_does_not_swing_at_a_person_a_floor_over_its_head() -> void:
	var sim := ZombieFixture.sim()
	ZombieFixture.standing(sim, 1, Vector3(0.0, 0.0, 0.0), 2.0)
	var events := ZombieFixture.run(sim, 3.0, {1: Vector3(0.5, 3.9, 0.0)})
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)
	assert_int(sim.zombies[1].mode).is_not_equal(ZombieBody.Mode.ATTACK)


func test_a_zombie_swings_at_a_person_a_jump_above_it() -> void:
	var sim := ZombieFixture.sim()
	ZombieFixture.standing(sim, 1, Vector3(0.0, 0.0, 0.0), 2.0)
	var events := ZombieFixture.run(sim, 3.0, {1: Vector3(0.5, 1.2, 0.0)})
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_greater(0)


func test_zombies_on_different_floors_do_not_push_each_other() -> void:
	var sim := ZombieFixture.sim()
	var low := sim.spawn(1, 0.0, Vector3(0.0, 0.0, 0.0))
	var high := sim.spawn(2, 0.0, Vector3(0.1, 2.5, 0.0))
	low.enter(ZombieBody.Mode.CHASE)
	high.enter(ZombieBody.Mode.CHASE)
	ZombieFixture.run(sim, 1.0, {})
	assert_vector(low.position).is_equal(Vector3(0.0, 0.0, 0.0))
	assert_vector(high.position).is_equal(Vector3(0.1, 2.5, 0.0))


func test_zombies_on_one_floor_still_push_each_other() -> void:
	var sim := ZombieFixture.sim()
	var a := sim.spawn(1, 0.0, Vector3(0.0, 2.5, 0.0))
	var b := sim.spawn(2, 0.0, Vector3(0.1, 2.5, 0.0))
	a.enter(ZombieBody.Mode.CHASE)
	b.enter(ZombieBody.Mode.CHASE)
	ZombieFixture.run(sim, 1.0, {})
	assert_float(a.position.distance_to(b.position)).is_greater(0.5)
