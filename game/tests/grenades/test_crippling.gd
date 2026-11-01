extends GdUnitTestSuite
## The rules' decisions about a blast: damage, crippling by the legs or by a band of health,
## the seeded roll, refills and the shop.

var _tuning: RulesTuning
var _rules: GameRules
var _log: RulesFixture
var _zombie: int


func before_test() -> void:
	_tuning = RulesFixture.tuning()
	_begin()


func _begin(seed_value: int = 1234) -> void:
	_rules = RulesFixture.make_rules(1, seed_value, _tuning)
	_log = RulesFixture.record(_rules)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 12.0)
	_zombie = _log.spawned_ids()[0]


func _blast(damage: float, leg_damage: float, id: int = -1) -> Array[Dictionary]:
	var victim := {
		"zombie_id": _zombie if id < 0 else id, "damage": damage, "leg_damage": leg_damage
	}
	return _rules.apply(RulesAction.explosion(1, [victim]))


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


func test_a_blast_takes_health_off_and_names_the_blast_zone() -> void:
	var events := _blast(20.0, 0.0)
	var damaged := events.filter(func(e: Dictionary) -> bool: return e["type"] == &"zombie_damaged")
	assert_float(damaged[0]["damage"]).is_equal(20.0)
	assert_float(damaged[0]["health"]).is_equal(RulesFixture.round_health(1) - 20.0)
	assert_str(damaged[0]["zone"]).is_equal("blast")


func test_enough_damage_on_the_legs_cripples_the_zombie() -> void:
	# A quarter of a round 1 zombie's health (12.5) on the legs is enough.
	var events := _blast(25.0, 20.0)
	var crippled := events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"zombie_crippled"
	)
	assert_array(crippled).has_size(1)
	assert_str(crippled[0]["cause"]).is_equal("legs")
	assert_int(crippled[0]["zombie_id"]).is_equal(_zombie)
	assert_float(crippled[0]["speed_scale"]).is_equal(_tuning.explosives.crawler_speed_fraction)
	assert_bool(_rules.is_crippled(_zombie)).is_true()


func test_leg_damage_adds_up_over_blasts() -> void:
	assert_array(_types(_blast(10.0, 10.0))).not_contains([&"zombie_crippled"])
	assert_bool(_rules.is_crippled(_zombie)).is_false()
	assert_array(_types(_blast(10.0, 10.0))).contains([&"zombie_crippled"])


func test_a_little_leg_damage_alone_does_not_cripple() -> void:
	_tuning.explosives.band_chance = 0.0
	assert_array(_types(_blast(10.0, 10.0))).not_contains([&"zombie_crippled"])


func test_a_zombie_left_badly_hurt_may_lose_its_legs_by_the_band() -> void:
	_tuning.explosives.band_chance = 1.0
	_begin()
	# 60 health, 45 damage leaves 15 = 25 percent, inside 5 to 40 percent.
	var events := _blast(45.0, 0.0)
	var crippled := events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"zombie_crippled"
	)
	assert_array(crippled).has_size(1)
	assert_str(crippled[0]["cause"]).is_equal("wounded")


func test_the_band_edges() -> void:
	_tuning.explosives.band_chance = 1.0
	_begin()
	# Left with 70 percent: above the band.
	assert_array(_types(_blast(18.0, 0.0))).not_contains([&"zombie_crippled"])
	# Left with 1 percent (60 - 18 - 41.4): below the band, nearly dead.
	assert_array(_types(_blast(41.4, 0.0))).not_contains([&"zombie_crippled"])
	assert_bool(_rules.is_crippled(_zombie)).is_false()


func test_a_zombie_the_blast_kills_is_not_crippled() -> void:
	var events := _blast(500.0, 100.0)
	assert_array(_types(events)).contains([&"zombie_removed"])
	assert_array(_types(events)).not_contains([&"zombie_crippled"])


func test_a_crawler_is_crippled_once() -> void:
	_tuning.explosives.band_chance = 1.0
	_begin()
	assert_array(_types(_blast(45.0, 25.0))).contains([&"zombie_crippled"])
	assert_array(_types(_blast(2.0, 2.0))).not_contains([&"zombie_crippled"])


func test_the_roll_is_seeded_so_every_machine_agrees() -> void:
	_tuning.explosives.band_chance = 0.5
	var outcomes: Array = []
	for seed_value in [1, 2]:
		for _repeat in 2:
			_begin(seed_value)
			var ids := _log.spawned_ids()
			var row := []
			for id in ids:
				row.append(_types(_blast(45.0, 0.0, id)).has(&"zombie_crippled"))
			outcomes.append(row)
	assert_array(outcomes[0]).is_equal(outcomes[1])
	assert_array(outcomes[2]).is_equal(outcomes[3])
	var mixed := false
	for row in outcomes:
		mixed = mixed or (row.has(true) and row.has(false))
	assert_bool(mixed).is_true()


func test_a_gunshot_never_cripples() -> void:
	_tuning.explosives.band_chance = 1.0
	_begin()
	var events := _rules.apply(RulesAction.hit(1, _zombie, &"limb", 45.0))
	assert_array(_types(events)).not_contains([&"zombie_crippled"])


func test_a_snapshot_keeps_a_crawler_a_crawler_and_the_roll_going() -> void:
	_tuning.explosives.band_chance = 0.5
	_begin()
	_blast(45.0, 25.0)
	var copy := GameRules.new(_tuning, 1234)
	assert_str(copy.from_bytes(_rules.to_bytes())).is_equal("")
	assert_bool(copy.is_crippled(_zombie)).is_true()
	var other := _log.spawned_ids()[1]
	var victims := [{"zombie_id": other, "damage": 45.0, "leg_damage": 0.0}]
	var a := _rules.apply(RulesAction.explosion(1, victims))
	var b := copy.apply(RulesAction.explosion(1, victims))
	assert_str(str(a)).is_equal(str(b))


func test_a_blast_on_a_zombie_that_is_gone_is_skipped() -> void:
	RulesFixture.kill(_rules, 1, _zombie)
	var events := _blast(10.0, 0.0)
	assert_array(events).is_empty()


func test_nonsense_victims_are_refused() -> void:
	for victims in [
		[{"zombie_id": _zombie, "damage": -5.0, "leg_damage": 0.0}],
		[{"zombie_id": _zombie, "damage": 5.0, "leg_damage": 9.0}],
		[{"zombie_id": _zombie, "damage": NAN, "leg_damage": 0.0}],
		[{"zombie_id": _zombie}],
		["a zombie"],
	]:
		var events := _rules.apply(RulesAction.explosion(1, victims))
		assert_str(events[0]["type"]).is_equal("action_rejected")
		assert_str(events[0]["reason"]).is_equal("out_of_range")


# --- grenades the player carries ---


func _use_all() -> void:
	while _rules.grenades_of(1) > 0:
		_rules.apply(RulesAction.use_grenade(1))


func test_a_player_carries_the_round_amount_when_round_one_starts() -> void:
	assert_int(_rules.grenades_of(1)).is_equal(_tuning.explosives.refill_to)
	assert_int(_tuning.explosives.start_grenades).is_less_equal(_tuning.explosives.refill_to)


func test_using_one_takes_one_and_none_left_is_refused() -> void:
	var have := _rules.grenades_of(1)
	_rules.apply(RulesAction.use_grenade(1))
	assert_int(_rules.grenades_of(1)).is_equal(have - 1)
	_use_all()
	var events := _rules.apply(RulesAction.use_grenade(1))
	assert_str(events[0]["reason"]).is_equal("no_grenades")
	assert_int(_rules.grenades_of(1)).is_equal(0)


func _clear_the_round() -> void:
	var guard := 0
	while _rules.phase == GameRules.Phase.ACTIVE and guard < 600:
		RulesFixture.run(_rules, 1.0)
		for id in _log.spawned_ids():
			_rules.apply(RulesAction.zombie_gone(id))
		guard += 1


func test_the_next_round_refills_to_the_round_amount() -> void:
	_use_all()
	_clear_the_round()
	assert_int(_rules.grenades_of(1)).is_equal(0)
	_rules.apply(RulesAction.skip_break())
	assert_int(_rules.round_number).is_equal(2)
	assert_int(_rules.grenades_of(1)).is_equal(_tuning.explosives.refill_to)
	(
		assert_array(
			_log.of(&"grenade_count_changed").map(
				func(e: Dictionary) -> Variant: return e["reason"]
			)
		)
		. contains(["thrown", "refill"])
	)


func test_a_refill_tops_up_and_never_takes_grenades_away() -> void:
	_rules.apply(RulesAction.grant_points(1, 5000))
	RulesFixture.buy(_rules, 1, &"grenades")
	RulesFixture.buy(_rules, 1, &"grenades")
	assert_int(_rules.grenades_of(1)).is_equal(_tuning.explosives.max_grenades)
	_clear_the_round()
	_rules.apply(RulesAction.skip_break())
	assert_int(_rules.grenades_of(1)).is_equal(_tuning.explosives.max_grenades)


func test_the_shop_sells_grenades_up_to_the_carry_limit() -> void:
	_rules.apply(RulesAction.grant_points(1, 5000))
	_use_all()
	var before := _rules.points_of(1)
	assert_int(RulesFixture.buy(_rules, 1, &"grenades")).is_equal(GameRules.BuyResult.OK)
	assert_int(_rules.grenades_of(1)).is_equal(2)
	assert_int(before - _rules.points_of(1)).is_equal(_tuning.economy.item(&"grenades").price)
	RulesFixture.buy(_rules, 1, &"grenades")
	RulesFixture.buy(_rules, 1, &"grenades")
	assert_int(_rules.grenades_of(1)).is_equal(_tuning.explosives.max_grenades)
	assert_int(RulesFixture.buy(_rules, 1, &"grenades")).is_equal(GameRules.BuyResult.LIMIT_REACHED)


func test_a_part_purchase_costs_a_part_of_the_price() -> void:
	_rules.apply(RulesAction.grant_points(1, 5000))
	_use_all()
	RulesFixture.buy(_rules, 1, &"grenades")
	RulesFixture.buy(_rules, 1, &"grenades")
	assert_int(_rules.grenades_of(1)).is_equal(4)
	var before := _rules.points_of(1)
	RulesFixture.buy(_rules, 1, &"grenades")
	assert_int(_rules.grenades_of(1)).is_equal(5)
	var full := _tuning.economy.item(&"grenades").price
	assert_int(before - _rules.points_of(1)).is_equal(ceili(full / 2.0))
