# The revive risk function (bots plan, phase 5), a pure function pinned one case at a time: no
# zombie in the window is safe, a pack that can be killed in time is cleared first, a pack that
# cannot is unsafe, a victim who bleeds out before the walk is late, and the tables of the zombie
# types are the game's.
extends GdUnitTestSuite

const VICTIM := Vector3(0, 0, -10)
const REVIVER := Vector3.ZERO
const SECONDS := 3.5
const REACH := 2.0
## A walker's pace in the first rounds (m/s) and health.
const SLOW := 1.3
const HEALTH := 60.0
const BLEED := 40.0
## Health a second a decent weapon kills.
const RATE := 60.0


func _threat(at: Vector3, speed := SLOW, health := HEALTH) -> BotReviveRisk.Threat:
	return BotReviveRisk.Threat.make(at, speed, health)


func _judge(
	threats: Array[BotReviveRisk.Threat], rate := RATE, bleed := BLEED, eagerness := 0.5
) -> BotReviveRisk.Verdict:
	return BotReviveRisk.assess(VICTIM, REVIVER, threats, SECONDS, REACH, rate, bleed, eagerness)


func test_the_numbers_are_the_games() -> void:
	var rules := RulesFixture.tuning()
	assert_float(BotRevive.REVIVE_SECONDS).is_equal(rules.health.revive_seconds)
	assert_float(BotRevive.REVIVE_REACH).is_equal(NightTuning.shipped().revive_reach)
	assert_float(BotRevive.HOLD_FROM).is_less(BotRevive.REVIVE_REACH)
	for type in rules.roster.types:
		var look: StringName = type.looks[0]
		var health := float(BotReviveRisk.HEALTH_BY_LOOK.get(look, 1.0))
		var speed := float(BotReviveRisk.SPEED_BY_LOOK.get(look, 1.0))
		assert_float(health).is_equal(type.health_multiplier)
		assert_float(speed).is_equal(type.speed_multiplier)
	assert_float(BotReviveRisk.DARK_SPEED).is_equal(rules.rounds.dark_speed_multiplier)


func test_no_zombie_near_is_safe() -> void:
	var none: Array[BotReviveRisk.Threat] = []
	assert_int(_judge(none).kind).is_equal(BotReviveRisk.Kind.SAFE)
	var far: Array[BotReviveRisk.Threat] = [_threat(Vector3(40, 0, -10))]
	assert_int(_judge(far).kind).is_equal(BotReviveRisk.Kind.SAFE)


func test_a_slow_zombie_far_off_is_outwaited_and_a_near_one_is_not() -> void:
	var window := _judge([]).window
	# Seven metres from the body at 1.3 m/s: five seconds, a window of about 6.
	assert_float(window).is_greater(5.0)
	var edge: Array[BotReviveRisk.Threat] = [_threat(VICTIM + Vector3(40, 0, 0), SLOW)]
	assert_int(_judge(edge).kind).is_equal(BotReviveRisk.Kind.SAFE)
	var near: Array[BotReviveRisk.Threat] = [_threat(VICTIM + Vector3(5, 0, 0), SLOW)]
	assert_int(_judge(near).kind).is_equal(BotReviveRisk.Kind.CLEAR)


func test_three_zombies_at_the_body_are_cleared_first_not_ignored() -> void:
	var pack: Array[BotReviveRisk.Threat] = []
	for i in 3:
		pack.append(_threat(VICTIM + Vector3(float(i), 0, 2)))
	var verdict := _judge(pack)
	assert_int(verdict.kind).is_equal(BotReviveRisk.Kind.CLEAR)
	assert_int(verdict.count).is_equal(3)
	assert_float(verdict.kill_seconds).is_equal_approx(3.0 * HEALTH / RATE, 0.001)
	assert_float(verdict.first_arrival).is_less(verdict.window)


func test_a_pack_too_big_or_too_tough_to_clear_is_unsafe() -> void:
	var crowd: Array[BotReviveRisk.Threat] = []
	for i in 14:
		crowd.append(_threat(VICTIM + Vector3(float(i) * 0.3, 0, 2)))
	assert_int(_judge(crowd).kind).is_equal(BotReviveRisk.Kind.UNSAFE)
	var boss: Array[BotReviveRisk.Threat] = [_threat(VICTIM + Vector3(3, 0, 0), 2.0, 900.0)]
	assert_int(_judge(boss).kind).is_equal(BotReviveRisk.Kind.UNSAFE)
	# The same boss against a bot that kills fast enough for it.
	assert_int(_judge(boss, 400.0, BLEED, 1.0).kind).is_equal(BotReviveRisk.Kind.CLEAR)


func test_a_weapon_that_cannot_kill_makes_even_one_zombie_unsafe() -> void:
	var one: Array[BotReviveRisk.Threat] = [_threat(VICTIM + Vector3(3, 0, 0))]
	assert_int(_judge(one, 0.0).kind).is_equal(BotReviveRisk.Kind.UNSAFE)


func test_a_victim_who_bleeds_out_before_the_walk_is_late() -> void:
	var none: Array[BotReviveRisk.Threat] = []
	var walk := BotReviveRisk.walk_seconds(REVIVER, VICTIM, REACH)
	assert_float(walk).is_greater(1.5)
	assert_int(_judge(none, RATE, walk).kind).is_equal(BotReviveRisk.Kind.LATE)
	assert_int(_judge(none, RATE, walk + 2.0).kind).is_equal(BotReviveRisk.Kind.SAFE)


func test_a_bold_bot_takes_a_risk_a_cautious_one_does_not() -> void:
	# A zombie that arrives a moment after the hold would be over.
	var window := _judge([]).window
	var arrives := window - 0.4
	var at := VICTIM + Vector3(arrives * SLOW + BotReviveRisk.STRIKE_REACH, 0, 0)
	var one: Array[BotReviveRisk.Threat] = [_threat(at)]
	var bold := _judge(one, RATE, BLEED, 1.0)
	var careful := _judge(one, RATE, BLEED, 0.0)
	assert_int(careful.kind).is_not_equal(BotReviveRisk.Kind.SAFE)
	assert_int(bold.kind).is_equal(BotReviveRisk.Kind.SAFE)


func test_a_zombie_on_the_reviver_counts_as_well_as_one_at_the_body() -> void:
	var on_me: Array[BotReviveRisk.Threat] = [_threat(REVIVER + Vector3(1.5, 0, 0))]
	assert_int(_judge(on_me).kind).is_equal(BotReviveRisk.Kind.CLEAR)


func test_the_danger_list_is_ordered_by_arrival() -> void:
	var list: Array[BotReviveRisk.Threat] = [
		_threat(VICTIM + Vector3(6, 0, 0)), _threat(VICTIM + Vector3(2, 0, 0))
	]
	var verdict := _judge(list)
	assert_array(verdict.danger).is_equal([1, 0])


func test_health_and_speed_follow_the_rounds_public_formula() -> void:
	var rounds := RulesFixture.tuning().rounds
	var walker := BotReviveRisk.health_of(&"walker", 5, rounds)
	assert_float(walker).is_equal(rounds.health_for_round(5))
	assert_float(BotReviveRisk.health_of(&"brute", 5, rounds)).is_equal(walker * 2.5)
	var run := BotReviveRisk.speed_of(&"runner", 5, rounds)
	assert_float(run).is_greater(BotReviveRisk.speed_of(&"walker", 5, rounds))


func test_the_kill_rate_is_the_held_weapons_share() -> void:
	var rifle := WeaponCatalog.get_def(&"rifle")
	var rate := BotReviveRisk.kill_rate_of(rifle, 80.0)
	assert_float(rate).is_equal_approx(WeaponWorth.of(rifle, 80.0) * BotReviveRisk.HIT_SHARE, 0.001)
	assert_float(BotReviveRisk.kill_rate_of(null, 80.0)).is_equal(0.0)
