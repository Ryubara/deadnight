extends GdUnitTestSuite
## A dead at a window whose boards a player puts back as fast as it tears them (a walker pulls one
## off in 1.2 s, a hand puts one on every second) holds a round open for ever when nobody can shoot
## it: the soak found one beside a jamb, out of the line of fire, for two and a half minutes (#950).
## After `ZombieSim.SIEGE_SECONDS` of it the boards burst.

const GATE := &"nw"
const TARGETS := {1: Vector3(20.0, 0.0, 0.0)}

var _barricades: BarricadeState


func before_test() -> void:
	_barricades = BarricadeState.new(BarricadeTuning.new())
	_barricades.boards[GATE] = 5


func _sim() -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.gates[GATE] = ZombieGate.new(GATE, Vector3.ZERO, Vector3.RIGHT)
	sim.barricades = _barricades
	sim.board_seconds = 1.2
	return sim


func _gated(sim: ZombieSim, id: int) -> ZombieBody:
	var zombie := sim.spawn(
		id, 2.0, Vector3(-1.0, 0.0, 0.0), 0.0, ZombieProfile.plain(sim.tuning), GATE
	)
	zombie.enter(ZombieBody.Mode.CHASE)
	return zombie


## Runs `seconds` as the night does: the dead's tears take boards off, a hand puts one back every
## `mend_every` seconds (0 for no one). Returns the events.
func _run(sim: ZombieSim, seconds: float, mend_every: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var since := 0.0
	for _i in ceili(seconds / ZombieFixture.STEP):
		for event in sim.tick(ZombieFixture.STEP, TARGETS):
			events.append(event)
			if event["type"] == &"zombie_tore":
				_barricades.tear(GATE)
		since += ZombieFixture.STEP
		if mend_every > 0.0 and since >= mend_every:
			since = 0.0
			_barricades.repair(GATE)
	return events


func test_boards_mended_as_fast_as_they_are_torn_burst_after_the_siege() -> void:
	var sim := _sim()
	_gated(sim, 1)
	var early := _run(sim, ZombieSim.SIEGE_SECONDS - 3.0, 1.0)
	assert_int(ZombieFixture.count(early, &"zombie_burst")).is_equal(0)
	var later := _run(sim, 6.0, 1.0)
	assert_int(ZombieFixture.count(later, &"zombie_burst")).is_equal(1)
	(
		assert_str(
			later.filter(func(e: Dictionary) -> bool: return e["type"] == &"zombie_burst")[0]["gate_id"]
		)
		. is_equal(GATE)
	)


func test_the_dead_one_is_through_for_good_though_a_hand_puts_a_board_back_at_once() -> void:
	var sim := _sim()
	var zombie := _gated(sim, 1)
	_run(sim, ZombieSim.SIEGE_SECONDS + 1.0, 1.0)
	assert_str(zombie.gate_id).is_equal("")
	_run(sim, 6.0, 1.0)
	assert_float(zombie.position.x).is_greater(1.0)


func test_a_dead_that_tears_the_boards_down_in_good_time_never_bursts_them() -> void:
	var sim := _sim()
	_gated(sim, 1)
	var events := _run(sim, ZombieSim.SIEGE_SECONDS * 2.0, 0.0)
	assert_int(ZombieFixture.count(events, &"zombie_burst")).is_equal(0)
	assert_int(_barricades.boards_of(GATE)).is_equal(0)


func test_the_siege_starts_over_when_the_zombie_is_hit() -> void:
	var sim := _sim()
	var zombie := _gated(sim, 1)
	_run(sim, ZombieSim.SIEGE_SECONDS - 5.0, 1.0)
	assert_float(zombie.siege_seconds).is_greater(ZombieSim.SIEGE_SECONDS - 7.0)
	sim.react_to_hit(1)
	_run(sim, 0.1, 1.0)
	assert_float(zombie.siege_seconds).is_equal(0.0)
