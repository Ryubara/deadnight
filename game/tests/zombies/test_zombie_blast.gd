extends GdUnitTestSuite
## What a grenade blast does to a zombie in the sim (#357): it is thrown along the ground away
## from the blast, slows to a stop, and is held still for the blast's stun, longer than a bullet's
## stagger.

const TARGETS := {7: Vector3(30.0, 0.0, 0.0)}
const IMPULSE := Vector3(6.0, 3.0, 0.0)
const STUN := 1.6


func test_a_blast_throws_the_zombie_along_the_ground_and_it_comes_to_rest() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	sim.blast(1, IMPULSE, STUN)
	ZombieFixture.run(sim, 0.1, TARGETS)
	assert_float(zombie.position.x).is_greater(0.3)
	assert_float(zombie.position.y).is_equal(0.0)
	ZombieFixture.run(sim, 1.0, TARGETS)
	var rested := zombie.position
	assert_vector(zombie.push).is_equal(Vector3.ZERO)
	ZombieFixture.run(sim, 0.2, TARGETS)
	assert_vector(zombie.position).is_equal(rested)
	# 6 m/s slowing at 14 m/s per second: v squared over twice that, 1.29 m.
	assert_float(rested.x).is_equal_approx(1.29, 0.2)


func test_a_blast_holds_the_zombie_for_the_stun_not_the_shorter_stagger() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	sim.blast(1, IMPULSE, STUN)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.STAGGER)
	ZombieFixture.run(sim, sim.tuning.stagger_seconds + 0.3, TARGETS)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.STAGGER)
	assert_vector(zombie.velocity).is_equal(Vector3.ZERO)
	ZombieFixture.run(sim, STUN, TARGETS)
	assert_int(zombie.mode).is_not_equal(ZombieBody.Mode.STAGGER)


func test_a_bullet_stagger_after_a_blast_keeps_its_own_short_hold() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	sim.blast(1, IMPULSE, STUN)
	ZombieFixture.run(sim, STUN + 0.2, TARGETS)
	sim.react_to_hit(1)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.STAGGER)
	ZombieFixture.run(sim, sim.tuning.stagger_seconds + 0.1, TARGETS)
	assert_int(zombie.mode).is_not_equal(ZombieBody.Mode.STAGGER)


func test_a_second_blast_starts_the_stun_over() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	sim.blast(1, IMPULSE, STUN)
	ZombieFixture.run(sim, STUN - 0.3, TARGETS)
	sim.blast(1, IMPULSE, STUN)
	ZombieFixture.run(sim, STUN - 0.3, TARGETS)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.STAGGER)


func test_the_dying_and_the_rising_are_not_thrown() -> void:
	var sim := ZombieFixture.sim()
	var dying := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	sim.begin_death(1)
	sim.blast(1, IMPULSE, STUN)
	assert_vector(dying.push).is_equal(Vector3.ZERO)
	var rising := sim.spawn(2, 2.0, Vector3(5.0, 0.0, 0.0))
	sim.blast(2, IMPULSE, STUN)
	assert_int(rising.mode).is_equal(ZombieBody.Mode.EMERGING)


func test_the_throw_is_capped_so_a_huge_impulse_cannot_launch_one() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	sim.blast(1, Vector3(500.0, 0.0, 0.0), STUN)
	assert_float(zombie.push.length()).is_equal_approx(sim.tuning.push_max_speed, 0.001)


func test_the_same_blast_gives_the_same_zombie_every_time() -> void:
	var results: Array[Vector3] = []
	for _run in 2:
		var sim := ZombieFixture.sim()
		var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
		sim.blast(1, IMPULSE, STUN)
		ZombieFixture.run(sim, 2.0, TARGETS)
		results.append(zombie.position)
	assert_vector(results[0]).is_equal(results[1])
