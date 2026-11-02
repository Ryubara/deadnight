# A lure (a burning flare) calls the zombies near it away from the players, for a while, and then
# lets them go (#439). The sim only: where the lure comes from is the weapons' and the night's.
extends GdUnitTestSuite

const SECONDS := 8.0
const RADIUS := 25.0
const LURE_AT := Vector3(0.0, 0.0, 40.0)
const PLAYER_AT := Vector3(0.0, 0.0, 0.0)
const TARGETS := {1: Vector3(0.0, 0.0, 0.0)}

var _sim: ZombieSim


func before_test() -> void:
	_sim = ZombieFixture.sim()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A zombie standing at `at`, up and chasing, with the player as its target.
func _zombie(zombie_id: int, at: Vector3) -> ZombieBody:
	var zombie := ZombieFixture.standing(_sim, zombie_id, at, 2.0)
	zombie.target_id = 1
	return zombie


func test_zombies_inside_the_radius_go_to_the_lure_and_stand_about_it() -> void:
	var near := _zombie(1, Vector3(10.0, 0.0, 30.0))
	_sim.add_lure(5, LURE_AT, RADIUS, SECONDS)
	ZombieFixture.run(_sim, 7.0, TARGETS)
	assert_float(_flat(near.position, LURE_AT)).is_less(_sim.tuning.lure_gather_distance + 0.3)
	# It stands there, facing the lure, and does not swing.
	assert_vector(near.velocity).is_equal(Vector3.ZERO)
	var toward := LURE_AT - near.position
	assert_float(absf(angle_difference(near.yaw, atan2(toward.x, toward.z)))).is_less(0.5)


func test_zombies_outside_the_radius_keep_chasing_the_player() -> void:
	var far := _zombie(2, Vector3(0.0, 0.0, 80.0))
	_sim.add_lure(5, LURE_AT, RADIUS, SECONDS)
	var before := _flat(far.position, PLAYER_AT)
	ZombieFixture.run(_sim, 3.0, TARGETS)
	assert_float(_flat(far.position, PLAYER_AT)).is_less(before - 3.0)
	assert_float(_flat(far.position, LURE_AT)).is_greater(RADIUS)
	assert_int(far.lure_id).is_equal(0)


func test_the_zombies_go_back_to_the_players_when_it_burns_out() -> void:
	var near := _zombie(1, Vector3(10.0, 0.0, 30.0))
	_sim.add_lure(5, LURE_AT, RADIUS, SECONDS)
	ZombieFixture.run(_sim, SECONDS - 1.0, TARGETS)
	assert_int(_sim.lures.size()).is_equal(1)
	assert_int(near.lure_id).is_equal(5)
	ZombieFixture.run(_sim, 2.0, TARGETS)
	assert_int(_sim.lures.size()).is_equal(0)
	assert_int(near.lure_id).is_equal(0)
	var at_burnout := _flat(near.position, PLAYER_AT)
	ZombieFixture.run(_sim, 4.0, TARGETS)
	assert_float(_flat(near.position, PLAYER_AT)).is_less(at_burnout - 4.0)


func test_a_lured_zombie_next_to_a_player_walks_away_and_never_swings() -> void:
	var near := _zombie(1, Vector3(0.0, 0.0, 3.0))
	_sim.add_lure(5, LURE_AT, RADIUS + 20.0, SECONDS)
	var events := ZombieFixture.run(_sim, 5.0, TARGETS)
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)
	assert_float(_flat(near.position, LURE_AT)).is_less(_flat(Vector3(0, 0, 3), LURE_AT) - 8.0)


func test_the_nearest_of_two_lures_wins() -> void:
	var zombie := _zombie(1, Vector3(0.0, 0.0, 30.0))
	_sim.add_lure(5, Vector3(0.0, 0.0, 60.0), RADIUS + 10.0, SECONDS)
	_sim.add_lure(6, Vector3(0.0, 0.0, 20.0), RADIUS, SECONDS)
	ZombieFixture.run(_sim, 1.0, TARGETS)
	assert_int(zombie.lure_id).is_equal(6)


func test_a_zombie_still_rising_hears_nothing_until_it_is_up() -> void:
	var rising := _sim.spawn(1, 2.0, Vector3(10.0, 0.0, 30.0))
	rising.target_id = 1
	_sim.add_lure(5, LURE_AT, RADIUS, SECONDS)
	ZombieFixture.run(_sim, 0.2, TARGETS)
	assert_int(rising.lure_id).is_equal(0)
	assert_int(rising.mode).is_equal(ZombieBody.Mode.EMERGING)
	ZombieFixture.run(_sim, 3.0, TARGETS)
	assert_int(rising.lure_id).is_equal(5)


func test_boards_a_boss_and_a_swing_in_progress_are_left_alone_by_default() -> void:
	var tearing := _zombie(1, Vector3(10.0, 0.0, 30.0))
	tearing.gate_id = &"north"
	var boss := _zombie(2, Vector3(12.0, 0.0, 30.0))
	boss.profile = ZombieProfile.plain(_sim.tuning)
	boss.profile.boss = true
	var swinging := _zombie(3, Vector3(14.0, 0.0, 30.0))
	swinging.enter(ZombieBody.Mode.ATTACK)
	_sim.add_lure(5, LURE_AT, RADIUS, SECONDS)
	_sim.tick(ZombieFixture.STEP, TARGETS)
	assert_int(tearing.lure_id).is_equal(0)
	assert_int(boss.lure_id).is_equal(0)
	assert_int(swinging.lure_id).is_equal(0)


func test_the_tuning_can_pull_the_boards_the_boss_and_the_swing_too() -> void:
	_sim.tuning.lure_pulls_gate_zombies = true
	_sim.tuning.lure_pulls_bosses = true
	_sim.tuning.lure_breaks_swings = true
	var tearing := _zombie(1, Vector3(10.0, 0.0, 30.0))
	tearing.gate_id = &"north"
	var boss := _zombie(2, Vector3(12.0, 0.0, 30.0))
	boss.profile = ZombieProfile.plain(_sim.tuning)
	boss.profile.boss = true
	var swinging := _zombie(3, Vector3(14.0, 0.0, 30.0))
	swinging.enter(ZombieBody.Mode.ATTACK)
	_sim.add_lure(5, LURE_AT, RADIUS, SECONDS)
	_sim.tick(ZombieFixture.STEP, TARGETS)
	assert_int(tearing.lure_id).is_equal(5)
	assert_int(boss.lure_id).is_equal(5)
	assert_int(swinging.lure_id).is_equal(5)


func test_a_lure_with_the_same_id_replaces_the_first() -> void:
	_sim.add_lure(5, LURE_AT, RADIUS, SECONDS)
	_sim.add_lure(5, Vector3(1.0, 0.0, 1.0), 3.0, 1.0)
	assert_int(_sim.lures.size()).is_equal(1)
	assert_float(_sim.lures[0].radius).is_equal(3.0)


func test_a_run_with_a_lure_is_the_same_every_time() -> void:
	var hashes: Array[int] = []
	for _run in 2:
		var sim := ZombieFixture.sim(11)
		for i in 5:
			var zombie := ZombieFixture.standing(sim, i + 1, Vector3(float(i) * 3.0, 0.0, 30.0))
			zombie.target_id = 1
		sim.add_lure(5, LURE_AT, RADIUS, SECONDS)
		var running := 0
		for _i in 180:
			sim.tick(ZombieFixture.STEP, TARGETS)
			running = ZombieFixture.state_hash(sim, running)
		hashes.append(running)
	assert_int(hashes[0]).is_equal(hashes[1])
