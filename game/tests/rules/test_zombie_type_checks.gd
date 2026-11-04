extends GdUnitTestSuite
## What the zombie types promise beyond their mix: the speed cap, a look for every type, and a
## blast paying by type like a bullet.

var _t: RulesTuning


func before_test() -> void:
	_t = RulesFixture.tuning()


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_no_type_outruns_the_speed_cap_even_with_the_jitter_at_its_top() -> void:
	# A type may never outrun a sprinting player (docs/design/rounds.md). Late in the night every
	# type's base speed is at or past the cap, so the jitter pushes a roll over it unless
	# `roll_speed` holds it back: without its `minf`, this fails for every type that is not slow.
	var cap := _t.rounds.speed_cap
	var reached_cap := false
	for type in _t.roster.types:
		var rng := _rng(7)
		for round_number in [20, 40, 500]:
			for _i in 200:
				var speed := _t.rounds.roll_speed(round_number, rng, type.speed_multiplier)
				(
					assert_float(speed)
					. override_failure_message("%s rolled %s past the cap" % [type.id, speed])
					. is_less_equal(cap)
				)
				reached_cap = reached_cap or is_equal_approx(speed, cap)
	assert_bool(reached_cap).override_failure_message("no roll ever met the cap").is_true()


func test_the_speed_cap_sits_between_the_players_run_and_sprint() -> void:
	# The fastest zombie matches the player's run (running alone no longer shakes it) and stays well
	# under the sprint (a sprinting player always gets away): docs/research/movement-speeds.md.
	var player: PlayerTuning = load("res://gameplay/player/player_tuning_default.tres")
	var cap := _t.rounds.speed_cap
	(
		assert_float(cap)
		. override_failure_message("a cap below the run speed lets running outpace every zombie")
		. is_greater(player.run_speed)
	)
	assert_float(cap).is_less_equal(player.sprint_speed * 0.75)


func test_every_type_has_a_look_that_has_a_model() -> void:
	for type in _t.roster.types:
		for look in type.looks:
			(
				assert_bool(ZombieModels.VARIANTS.has(look))
				. override_failure_message(
					"%s: look %s has no ZombieModels variant" % [type.id, look]
				)
				. is_true()
			)


func test_a_blast_pays_by_the_type_like_a_bullet() -> void:
	var brute := _rules_with_one_living(&"brute")
	var multiplier := _t.roster.type_of(&"brute").points_multiplier
	var brute_id: int = brute.zombie_ids()[0]
	var before := brute.points_of(1)
	brute.apply(
		RulesAction.explosion(1, [{"zombie_id": brute_id, "damage": 1.0, "leg_damage": 0.0}])
	)
	assert_int(brute.points_of(1) - before).is_equal(PointSteps.award(_t.economy.hit * multiplier))
	before = brute.points_of(1)
	brute.apply(
		RulesAction.explosion(
			1, [{"zombie_id": brute_id, "damage": RulesFixture.KILLING_DAMAGE, "leg_damage": 0.0}]
		)
	)
	# The only zombie of the round: its death also pays the round bonus.
	var kill_pay := brute.points_of(1) - before - _t.economy.round_bonus(brute.round_number)
	assert_int(kill_pay).is_equal(PointSteps.award(_t.explosives.explosion_kill * multiplier))


func test_a_blast_on_a_walker_still_pays_the_flat_amounts() -> void:
	var walker := _rules_with_one_living(&"walker")
	var walker_id: int = walker.zombie_ids()[0]
	var before := walker.points_of(1)
	walker.apply(
		RulesAction.explosion(1, [{"zombie_id": walker_id, "damage": 1.0, "leg_damage": 0.0}])
	)
	assert_int(walker.points_of(1) - before).is_equal(_t.economy.hit)


func test_blast_hits_on_a_boss_pay_up_to_its_own_limit() -> void:
	var boss := _rules_with_one_living(&"headliner")
	var boss_id: int = boss.zombie_ids()[0]
	var before := boss.points_of(1)
	for _i in 10:
		boss.apply(
			RulesAction.explosion(1, [{"zombie_id": boss_id, "damage": 1.0, "leg_damage": 0.0}])
		)
	var per_hit := PointSteps.award(
		_t.economy.hit * _t.roster.type_of(&"headliner").points_multiplier
	)
	assert_int(boss.points_of(1) - before).is_equal(10 * per_hit)


func _rules_with_one_living(type_id: StringName) -> GameRules:
	return RulesFixture.with_one_living(type_id, _t)
