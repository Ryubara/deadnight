extends GdUnitTestSuite
## The zombies joined to the rules: spawn from events, hits through the rules, deaths from events,
## the crowd cap, and the wire format.

var _rules: GameRules
var _sim: ZombieSim
var _director: ZombieDirector
var _struck: Array[Dictionary] = []


func _begin(round_tuning: Callable = Callable(), players: int = 1) -> void:
	var tuning := RulesFixture.tuning()
	if round_tuning.is_valid():
		round_tuning.call(tuning.rounds)
	_rules = RulesFixture.make_rules(players, 99, tuning)
	_sim = ZombieFixture.sim()
	var points: Array[Vector3] = [Vector3(30, 0, 0), Vector3(-30, 0, 0)]
	_director = ZombieDirector.new(_rules, _sim, points)
	_struck.clear()
	_director.player_struck.connect(
		func(player_id: int, zombie_id: int, damage: float) -> void:
			_struck.append({"player": player_id, "zombie": zombie_id, "damage": damage})
	)
	RulesFixture.into_round_one(_rules)


## Lets the rules and the zombies run `seconds` together, players standing at the origin.
func _run(seconds: float) -> void:
	var targets := {1: Vector3.ZERO}
	for _i in ceili(seconds / ZombieSim.STEP):
		_rules.apply(RulesAction.tick(ZombieSim.STEP))
		_director.tick(ZombieSim.STEP, targets)


func test_a_spawn_request_puts_a_zombie_at_the_rolled_spawn_point() -> void:
	_begin()
	_run(2.0)
	assert_int(_sim.zombies.size()).is_greater(0)
	var zombie: ZombieBody = _sim.zombies.values()[0]
	assert_float(absf(zombie.position.x)).is_greater(25.0)


func test_a_killing_hit_goes_through_the_rules_and_the_zombie_falls() -> void:
	_begin()
	_run(2.0)
	var zombie_id: int = _sim.zombies.keys()[0]
	var result := _director.take_hit(zombie_id, &"head", 1000.0, 1, false)
	assert_bool(result["killed"]).is_true()
	assert_int(_sim.zombies[zombie_id].mode).is_equal(ZombieBody.Mode.DYING)
	assert_int(_rules.players[1].kills).is_equal(1)
	assert_int(_rules.players[1].headshot_kills).is_equal(1)


func test_a_hit_that_does_not_kill_pays_staggers_and_leaves_it_standing() -> void:
	_begin()
	_run(2.0)
	var zombie_id: int = _sim.zombies.keys()[0]
	var points := _rules.points_of(1)
	_sim.zombies[zombie_id].enter(ZombieBody.Mode.CHASE)
	var result := _director.take_hit(zombie_id, &"body", 1.0, 1)
	assert_bool(result["accepted"]).is_true()
	assert_bool(result["killed"]).is_false()
	assert_int(_sim.zombies[zombie_id].mode).is_equal(ZombieBody.Mode.STAGGER)
	assert_int(_rules.points_of(1)).is_greater(points)


func test_a_hit_on_a_dead_zombie_is_not_accepted_and_pays_nothing() -> void:
	_begin()
	_run(2.0)
	var zombie_id: int = _sim.zombies.keys()[0]
	_director.take_hit(zombie_id, &"body", 1000.0, 1)
	var points := _rules.points_of(1)
	var again := _director.take_hit(zombie_id, &"head", 1000.0, 1)
	assert_bool(again["accepted"]).is_false()
	assert_int(_rules.points_of(1)).is_equal(points)


func test_a_removal_without_a_killer_just_takes_the_zombie_away() -> void:
	_begin()
	_run(2.0)
	var zombie_id: int = _sim.zombies.keys()[0]
	_rules.apply(RulesAction.zombie_gone(zombie_id))
	assert_bool(_sim.zombies.has(zombie_id)).is_false()


func test_requests_past_the_crowd_cap_wait_for_a_kill() -> void:
	_begin(
		func(rounds: RoundTuning) -> void:
			rounds.alive_cap_start = 60.0
			rounds.alive_cap_max = 60.0
			rounds.count_base = 80.0
			rounds.spawn_interval_start = 0.2
			rounds.spawn_interval_min = 0.2
	)
	_run(30.0)
	assert_int(_sim.standing_count()).is_equal(_sim.tuning.hard_cap)
	assert_int(_director.waiting_count()).is_greater(0)
	var victim: int = _sim.zombies.keys()[0]
	_director.take_hit(victim, &"body", 10000.0, 1)
	_run(0.1)
	assert_int(_sim.standing_count()).is_equal(_sim.tuning.hard_cap)


func test_a_zombie_that_reaches_a_player_reports_the_blow() -> void:
	_begin()
	_run(40.0)
	assert_int(_struck.size()).is_greater(0)
	assert_int(_struck[0]["player"]).is_equal(1)


func test_the_wire_format_round_trips_what_a_client_needs() -> void:
	var sim := ZombieFixture.sim()
	var zombie := sim.spawn(300, 3.0, Vector3(12.34, 0.5, -7.89), 1.0)
	zombie.move_speed = 3.0
	zombie.yaw = -2.0
	var bytes := ZombieCodec.encode(sim.zombies)
	assert_int(bytes.size()).is_equal(ZombieCodec.HEADER_BYTES + ZombieCodec.ENTRY_BYTES)
	var entry := ZombieCodec.decode(bytes)[0]
	assert_int(entry["id"]).is_equal(300)
	assert_vector(entry["position"]).is_equal_approx(zombie.position, Vector3.ONE * 0.006)
	assert_float(entry["yaw"]).is_equal_approx(wrapf(-2.0, 0.0, TAU), 0.02)
	assert_int(entry["mode"]).is_equal(ZombieBody.Mode.EMERGING)
	assert_float(entry["speed"]).is_equal_approx(3.0, 0.03)


func test_a_short_packet_decodes_to_nothing() -> void:
	var sim := ZombieFixture.sim()
	sim.spawn(1, 1.0, Vector3.ZERO)
	var bytes := ZombieCodec.encode(sim.zombies)
	bytes.resize(bytes.size() - 1)
	assert_array(ZombieCodec.decode(bytes)).is_empty()
	assert_array(ZombieCodec.decode(PackedByteArray())).is_empty()
