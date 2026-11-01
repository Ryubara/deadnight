extends GdUnitTestSuite
## The zombie state machine and simulation, with no scene tree: emerging, chasing the nearest
## player, attacking, staggering, dying, light, spacing, determinism.

## The farthest a zombie may move in one tick when only separation acts on it. A walking zombie
## strides about 0.1 m a tick; many times that is a launch.
const SANE_STEP_METRES := 0.5
const _CHASE_TARGETS := {1: Vector3.ZERO, 2: Vector3(0, 0, 20)}


func test_a_zombie_rises_before_it_chases() -> void:
	var sim := ZombieFixture.sim()
	var zombie := sim.spawn(1, 2.0, Vector3.ZERO)
	ZombieFixture.run(sim, 0.3, {1: Vector3(20, 0, 0)})
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.EMERGING)
	assert_float(zombie.position.x).is_equal(0.0)
	ZombieFixture.run(sim, 0.6, {1: Vector3(20, 0, 0)})
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.CHASE)


func test_a_zombie_walks_to_a_player_at_its_speed() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	ZombieFixture.run(sim, 3.0, {1: Vector3(20, 0, 0)})
	# 3 s at 2 m/s, less a step or so while the first path is found.
	assert_float(zombie.position.x).is_between(5.5, 6.1)
	assert_float(zombie.move_speed).is_equal_approx(2.0, 0.01)
	assert_float(zombie.yaw).is_equal_approx(PI / 2.0, 0.05)


func test_it_chases_the_nearest_player() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	ZombieFixture.run(sim, 0.1, {1: Vector3(30, 0, 0), 2: Vector3(0, 0, -10)})
	assert_int(zombie.target_id).is_equal(2)


func test_it_keeps_its_target_unless_another_is_clearly_nearer() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	ZombieFixture.run(sim, 0.6, {1: Vector3(10, 0, 0), 2: Vector3(0, 0, 14)})
	assert_int(zombie.target_id).is_equal(1)
	# Player 2 is now 1 m nearer: inside the margin, so no switch.
	ZombieFixture.run(sim, 1.0, {1: Vector3(10, 0, 0), 2: Vector3(0, 0, 9)})
	assert_int(zombie.target_id).is_equal(1)
	ZombieFixture.run(sim, 1.0, {1: Vector3(10, 0, 0), 2: Vector3(0, 0, 4)})
	assert_int(zombie.target_id).is_equal(2)


func test_it_retargets_when_its_player_leaves() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	ZombieFixture.run(sim, 0.6, {1: Vector3(10, 0, 0), 2: Vector3(0, 0, 30)})
	ZombieFixture.run(sim, 0.1, {2: Vector3(0, 0, 30)})
	assert_int(zombie.target_id).is_equal(2)


func test_with_nobody_to_chase_it_stands() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3(3, 0, 3))
	ZombieFixture.run(sim, 2.0, {})
	assert_vector(zombie.position).is_equal(Vector3(3, 0, 3))
	assert_int(zombie.target_id).is_equal(-1)


func test_in_reach_it_swings_and_the_blow_lands_once_at_the_windup() -> void:
	var sim := ZombieFixture.sim()
	var tuning := sim.tuning
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	var targets := {7: Vector3(1.0, 0, 0)}
	var before := ZombieFixture.run(sim, tuning.windup_seconds - 0.1, targets)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.ATTACK)
	assert_int(ZombieFixture.count(before, &"zombie_struck")).is_equal(0)
	var landing := ZombieFixture.run(sim, 0.2, targets)
	assert_int(ZombieFixture.count(landing, &"zombie_struck")).is_equal(1)
	var strikes := landing.filter(func(e: Dictionary) -> bool: return e["type"] == &"zombie_struck")
	var strike: Dictionary = strikes[0]
	assert_int(strike["target_id"]).is_equal(7)
	assert_float(strike["damage"]).is_equal(tuning.strike_damage)
	# The rest of the swing adds none; the next swing starts after it.
	var rest := ZombieFixture.run(sim, tuning.swing_seconds - tuning.windup_seconds - 0.2, targets)
	assert_int(ZombieFixture.count(rest, &"zombie_struck")).is_equal(0)


func test_a_player_who_steps_away_during_the_windup_is_missed() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	ZombieFixture.run(sim, 0.2, {7: Vector3(1.0, 0, 0)})
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.ATTACK)
	var events := ZombieFixture.run(sim, 0.5, {7: Vector3(4.0, 0, 0)})
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)


func test_a_hit_during_the_windup_staggers_and_cancels_the_blow() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	var targets := {7: Vector3(1.0, 0, 0)}
	ZombieFixture.run(sim, 0.3, targets)
	sim.react_to_hit(1)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.STAGGER)
	var events := ZombieFixture.run(sim, 0.3, targets)
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)
	assert_vector(zombie.velocity).is_equal(Vector3.ZERO)
	ZombieFixture.run(sim, 0.3, targets)
	assert_int(zombie.mode).is_not_equal(ZombieBody.Mode.STAGGER)


func test_a_dying_zombie_is_still_then_cleared_and_never_stands_again() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	sim.begin_death(1)
	sim.react_to_hit(1)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.DYING)
	assert_int(sim.standing_count()).is_equal(0)
	var events := ZombieFixture.run(sim, 1.0, {7: Vector3(1, 0, 0)})
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.DYING)
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)
	events = ZombieFixture.run(sim, sim.tuning.death_seconds, {7: Vector3(1, 0, 0)})
	assert_int(ZombieFixture.count(events, &"zombie_cleared")).is_equal(1)
	assert_bool(sim.zombies.has(1)).is_false()


func test_dark_ground_speeds_a_zombie_up_by_the_rules_factor() -> void:
	var rounds := load("res://gameplay/rules/default_tuning.tres").rounds as RoundTuning
	var dark := ZombieFixture.sim()
	var lit := ZombieFixture.sim()
	for sim in [dark, lit]:
		sim.rounds = rounds
		ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	lit.lit_probe = func(_p: Vector3) -> bool: return true
	ZombieFixture.run(dark, 2.0, {1: Vector3(40, 0, 0)})
	ZombieFixture.run(lit, 2.0, {1: Vector3(40, 0, 0)})
	assert_float(lit.zombies[1].move_speed).is_equal_approx(2.0, 0.01)
	assert_float(dark.zombies[1].move_speed).is_equal_approx(
		2.0 * rounds.dark_speed_multiplier, 0.01
	)


func test_a_crowd_on_one_spot_spreads_out_and_none_stays_stacked() -> void:
	var sim := ZombieFixture.sim()
	for i in 12:
		ZombieFixture.standing(sim, i + 1, Vector3(0.01 * i, 0, 0.0), 0.0)
	ZombieFixture.run(sim, 3.0, {})
	var closest := INF
	for a: ZombieBody in sim.zombies.values():
		for b: ZombieBody in sim.zombies.values():
			if a != b:
				closest = minf(closest, a.position.distance_to(b.position))
	assert_float(closest).is_greater(sim.tuning.separation_radius * 0.5)


func test_the_same_seed_gives_the_same_chase() -> void:
	assert_vector(_chase(11)).is_equal(_chase(11))


func _chase(p_seed: int) -> Vector3:
	var sim := ZombieFixture.sim(p_seed)
	for i in 6:
		sim.spawn(i + 1, 1.5 + i * 0.3, Vector3(10 + i, 0, 3 * i))
	ZombieFixture.run(sim, 6.0, {1: Vector3.ZERO, 2: Vector3(0, 0, 20)})
	return sim.zombies[4].position


func test_forty_zombies_fit_in_the_budget_of_the_server_tick() -> void:
	var sim := ZombieFixture.sim()
	for i in 40:
		sim.spawn(i + 1, 2.0, Vector3(20 + i % 8, 0, i / 8 * 2))
	var start := Time.get_ticks_usec()
	ZombieFixture.run(sim, 5.0, {1: Vector3.ZERO, 2: Vector3(0, 0, 10)})
	var per_tick_ms := (Time.get_ticks_usec() - start) / 1000.0 / 150.0
	print("40 zombies: %.3f ms per 30 Hz tick" % per_tick_ms)
	assert_float(per_tick_ms).is_less(3.0)


func _stacked(count: int, at: Vector3) -> ZombieSim:
	var sim := ZombieFixture.sim()
	for i in count:
		ZombieFixture.standing(sim, i + 1, at, 0.0)
	return sim


## x: the farthest any zombie moved in one tick; y: the farthest any got from `origin`.
func _farthest_step_and_distance(sim: ZombieSim, origin: Vector3, ticks: int) -> Vector2:
	var farthest_step := 0.0
	var farthest_out := 0.0
	for _i in ticks:
		var before := {}
		for zombie: ZombieBody in sim.zombies.values():
			before[zombie.id] = zombie.position
		sim.tick(ZombieSim.STEP, {})
		for zombie: ZombieBody in sim.zombies.values():
			farthest_step = maxf(farthest_step, zombie.position.distance_to(before[zombie.id]))
			farthest_out = maxf(farthest_out, zombie.position.distance_to(origin))
	return Vector2(farthest_step, farthest_out)


func test_two_zombies_on_one_point_are_eased_apart_not_thrown() -> void:
	var origin := Vector3(10, 0, 0)
	var sim := _stacked(2, origin)
	var worst := _farthest_step_and_distance(sim, origin, 150)
	assert_float(worst.x).is_less(SANE_STEP_METRES)
	assert_float(worst.y).is_less(3.0)
	assert_float(sim.zombies[1].position.distance_to(sim.zombies[2].position)).is_greater(
		sim.tuning.separation_radius * 0.9
	)


func test_forty_zombies_on_one_point_stay_in_the_lot_and_spread() -> void:
	var origin := Vector3(10, 0, 0)
	var sim := _stacked(40, origin)
	var worst := _farthest_step_and_distance(sim, origin, 300)
	assert_float(worst.x).is_less(SANE_STEP_METRES)
	# Forty bodies 0.8 m apart need a patch about 6 m across; the lot is far larger than any throw.
	assert_float(worst.y).is_less(8.0)
	var closest := INF
	for a: ZombieBody in sim.zombies.values():
		for b: ZombieBody in sim.zombies.values():
			if a != b:
				closest = minf(closest, a.position.distance_to(b.position))
	assert_float(closest).is_greater(sim.tuning.separation_radius * 0.5)


func test_where_coincident_zombies_part_depends_only_on_their_ids() -> void:
	var first := _stacked(5, Vector3.ZERO)
	var second := _stacked(5, Vector3.ZERO)
	first.tick(ZombieSim.STEP, {})
	second.tick(ZombieSim.STEP, {})
	for id in range(1, 6):
		assert_vector(first.zombies[id].position).is_equal(second.zombies[id].position)
	# They did not all go the same way, nor along one axis: a pile that moved as one is still a pile.
	var sideways := 0
	for id in range(1, 6):
		if absf(first.zombies[id].position.z) > 0.001:
			sideways += 1
	assert_int(sideways).is_greater(2)
	assert_bool(first.zombies[1].position.is_equal_approx(first.zombies[2].position)).is_false()


func _chase_world() -> ZombieSim:
	var sim := ZombieFixture.sim(11)
	for i in 6:
		sim.spawn(i + 1, 1.5 + i * 0.3, Vector3(10 + i, 0, 3 * i))
	return sim


func test_ticking_in_smaller_or_uneven_deltas_gives_the_same_zombies() -> void:
	var reference := _chase_world()
	var halves := _chase_world()
	var uneven := _chase_world()
	var uneven_deltas: Array[float] = [1.0 / 60.0, 1.0 / 15.0, 1.0 / 60.0]  # 0.1 s, three steps
	for i in 90:
		reference.tick(ZombieSim.STEP, _CHASE_TARGETS)
		halves.tick(ZombieSim.STEP / 2.0, _CHASE_TARGETS)
		halves.tick(ZombieSim.STEP / 2.0, _CHASE_TARGETS)
		assert_int(ZombieFixture.state_hash(halves)).is_equal(ZombieFixture.state_hash(reference))
		if i % 3 == 2:
			for delta in uneven_deltas:
				uneven.tick(delta, _CHASE_TARGETS)
			assert_int(ZombieFixture.state_hash(uneven)).is_equal(
				ZombieFixture.state_hash(reference)
			)


func test_a_delta_that_is_not_a_time_does_nothing() -> void:
	var sim := _chase_world()
	ZombieFixture.run(sim, 1.0, _CHASE_TARGETS)
	var before := ZombieFixture.state_hash(sim)
	for bad in [0.0, -1.0, NAN, INF, -INF]:
		sim.tick(bad, _CHASE_TARGETS)
	assert_int(ZombieFixture.state_hash(sim)).is_equal(before)


func test_a_long_stall_catches_up_a_few_steps_not_all_of_it() -> void:
	var sim := ZombieSim.new(ZombieTuning.new(), 3)
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	sim.tick(10.0, {1: Vector3(60, 0, 0)})
	# Ten seconds at 2 m/s is 20 m; the catch-up is a fraction of a second.
	assert_float(zombie.position.x).is_less(1.5)
