extends GdUnitTestSuite
## The server end to end: firing, damage, kills into the rules, reload, projectiles, melee and
## that every action and event is plain data.

const SHOOTER := WeaponsFixture.SHOOTER
const BODY := Vector3(0, 1.1, 0)
const HEAD := Vector3(0, 1.62, 0)

var _server: CombatServer


func before_test() -> void:
	_server = WeaponsFixture.make_server()
	_server.apply(CombatAction.register_target(1, 60.0))
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	WeaponsFixture.step(_server, {1: Vector3.ZERO}, 2)


func _fire(to: Vector3, seq: int = 1, from: Vector3 = SHOOTER) -> Array[Dictionary]:
	return _server.apply(WeaponsFixture.fire_at(1, seq, from, to, _server.now))


func test_a_body_shot_hurts_and_a_headshot_kills() -> void:
	var body := _fire(BODY, 1)
	var hurt := WeaponsFixture.of(body, &"damage_dealt")[0]
	assert_float(hurt["damage"]).is_equal_approx(24.0, 0.01)
	assert_float(hurt["health"]).is_equal_approx(36.0, 0.01)
	assert_bool(hurt["headshot"]).is_false()
	WeaponsFixture.step(_server, {1: Vector3.ZERO}, 30)
	var head := _fire(HEAD, 2)
	assert_array(WeaponsFixture.of(head, &"target_killed")).has_size(1)
	assert_bool(WeaponsFixture.of(head, &"target_killed")[0]["headshot"]).is_true()
	assert_bool(_server.is_target_alive(1)).is_false()


func test_the_distance_costs_damage() -> void:
	var near := WeaponsFixture.of(_fire(BODY, 1, Vector3(0, 1.1, 5)), &"damage_dealt")[0]
	WeaponsFixture.step(_server, {1: Vector3.ZERO}, 30)
	var far := WeaponsFixture.of(_fire(BODY, 2, Vector3(0, 1.1, 40)), &"damage_dealt")[0]
	assert_float(far["damage"]).is_less(near["damage"])


func test_a_miss_still_spends_the_round_and_reports_the_tracer() -> void:
	var events := _fire(Vector3(8, 1.1, 0))
	assert_array(WeaponsFixture.of(events, &"damage_dealt")).is_empty()
	var fired := WeaponsFixture.of(events, &"shot_fired")[0]
	assert_int(fired["ammo"]).is_equal(9)
	assert_array(fired["ends"]).has_size(1)


func test_the_fire_interval_is_enforced_by_the_server() -> void:
	_fire(BODY, 1)
	var again := _fire(BODY, 2)
	assert_str(WeaponsFixture.of(again, &"fire_rejected")[0]["reason"]).is_equal("cooldown")
	assert_array(WeaponsFixture.of(again, &"damage_dealt")).is_empty()
	WeaponsFixture.step(_server, {1: Vector3.ZERO}, 20)
	assert_array(WeaponsFixture.of(_fire(BODY, 3), &"fire_rejected")).is_empty()


func test_an_empty_magazine_starts_a_reload_that_ends_with_a_full_one() -> void:
	_server.weapon_of(1).ammo = 0
	var events := _fire(BODY)
	assert_str(WeaponsFixture.of(events, &"fire_rejected")[0]["reason"]).is_equal("empty")
	assert_array(WeaponsFixture.of(events, &"reload_started")).has_size(1)
	assert_str(WeaponsFixture.of(_fire(BODY, 2), &"fire_rejected")[0]["reason"]).is_equal(
		"reloading"
	)
	var finished: Array[Dictionary] = []
	for _i in 100:
		var stepped := _server.apply(CombatAction.tick(WeaponsFixture.STEP))
		finished.append_array(WeaponsFixture.of(stepped, &"reload_finished"))
	assert_array(finished).has_size(1)
	assert_int(finished[0]["ammo"]).is_equal(10)
	assert_int(finished[0]["reserve"]).is_equal(30)


func test_a_reload_can_be_asked_for() -> void:
	_fire(BODY)
	var started := _server.apply(CombatAction.reload_weapon(1))
	assert_array(WeaponsFixture.of(started, &"reload_started")).has_size(1)
	var again := _server.apply(CombatAction.reload_weapon(1))
	assert_str(WeaponsFixture.of(again, &"reload_rejected")[0]["reason"]).is_equal("reloading")


func test_switching_weapons_cancels_a_reload() -> void:
	_fire(BODY)
	_server.apply(CombatAction.reload_weapon(1))
	_server.apply(CombatAction.give_weapon(1, &"smg"))
	_server.apply(CombatAction.equip(1, &"pistol"))
	assert_bool(_server.weapon_of(1).is_reloading()).is_false()


func test_a_player_without_a_weapon_cannot_fire() -> void:
	var events := _server.apply(WeaponsFixture.fire_at(9, 1, SHOOTER, BODY, 0.0))
	assert_str(WeaponsFixture.of(events, &"fire_rejected")[0]["reason"]).is_equal("no_weapon")


func test_a_nonsense_aim_is_refused() -> void:
	var bad := CombatAction.fire(1, 1, SHOOTER, Vector3.ZERO, SHOOTER, 0.0)
	assert_str(WeaponsFixture.of(_server.apply(bad), &"fire_rejected")[0]["reason"]).is_equal(
		"bad_aim"
	)
	var nan := CombatAction.fire(1, 2, SHOOTER, Vector3(NAN, 0, 1), SHOOTER, 0.0)
	assert_str(WeaponsFixture.of(_server.apply(nan), &"fire_rejected")[0]["reason"]).is_equal(
		"bad_aim"
	)


func test_a_dead_target_cannot_be_shot_again() -> void:
	_server.apply(CombatAction.remove_target(1))
	assert_array(WeaponsFixture.of(_fire(BODY), &"damage_dealt")).is_empty()
