# A list of targets that says which state of the dead it is (`revision`, #931): the same number as
# the last action means the same list, so the combat server keeps its table and repeats the last
# frame in the lag history, and the grenade server keeps its table. A list with no revision, or a
# new one, is always read.
extends GdUnitTestSuite

const STEP := WeaponsFixture.STEP


func _at(x: float) -> Array:
	return [{"id": 1, "pos": Vector3(x, 0, 0), "yaw": 0.0}]


func test_the_lag_history_repeats_the_last_frame_with_a_new_time() -> void:
	var lag := LagCompensator.new()
	lag.record_again(0.0)
	assert_int(lag.frame_count()).is_equal(0)
	lag.record(0.0, _at(0.0))
	lag.record_again(0.1)
	lag.record(0.2, _at(10.0))
	assert_int(lag.frame_count()).is_equal(3)
	# At 0.1 it stood where it did at 0.0 (not halfway to where it was at 0.2).
	var then := lag.rewind(0.1, 0.2)
	assert_vector(then["targets"][1]["pos"]).is_equal(Vector3.ZERO)
	var between := lag.rewind(0.15, 0.2)
	assert_vector(between["targets"][1]["pos"]).is_equal_approx(
		Vector3(5, 0, 0), Vector3.ONE * 0.001
	)


func test_the_lag_history_trims_as_it_repeats() -> void:
	var lag := LagCompensator.new()
	lag.record(0.0, _at(0.0))
	for i in 600:
		lag.record_again((i + 1) * STEP)
	# 0.25 s of rewind and a margin of 0.1 s at 60 Hz: about 21 frames, not 600.
	assert_int(lag.frame_count()).is_less(30)


func test_the_combat_server_keeps_its_table_for_the_same_revision() -> void:
	var server := WeaponsFixture.make_server()
	server.apply(CombatAction.targets(_at(1.0), 5))
	server.apply(CombatAction.tick(STEP))
	var frames := server.lag.frame_count()
	# The same revision: the list is not read (it is not even looked at), but the history moves on.
	server.apply(CombatAction.targets(_at(99.0), 5))
	assert_int(server.lag.frame_count()).is_equal(frames + 1)
	assert_vector(server.lag.rewind(server.now, server.now)["targets"][1]["pos"]).is_equal(
		Vector3(1, 0, 0)
	)
	# A new revision is read, and so is a list with none.
	server.apply(CombatAction.targets(_at(2.0), 6))
	assert_vector(server.lag.rewind(server.now, server.now)["targets"][1]["pos"]).is_equal(
		Vector3(2, 0, 0)
	)
	server.apply(CombatAction.targets(_at(3.0)))
	server.apply(CombatAction.targets(_at(4.0)))
	assert_vector(server.lag.rewind(server.now, server.now)["targets"][1]["pos"]).is_equal(
		Vector3(4, 0, 0)
	)


## A zombie walking along x that the sim moves on every second tick (as the real one steps at 30
## Hz),
## told to the server with a revision (`keyed`) or without.
func _walked(keyed: bool) -> CombatServer:
	var server := WeaponsFixture.make_server()
	server.apply(CombatAction.give_weapon(1, &"rifle"))
	var x := 0.0
	var revision := 0
	for tick in 120:
		if tick % 2 == 0:
			x += 0.1
			revision += 1
		server.apply(CombatAction.targets(_at(x), revision if keyed else -1))
		server.apply(CombatAction.tick(STEP))
	server.apply(CombatAction.targets(_at(x), revision if keyed else -1))
	return server


func _shot_at(server: CombatServer, ago: float) -> Array[Dictionary]:
	# Where it stood `ago` seconds back: it walks 3 m a second.
	var aim := Vector3(3.0 * (server.now - ago), 1.1, 0)
	return server.apply(WeaponsFixture.fire_at(1, 1, WeaponsFixture.SHOOTER, aim, server.now - ago))


func test_a_rewound_shot_is_judged_the_same_with_and_without_a_revision() -> void:
	for ago in [0.0, 0.1, 0.2]:
		var keyed := _shot_at(_walked(true), ago)
		var plain := _shot_at(_walked(false), ago)
		assert_int(WeaponsFixture.of(keyed, &"damage_dealt").size()).is_equal(
			WeaponsFixture.of(plain, &"damage_dealt").size()
		)
		assert_float(WeaponsFixture.of(keyed, &"shot_fired")[0]["rewound_by"]).is_equal_approx(
			WeaponsFixture.of(plain, &"shot_fired")[0]["rewound_by"], 0.0001
		)
	# And the shot at the old place hits (the test is not two misses).
	assert_array(WeaponsFixture.of(_shot_at(_walked(true), 0.2), &"damage_dealt")).has_size(1)


func _blasted(first_revision: int, second_revision: int) -> Array[Dictionary]:
	var night := GrenadesFixture.night(1, GrenadesFixture.world_cast())
	var id := night.zombies[0]
	night.server.apply(
		GrenadeAction.targets([{"id": id, "pos": Vector3(0.5, 0, 0), "yaw": 0.0}], first_revision)
	)
	# A second list, with the zombie out of reach.
	night.server.apply(
		GrenadeAction.targets([{"id": id, "pos": Vector3(0, 0, -40), "yaw": 0.0}], second_revision)
	)
	night.server.apply(GrenadeAction.cook(1, 1, Vector3(0, 1.0, 0)))
	return night.run_seconds(GrenadesFixture.def().fuse + 0.1)


func test_the_grenade_server_keeps_its_table_for_the_same_revision() -> void:
	# The same revision: the second list is not read, the zombie still stands beside the pin.
	var events := _blasted(3, 3)
	assert_array(GrenadesFixture.of(events, &"blast_hit")).has_size(1)


func test_the_grenade_server_reads_a_new_revision_and_a_list_with_none() -> void:
	assert_array(GrenadesFixture.of(_blasted(3, 4), &"blast_hit")).is_empty()
	assert_array(GrenadesFixture.of(_blasted(-1, -1), &"blast_hit")).is_empty()
	assert_array(GrenadesFixture.of(_blasted(3, -1), &"blast_hit")).is_empty()
