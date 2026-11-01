extends GdUnitTestSuite
## The dead at the fence: a zombie that came for a breach stops short of its boards while any
## stand, tears them off a swing at a time, and walks through once none are left. Pure simulation,
## a straight-line field: the gate is the line x = 0 and the way in is +x.

const GATE := &"nw"
const TARGETS := {1: Vector3(20.0, 0.0, 0.0)}

var _boards: Array[int] = [3]


func before_test() -> void:
	_boards[0] = 3


func _sim() -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.gates[GATE] = ZombieGate.new(GATE, Vector3.ZERO, Vector3.RIGHT)
	sim.boards_probe = func(_id: StringName) -> int: return _boards[0]
	sim.board_seconds = 1.2
	return sim


func _gated(sim: ZombieSim, id: int, at: Vector3, barrier_speed: float = 1.0) -> ZombieBody:
	var profile := ZombieProfile.plain(sim.tuning)
	profile.barrier_speed = barrier_speed
	var zombie := sim.spawn(id, 2.0, at, 0.0, profile, GATE)
	zombie.enter(ZombieBody.Mode.CHASE)
	return zombie


func test_a_zombie_stops_short_of_standing_boards() -> void:
	var sim := _sim()
	var zombie := _gated(sim, 1, Vector3(-8.0, 0.0, 0.0))
	ZombieFixture.run(sim, 10.0, TARGETS)
	assert_float(zombie.position.x).is_between(-1.2, -0.85)
	assert_str(zombie.gate_id).is_equal(GATE)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.ATTACK)


func test_it_finishes_a_board_every_board_seconds() -> void:
	var sim := _sim()
	_gated(sim, 1, Vector3(-1.0, 0.0, 0.0))
	var events := ZombieFixture.run(sim, 6.0, TARGETS)
	# 6 s of work at 1.2 s a board: 5 boards' worth, give or take the step it started on.
	assert_int(ZombieFixture.count(events, &"zombie_tore")).is_between(4, 5)
	for event in events:
		if event["type"] == &"zombie_tore":
			assert_str(event["gate_id"]).is_equal(GATE)
			assert_int(event["zombie_id"]).is_equal(1)


func test_a_stronger_zombie_tears_faster() -> void:
	var walker := _sim()
	_gated(walker, 1, Vector3(-1.0, 0.0, 0.0), 1.0)
	var brute := _sim()
	_gated(brute, 1, Vector3(-1.0, 0.0, 0.0), 2.5)
	var slow := ZombieFixture.count(ZombieFixture.run(walker, 6.0, TARGETS), &"zombie_tore")
	var fast := ZombieFixture.count(ZombieFixture.run(brute, 6.0, TARGETS), &"zombie_tore")
	assert_int(fast).is_greater(slow * 2)


func test_with_no_boards_left_it_walks_in_and_the_gate_is_behind_it() -> void:
	_boards[0] = 0
	var sim := _sim()
	var zombie := _gated(sim, 1, Vector3(-4.0, 0.0, 0.0))
	var events := ZombieFixture.run(sim, 4.0, TARGETS)
	assert_float(zombie.position.x).is_greater(2.0)
	assert_str(zombie.gate_id).is_equal(&"")
	assert_int(ZombieFixture.count(events, &"zombie_tore")).is_equal(0)


func test_boards_that_go_up_again_hold_the_next_zombie() -> void:
	_boards[0] = 0
	var sim := _sim()
	var zombie := _gated(sim, 1, Vector3(-4.0, 0.0, 0.0))
	ZombieFixture.run(sim, 1.0, TARGETS)
	assert_float(zombie.position.x).is_less(0.0)
	_boards[0] = 2
	ZombieFixture.run(sim, 6.0, TARGETS)
	assert_float(zombie.position.x).is_less(0.0)


func test_a_zombie_that_cannot_tear_goes_under() -> void:
	var sim := _sim()
	var zombie := _gated(sim, 1, Vector3(-4.0, 0.0, 0.0), 0.0)
	var events := ZombieFixture.run(sim, 4.0, TARGETS)
	assert_float(zombie.position.x).is_greater(2.0)
	assert_int(ZombieFixture.count(events, &"zombie_tore")).is_equal(0)


func test_a_zombie_with_no_gate_is_not_held() -> void:
	var sim := _sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3(-4.0, 0.0, 0.0))
	ZombieFixture.run(sim, 4.0, TARGETS)
	assert_float(zombie.position.x).is_greater(2.0)


func test_a_crowd_cannot_push_one_through_the_boards() -> void:
	var sim := _sim()
	var crowd: Array[ZombieBody] = []
	for i in 12:
		crowd.append(_gated(sim, i + 1, Vector3(-1.5 - 0.1 * (i % 4), 0.0, 0.3 * (i - 6))))
	ZombieFixture.run(sim, 8.0, TARGETS)
	for zombie in crowd:
		assert_float(zombie.position.x).is_less(0.0)


func test_a_staggered_zombie_does_not_work_on_the_boards() -> void:
	var sim := _sim()
	var zombie := _gated(sim, 1, Vector3(-1.0, 0.0, 0.0))
	ZombieFixture.run(sim, 0.2, TARGETS)
	var progress := zombie.tear_progress
	assert_float(progress).is_greater(0.0)
	sim.react_to_hit(1)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.STAGGER)
	ZombieFixture.run(sim, 0.1, TARGETS)
	assert_float(zombie.tear_progress).is_equal(progress)


func test_the_boards_depend_only_on_the_steps_so_a_run_repeats() -> void:
	var first := _hash_of_a_run()
	var second := _hash_of_a_run()
	assert_int(first).is_equal(second)


func _hash_of_a_run() -> int:
	var sim := _sim()
	_gated(sim, 1, Vector3(-6.0, 0.0, 1.0))
	_gated(sim, 2, Vector3(-7.0, 0.0, -1.0), 2.5)
	var running := 0
	for _i in 300:
		sim.tick(ZombieFixture.STEP, TARGETS)
		running = ZombieFixture.state_hash(sim, running)
	return running
