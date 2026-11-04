extends GdUnitTestSuite
## A dead tears a window's boards from in front of the opening and never from beside it (#997): it
## came up to the gap's end, in front of a jamb, tore from there, and a person inside had the jamb
## between them and it. A straight-line field: the wall is the line x = 0, the way in is +x, the
## gap is 2.0 m wide with 0.4 m jambs, so the opening is 1.2 m (0.5 m either side of the middle
## for a dead's middle, `ZombieGate.TEAR_MARGIN`).

const GATE := &"win"
const CLEAR_HALF := 0.6
const TARGETS := {1: Vector3(20.0, 0.0, 0.0)}

var _barricades: BarricadeState


func before_test() -> void:
	_barricades = BarricadeState.new(BarricadeTuning.new())
	_barricades.boards[GATE] = 5


func _sim() -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.gates[GATE] = ZombieGate.new(
		GATE, Vector3.ZERO, Vector3.RIGHT, 1.0, 0.9, 0.4, 1.0, CLEAR_HALF
	)
	sim.barricades = _barricades
	return sim


func _dead_at(sim: ZombieSim, x: float, z: float) -> ZombieBody:
	var zombie := sim.spawn(1, 2.0, Vector3(x, 0.0, z), 0.0, null, GATE)
	zombie.enter(ZombieBody.Mode.CHASE)
	return zombie


## Runs `seconds` and returns the widest z a dead stood at while it tore, and how many boards it
## pulled off (the boards are put back each time, so it keeps tearing).
func _tear(sim: ZombieSim, zombie: ZombieBody, seconds: float) -> Dictionary:
	var out := {"widest": 0.0, "torn": 0, "ticks": 0}
	for _i in int(seconds / ZombieSim.STEP):
		var events := sim.tick(ZombieSim.STEP, TARGETS)
		_barricades.boards[GATE] = 5
		out["torn"] += ZombieFixture.count(events, &"zombie_tore")
		if zombie.tearing:
			out["ticks"] += 1
			out["widest"] = maxf(out["widest"], absf(zombie.position.z))
	return out


func test_the_front_of_the_opening_is_the_clear_width_less_a_margin() -> void:
	var gate := _sim().gates[GATE] as ZombieGate
	var room := CLEAR_HALF - ZombieGate.TEAR_MARGIN
	assert_float(gate.tear_room()).is_equal_approx(room, 0.001)
	assert_float(gate.aside_of(Vector3(-1.0, 0.0, 0.0))).is_equal(0.0)
	assert_float(gate.aside_of(Vector3(-1.0, 0.0, room - 0.01))).is_equal(0.0)
	assert_float(absf(gate.aside_of(Vector3(-1.0, 0.0, 1.0)))).is_equal_approx(1.0 - room, 0.001)
	# The sign is the same as `along_of`'s: a dead to the right of the middle is aside by a positive
	# amount, and has to go back the other way.
	var beside := Vector3(-1.0, 0.0, 1.0)
	assert_float(gate.aside_of(beside) * gate.along_of(beside)).is_greater(0.0)
	# A gate with no jambs (a straight-line field) has no beside.
	var open := ZombieGate.new(GATE, Vector3.ZERO, Vector3.RIGHT)
	assert_float(open.aside_of(Vector3(-1.0, 0.0, 30.0))).is_equal(0.0)


func test_a_dead_that_comes_to_the_gap_s_end_slides_to_the_opening_and_tears_there() -> void:
	for side in [-1.0, 1.0]:
		var sim := _sim()
		var zombie := _dead_at(sim, -3.0, 1.2 * side)
		var out := _tear(sim, zombie, 12.0)
		assert_int(out["torn"]).is_greater(0)
		assert_float(out["widest"]).is_less_equal(CLEAR_HALF - ZombieGate.TEAR_MARGIN + 0.02)


func test_a_dead_pushed_aside_at_the_boards_does_not_tear_until_it_is_back_in_front() -> void:
	var sim := _sim()
	var zombie := _dead_at(sim, -3.0, 0.0)
	_tear(sim, zombie, 6.0)
	assert_bool(zombie.tearing).is_true()
	zombie.position.z = 1.0
	zombie.push = Vector3.ZERO
	var torn_aside := 0
	var first_tick_tearing := -1
	for i in 60:
		var events := sim.tick(ZombieSim.STEP, TARGETS)
		_barricades.boards[GATE] = 5
		if zombie.tearing and first_tick_tearing < 0:
			first_tick_tearing = i
		if first_tick_tearing < 0:
			torn_aside += ZombieFixture.count(events, &"zombie_tore")
	assert_int(torn_aside).is_equal(0)
	assert_int(first_tick_tearing).is_greater(0)
	assert_float(absf(zombie.position.z)).is_less_equal(CLEAR_HALF)
