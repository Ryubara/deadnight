extends GdUnitTestSuite
## How many blows of each melee weapon a walker takes, round by round (#924, after #897), through
## the real damage path: the sweep from the player's eye, the fitted hit zones of the walker in
## the pose it has (walking up, striking), the combat server and the rules' health for the round.
## A melee sweep leaves the eye (1.55 m) with a 0.4 m thickness and the head sphere is at 1.62 m, so
## every blow meets the head wherever the crosshair is; the crowbar, the bat and the axe used to
## carry the head's multiplier (x1.5, x2.5) in every blow and did 68, 90 and 375 where their tables
## said 45, 60 and 150. Now each blow is flat, the number its table shows. The table is
## docs/design/weapons.md#hits-to-kill-by-round.

## Hits to kill a walker on rounds 1 to 10 (the table on the design page), by weapon.
const HITS := {
	&"quick_melee": [1, 2, 2, 2, 2, 2, 2, 3, 3, 3],
	&"crowbar": [1, 2, 2, 2, 2, 2, 2, 2, 3, 3],
	&"baseball_bat": [1, 1, 2, 2, 2, 2, 2, 2, 3, 3],
	&"fire_axe": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
}
## Where the crosshair is put on the walker: head, chest and legs, as a height above its feet.
const AIMED_AT: Array[float] = [1.62, 1.1, 0.5]
## How far the walker stands from the player, close to the end of the blow's reach.
const REACH: Array[float] = [0.7, 1.1, 1.5]
## The hit sets a walker is shot at while it walks up and while it strikes.
const MODES: Array[int] = [ZombieBody.Mode.CHASE, ZombieBody.Mode.ATTACK]
## The camera pivot's height: in the third-person view the crosshair ray runs from it through the
## point aimed at, and the blow is swept along that direction from the eye.
const PIVOT := 1.6
const BLOW_STEPS := 70

var _rules: GameRules
var _server: CombatServer
var _eye := Vector3.ZERO


func before_test() -> void:
	_eye = Vector3(0.0, NightTuning.new().eye_height, 0.0)


## A night at `round_number` with a walker standing on the lot (the specials off, so the round is
## the ordinary one, and every other kind of dead gone), and its id; `weapon` is in hand.
func _walker_in(round_number: int, weapon: StringName) -> int:
	var tuning := RulesFixture.tuning()
	tuning.specials.every = 0
	_rules = RulesFixture.make_rules(1, 1234, tuning)
	_server = WeaponsFixture.make_server(_rules)
	_rules.round_number = round_number - 1
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 40.0)
	var walker := -1
	for id in _rules.zombie_ids():
		if walker < 0 and _rules.zombie_type(id) == &"walker":
			walker = id
		else:
			RulesFixture.kill(_rules, 1, id)
	assert_int(walker).is_greater(0)
	if weapon != WeaponCatalog.QUICK_MELEE:
		_server.apply(CombatAction.give_weapon(1, weapon, weapon))
	return walker


## The walker standing `reach` metres ahead, facing the player, in `mode`'s hit set, for `steps`.
func _stand(walker: int, reach: float, mode: int, steps: int) -> void:
	var target := {
		"id": walker,
		"pos": Vector3(0.0, 0.0, -reach),
		"yaw": 0.0,
		"pose": ZombiePose.hit_set(ZombieModels.DEFAULT, mode),
	}
	for _i in steps:
		_server.apply(CombatAction.targets([target]))
		_server.apply(CombatAction.tick(WeaponsFixture.STEP))


## One blow with `weapon`, the way the night sends it (from the eye, along the crosshair).
func _blow(weapon: StringName, seq: int, reach: float, aimed_at: float) -> Array[Dictionary]:
	var aim := Vector3(0.0, aimed_at, -reach) - Vector3(0.0, PIVOT, 0.0)
	var dir := aim.normalized()
	if weapon == WeaponCatalog.QUICK_MELEE:
		return _server.apply(CombatAction.quick_melee(1, seq, _eye, dir, _eye, _server.now))
	return _server.apply(CombatAction.fire(1, seq, _eye, dir, _eye, _server.now))


## Blows it takes to kill the walker, one every time the cooldown allows; 0 when it never dies.
func _blows_to_kill(
	weapon: StringName, walker: int, reach: float, aimed_at: float, mode: int
) -> int:
	for blows in range(1, 12):
		_stand(walker, reach, mode, BLOW_STEPS)
		var events := _blow(weapon, blows, reach, aimed_at)
		if not WeaponsFixture.of(events, &"target_killed").is_empty():
			return blows
	return 0


func test_each_weapon_takes_the_blows_of_its_table_on_every_round() -> void:
	for weapon: StringName in HITS:
		for round_number in range(1, 11):
			var walker := _walker_in(round_number, weapon)
			(
				assert_int(_blows_to_kill(weapon, walker, 1.1, AIMED_AT[1], MODES[0]))
				. override_failure_message(
					(
						"%s on round %d: a walker of %.0f health took the wrong number of blows"
						% [weapon, round_number, RulesFixture.round_health(round_number)]
					)
				)
				. is_equal(HITS[weapon][round_number - 1])
			)


func test_the_count_does_not_depend_on_where_the_crosshair_is_or_how_far_off() -> void:
	# The sweep meets the head nearly every time (that is how the crowbar, the bat and the axe
	# landed head hits of 68, 90 and 375), so the blow is flat: the same count on the head, the
	# chest and the legs, near and far, walking up or striking.
	for weapon: StringName in HITS:
		for round_number in [1, 2, 8, 10]:
			for reach in REACH:
				for aimed_at in AIMED_AT:
					for mode in MODES:
						var walker := _walker_in(round_number, weapon)
						(
							assert_int(_blows_to_kill(weapon, walker, reach, aimed_at, mode))
							. override_failure_message(
								(
									(
										"%s, round %d, %.1f m, aimed at %.2f m, mode %d: the count "
										+ "changed with the aim"
									)
									% [weapon, round_number, reach, aimed_at, mode]
								)
							)
							. is_equal(HITS[weapon][round_number - 1])
						)


func test_a_blow_does_the_damage_its_table_shows_wherever_it_lands() -> void:
	for weapon: StringName in HITS:
		var def := WeaponCatalog.get_def(weapon)
		for reach in REACH:
			for aimed_at in AIMED_AT:
				var walker := _walker_in(10, weapon)
				_stand(walker, reach, MODES[0], BLOW_STEPS)
				var hurt := WeaponsFixture.of(_blow(weapon, 1, reach, aimed_at), &"damage_dealt")
				assert_array(hurt).is_not_empty()
				(
					assert_float(hurt[0]["damage"])
					. override_failure_message(
						(
							"%s at %.1f m aimed at %.2f m did %.0f in the %s, not %.0f"
							% [
								weapon,
								reach,
								aimed_at,
								hurt[0]["damage"],
								hurt[0]["zone"],
								def.damage
							]
						)
					)
					. is_equal(def.damage)
				)


func test_a_melee_weapons_blow_is_the_same_in_every_zone() -> void:
	for weapon: StringName in HITS:
		var def := WeaponCatalog.get_def(weapon)
		for zone in [Hitbox.HEAD, Hitbox.BODY, Hitbox.LIMB]:
			assert_float(DamageModel.damage(def, 1.0, zone)).is_equal(def.damage)


func test_the_table_follows_from_the_health_curve() -> void:
	for weapon: StringName in HITS:
		var def := WeaponCatalog.get_def(weapon)
		for round_number in range(1, 11):
			var health := RulesFixture.round_health(round_number)
			assert_int(HITS[weapon][round_number - 1]).is_equal(ceili(health / def.damage))


func test_a_weapon_found_is_never_worse_than_the_free_blow_on_round_one() -> void:
	# The blow of V fells round 1 (50 health) and not round 2 (58); the weapons carried are as
	# strong in a blow, so a slot spent on one is worth it.
	var quick := WeaponCatalog.quick_melee()
	assert_float(quick.damage).is_greater_equal(RulesFixture.round_health(1))
	assert_float(quick.damage).is_less(RulesFixture.round_health(2))
	for weapon: StringName in [&"crowbar", &"baseball_bat", &"fire_axe"]:
		assert_float(WeaponCatalog.get_def(weapon).damage).is_greater_equal(quick.damage)


func test_the_simulator_and_the_bots_value_each_blow_by_the_same_hits() -> void:
	# `WeaponWorth` (the simulator's free hand, `BotEconomy.worth_taking`, the autopilot) reads the
	# definition: the health a second a blow kills is the walker's health over the blows it takes
	# and the wait between them, the same count the real night gave above.
	for weapon: StringName in HITS:
		var def := WeaponCatalog.get_def(weapon)
		for round_number in range(1, 11):
			var health := RulesFixture.round_health(round_number)
			var hits: int = HITS[weapon][round_number - 1]
			(
				assert_float(WeaponWorth.of(def, health))
				. override_failure_message(
					"%s, round %d: the blow is not valued by %d hits" % [weapon, round_number, hits]
				)
				. is_equal_approx(health / (float(hits) * def.fire_interval), 0.001)
			)
