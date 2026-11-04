# gdlint:disable=max-public-methods
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
	tuning.rounds.count_base = 12.0
	_rules = RulesFixture.make_rules(1, 1234, tuning)
	_server = CombatServer.new(WeaponsFixture.all_defs(), _rules, Callable(), WeaponsFixture.SEED)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, WeaponsFixture.SPAWN_SECONDS * FIVE * 2.0)
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
	var reach := Hitbox.distance_from(hit[0]["point"], placed[_ids[1]], 0.0)
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


# --- Fire rounds ---


## A zombie that outlasts the burn, so the count of its hits is the fire's length.
func _tough(index: int) -> void:
	_rules._zombies[_ids[index]].health = 100000.0


func _burn_hits(events: Array[Dictionary], index: int) -> Array[Dictionary]:
	return _damage_of(events, _ids[index]).filter(
		func(event: Dictionary) -> bool: return event["element"] == &"fire"
	)


func _total(hits: Array[Dictionary]) -> float:
	var total := 0.0
	for hit in hits:
		total += hit["damage"]
	return total


func test_the_pump_re_cut_carries_fire_rounds_of_thirty_a_second_for_three_seconds() -> void:
	var spec := UpgradeTuning.shipped()
	var cut := spec.profile_of(&"pump_870")
	assert_bool(cut.has_element()).is_true()
	var fire := cut.element
	assert_str(String(fire.id)).is_equal("fire")
	assert_bool(fire.has_burn()).is_true()
	assert_float(fire.burn_dps).is_equal(30.0)
	assert_float(fire.burn_seconds).is_equal(3.0)
	assert_float(fire.burn_total()).is_equal(90.0)
	assert_bool(fire.bleeds).is_false()
	assert_bool(fire.has_blast() or fire.has_arc() or fire.has_ground()).is_false()
	assert_str(cut.card_line(WeaponCatalog.get_def(&"pump_870"))).contains("FIRE ROUNDS")
	assert_str(fire.card_line()).contains("BURNING, 30 A SECOND FOR 3 S")
	# The burn is the pump's alone: no other re-cut carries one.
	for id in spec.weapon_ids():
		if id != &"pump_870" and spec.profile_of(id).has_element():
			assert_bool(spec.profile_of(id).element.has_burn()).is_false()


func test_a_re_cut_pump_hit_sets_the_zombie_burning_for_three_seconds() -> void:
	_arm(&"pump_870", {0: Vector3.ZERO})
	_tough(0)
	var events := _fire(CHEST)
	var applied := WeaponsFixture.of(events, &"status_applied")
	assert_array(applied).has_size(1)
	assert_str(String(applied[0]["status"])).is_equal("burning")
	assert_float(applied[0]["seconds"]).is_equal(3.0)
	assert_int(applied[0]["wire"]).is_equal(StatusCatalog.get_def(&"burning").wire)
	assert_bool(applied[0]["halts"]).is_false()
	assert_float(applied[0]["speed_scale"]).is_equal(1.0)
	var burn := WeaponsFixture.of(events, &"element_burn")
	assert_array(burn).has_size(1)
	assert_int(burn[0]["target_id"]).is_equal(_ids[0])
	assert_str(String(burn[0]["element"])).is_equal("fire")
	assert_float(burn[0]["seconds"]).is_equal(3.0)
	assert_bool(_server.statuses.has(_ids[0], &"burning")).is_true()


func test_a_plain_pump_burns_nothing() -> void:
	_server.apply(CombatAction.give_weapon(1, &"pump_870"))
	var placed := {_ids[0]: Vector3.ZERO}
	WeaponsFixture.step(_server, placed, 2)
	_tough(0)
	var events := _fire(CHEST)
	assert_array(WeaponsFixture.of(events, &"damage_dealt")).is_not_empty()
	assert_array(WeaponsFixture.of(events, &"element_burn")).is_empty()
	assert_bool(_server.statuses.any(_ids[0])).is_false()


func test_the_burn_takes_ninety_in_hits_of_fifteen_and_then_ends() -> void:
	var placed := _arm(&"pump_870", {0: Vector3.ZERO})
	_tough(0)
	var events := _fire(CHEST)
	_run(4.0, placed, events)
	var burns := _burn_hits(events, 0)
	assert_int(burns.size()).is_equal(6)
	for hit in burns:
		assert_float(hit["damage"]).is_equal_approx(15.0, 0.001)
		assert_bool(hit["melee"]).is_false()
	assert_float(_total(burns)).is_equal_approx(90.0, 0.001)
	var ended := WeaponsFixture.of(events, &"status_ended")
	assert_array(ended).has_size(1)
	assert_str(String(ended[0]["status"])).is_equal("burning")
	assert_bool(_server.statuses.any(_ids[0])).is_false()
	# Nothing burns after the seconds are up.
	var later: Array[Dictionary] = []
	_run(2.0, placed, later)
	assert_array(_burn_hits(later, 0)).is_empty()


func test_a_second_hit_restarts_the_burn_and_never_stacks_a_second_fire() -> void:
	var placed := _arm(&"pump_870", {0: Vector3.ZERO})
	_tough(0)
	var events := _fire(CHEST)
	_run(1.0, placed, events)
	var second := _fire(CHEST)
	events.append_array(second)
	assert_array(WeaponsFixture.of(second, &"element_burn")).has_size(1)
	# Still one burning status, with the three seconds begun again.
	assert_float(_server.statuses.left(_ids[0], &"burning")).is_greater(2.8)
	_run(5.0, placed, events)
	# One fire all along: 30 a second from the first hit to three seconds after the second (4 s,
	# not the 6 s two stacked fires would burn), in hits of 15.
	var total := _total(_burn_hits(events, 0))
	assert_float(total).is_between(30.0 * 3.8, 30.0 * 4.3)


func test_every_zombie_the_shot_hits_burns_and_the_burn_is_the_shooters() -> void:
	var placed := _arm(&"pump_870", {0: Vector3.ZERO, 1: Vector3(0.3, 0, 0), 2: Vector3(9, 0, 0)})
	_tough(0)
	_tough(1)
	var events := _fire(CHEST)
	_run(4.0, placed, events)
	assert_float(_total(_burn_hits(events, 0))).is_equal_approx(90.0, 0.001)
	# The one far off to the side was not hit, so it does not burn.
	assert_array(_burn_hits(events, 2)).is_empty()
	for event in _burn_hits(events, 0):
		assert_int(event["shooter_id"]).is_equal(1)


func test_the_burn_kills_and_pays_the_shooter() -> void:
	var placed := _arm(&"pump_870", {0: Vector3.ZERO})
	_tough(0)
	var events := _fire(CHEST)
	# What the shell left standing is finished by the fire: 40 health is under three burns.
	_rules._zombies[_ids[0]].health = 40.0
	var points := _rules.points_of(1)
	_run(3.5, placed, events)
	var killed := WeaponsFixture.of(events, &"target_killed")
	assert_array(killed).has_size(1)
	assert_int(killed[0]["shooter_id"]).is_equal(1)
	assert_int(_rules.players[1].kills).is_equal(1)
	assert_int(_rules.points_of(1)).is_greater(points)
	assert_bool(_server.statuses.any(_ids[0])).is_false()
	assert_int(_burn_hits(events, 0).size()).is_equal(3)


func test_a_zombie_the_shell_kills_is_not_set_alight() -> void:
	_arm(&"pump_870", {0: Vector3.ZERO})
	var events := _fire(CHEST)
	assert_array(WeaponsFixture.of(events, &"target_killed")).has_size(1)
	assert_array(WeaponsFixture.of(events, &"element_burn")).is_empty()
	assert_bool(_server.statuses.any(_ids[0])).is_false()


func test_a_frozen_burning_zombie_takes_no_burn_until_it_thaws() -> void:
	var placed := _arm(&"pump_870", {0: Vector3.ZERO})
	_tough(0)
	_fire(CHEST)
	_server.statuses.apply(_ids[0], StatusCatalog.get_def(&"frozen"), 1.0)
	var during: Array[Dictionary] = []
	_run(0.9, placed, during)
	assert_array(_burn_hits(during, 0)).is_empty()
	assert_array(WeaponsFixture.of(during, &"zombie_removed")).is_empty()


func test_a_burn_dies_with_the_zombie_that_dies_of_something_else() -> void:
	var placed := _arm(&"pump_870", {0: Vector3.ZERO})
	_tough(0)
	_fire(CHEST)
	_rules.apply(RulesAction.hit(1, _ids[0], &"body", RulesFixture.KILLING_DAMAGE))
	var later: Array[Dictionary] = []
	_run(4.0, placed, later)
	assert_array(WeaponsFixture.of(later, &"damage_dealt")).is_empty()


func test_the_burn_events_are_plain_data_a_client_can_receive() -> void:
	_arm(&"pump_870", {0: Vector3.ZERO})
	_tough(0)
	for event in WeaponsFixture.of(_fire(CHEST), &"element_burn"):
		var sent := bytes_to_var(var_to_bytes(event)) as Dictionary
		assert_int(sent["target_id"]).is_equal(_ids[0])
		assert_str(String(sent["element"])).is_equal("fire")


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
