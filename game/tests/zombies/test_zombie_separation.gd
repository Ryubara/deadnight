extends GdUnitTestSuite
## The flat separation grid (`SeparationGrid`) pushes exactly as the grid of `Array`s it replaced
## (`SeparationReference`, the old code kept as the oracle), makes nothing once it has grown, and
## copes with a crowd that grows, shrinks and loses its dead (#933).

const DEAD := 120
const STEPS := 100
const SEED := 933
## A pass that holds more than this many bytes at once is making something (an `Array` is 40 B).
const HELD_BYTES_LIMIT := 64


func _crowd(sim: ZombieSim, spread: float, count: int = DEAD, first_id: int = 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in count:
		var at := Vector3(
			rng.randf_range(-spread, spread) / 2.0,
			# Some stand on the ramp over the floor beside them, which do not touch.
			0.0 if i % 7 != 0 else 1.5,
			rng.randf_range(-spread, spread) / 2.0
		)
		sim.spawn(first_id + i, 1.5, at).enter(ZombieBody.Mode.CHASE)


func _positions(sim: ZombieSim) -> PackedVector3Array:
	var positions := PackedVector3Array()
	var ids: Array = sim.zombies.keys()
	ids.sort()
	for id: int in ids:
		positions.append(sim.zombies[id].position)
	return positions


## A sim with the flat grid and one with the old one, each given the same crowd.
func _pair(spread: float, count: int = DEAD) -> Array[ZombieSim]:
	var now := ZombieSim.new(null, SEED)
	var then := SeparationReference.new(null, SEED)
	now.tuning.hard_cap = 1000
	then.tuning.hard_cap = 1000
	_crowd(now, spread, count)
	_crowd(then, spread, count)
	return [now, then]


func _assert_same_pushes(spread: float) -> void:
	var pair := _pair(spread)
	var start := _positions(pair[0])
	for step in STEPS:
		pair[0]._separate(ZombieSim.STEP)
		pair[1]._separate(ZombieSim.STEP)
		(
			assert_bool(_positions(pair[0]) == _positions(pair[1]))
			. override_failure_message("spread %.0f differs after step %d" % [spread, step + 1])
			. is_true()
		)
	# The oracle is not a pass that moves nothing.
	assert_bool(_positions(pair[0]) != start).is_true()


func test_a_pile_in_a_small_square_moves_as_the_old_grid_did() -> void:
	_assert_same_pushes(3.0)


func test_a_crowd_spread_over_the_lot_moves_as_the_old_grid_did() -> void:
	_assert_same_pushes(30.0)


func test_a_crowd_in_a_corner_of_negative_cells_moves_as_the_old_grid_did() -> void:
	var pair := _pair(1.0, 0)
	for sim in pair:
		for i in 60:
			var at := Vector3(-300.0 - 0.3 * (i % 9), 0.0, -500.0 + 0.3 * (i / 9))
			sim.spawn(i + 1, 1.5, at).enter(ZombieBody.Mode.CHASE)
	for _i in STEPS:
		pair[0]._separate(ZombieSim.STEP)
		pair[1]._separate(ZombieSim.STEP)
	assert_bool(_positions(pair[0]) == _positions(pair[1])).is_true()


func test_zombies_on_one_point_part_as_the_old_grid_parted_them() -> void:
	var pair := _pair(1.0, 0)
	for sim in pair:
		for i in 12:
			sim.spawn(i + 1, 1.5, Vector3(4.0, 0.0, 4.0)).enter(ZombieBody.Mode.CHASE)
	for _i in STEPS:
		pair[0]._separate(ZombieSim.STEP)
		pair[1]._separate(ZombieSim.STEP)
	assert_bool(_positions(pair[0]) == _positions(pair[1])).is_true()


func test_a_whole_night_of_ticks_with_dying_and_cleared_dead_matches_the_old_grid() -> void:
	var pair := _pair(10.0)
	var targets := {1: Vector3.ZERO}
	var hashes: Array[Array] = [[], []]
	for tick in STEPS:
		if tick == 20 or tick == 45:
			# The rules kill some: they lie dying a while, then the sim clears them.
			for sim in pair:
				for id in range(tick, tick + 15):
					sim.begin_death(id)
		if tick == 60:
			for sim in pair:
				_crowd(sim, 10.0, 10, 500)
		var events: Array = []
		for k in 2:
			events.append(pair[k].tick(ZombieSim.STEP, targets))
			hashes[k].append(ZombieFixture.state_hash(pair[k]))
		assert_array(events[0]).is_equal(events[1])
	assert_array(hashes[0]).is_equal(hashes[1])
	assert_int(pair[0].zombies.size()).is_equal(pair[1].zombies.size())


func test_the_grid_lists_only_the_standing_and_lets_go_of_the_rest() -> void:
	var sim := ZombieSim.new(null, SEED)
	_crowd(sim, 6.0, 20)
	sim._separate(ZombieSim.STEP)
	assert_int(sim._grid.count).is_equal(20)
	sim.begin_death(3)
	sim.begin_death(4)
	sim.zombies.erase(5)
	sim._separate(ZombieSim.STEP)
	assert_int(sim._grid.count).is_equal(17)
	for i in range(17, 20):
		assert_object(sim._grid.bodies[i]).is_null()
	for i in sim._grid.count:
		assert_bool(sim._grid.bodies[i].is_alive()).is_true()


func test_a_crowd_that_outgrows_the_grid_still_moves_as_the_old_grid_did() -> void:
	var pair := _pair(8.0, 30)
	for step in 30:
		if step == 10:
			for sim in pair:
				_crowd(sim, 8.0, 300, 100)
		pair[0]._separate(ZombieSim.STEP)
		pair[1]._separate(ZombieSim.STEP)
		assert_bool(_positions(pair[0]) == _positions(pair[1])).is_true()


func test_a_step_at_full_crowd_holds_no_memory_once_the_grid_has_grown() -> void:
	if OS.get_static_memory_peak_usage() == 0:
		return  # a build that does not track memory
	for spread in [30.0, 3.0]:
		var pair := _pair(spread)
		for sim in pair:
			for _i in 10:
				sim.tick(ZombieSim.STEP, {1: Vector3.ZERO})
		assert_int(_held_by_a_pass(pair[0])).is_less(HELD_BYTES_LIMIT)
		# The old grid, for the same crowd, held kilobytes: the test can tell the two apart.
		assert_int(_held_by_a_pass(pair[1])).is_greater(HELD_BYTES_LIMIT * 10)


## The most memory the allocator holds above where it stood while one pass runs: a ballast lifts
## the live memory to the old peak first, so the peak moves only for what the pass holds.
func _held_by_a_pass(sim: ZombieSim) -> int:
	var ballast := PackedByteArray()
	ballast.resize(OS.get_static_memory_peak_usage() - OS.get_static_memory_usage() + 4096)
	var before := OS.get_static_memory_peak_usage()
	sim._separate(ZombieSim.STEP)
	var after := OS.get_static_memory_peak_usage()
	ballast.clear()
	return maxi(after - before, 0)
