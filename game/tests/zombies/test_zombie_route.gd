extends GdUnitTestSuite
## A target that stands where the walking mesh is not (between two parked cars) is reached at the
## nearest point of the mesh, and that point changes as the target shuffles a metre: the way round
## the other side is 20 m longer. A dead that turned back at every repath walked up and down between
## the two routes for ever while a round waited for it (#950, found by the soak: six dead at the
## cars for seven minutes).

const WEST := Vector3(-1.5, 0.0, -8.0)
const EAST := Vector3(1.5, 0.0, -8.0)
const FAR_AROUND := Vector3(30.0, 0.0, -2.0)


## The nearest-point answer of a mesh with an obstacle between two goals: a target left of the
## middle is reached at WEST by a short way, one right of it at EAST by a long one round.
class TwoWays:
	extends ZombiePathing

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		if to.x < 0.0:
			return PackedVector3Array([from, WEST])
		return PackedVector3Array([from, FAR_AROUND, EAST])


func _sim() -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.pathing = TwoWays.new()
	return sim


func test_a_target_that_shuffles_across_the_middle_does_not_turn_the_dead_round() -> void:
	var sim := _sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	var sides := [Vector3(-1.0, 0.0, -10.0), Vector3(1.0, 0.0, -10.0)]
	for second in 12:
		ZombieFixture.run(sim, 1.0, {1: sides[second % 2]})
	assert_float(zombie.position.z).is_less(-6.0)
	assert_float(absf(zombie.position.x)).is_less(3.0)


func test_a_route_that_is_not_much_longer_is_taken() -> void:
	var sim := _sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	ZombieFixture.run(sim, 0.3, {1: Vector3(-1.0, 0.0, -10.0)})
	assert_vector(zombie.path[-1]).is_equal(WEST)
	# The target walks 12 m to the east, where the old goal is no use: the new route is taken.
	ZombieFixture.run(sim, 0.6, {1: Vector3(12.0, 0.0, -10.0)})
	assert_vector(zombie.path[-1]).is_equal(EAST)


func test_a_zombie_that_has_walked_its_route_takes_the_new_one() -> void:
	var sim := _sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 3.0)
	ZombieFixture.run(sim, 0.3, {1: Vector3(-1.0, 0.0, -10.0)})
	# It walks to the west goal (8 m) and stands there; the target shuffles across.
	ZombieFixture.run(sim, 6.0, {1: Vector3(-1.0, 0.0, -10.0)})
	assert_float(Vector2(zombie.position.x - WEST.x, zombie.position.z - WEST.z).length()).is_less(
		1.5
	)
	ZombieFixture.run(sim, 1.0, {1: Vector3(1.0, 0.0, -10.0)})
	assert_vector(zombie.path[-1]).is_equal(EAST)
