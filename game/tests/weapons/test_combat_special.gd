extends GdUnitTestSuite
## The server end to end, part two: pellets, projectiles, melee, and that every action and event
## is plain data.

const SHOOTER := WeaponsFixture.SHOOTER
const BODY := Vector3(0, 1.1, 0)

var _server: CombatServer


func before_test() -> void:
	_server = WeaponsFixture.make_server()
	_server.apply(CombatAction.register_target(1, 60.0))
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	WeaponsFixture.step(_server, {1: Vector3.ZERO}, 2)


func _fire(to: Vector3, seq: int = 1, from: Vector3 = SHOOTER) -> Array[Dictionary]:
	return _server.apply(WeaponsFixture.fire_at(1, seq, from, to, _server.now))


func test_the_shotgun_hurts_a_close_target_from_many_pellets_once() -> void:
	_server.apply(CombatAction.give_weapon(1, &"shotgun"))
	_server.apply(CombatAction.register_target(2, 500.0))
	WeaponsFixture.step(_server, {1: Vector3(20, 0, 0), 2: Vector3.ZERO}, 2)
	var events := _fire(BODY, 1, Vector3(0, 1.1, 3))
	var damage := WeaponsFixture.of(events, &"damage_dealt")
	assert_array(damage).has_size(1)
	assert_int(damage[0]["pellets"]).is_greater_equal(5)
	assert_float(damage[0]["damage"]).is_greater(50.0)


func test_the_same_shot_number_scatters_the_same_way_on_a_second_server() -> void:
	var other := WeaponsFixture.make_server()
	other.apply(CombatAction.register_target(1, 60.0))
	WeaponsFixture.step(other, {1: Vector3.ZERO}, 2)
	for server in [_server, other]:
		server.apply(CombatAction.give_weapon(1, &"shotgun"))
	var a := _fire(BODY, 5, Vector3(0, 1.1, 12))
	var b := other.apply(WeaponsFixture.fire_at(1, 5, Vector3(0, 1.1, 12), BODY, other.now))
	assert_array(WeaponsFixture.of(a, &"shot_fired")[0]["ends"]).is_equal(
		WeaponsFixture.of(b, &"shot_fired")[0]["ends"]
	)


func test_a_flare_flies_bursts_on_the_target_and_hurts_its_neighbour() -> void:
	_server.apply(CombatAction.give_weapon(1, &"flare_gun"))
	_server.apply(CombatAction.register_target(1, 300.0))
	_server.apply(CombatAction.register_target(2, 300.0))
	var targets := {1: Vector3(0, 0, 0), 2: Vector3(1.0, 0, 0)}
	WeaponsFixture.step(_server, targets, 2)
	var launch := _fire(BODY)
	assert_array(WeaponsFixture.of(launch, &"projectile_spawned")).has_size(1)
	assert_array(WeaponsFixture.of(launch, &"damage_dealt")).is_empty()
	assert_int(_server.projectiles_in_flight()).is_equal(1)
	var events: Array[Dictionary] = []
	for _i in 60:
		server_step(targets, events)
	var burst := WeaponsFixture.of(events, &"projectile_burst")
	assert_array(burst).has_size(1)
	assert_str(burst[0]["kind"]).is_equal("target")
	assert_int(_server.projectiles_in_flight()).is_equal(0)
	var by_target := {}
	for hit in WeaponsFixture.of(events, &"damage_dealt"):
		by_target[hit["target_id"]] = hit["damage"]
	assert_float(by_target[1]).is_greater_equal(90.0)
	assert_float(by_target[2]).is_between(1.0, 60.0)


func server_step(targets: Dictionary, into: Array[Dictionary]) -> void:
	into.append_array(_server.apply(CombatAction.targets(WeaponsFixture.list_of(targets))))
	into.append_array(_server.apply(CombatAction.tick(WeaponsFixture.STEP)))


func test_a_flare_into_a_wall_bursts_on_the_wall() -> void:
	var wall := AABB(Vector3(-3, 0, 3.9), Vector3(6, 3, 0.2))
	var server := WeaponsFixture.make_server(null, WeaponsFixture.box_world(wall))
	server.apply(CombatAction.give_weapon(1, &"flare_gun"))
	server.apply(CombatAction.fire(1, 1, SHOOTER, Vector3(0, 0, -1), SHOOTER, 0.0))
	var events: Array[Dictionary] = []
	for _i in 60:
		events.append_array(server.apply(CombatAction.tick(WeaponsFixture.STEP)))
	var burst := WeaponsFixture.of(events, &"projectile_burst")
	assert_array(burst).has_size(1)
	assert_str(burst[0]["kind"]).is_equal("world")
	assert_float(burst[0]["point"].z).is_equal_approx(4.1, 0.1)


func test_a_flare_that_hits_nothing_bursts_in_the_air_when_its_time_is_up() -> void:
	_server.apply(CombatAction.give_weapon(1, &"flare_gun"))
	_server.apply(CombatAction.fire(1, 1, SHOOTER, Vector3(0, 0.5, -1).normalized(), SHOOTER, 0.0))
	var events: Array[Dictionary] = []
	for _i in 200:
		events.append_array(_server.apply(CombatAction.tick(WeaponsFixture.STEP)))
	var burst := WeaponsFixture.of(events, &"projectile_burst")
	assert_array(burst).has_size(1)
	assert_str(burst[0]["kind"]).is_equal("expired")


func test_a_crowbar_swing_hits_what_is_in_front_and_pays_as_melee() -> void:
	_server.apply(CombatAction.give_weapon(1, &"crowbar"))
	WeaponsFixture.step(_server, {1: Vector3(0, 0, -1.2)}, 2)
	var swing := CombatAction.fire(
		1, 1, Vector3(0, 1.1, 0), Vector3(0, 0, -1), Vector3(0, 1.1, 0), _server.now
	)
	var events := _server.apply(swing)
	var hit := WeaponsFixture.of(events, &"damage_dealt")[0]
	assert_bool(hit["melee"]).is_true()
	assert_float(hit["damage"]).is_equal_approx(45.0, 0.5)
	assert_int(WeaponsFixture.of(events, &"shot_fired")[0]["ammo"]).is_equal(0)


func test_a_swing_at_nothing_hits_nothing() -> void:
	_server.apply(CombatAction.give_weapon(1, &"crowbar"))
	WeaponsFixture.step(_server, {1: Vector3(0, 0, -5)}, 2)
	var swing := CombatAction.fire(
		1, 1, Vector3(0, 1.1, 0), Vector3(0, 0, -1), Vector3(0, 1.1, 0), _server.now
	)
	assert_array(WeaponsFixture.of(_server.apply(swing), &"damage_dealt")).is_empty()


func test_actions_and_events_are_plain_data_that_survive_the_wire() -> void:
	var actions: Array[Dictionary] = [
		WeaponsFixture.fire_at(1, 3, SHOOTER, BODY, 0.5),
		CombatAction.reload_weapon(1),
		CombatAction.give_weapon(1, &"rifle"),
		CombatAction.targets(WeaponsFixture.list_of({1: Vector3.ZERO})),
		CombatAction.tick(WeaponsFixture.STEP),
	]
	for action in actions:
		assert_dict(bytes_to_var(var_to_bytes(action))).is_equal(action)
	var events := _fire(BODY)
	assert_array(events).is_not_empty()
	for event in events:
		assert_dict(bytes_to_var(var_to_bytes(event))).is_equal(event)


func test_an_action_that_crossed_the_wire_does_the_same_as_the_original() -> void:
	var twin := WeaponsFixture.make_server()
	twin.apply(CombatAction.register_target(1, 60.0))
	twin.apply(CombatAction.give_weapon(1, &"pistol"))
	WeaponsFixture.step(twin, {1: Vector3.ZERO}, 2)
	var action := WeaponsFixture.fire_at(1, 1, SHOOTER, BODY, twin.now)
	var direct := _server.apply(action)
	var wired := twin.apply(bytes_to_var(var_to_bytes(action)))
	assert_array(wired).is_equal(direct)


func test_an_unknown_action_is_refused_not_crashed() -> void:
	var events := _server.apply({"type": &"cheat"})
	assert_str(events[0]["type"]).is_equal("action_rejected")
	assert_array(_server.apply({})).has_size(1)
