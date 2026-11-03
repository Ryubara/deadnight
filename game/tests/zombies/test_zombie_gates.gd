extends GdUnitTestSuite
## The dead at the fence: a zombie that came for a breach stops short of its boards while any
## stand, tears them off a swing at a time, and walks through once none are left. Pure simulation,
## a straight-line field: the gate is the line x = 0 and the way in is +x.

const GATE := &"nw"
const TARGETS := {1: Vector3(20.0, 0.0, 0.0)}
## Two windows on one wall (the line x = 0), ten metres apart, each 1.5 m wide. The dead walk the
## way a navigation mesh leads them: along the wall to the second window's gap and through it.
const NEAR := &"win_a"
const FAR := &"win_b"
const FAR_Z := 10.0
const GAP_HALF := 0.75
const WINDOW_TARGETS := {1: Vector3(20.0, 0.0, FAR_Z)}


## A path hugging the wall to the far window's gap, then through it.
class AlongTheWall:
	extends ZombiePathing

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		if from.x > -0.5:  # in the gap: straight on
			return PackedVector3Array([to])
		return PackedVector3Array([Vector3(-1.0, 0.0, FAR_Z), Vector3(5.0, 0.0, FAR_Z), to])


var _barricades: BarricadeState


func before_test() -> void:
	_barricades = BarricadeState.new(BarricadeTuning.new())
	_set_boards(3)


func _set_boards(count: int) -> void:
	_barricades.boards[GATE] = count


func _sim() -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.gates[GATE] = ZombieGate.new(GATE, Vector3.ZERO, Vector3.RIGHT)
	sim.barricades = _barricades
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
	_set_boards(0)
	var sim := _sim()
	var zombie := _gated(sim, 1, Vector3(-4.0, 0.0, 0.0))
	var events := ZombieFixture.run(sim, 4.0, TARGETS)
	assert_float(zombie.position.x).is_greater(2.0)
	assert_str(zombie.gate_id).is_equal(&"")
	assert_int(ZombieFixture.count(events, &"zombie_tore")).is_equal(0)


func test_boards_that_go_up_again_hold_the_next_zombie() -> void:
	_set_boards(0)
	var sim := _sim()
	var zombie := _gated(sim, 1, Vector3(-4.0, 0.0, 0.0))
	ZombieFixture.run(sim, 1.0, TARGETS)
	assert_float(zombie.position.x).is_less(0.0)
	_set_boards(2)
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


func _two_windows(near_boards: int, far_boards: int) -> ZombieSim:
	_barricades.boards[NEAR] = near_boards
	_barricades.boards[FAR] = far_boards
	var sim := ZombieFixture.sim()
	sim.gates[NEAR] = ZombieGate.new(NEAR, Vector3.ZERO, Vector3.RIGHT, GAP_HALF)
	sim.gates[FAR] = ZombieGate.new(FAR, Vector3(0.0, 0.0, FAR_Z), Vector3.RIGHT, GAP_HALF)
	sim.barricades = _barricades
	sim.board_seconds = 1.2
	sim.pathing = AlongTheWall.new()
	return sim


func _tore_at(events: Array[Dictionary], gate: StringName) -> int:
	var n := 0
	for event in events:
		if event["type"] == &"zombie_tore" and event["gate_id"] == gate:
			n += 1
	return n


func test_a_dead_beside_the_wall_between_two_windows_tears_no_boards() -> void:
	var sim := _two_windows(3, 3)
	var profile := ZombieProfile.plain(sim.tuning)
	var zombie := sim.spawn(1, 2.0, Vector3(-1.0, 0.0, 5.0), 0.0, profile, NEAR)
	zombie.enter(ZombieBody.Mode.CHASE)
	var events := ZombieFixture.run(sim, 1.0, WINDOW_TARGETS)
	assert_int(_tore_at(events, NEAR)).is_equal(0)
	assert_float(zombie.position.z).is_between(5.5, 8.0)
	assert_float(zombie.tear_progress).is_equal(0.0)


func test_a_dead_walking_along_the_wall_tears_the_window_it_comes_to() -> void:
	var sim := _two_windows(3, 1)
	var profile := ZombieProfile.plain(sim.tuning)
	var zombie := sim.spawn(1, 2.0, Vector3(-1.0, 0.0, 5.0), 0.0, profile, NEAR)
	zombie.enter(ZombieBody.Mode.CHASE)
	var events := ZombieFixture.run(sim, 6.0, WINDOW_TARGETS)
	assert_int(_tore_at(events, NEAR)).is_equal(0)
	# It reached the far window, took that gate for its own and worked its boards.
	assert_str(zombie.gate_id).is_equal(FAR)
	assert_float(zombie.position.z).is_between(FAR_Z - GAP_HALF - 0.6, FAR_Z + GAP_HALF + 0.6)
	assert_int(_tore_at(events, FAR)).is_greater(0)


func test_a_dead_that_tore_the_far_window_down_walks_through_it() -> void:
	var sim := _two_windows(3, 1)
	var profile := ZombieProfile.plain(sim.tuning)
	var zombie := sim.spawn(1, 2.0, Vector3(-1.0, 0.0, 5.0), 0.0, profile, NEAR)
	zombie.enter(ZombieBody.Mode.CHASE)
	var events := ZombieFixture.run(sim, 8.0, WINDOW_TARGETS)
	_barricades.boards[FAR] = 0
	events.append_array(ZombieFixture.run(sim, 4.0, WINDOW_TARGETS))
	assert_int(_tore_at(events, NEAR)).is_equal(0)
	assert_float(zombie.position.x).is_greater(2.0)
	assert_str(zombie.gate_id).is_equal(&"")


func test_a_dead_in_front_of_its_own_window_still_tears_it() -> void:
	var sim := _two_windows(3, 3)
	sim.pathing = ZombiePathing.new()
	var profile := ZombieProfile.plain(sim.tuning)
	var zombie := sim.spawn(1, 2.0, Vector3(-3.0, 0.0, 0.3), 0.0, profile, NEAR)
	zombie.enter(ZombieBody.Mode.CHASE)
	var events := ZombieFixture.run(sim, 3.0, TARGETS)
	assert_int(_tore_at(events, NEAR)).is_greater(0)
	assert_str(zombie.gate_id).is_equal(NEAR)


func test_the_wrong_gates_boards_do_not_hold_a_dead_that_walks_through_another_gap() -> void:
	# The near window is boarded and the far one is open: a dead that came for the near one but is
	# in front of the open one walks in, and the near boards are not its business.
	var sim := _two_windows(3, 0)
	var profile := ZombieProfile.plain(sim.tuning)
	var zombie := sim.spawn(1, 2.0, Vector3(-3.0, 0.0, FAR_Z), 0.0, profile, NEAR)
	zombie.enter(ZombieBody.Mode.CHASE)
	var events := ZombieFixture.run(sim, 5.0, WINDOW_TARGETS)
	assert_float(zombie.position.x).is_greater(2.0)
	assert_int(_tore_at(events, NEAR)).is_equal(0)
