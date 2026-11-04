# `ZombieSim.revision` (#931): the number a list built from the dead is keyed by. It moves with
# every change a target list or a frame would show, and stands still while nothing happens, so the
# server builds the list once for it instead of once a tick.
extends GdUnitTestSuite

const STEP := ZombieSim.STEP


func _crowd() -> ZombieSim:
	var sim := ZombieFixture.sim()
	ZombieFixture.standing(sim, 1, Vector3(10, 0, 0))
	ZombieFixture.standing(sim, 2, Vector3(12, 0, 0))
	return sim


func test_a_tick_that_makes_no_whole_step_leaves_it_alone() -> void:
	var sim := _crowd()
	sim.tick(STEP, {1: Vector3.ZERO})
	var before := sim.revision
	# Half a step of time is kept, no zombie moves.
	sim.tick(STEP * 0.4, {1: Vector3.ZERO})
	assert_int(sim.revision).is_equal(before)


func test_a_step_moves_it() -> void:
	var sim := _crowd()
	var before := sim.revision
	sim.tick(STEP, {1: Vector3.ZERO})
	assert_int(sim.revision).is_greater(before)


func test_every_change_to_the_dead_moves_it() -> void:
	var sim := _crowd()
	var profile := ZombieProfile.plain(sim.tuning)
	var changes := {
		"spawn": func() -> void: sim.spawn(3, 2.0, Vector3(14, 0, 0)),
		"hit": func() -> void: sim.react_to_hit(1),
		"blast": func() -> void: sim.blast(1, Vector3(3, 0, 0), 0.5),
		"cripple": func() -> void: sim.cripple(2, profile, 0.5),
		"status": func() -> void: sim.set_status(2, 1, false, 0.5),
		"relocate": func() -> void: sim.relocate(1, Vector3(20, 0, 0)),
		"death": func() -> void: sim.begin_death(1),
		"shatter": func() -> void: sim.shatter(3),
		"despawn": func() -> void: sim.despawn(2),
		"touch": func() -> void: sim.touch(),
	}
	for name: String in changes:
		var before := sim.revision
		changes[name].call()
		assert_int(sim.revision).override_failure_message(name).is_greater(before)


func test_a_change_to_a_zombie_that_is_not_there_leaves_it_alone() -> void:
	var sim := _crowd()
	var before := sim.revision
	sim.react_to_hit(99)
	sim.blast(99, Vector3.ONE, 0.5)
	sim.set_status(99, 1, true, 0.5)
	sim.begin_death(99)
	sim.cripple(99, ZombieProfile.plain(sim.tuning), 0.5)
	assert_dict(sim.shatter(99)).is_empty()
	assert_int(sim.revision).is_equal(before)
