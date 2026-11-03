extends GdUnitTestSuite
## The elements of the re-cut (docs/design/upgrades.md, "The four elements"), on the server: what
## a hit of a re-cut weapon does besides its own damage, for how long, and who it spares. Each test
## gives a player the weapon, re-cuts it through the combat action the bench sends, and fires with
## the real command at zombies of a real night in round one.

const SHOOTER := WeaponsFixture.SHOOTER
const CHEST := Vector3(0, 1.1, 0)
const FIVE := 5

var _rules: GameRules
var _server: CombatServer
var _ids: Array


func before_test() -> void:
	_start(UpgradeTuning.shipped())


## A night in round one with five zombies (ids in `_ids`), over `spec` as its re-cut table.
func _start(spec: UpgradeTuning) -> void:
	var tuning := RulesFixture.tuning()
	tuning.upgrade = spec
	_rules = RulesFixture.make_rules(1, 1234, tuning)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, WeaponsFixture.SPAWN_SECONDS * FIVE)
	_server = CombatServer.new(WeaponsFixture.all_defs(), _rules, Callable(), WeaponsFixture.SEED)
	_ids = _rules.zombie_ids().slice(0, FIVE)
	assert_int(_ids.size()).is_equal(FIVE)


## Gives the weapon, re-cuts it, and stands the zombies where `at` says (ids by index in `_ids`).
func _arm(weapon: StringName, at: Dictionary) -> Dictionary:
	_server.apply(CombatAction.give_weapon(1, weapon))
	_server.apply(CombatAction.upgrade_weapon(1, weapon))
	var placed := {}
	for index: int in at:
		placed[_ids[index]] = at[index]
	WeaponsFixture.step(_server, placed, 2)
	return placed


func _fire(to: Vector3, from: Vector3 = SHOOTER) -> Array[Dictionary]:
	return _server.apply(WeaponsFixture.fire_at(1, 1, from, to, _server.now))


func _damage_of(events: Array[Dictionary], target_id: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in WeaponsFixture.of(events, &"damage_dealt"):
		if event["target_id"] == target_id:
			found.append(event)
	return found


# --- Explosive rounds ---


func test_a_re_cut_revolver_hit_bursts_on_the_zombies_beside_the_one_it_hit() -> void:
	var placed := _arm(&"pistol", {0: Vector3.ZERO, 1: Vector3(1.0, 0, 0), 2: Vector3(6.0, 0, 0)})
	var def := _server.weapon_of(1).def
	var events := _fire(CHEST)
	var hit := _damage_of(events, _ids[0])
	assert_array(hit).has_size(1)
	assert_str(hit[0]["element"]).is_equal("")
	# The zombie that was hit takes the hit alone: one damage, the weapon's.
	assert_float(hit[0]["damage"]).is_equal(DamageModel.damage(def, 8.0, &"body"))
	var near := _damage_of(events, _ids[1])
	assert_array(near).has_size(1)
	assert_str(near[0]["element"]).is_equal("explosive")
	var reach := Hitbox.distance_from(CHEST, placed[_ids[1]], 0.0)
	var share := lerpf(1.0, 0.5, reach / 2.0)
	assert_float(near[0]["damage"]).is_equal_approx(def.damage * 0.5 * share, 0.01)
	assert_float(near[0]["damage"]).is_between(def.damage * 0.25, def.damage * 0.5)
	# One 6 m away is outside the 2 m burst.
	assert_array(_damage_of(events, _ids[2])).is_empty()
	var burst := WeaponsFixture.of(events, &"element_burst")
	assert_array(burst).has_size(1)
	assert_str(burst[0]["element"]).is_equal("explosive")
	assert_float(burst[0]["radius"]).is_equal(2.0)


func test_a_burst_hurts_the_nearer_zombie_more_and_pays_like_a_hit() -> void:
	_arm(&"pistol", {0: Vector3.ZERO, 1: Vector3(0.8, 0, 0), 2: Vector3(1.6, 0, 0)})
	var before := _rules.points_of(1)
	var events := _fire(CHEST)
	var nearer := _damage_of(events, _ids[1])[0]["damage"] as float
	var farther := _damage_of(events, _ids[2])[0]["damage"] as float
	assert_float(nearer).is_greater(farther)
	# The hit and the two blasts each paid as a hit: three non-lethal hits, three payments.
	var hit_pay: int = _rules.tuning.economy.hit
	assert_int(_rules.points_of(1) - before).is_equal(3 * hit_pay)


func test_a_plain_revolver_has_no_burst() -> void:
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	WeaponsFixture.step(_server, {_ids[0]: Vector3.ZERO, _ids[1]: Vector3(1.0, 0, 0)}, 2)
	var events := _fire(CHEST)
	assert_array(WeaponsFixture.of(events, &"element_burst")).is_empty()
	assert_array(_damage_of(events, _ids[1])).is_empty()


func test_a_burst_that_kills_the_zombie_beside_credits_the_shooter() -> void:
	_arm(&"pistol", {0: Vector3.ZERO, 1: Vector3(0.7, 0, 0)})
	# Leave the neighbour on a sliver of health.
	var neighbour: ZombieState = _rules._zombies[_ids[1]]
	neighbour.health = 3.0
	var events := _fire(CHEST)
	var killed := WeaponsFixture.of(events, &"target_killed")
	assert_array(killed).has_size(1)
	assert_int(killed[0]["target_id"]).is_equal(_ids[1])
	assert_int(killed[0]["shooter_id"]).is_equal(1)
	assert_int(_rules.players[1].kills).is_equal(1)


func test_a_burst_spares_the_shooter_and_the_team() -> void:
	# The combat server hurts zombies only: no player takes a hit from a burst of this weapon.
	_arm(&"pistol", {0: Vector3.ZERO, 1: Vector3(1.0, 0, 0)})
	var events := _fire(CHEST, Vector3(0.5, 1.1, 1.0))
	for event in events:
		assert_bool(event["type"] in [&"player_hurt", &"player_blasted"]).is_false()
	assert_float(_rules.players[1].health).is_equal(_rules.players[1].max_health)


# --- Shock arc ---


func _shock_tuning() -> UpgradeTuning:
	# The dual pistols are not in the catalogue yet: the revolver carries the shock for the test.
	var spec := UpgradeTuning.shipped().duplicate(true) as UpgradeTuning
	var cut := spec.profile_of(&"pistol")
	cut.element = load("res://gameplay/weapons/elements/defs/shock.tres")
	cut.fire_interval = 0.0
	return spec


func test_a_shock_hit_arcs_to_the_two_nearest_others_within_three_metres() -> void:
	_start(_shock_tuning())
	var placed := _arm(
		&"pistol",
		{
			0: Vector3.ZERO,
			1: Vector3(1.0, 0, 0),
			2: Vector3(0, 0, -1.5),
			3: Vector3(2.4, 0, 0),
			4: Vector3(9.0, 0, 0),
		}
	)
	var def := _server.weapon_of(1).def
	var events := _fire(CHEST)
	# The three nearest others by distance from the hit are within 3 m; only two are arced to.
	var arced: Array[int] = []
	for index in [1, 2, 3, 4]:
		for event in _damage_of(events, _ids[index]):
			if event["element"] == &"shock":
				arced.append(index)
				assert_float(event["damage"]).is_equal_approx(def.damage * 0.5, 0.01)
	assert_int(arced.size()).is_equal(2)
	assert_bool(arced.has(4)).is_false()
	var nearest := _nearest_two(placed)
	for index in nearest:
		assert_bool(arced.has(index)).override_failure_message("index %d" % index).is_true()
	var arcs := WeaponsFixture.of(events, &"element_arc")
	assert_array(arcs).has_size(1)
	assert_array(arcs[0]["to"]).has_size(2)
	assert_str(arcs[0]["element"]).is_equal("shock")


func _nearest_two(placed: Dictionary) -> Array[int]:
	var ranked: Array = []
	for index in [1, 2, 3, 4]:
		ranked.append([Hitbox.distance_from(CHEST, placed[_ids[index]], 0.0), index])
	ranked.sort()
	return [ranked[0][1], ranked[1][1]]


func test_a_shock_arc_is_one_jump_and_never_a_chain() -> void:
	_start(_shock_tuning())
	# 1 is 2 m from 0; 2 is 2 m further on: 2 is outside 0's 3 m, and an arc does not chain from 1.
	_arm(&"pistol", {0: Vector3.ZERO, 1: Vector3(2.0, 0, 0), 2: Vector3(4.0, 0, 0)})
	var events := _fire(CHEST)
	assert_array(_damage_of(events, _ids[1])).has_size(1)
	assert_array(_damage_of(events, _ids[2])).is_empty()


func test_a_shock_arc_pays_the_shooter_as_a_hit() -> void:
	_start(_shock_tuning())
	_arm(&"pistol", {0: Vector3.ZERO, 1: Vector3(1.0, 0, 0)})
	var before := _rules.points_of(1)
	_fire(CHEST)
	assert_int(_rules.points_of(1) - before).is_equal(2 * _rules.tuning.economy.hit)


# --- Burning ground ---


func _burn_flare() -> Array[Dictionary]:
	## Fires the re-cut flare gun at the ground 2 m behind the zombies' lane and runs until it bursts.
	var events: Array[Dictionary] = []
	var aim := Vector3(0, 0.0, -2.0)
	_server.apply(WeaponsFixture.fire_at(1, 1, SHOOTER, aim, _server.now))
	return events


func _run(seconds: float, placed: Dictionary, into: Array[Dictionary]) -> void:
	for _i in ceili(seconds / WeaponsFixture.STEP):
		into.append_array(_server.apply(CombatAction.targets(WeaponsFixture.list_of(placed))))
		into.append_array(_server.apply(CombatAction.tick(WeaponsFixture.STEP)))


func test_a_re_cut_flare_sets_the_ground_alight_and_it_burns_what_stands_in_it() -> void:
	var placed := _arm(
		&"flare_gun", {0: Vector3(0, 0, -2.0), 1: Vector3(1.5, 0, -2.0), 2: Vector3(8, 0, -2.0)}
	)
	var events: Array[Dictionary] = _server.apply(
		WeaponsFixture.fire_at(1, 1, SHOOTER, Vector3(0, 0.3, -2.0), _server.now)
	)
	_run(10.0, placed, events)
	var started := WeaponsFixture.of(events, &"fire_patch_started")
	assert_array(started).has_size(1)
	assert_float(started[0]["radius"]).is_equal(3.0)
	assert_float(started[0]["seconds"]).is_equal(WeaponCatalog.get_def(&"flare_gun").lure_seconds)
	assert_str(started[0]["element"]).is_equal("ground_fire")
	# The patch burns the zombies inside it, 25 a second in hits of 12.5, and not the one outside.
	var inside := _damage_of(events, _ids[1])
	assert_array(inside).is_not_empty()
	for event in inside:
		assert_str(event["element"]).is_equal("ground_fire")
		assert_float(event["damage"]).is_equal_approx(12.5, 0.001)
	assert_array(_damage_of(events, _ids[2])).is_empty()


func test_the_fire_burns_for_the_lure_seconds_and_no_longer() -> void:
	var placed := _arm(&"flare_gun", {0: Vector3(0, 0, -2.0)})
	# A zombie that would outlast the fire, so the count of its hits is the fire's length.
	var zombie: ZombieState = _rules._zombies[_ids[0]]
	zombie.health = 100000.0
	var events: Array[Dictionary] = _server.apply(
		WeaponsFixture.fire_at(1, 1, SHOOTER, Vector3(0, 0.3, -2.0), _server.now)
	)
	_run(14.0, placed, events)
	var seconds := WeaponCatalog.get_def(&"flare_gun").lure_seconds
	var burns := _damage_of(events, _ids[0])
	var total := 0.0
	for event in burns:
		total += event["damage"]
	# Hits stop with the patch: 25 a second for the seconds the lure lasts, a hit of slack each end.
	assert_float(total).is_between(25.0 * (seconds - 1.0), 25.0 * (seconds + 1.0))


func test_a_plain_flare_leaves_no_fire() -> void:
	_server.apply(CombatAction.give_weapon(1, &"flare_gun"))
	var placed := {_ids[0]: Vector3(0, 0, -2.0)}
	WeaponsFixture.step(_server, placed, 2)
	var events: Array[Dictionary] = _server.apply(
		WeaponsFixture.fire_at(1, 1, SHOOTER, Vector3(0, 0.3, -2.0), _server.now)
	)
	_run(6.0, placed, events)
	assert_array(WeaponsFixture.of(events, &"fire_patch_started")).is_empty()
	assert_array(WeaponsFixture.of(events, &"damage_dealt")).is_empty()


func test_the_fire_kills_what_burns_in_it_and_pays_the_shooter() -> void:
	var placed := _arm(&"flare_gun", {0: Vector3(0, 0, -2.0)})
	var events: Array[Dictionary] = _server.apply(
		WeaponsFixture.fire_at(1, 1, SHOOTER, Vector3(0, 0.3, -2.0), _server.now)
	)
	_run(10.0, placed, events)
	# A round-one zombie has 50 health: the fire takes it in about two seconds.
	var killed := WeaponsFixture.of(events, &"target_killed")
	assert_array(killed).has_size(1)
	assert_int(killed[0]["shooter_id"]).is_equal(1)
	assert_int(_rules.players[1].kills).is_equal(1)


# --- Plain data ---


func test_the_events_of_an_element_are_plain_data_a_client_can_receive() -> void:
	var placed := _arm(&"pistol", {0: Vector3.ZERO, 1: Vector3(1.0, 0, 0)})
	var events := _fire(CHEST)
	_run(0.1, placed, events)
	for event in WeaponsFixture.of(events, &"element_burst"):
		var sent := bytes_to_var(var_to_bytes(event)) as Dictionary
		assert_bool(sent["point"] == event["point"]).is_true()
		assert_str(String(sent["element"])).is_equal("explosive")
	var weapon_events := _server.apply(CombatAction.upgrade_weapon(1, &"pistol"))
	assert_array(WeaponsFixture.of(weapon_events, &"action_rejected")).has_size(1)
