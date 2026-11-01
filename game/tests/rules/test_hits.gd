extends GdUnitTestSuite
## Hits and kills: the rules own each zombie's health, so a hit pays only while it lives.

var _rules: GameRules
var _log: RulesFixture
var _zombie: int


func before_test() -> void:
	_rules = RulesFixture.make_rules(2)
	_log = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 2.0)
	_zombie = _log.spawned_ids()[0]


func _hit(
	zone: StringName, damage: float, player_id: int = 1, zombie_id: int = -1
) -> Array[Dictionary]:
	var target := _zombie if zombie_id < 0 else zombie_id
	return _rules.apply(RulesAction.hit(player_id, target, zone, damage))


func _health_left(zombie_id: int) -> float:
	return (_rules.to_dict()["zombies"][zombie_id] as Dictionary)["health"]


func test_a_body_hit_pays_a_little_and_takes_health_off() -> void:
	var events := _hit(RulesAction.ZONE_BODY, 20.0)
	assert_int(_rules.points_of(1)).is_equal(204)
	assert_float(_health_left(_zombie)).is_equal(40.0)
	assert_str(events[0]["type"]).is_equal("zombie_damaged")
	assert_float(events[0]["health"]).is_equal(40.0)
	assert_float(events[0]["damage"]).is_equal(20.0)
	assert_str(events[0]["zone"]).is_equal("body")


func test_a_headshot_hit_pays_double() -> void:
	_hit(RulesAction.ZONE_HEAD, 20.0)
	assert_int(_rules.points_of(1)).is_equal(208)


func test_the_hit_that_empties_the_health_is_the_kill() -> void:
	_hit(RulesAction.ZONE_BODY, 30.0)
	_hit(RulesAction.ZONE_BODY, 29.0)
	assert_int(_log.count(&"zombie_removed")).is_equal(0)
	var events := _hit(RulesAction.ZONE_BODY, 1.0)
	assert_int(_log.count(&"zombie_removed")).is_equal(1)
	assert_str(events.back()["type"]).is_equal("zombie_removed")
	assert_str(events.back()["cause"]).is_equal("killed")
	# Two body hits at 4, then the kill at 60 (not a third hit's 4 as well).
	assert_int(_rules.points_of(1)).is_equal(200 + 4 + 4 + 60)


func test_kills_pay_by_how_they_were_made() -> void:
	RulesFixture.run(_rules, 10.0)
	var ids := _log.spawned_ids()
	RulesFixture.kill(_rules, 1, ids[0])
	assert_int(_rules.points_of(1)).is_equal(200 + 60)
	RulesFixture.kill(_rules, 1, ids[1], RulesAction.ZONE_HEAD)
	assert_int(_rules.points_of(1)).is_equal(260 + 100)
	RulesFixture.kill(_rules, 1, ids[2], RulesAction.ZONE_BODY, true)
	assert_int(_rules.points_of(1)).is_equal(360 + 130)


func test_the_kill_is_credited_and_counted() -> void:
	RulesFixture.kill(_rules, 1, _zombie, RulesAction.ZONE_HEAD)
	var removed := _log.of(&"zombie_removed")[0]
	assert_int(removed["zombie_id"]).is_equal(_zombie)
	assert_int(removed["killer_id"]).is_equal(1)
	assert_str(removed["cause"]).is_equal("killed")
	assert_str(removed["zone"]).is_equal("head")
	assert_bool(removed["melee"]).is_false()
	assert_int((_rules.players[1] as PlayerState).kills).is_equal(1)
	assert_int((_rules.players[1] as PlayerState).headshot_kills).is_equal(1)


func test_overkill_pays_one_kill_and_damages_only_what_was_left() -> void:
	var events := RulesFixture.kill(_rules, 1, _zombie)
	assert_float(events[0]["damage"]).is_equal(60.0)
	assert_float(events[0]["health"]).is_equal(0.0)
	assert_int(_rules.points_of(1)).is_equal(260)


func test_a_zombie_pays_once_however_many_times_it_is_reported() -> void:
	RulesFixture.kill(_rules, 1, _zombie)
	var again := RulesFixture.kill(_rules, 1, _zombie)
	RulesFixture.kill(_rules, 2, _zombie)
	_hit(RulesAction.ZONE_BODY, 20.0)
	assert_int(_rules.points_of(1)).is_equal(260)
	assert_int(_rules.points_of(2)).is_equal(200)
	assert_str(again[0]["reason"]).is_equal("unknown_zombie")
	assert_int(_log.count(&"zombie_removed")).is_equal(1)


func test_farming_one_zombie_with_many_small_hits_pays_a_bounded_purse() -> void:
	for _i in 1000:
		_hit(RulesAction.ZONE_HEAD, 0.01)
	# Four paid hits at 8, then nothing; the zombie is still alive.
	assert_int(_rules.points_of(1)).is_equal(200 + 4 * 8)
	assert_float(_health_left(_zombie)).is_between(49.0, 51.0)
	RulesFixture.kill(_rules, 1, _zombie, RulesAction.ZONE_HEAD)
	assert_int(_rules.points_of(1)).is_equal(200 + 4 * 8 + 100)


func test_farming_with_real_damage_ends_at_the_kill() -> void:
	for _i in 1000:
		_hit(RulesAction.ZONE_HEAD, 20.0)
	# Hits of 20 against 60 health: two paid hits, then the kill; the rest hit a dead zombie.
	assert_int(_rules.points_of(1)).is_equal(200 + 2 * 8 + 100)
	assert_int(_log.count(&"zombie_removed")).is_equal(1)


func test_a_zombie_that_never_existed_pays_nothing() -> void:
	var events := _hit(RulesAction.ZONE_BODY, 20.0, 1, 9999)
	assert_str(events[0]["reason"]).is_equal("unknown_zombie")
	assert_int(_rules.points_of(1)).is_equal(200)


func test_a_downed_player_cannot_hit() -> void:
	_rules.apply(RulesAction.set_downed(1, true))
	var events := _hit(RulesAction.ZONE_BODY, 1000.0)
	assert_str(events[0]["reason"]).is_equal("player_downed")
	assert_int(_rules.points_of(1)).is_equal(200)
	assert_int(_log.count(&"zombie_removed")).is_equal(0)


func test_a_hit_from_a_player_the_rules_do_not_know_is_rejected() -> void:
	var events := _hit(RulesAction.ZONE_BODY, 20.0, 77)
	assert_str(events[0]["reason"]).is_equal("unknown_player")


func test_a_zombie_lost_to_a_trap_pays_nobody() -> void:
	var events := _rules.apply(RulesAction.zombie_gone(_zombie))
	assert_str(events[0]["cause"]).is_equal("gone")
	assert_int(events[0]["killer_id"]).is_equal(-1)
	assert_int(_rules.points_of(1)).is_equal(200)
	assert_str(_rules.apply(RulesAction.zombie_gone(_zombie))[0]["reason"]).is_equal(
		"unknown_zombie"
	)
