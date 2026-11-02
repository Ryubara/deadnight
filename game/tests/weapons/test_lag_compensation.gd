extends GdUnitTestSuite
## The rewind: the server judges a shot against where the shooter saw the target, up to a cap.

const SPEED := 4.0  # m/s along x
const SHOOTER := Vector3(0, 1.1, 10)


func _x_at(time: float) -> Vector3:
	return Vector3(SPEED * time, 0, 0)


## A server on which one zombie (id 1) has been walking along x for `seconds`.
func _walked(seconds: float) -> CombatServer:
	var server := WeaponsFixture.make_server()
	server.apply(CombatAction.give_weapon(1, &"rifle"))
	var steps := roundi(seconds / WeaponsFixture.STEP)
	for _i in steps:
		server.apply(CombatAction.targets([{"id": 1, "pos": _x_at(server.now), "yaw": 0.0}]))
		server.apply(CombatAction.tick(WeaponsFixture.STEP))
	server.apply(CombatAction.targets([{"id": 1, "pos": _x_at(server.now), "yaw": 0.0}]))
	return server


func _shot_at_where_it_was(server: CombatServer, ago: float, view_ago: float) -> Array[Dictionary]:
	var aim := _x_at(server.now - ago) + Vector3(0, 1.1, 0)
	var view_time := server.now - view_ago
	return server.apply(WeaponsFixture.fire_at(1, 1, SHOOTER, aim, view_time))


func test_it_remembers_and_interpolates_between_frames() -> void:
	var lag := LagCompensator.new()
	lag.record(0.0, [{"id": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0}])
	lag.record(0.1, [{"id": 1, "pos": Vector3(10, 0, 0), "yaw": 0.0}])
	var halfway := lag.rewind(0.05, 0.1)
	assert_vector(halfway["targets"][1]["pos"]).is_equal_approx(
		Vector3(5, 0, 0), Vector3.ONE * 0.001
	)
	assert_float(halfway["rewound_by"]).is_equal_approx(0.05, 0.0001)
	assert_bool(halfway["clamped"]).is_false()


func test_a_view_time_in_the_future_answers_now() -> void:
	var lag := LagCompensator.new()
	lag.record(0.0, [{"id": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0}])
	lag.record(0.1, [{"id": 1, "pos": Vector3(10, 0, 0), "yaw": 0.0}])
	var answer := lag.rewind(5.0, 0.1)
	assert_vector(answer["targets"][1]["pos"]).is_equal(Vector3(10, 0, 0))
	assert_float(answer["rewound_by"]).is_equal(0.0)
	assert_bool(answer["clamped"]).is_true()


func test_the_rewind_is_capped() -> void:
	var lag := LagCompensator.new(0.25)
	for i in 61:
		lag.record(i / 60.0, [{"id": 1, "pos": Vector3(i, 0, 0), "yaw": 0.0}])
	var answer := lag.rewind(0.0, 1.0)
	assert_float(answer["rewound_by"]).is_equal_approx(0.25, 0.0001)
	assert_bool(answer["clamped"]).is_true()
	assert_float(answer["targets"][1]["pos"].x).is_equal_approx(45.0, 0.01)


func test_old_frames_are_dropped() -> void:
	var lag := LagCompensator.new(0.25)
	for i in 600:
		lag.record(i / 60.0, [{"id": 1, "pos": Vector3.ZERO, "yaw": 0.0}])
	assert_int(lag.frame_count()).is_less(30)


func test_a_target_that_spawned_after_the_view_time_is_not_there() -> void:
	var lag := LagCompensator.new()
	lag.record(0.0, [{"id": 1, "pos": Vector3.ZERO, "yaw": 0.0}])
	lag.record(
		0.1, [{"id": 1, "pos": Vector3.ZERO, "yaw": 0.0}, {"id": 2, "pos": Vector3.ONE, "yaw": 0.0}]
	)
	assert_bool(lag.rewind(0.02, 0.1)["targets"].has(2)).is_false()
	assert_bool(lag.rewind(0.09, 0.1)["targets"].has(2)).is_true()


func test_with_the_rewind_a_shot_at_the_old_position_hits() -> void:
	var server := _walked(1.0)
	var events := _shot_at_where_it_was(server, 0.2, 0.2)
	assert_array(WeaponsFixture.of(events, &"damage_dealt")).has_size(1)
	assert_float(WeaponsFixture.of(events, &"shot_fired")[0]["rewound_by"]).is_equal_approx(
		0.2, 0.001
	)


func test_without_the_rewind_the_same_shot_misses() -> void:
	var server := _walked(1.0)
	var events := _shot_at_where_it_was(server, 0.2, 0.0)
	assert_array(WeaponsFixture.of(events, &"damage_dealt")).is_empty()


func test_a_client_claiming_more_lag_than_the_cap_leads_the_target() -> void:
	var server := _walked(2.0)
	# It saw the target a full second ago, but the server will only go back a quarter second.
	var events := _shot_at_where_it_was(server, 1.0, 1.0)
	assert_array(WeaponsFixture.of(events, &"damage_dealt")).is_empty()
	assert_float(WeaponsFixture.of(events, &"shot_fired")[0]["rewound_by"]).is_equal_approx(
		0.25, 0.001
	)


func test_a_shot_inside_the_cap_still_hits_at_its_edge() -> void:
	var server := _walked(2.0)
	var events := _shot_at_where_it_was(server, 0.24, 0.24)
	assert_array(WeaponsFixture.of(events, &"damage_dealt")).has_size(1)


func test_a_dead_target_cannot_be_hit_from_the_past() -> void:
	var server := _walked(1.0)
	server.apply(CombatAction.untrack_target(1))
	var events := _shot_at_where_it_was(server, 0.1, 0.1)
	assert_array(WeaponsFixture.of(events, &"damage_dealt")).is_empty()


## Shots at a zombie walking across the view, each aimed where the shooter saw it `latency` ago
## (one way to the shooter, plus the frame it was drawn from), with the rewind and without: how
## many of 24 starts of the walk (different phases of the 60 Hz step) are hits.
func _hit_rate(latency: float, rewind: bool) -> int:
	var hits := 0
	for phase in 24:
		var server := _walked(0.5 + phase * 0.0137)
		var events := _shot_at_where_it_was(server, latency, latency if rewind else 0.0)
		if not WeaponsFixture.of(events, &"damage_dealt").is_empty():
			hits += 1
	return hits


func test_the_hit_rate_at_100_and_200_ms() -> void:
	# The zombie runs at 4 m/s, a fast one: 0.4 m of lead at 100 ms and 0.8 m at 200 ms.
	var rates := {}
	for latency in [0.1, 0.2]:
		rates[latency] = [_hit_rate(latency, true), _hit_rate(latency, false)]
	print("lag compensation hits of 24 shots at a 4 m/s walker: ", rates)
	assert_int(rates[0.1][0]).is_equal(24)
	assert_int(rates[0.2][0]).is_equal(24)
	# Without it the 200 ms shots all miss (a walker is 0.8 m from where it is shot at).
	assert_int(rates[0.2][1]).is_equal(0)
	# At 100 ms the 0.4 m lead is still inside the body's zones, so both hit.
	assert_int(rates[0.1][1]).is_less_equal(rates[0.1][0])
