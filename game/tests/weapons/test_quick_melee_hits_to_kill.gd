extends GdUnitTestSuite
## How many blows of the quick melee (V) a walker takes, round by round (#897), through the real
## damage path: the sweep from the player's eye with the real fitted hit zones, the combat server
## and the rules' health for the round. The maintainer's rule: one blow on round 1 and more from
## round 2. The table is docs/design/weapons.md#hits-to-kill-by-round.

## Hits to kill a walker on rounds 1 to 10 (the table on the design page).
const WALKER_HITS: Array[int] = [1, 2, 2, 2, 2, 2, 2, 3, 3, 3]
## Where the blow is aimed from the eye, as a height on the zombie: head, chest and legs.
const AIMED_AT: Array[float] = [1.62, 1.1, 0.5]
## How far the zombie stands from the player, close to the end of the blow's reach.
const REACH: Array[float] = [0.7, 1.1, 1.5]
const BLOW_STEPS := 40

var _rules: GameRules
var _server: CombatServer
var _quick: WeaponDef
var _eye := Vector3.ZERO


func before_test() -> void:
	_quick = WeaponCatalog.quick_melee()
	_eye = Vector3(0.0, NightTuning.new().eye_height, 0.0)


## A night at `round_number` with a walker standing on the lot (the specials off, so the round is
## the ordinary one, and every other kind of dead gone), and its id.
func _walker_in(round_number: int) -> int:
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
	return walker


## Blows it takes to kill `zombie` standing `reach` metres ahead, aimed at height `aimed_at`, one
## every time the cooldown allows; 0 when it never dies.
func _blows_to_kill(zombie: int, reach: float, aimed_at: float) -> int:
	var feet := Vector3(0.0, 0.0, -reach)
	var dir := (feet + Vector3(0.0, aimed_at, 0.0) - _eye).normalized()
	for blows in range(1, 12):
		WeaponsFixture.step(_server, {zombie: feet}, BLOW_STEPS)
		var events := _server.apply(
			CombatAction.quick_melee(1, blows, _eye, dir, _eye, _server.now)
		)
		if not WeaponsFixture.of(events, &"target_killed").is_empty():
			return blows
	return 0


func test_a_round_one_walker_falls_to_one_blow_and_the_later_rounds_need_more() -> void:
	for round_number in range(1, WALKER_HITS.size() + 1):
		var walker := _walker_in(round_number)
		(
			assert_int(_blows_to_kill(walker, 1.1, AIMED_AT[0]))
			. override_failure_message(
				(
					"round %d: a walker of %.0f health took the wrong number of blows"
					% [round_number, RulesFixture.round_health(round_number)]
				)
			)
			. is_equal(WALKER_HITS[round_number - 1])
		)


func test_the_count_does_not_depend_on_where_the_blow_lands_or_how_far_off() -> void:
	# The sweep from the eye meets the head nearly every time (that is how it one-tapped before), so
	# the blow is flat: the same count on the head, the chest and the legs, near and far.
	for round_number in [1, 2, 4, 8]:
		for reach in REACH:
			for aimed_at in AIMED_AT:
				var walker := _walker_in(round_number)
				(
					assert_int(_blows_to_kill(walker, reach, aimed_at))
					. override_failure_message(
						(
							"round %d, %.1f m, aimed at %.2f m: the count changed with the aim"
							% [round_number, reach, aimed_at]
						)
					)
					. is_equal(WALKER_HITS[round_number - 1])
				)


func test_the_blow_does_the_same_damage_in_every_zone() -> void:
	for zone in [Hitbox.HEAD, Hitbox.BODY, Hitbox.LIMB]:
		assert_float(DamageModel.damage(_quick, 1.0, zone)).is_equal(_quick.damage)


func test_one_blow_fells_round_one_and_not_round_two_by_the_health_curve() -> void:
	# The rule the table follows from: the blow is at least round 1's health and under round 2's.
	assert_float(_quick.damage).is_greater_equal(RulesFixture.round_health(1))
	assert_float(_quick.damage).is_less(RulesFixture.round_health(2))


func test_the_table_follows_from_the_health_curve() -> void:
	for round_number in range(1, WALKER_HITS.size() + 1):
		var health := RulesFixture.round_health(round_number)
		assert_int(WALKER_HITS[round_number - 1]).is_equal(ceili(health / _quick.damage))


func test_the_simulator_and_the_bots_value_the_blow_by_the_same_hits() -> void:
	# `WeaponWorth` (the simulator's free hand, `BotEconomy.worth_taking`, the autopilot) reads the
	# definition: the health a second the blow kills is the walker's health over the blows it takes
	# and the wait between them, the same count the real night gave above.
	for round_number in range(1, WALKER_HITS.size() + 1):
		var health := RulesFixture.round_health(round_number)
		var hits: int = WALKER_HITS[round_number - 1]
		(
			assert_float(WeaponWorth.of(_quick, health))
			. override_failure_message(
				"round %d: the blow is not valued by %d hits" % [round_number, hits]
			)
			. is_equal_approx(health / (float(hits) * _quick.fire_interval), 0.001)
		)
