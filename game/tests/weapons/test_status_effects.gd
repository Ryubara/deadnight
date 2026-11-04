# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## The status effects on the combat server (#788): the freeze gun's bolt freezes the zombies in its
## burst for 3 s, any hit on a frozen zombie but the freeze gun's own kills it and shatters it, the
## bolts it takes grow with the round, a boss is only slowed, and the board that keeps the time is
## plain data that steps on the combat clock.

const SHOOTER := WeaponsFixture.SHOOTER
const BODY := Vector3(0, 1.1, 0)
## Combat steps a bolt is given to fly the 8 m to the zombie and burst (45 m/s: 11 steps).
const FLIGHT := 20

var _server: CombatServer
var _rules: GameRules
var _places := {1: Vector3.ZERO, 2: Vector3(30, 0, 0), 3: Vector3(30, 0, 5)}


func before_test() -> void:
	_places = {1: Vector3.ZERO, 2: Vector3(30, 0, 0), 3: Vector3(30, 0, 5)}
	_rules = RulesFixture.make_rules(1)
	# Zombies that a few hits do not kill: round one's have 20 health.
	_rules.tuning.rounds.health_base = 600.0
	_server = WeaponsFixture.make_server(_rules)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, WeaponsFixture.SPAWN_SECONDS * 6)
	_server.apply(CombatAction.give_weapon(1, &"freeze_gun"))
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	_server.apply(CombatAction.equip(1, &"freeze_gun"))
	assert_int(_rules.zombie_ids().size()).is_greater_equal(3)
	_stand(2)


func _stand(steps: int = 1) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _i in steps:
		events.append_array(_server.apply(CombatAction.targets(WeaponsFixture.list_of(_places))))
		events.append_array(_server.apply(CombatAction.tick(WeaponsFixture.STEP)))
	return events


func _run(seconds: float) -> Array[Dictionary]:
	return _stand(ceili(seconds / WeaponsFixture.STEP))


## One shot at the zombie in front of the shooter, and the bolt's flight until it bursts.
func _fire(seq: int = 1) -> Array[Dictionary]:
	var events := _server.apply(WeaponsFixture.fire_at(1, seq, SHOOTER, BODY, _server.now))
	events.append_array(_stand(FLIGHT))
	return events


func _cool() -> void:
	_run(1.0)


func _frozen() -> int:
	return StatusCatalog.get_def(&"frozen").wire


func _chilled() -> int:
	return StatusCatalog.get_def(&"chilled").wire


func test_the_freeze_gun_is_a_bolt_that_puts_a_status_on_its_burst() -> void:
	var freeze := WeaponCatalog.get_def(&"freeze_gun")
	assert_bool(freeze.is_projectile()).is_true()
	assert_bool(freeze.has_status()).is_true()
	assert_str(String(freeze.status)).is_equal("frozen")
	assert_float(freeze.status_seconds).is_equal(3.0)
	assert_float(freeze.splash_radius).is_equal(2.2)
	assert_float(freeze.splash_damage).is_equal(0.0)
	assert_float(freeze.damage).is_equal(30.0)
	assert_bool(WeaponCatalog.get_def(&"ray_gun").has_status()).is_false()


func test_a_bolt_freezes_the_zombie_it_hits_for_three_seconds_and_then_it_thaws() -> void:
	var events := _fire()
	var applied := WeaponsFixture.of(events, &"status_applied")
	assert_array(applied).has_size(1)
	assert_int(applied[0]["target_id"]).is_equal(1)
	assert_str(String(applied[0]["status"])).is_equal("frozen")
	assert_float(applied[0]["seconds"]).is_equal(3.0)
	assert_bool(applied[0]["halts"]).is_true()
	assert_int(applied[0]["wire"]).is_equal(_frozen())
	assert_bool(_server.statuses.has(1, &"frozen")).is_true()
	# Still frozen just before the three seconds are up, thawed just after.
	assert_array(WeaponsFixture.of(_run(2.7), &"status_ended")).is_empty()
	assert_bool(_server.statuses.has(1, &"frozen")).is_true()
	var ended := WeaponsFixture.of(_run(0.5), &"status_ended")
	assert_array(ended).has_size(1)
	assert_int(ended[0]["wire"]).is_equal(StatusDef.NONE)
	assert_bool(ended[0]["halts"]).is_false()
	assert_bool(_server.statuses.has(1, &"frozen")).is_false()


func test_the_bolt_that_freezes_does_not_shatter() -> void:
	var events := _fire()
	assert_array(WeaponsFixture.of(events, &"target_killed")).is_empty()
	var dealt := WeaponsFixture.of(events, &"damage_dealt")
	assert_array(dealt).has_size(1)
	assert_bool(dealt[0]["shattered"]).is_false()
	assert_float(dealt[0]["damage"]).is_equal(30.0)
	assert_bool(_rules.has_zombie(1)).is_true()


func test_the_burst_freezes_every_zombie_in_its_bloom_and_none_beyond() -> void:
	_places = {1: Vector3.ZERO, 2: Vector3(1.4, 0, 0), 3: Vector3(2.6, 0, 0), 4: Vector3(30, 0, 0)}
	_stand(2)
	var events := _fire()
	var point: Vector3 = WeaponsFixture.of(events, &"projectile_burst")[0]["point"]
	var frozen: Array[int] = []
	for event in WeaponsFixture.of(events, &"status_applied"):
		frozen.append(event["target_id"])
	var radius := WeaponCatalog.get_def(&"freeze_gun").splash_radius
	for id in [1, 2, 3]:
		var reach := Hitbox.distance_from(point, _places[id], 0.0)
		(
			assert_bool(frozen.has(id))
			. override_failure_message(
				"zombie %d at %.2f m of the burst (the bloom is %.1f m)" % [id, reach, radius]
			)
			. is_equal(reach <= radius)
		)
	assert_bool(frozen.has(4)).is_false()
	assert_bool(frozen.has(1) and frozen.has(2)).is_true()


func test_a_bolt_into_a_wall_still_blooms() -> void:
	var wall := AABB(Vector3(-3, 0, 3.9), Vector3(6, 3, 0.2))
	var server := WeaponsFixture.make_server(_rules, WeaponsFixture.box_world(wall))
	server.apply(CombatAction.give_weapon(1, &"freeze_gun"))
	server.apply(CombatAction.track_target(1))
	var near := {1: Vector3(0, 0, 3.0)}
	for _i in 2:
		server.apply(CombatAction.targets(WeaponsFixture.list_of(near)))
		server.apply(CombatAction.tick(WeaponsFixture.STEP))
	var events := server.apply(
		CombatAction.fire(1, 1, SHOOTER, Vector3(0, 0, -1), SHOOTER, server.now)
	)
	for _i in FLIGHT:
		events.append_array(server.apply(CombatAction.targets(WeaponsFixture.list_of(near))))
		events.append_array(server.apply(CombatAction.tick(WeaponsFixture.STEP)))
	assert_str(String(WeaponsFixture.of(events, &"projectile_burst")[0]["kind"])).is_equal("world")
	assert_array(WeaponsFixture.of(events, &"status_applied")).has_size(1)


func test_any_hit_on_a_frozen_zombie_kills_it_and_it_shatters() -> void:
	_fire(1)
	var before := _rules.zombie_health(1)
	_server.apply(CombatAction.equip(1, &"pistol"))
	_run(0.6)
	var events := _server.apply(WeaponsFixture.fire_at(1, 2, SHOOTER, BODY, _server.now))
	var killed := WeaponsFixture.of(events, &"target_killed")
	assert_array(killed).has_size(1)
	assert_bool(killed[0]["shattered"]).is_true()
	var removed := WeaponsFixture.of(events, &"zombie_removed")
	assert_array(removed).has_size(1)
	assert_bool(removed[0]["shattered"]).is_true()
	assert_str(String(removed[0]["cause"])).is_equal("killed")
	# The pistol's 24 would not have killed it: the hit took all the zombie had left.
	assert_float(before).is_greater(24.0)
	assert_bool(_rules.has_zombie(1)).is_false()
	assert_bool(_server.statuses.has(1, &"frozen")).is_false()


func test_the_freeze_guns_own_bolt_does_not_kill_a_frozen_zombie_it_keeps_it_frozen() -> void:
	_fire(1)
	_run(1.5)
	var left := _server.statuses.left(1, &"frozen")
	var events := _fire(2)
	assert_array(WeaponsFixture.of(events, &"target_killed")).is_empty()
	assert_bool(_rules.has_zombie(1)).is_true()
	# The three seconds start again.
	assert_float(_server.statuses.left(1, &"frozen")).is_greater(left)
	assert_float(_server.statuses.left(1, &"frozen")).is_greater(2.5)
	assert_bool(WeaponsFixture.of(events, &"damage_dealt")[0]["shattered"]).is_false()


func test_a_frozen_zombie_pays_the_kill_the_hit_that_broke_it_pays() -> void:
	_fire(1)
	var points := _rules.points_of(1)
	_server.apply(CombatAction.equip(1, &"pistol"))
	_run(0.6)
	var events := _server.apply(WeaponsFixture.fire_at(1, 2, SHOOTER, BODY, _server.now))
	var paid := WeaponsFixture.of(events, &"points_changed")
	assert_array(paid).is_not_empty()
	assert_str(String(paid[-1]["reason"])).is_equal("kill")
	assert_int(_rules.points_of(1)).is_greater(points)


func test_a_quick_melee_blow_on_a_frozen_zombie_shatters_it() -> void:
	_fire(1)
	var head := Vector3(0, 1.1, 1.0)
	var events := _server.apply(
		CombatAction.quick_melee(1, 5, head, Vector3(0, 0, -1), head, _server.now)
	)
	var removed := WeaponsFixture.of(events, &"zombie_removed")
	assert_array(removed).has_size(1)
	assert_bool(removed[0]["shattered"]).is_true()


func test_a_blast_on_a_frozen_zombie_kills_it_and_it_shatters() -> void:
	_fire(1)
	var events := _rules.apply(
		RulesAction.explosion(1, [{"zombie_id": 1, "damage": 1.0, "leg_damage": 0.0}])
	)
	var removed := RulesFixture.first(events, &"zombie_removed")
	assert_bool(removed.is_empty()).is_false()
	assert_bool(removed["shattered"]).is_true()
	assert_bool(_rules.has_zombie(1)).is_false()


func test_a_blast_on_a_zombie_that_is_not_frozen_does_what_it_always_did() -> void:
	var events := _rules.apply(
		RulesAction.explosion(1, [{"zombie_id": 1, "damage": 1.0, "leg_damage": 0.0}])
	)
	assert_bool(RulesFixture.first(events, &"zombie_removed").is_empty()).is_true()
	assert_bool(_rules.has_zombie(1)).is_true()


func test_a_zombie_that_thawed_is_hurt_like_any_other() -> void:
	_fire(1)
	_run(3.2)
	_server.apply(CombatAction.equip(1, &"pistol"))
	_run(0.6)
	var events := _server.apply(WeaponsFixture.fire_at(1, 3, SHOOTER, BODY, _server.now))
	assert_array(WeaponsFixture.of(events, &"target_killed")).is_empty()
	assert_bool(_rules.has_zombie(1)).is_true()


# --- More bolts for a tougher kind, and kinds that cannot be frozen ---


## The kind of the zombie in front of the shooter, as the rules' data has it.
func _kind() -> ZombieType:
	return _rules.tuning.roster.type_of(_rules.zombie_type(1))


func test_the_shipped_kinds_take_the_bolts_the_maintainer_said() -> void:
	var roster := RulesFixture.tuning().roster
	assert_int(roster.type_of(&"walker").freeze_bolts).is_equal(1)
	assert_int(roster.type_of(&"runner").freeze_bolts).is_equal(1)
	assert_int(roster.type_of(&"brute").freeze_bolts).is_equal(3)
	for type in roster.types:
		assert_bool(type.freezable).override_failure_message(String(type.id)).is_equal(
			not type.boss
		)


func test_a_brute_is_slowed_by_the_first_two_bolts_and_frozen_by_the_third() -> void:
	_kind().freeze_bolts = 3
	for shot in 2:
		var applied := WeaponsFixture.of(_fire(shot + 1), &"status_applied")
		assert_array(applied).has_size(1)
		assert_str(String(applied[0]["status"])).is_equal("chilled")
		assert_bool(applied[0]["halts"]).is_false()
		assert_float(applied[0]["speed_scale"]).is_equal(0.4)
		assert_int(applied[0]["wire"]).is_equal(_chilled())
		assert_bool(_server.statuses.shatterable(1)).is_false()
		_cool()
	var third := WeaponsFixture.of(_fire(3), &"status_applied")
	assert_str(String(third[0]["status"])).is_equal("frozen")
	assert_bool(_server.statuses.shatterable(1)).is_true()


func test_a_frozen_brute_shatters_on_one_hit() -> void:
	_kind().freeze_bolts = 3
	for shot in 3:
		_fire(shot + 1)
		_cool()
	_server.apply(CombatAction.equip(1, &"pistol"))
	_run(0.6)
	var events := _server.apply(WeaponsFixture.fire_at(1, 9, SHOOTER, BODY, _server.now))
	assert_bool(WeaponsFixture.of(events, &"zombie_removed")[0]["shattered"]).is_true()


func test_the_bolts_of_a_zombie_are_counted_only_while_the_chill_lasts() -> void:
	_kind().freeze_bolts = 2
	_fire(1)
	# The chill (3 s) and the count with it run out; the next bolt is a first one again.
	_run(3.5)
	var again := WeaponsFixture.of(_fire(2), &"status_applied")
	assert_str(String(again[0]["status"])).is_equal("chilled")


func test_a_re_cut_freeze_gun_blooms_wider() -> void:
	var spec := UpgradeTuning.shipped()
	var freeze := WeaponCatalog.get_def(&"freeze_gun")
	var re_cut := freeze.upgraded(spec)
	assert_float(re_cut.splash_radius).is_equal_approx(2.8, 0.05)
	assert_float(re_cut.status_seconds).is_equal(3.0)
	assert_int(re_cut.magazine_size).is_equal(9)
	assert_int(re_cut.reserve_max).is_equal(54)
	assert_bool(spec.allows(&"freeze_gun")).is_true()
	# Only a weapon that puts a status on grows its burst.
	var ray := WeaponCatalog.get_def(&"ray_gun")
	assert_float(ray.upgraded(spec).splash_radius).is_equal(ray.splash_radius)


func test_the_re_cut_bloom_reaches_a_zombie_the_plain_one_leaves_standing() -> void:
	# A zombie 3 m beside the one the bolt hits: its body is about 2.5 m from the burst, outside the
	# plain bloom (2.2 m) and inside the re-cut one (2.8 m).
	_places[2] = Vector3(3.0, 0, 0)
	_stand(2)
	var plain_events := _fire(1)
	var burst := WeaponsFixture.of(plain_events, &"projectile_burst")[0]
	var reach := Hitbox.distance_from(burst["point"], _places[2], 0.0)
	assert_float(reach).is_between(2.3, 2.7)
	var plain := WeaponsFixture.of(plain_events, &"status_applied")
	assert_array(plain.filter(func(e: Dictionary) -> bool: return e["target_id"] == 2)).is_empty()
	_run(3.5)
	_server.apply(CombatAction.upgrade_weapon(1, &"freeze_gun"))
	_stand(2)
	var cut := WeaponsFixture.of(_fire(2), &"status_applied")
	assert_array(cut.filter(func(e: Dictionary) -> bool: return e["target_id"] == 2)).has_size(1)


func test_the_re_cut_freezes_a_brute_a_bolt_sooner_and_never_below_one_bolt() -> void:
	var spec := UpgradeTuning.shipped()
	var freeze := WeaponCatalog.get_def(&"freeze_gun")
	assert_int(freeze.freeze_bolts_less).is_equal(0)
	assert_int(freeze.upgraded(spec).freeze_bolts_less).is_equal(1)
	# A brute (three bolts): the plain gun slows it twice and freezes it on the third; the re-cut
	# slows it once and freezes it on the second.
	_kind().freeze_bolts = 3
	_server.apply(CombatAction.upgrade_weapon(1, &"freeze_gun"))
	var first := WeaponsFixture.of(_fire(1), &"status_applied")
	assert_str(String(first[0]["status"])).is_equal("chilled")
	_cool()
	var second := WeaponsFixture.of(_fire(2), &"status_applied")
	assert_str(String(second[0]["status"])).is_equal("frozen")
	assert_bool(_server.statuses.shatterable(1)).is_true()


func test_the_re_cut_still_freezes_an_ordinary_zombie_on_its_first_bolt() -> void:
	# One bolt fewer than one is still one: the walker is frozen by the first, as before.
	assert_int(_kind().freeze_bolts).is_equal(1)
	_server.apply(CombatAction.upgrade_weapon(1, &"freeze_gun"))
	var applied := WeaponsFixture.of(_fire(1), &"status_applied")
	assert_str(String(applied[0]["status"])).is_equal("frozen")


# --- Kinds that cannot be frozen (bosses) ---


func test_a_kind_that_is_not_freezable_is_only_slowed_whatever_the_bolts() -> void:
	_kind().freezable = false
	for shot in 4:
		var events := _fire(shot + 1)
		var applied := WeaponsFixture.of(events, &"status_applied")
		assert_str(String(applied[0]["status"])).is_equal("chilled")
		assert_float(applied[0]["speed_scale"]).is_equal(0.4)
		assert_bool(applied[0]["halts"]).is_false()
		_cool()
	assert_bool(_server.statuses.shatterable(1)).is_false()
	_server.apply(CombatAction.equip(1, &"pistol"))
	_run(0.6)
	var second := _server.apply(WeaponsFixture.fire_at(1, 9, SHOOTER, BODY, _server.now))
	assert_array(WeaponsFixture.of(second, &"zombie_removed")).is_empty()
	assert_bool(_rules.has_zombie(1)).is_true()


func test_a_status_goes_with_the_zombie_that_dies_of_something_else() -> void:
	_fire(1)
	_rules.apply(RulesAction.hit(1, 1, &"body", RulesFixture.KILLING_DAMAGE))
	assert_bool(_server.statuses.any(1)).is_false()


# --- The board alone ---


func test_the_board_keeps_the_longer_time_when_a_status_is_put_on_again() -> void:
	var board := StatusBoard.new()
	var frozen := StatusCatalog.get_def(&"frozen")
	board.apply(7, frozen, 3.0)
	board.step(2.0)
	var again := board.apply(7, frozen, 0.5)
	assert_float(again["seconds"]).is_equal_approx(1.0, 0.001)
	board.apply(7, frozen, 3.0)
	assert_float(board.left(7, &"frozen")).is_equal_approx(3.0, 0.001)


func test_the_board_counts_bolts_for_as_long_as_it_is_told_to_and_forgets() -> void:
	var board := StatusBoard.new()
	assert_int(board.add_bolt(1, &"frozen", 3.0)).is_equal(1)
	assert_int(board.add_bolt(1, &"frozen", 3.0)).is_equal(2)
	board.step(3.1)
	assert_int(board.add_bolt(1, &"frozen", 3.0)).is_equal(1)
	board.clear_bolts(1, &"frozen")
	assert_int(board.add_bolt(1, &"frozen", 3.0)).is_equal(1)
	board.forget(1)
	assert_int(board.add_bolt(1, &"frozen", 3.0)).is_equal(1)


func test_the_board_sums_up_what_a_zombie_under_several_statuses_does() -> void:
	var board := StatusBoard.new()
	board.apply(1, StatusCatalog.get_def(&"chilled"), 5.0)
	var chilled := board.summary_of(1)
	assert_int(chilled["wire"]).is_equal(_chilled())
	assert_bool(chilled["halts"]).is_false()
	assert_float(chilled["speed_scale"]).is_equal(0.4)
	board.apply(1, StatusCatalog.get_def(&"frozen"), 3.0)
	var both := board.summary_of(1)
	# The frozen one has the higher priority: it is the one drawn.
	assert_int(both["wire"]).is_equal(_frozen())
	assert_bool(both["halts"]).is_true()
	assert_bool(board.shatterable(1)).is_true()
	assert_bool(board.shatterable(1, &"frozen")).is_false()
	board.step(3.5)
	assert_bool(board.shatterable(1)).is_false()
	assert_int(board.summary_of(1)["wire"]).is_equal(_chilled())


func test_a_status_is_found_by_the_wire_id_a_snapshot_carries() -> void:
	assert_object(StatusCatalog.by_wire(StatusDef.NONE)).is_null()
	assert_object(StatusCatalog.by_wire(StatusDef.WIRE_MAX)).is_null()
	var seen: Array[int] = []
	for id in StatusCatalog.IDS:
		var def := StatusCatalog.get_def(id)
		assert_object(def).is_not_null()
		assert_str(String(def.id)).is_equal(String(id))
		assert_int(def.wire).is_between(1, StatusDef.WIRE_MAX)
		assert_array(seen).not_contains([def.wire])
		seen.append(def.wire)
		assert_object(StatusCatalog.by_wire(def.wire)).is_same(def)
	for def in WeaponCatalog.all():
		if def.has_status():
			assert_object(StatusCatalog.get_def(def.status)).is_not_null()
