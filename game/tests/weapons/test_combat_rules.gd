extends GdUnitTestSuite
## Hits and kills reach the rules engine as its own actions, and the rules' zombies are the
## server's targets.

const SHOOTER := WeaponsFixture.SHOOTER

var _rules: GameRules
var _log: RulesFixture
var _server: CombatServer
var _zombie: int


func before_test() -> void:
	_rules = RulesFixture.make_rules(1)
	_log = RulesFixture.record(_rules)
	_server = WeaponsFixture.make_server(_rules)
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 2.0)
	_zombie = _log.spawned_ids()[0]
	WeaponsFixture.step(_server, {_zombie: Vector3.ZERO}, 2)


func _fire(to: Vector3, seq: int = 1) -> Array[Dictionary]:
	return _server.apply(WeaponsFixture.fire_at(1, seq, SHOOTER, to, _server.now))


func test_a_spawned_zombie_becomes_a_target_with_the_rules_health() -> void:
	assert_bool(_server.is_target_alive(_zombie)).is_true()
	assert_float(_server.health_of(_zombie)).is_equal(60.0)


func test_a_hit_that_does_not_kill_pays_the_hit_points() -> void:
	var before := _rules.points_of(1)
	var events := _fire(Vector3(0, 1.1, 0))
	assert_int(_rules.points_of(1) - before).is_equal(4)
	assert_array(WeaponsFixture.of(events, &"points_changed")).has_size(1)


func test_a_headshot_hit_pays_double() -> void:
	_server.apply(CombatAction.register_target(_zombie, 500.0))
	var before := _rules.points_of(1)
	_fire(Vector3(0, 1.62, 0))
	assert_int(_rules.points_of(1) - before).is_equal(8)


func test_a_headshot_kill_pays_the_headshot_kill_and_removes_the_zombie() -> void:
	var before := _rules.points_of(1)
	var events := _fire(Vector3(0, 1.62, 0))
	assert_int(_rules.points_of(1) - before).is_equal(100)
	assert_array(WeaponsFixture.of(events, &"zombie_removed")).has_size(1)
	assert_bool(_server.is_target_alive(_zombie)).is_false()


func test_the_combat_events_come_before_the_rules_events_they_caused() -> void:
	var events := _fire(Vector3(0, 1.62, 0))
	var types: Array = events.map(func(e: Dictionary) -> StringName: return e["type"])
	assert_bool(types.find(&"target_killed") < types.find(&"points_changed")).is_true()


func test_a_melee_kill_pays_the_melee_price() -> void:
	_server.apply(CombatAction.register_target(_zombie, 30.0))
	_server.apply(CombatAction.give_weapon(1, &"crowbar"))
	WeaponsFixture.step(_server, {_zombie: Vector3(0, 0, -1.2)}, 2)
	var before := _rules.points_of(1)
	var swing := CombatAction.fire(
		1, 1, Vector3(0, 1.1, 0), Vector3(0, 0, -1), Vector3(0, 1.1, 0), _server.now
	)
	_server.apply(swing)
	assert_int(_rules.points_of(1) - before).is_equal(130)


func test_a_server_with_no_rules_still_runs_the_combat() -> void:
	var alone := WeaponsFixture.make_server()
	alone.apply(CombatAction.register_target(5, 20.0))
	alone.apply(CombatAction.give_weapon(1, &"pistol"))
	WeaponsFixture.step(alone, {5: Vector3.ZERO}, 2)
	var events := alone.apply(WeaponsFixture.fire_at(1, 1, SHOOTER, Vector3(0, 1.1, 0), alone.now))
	assert_array(WeaponsFixture.of(events, &"target_killed")).has_size(1)
