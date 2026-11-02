extends GdUnitTestSuite
## The balance simulator plays the re-cut and the hearty tonic through the real rules: the same
## item, the same price, the same `WeaponDef.upgraded`, and the health the rules give.

const BIG_PURSE := 100000


func _rich_night(skill: StringName = SimSkill.STRONG) -> NightSim:
	var tuning := RulesFixture.tuning()
	tuning.economy.start_points = BIG_PURSE
	var sim := NightSim.new(tuning, SimSkill.named(skill), 1, 5, 0.25)
	sim.run(3)
	return sim


func test_an_arm_re_cut_is_the_weapon_state_re_cut() -> void:
	var spec := UpgradeTuning.new()
	var arm := NightSim.SimArm.of(&"rifle")
	arm.mag = 1
	arm.reserve = 1
	arm.upgrade(spec)
	var state := WeaponState.new(WeaponCatalog.get_def(&"rifle"))
	state.upgrade(spec)
	assert_int(arm.tier()).is_equal(1)
	assert_int(arm.mag).is_equal(state.ammo)
	assert_int(arm.reserve).is_equal(state.reserve)
	assert_float(arm.def().damage).is_equal(state.def.damage)
	assert_int(arm.def().magazine_size).is_equal(state.def.magazine_size)


func test_a_re_cut_weapon_kills_faster_than_the_same_one_as_shipped() -> void:
	var health := RulesFixture.round_health(15)
	for id in UpgradeTuning.new().weapons:
		var plain := WeaponCatalog.get_def(id)
		var tuned := plain.upgraded(UpgradeTuning.new())
		(
			assert_float(SimWeapons.sustained_dps_of(tuned, health))
			. override_failure_message(String(id))
			. is_greater(SimWeapons.sustained_dps_of(plain, health))
		)


func test_a_player_with_the_points_re_cuts_and_the_rules_agree() -> void:
	var sim := _rich_night()
	var owned: PlayerState = sim.rules.players[1]
	assert_array(owned.upgraded).is_not_empty()
	var tuned := 0
	for arm: NightSim.SimArm in sim._players[1].arms.values():
		if arm.tier() > 0:
			tuned += 1
			assert_bool(owned.upgraded.has(arm.id)).is_true()
	assert_int(tuned).is_equal(owned.upgraded.size())


func test_the_bench_charges_the_step_for_each_weapon_already_re_cut() -> void:
	var rules := RulesFixture.make_rules(1)
	var first := rules.price_of(&"upgrade_weapon", 1)
	assert_int(first).is_equal(rules.price_of(&"upgrade_weapon"))
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.grant_points(1, BIG_PURSE))
	rules.apply(RulesAction.buy(1, &"upgrade_weapon", -1, &"pistol"))
	var step := rules.tuning.upgrade.price_step
	assert_int(rules.price_of(&"upgrade_weapon", 1)).is_equal(first + step)
	var before := rules.points_of(1)
	rules.apply(RulesAction.buy(1, &"upgrade_weapon", -1, &"rifle"))
	assert_int(before - rules.points_of(1)).is_equal(first + step)


func test_the_player_of_the_sim_has_the_health_the_tonic_gave() -> void:
	var sim := _rich_night()
	var owned: PlayerState = sim.rules.players[1]
	assert_bool(owned.tonics.has(&"tonic_hearty")).is_true()
	assert_float(sim._players[1].max_health).is_equal(owned.max_health)
	assert_float(owned.max_health).is_greater(sim.rules.tuning.health.max_health)


func test_what_the_simulator_says_it_spent_on_a_re_cut_is_what_was_charged() -> void:
	var sim := _rich_night()
	var charged := 0
	for player: PlayerState in sim.rules.players.values():
		charged += player.points_spent
	var said := 0
	for item_id: StringName in sim._result["spent_on"]:
		said += sim._result["spent_on"][item_id]
	assert_int(said).is_equal(charged)
	assert_int(sim._result["spent_on"].get(&"upgrade_weapon", 0)).is_greater(0)


func test_a_player_saving_for_the_re_cut_spends_nothing_else_first() -> void:
	# 1,400 points (the re-cut costs 1,500) and a list that wants a door first: the saver waits.
	var tuning := RulesFixture.tuning()
	tuning.economy.start_points = 1400
	var skill := SimSkill.named(SimSkill.AVERAGE)
	skill.shopping.assign([&"upgrade_weapon", &"door_concession"])
	skill.saves_for.assign([&"upgrade_weapon"])
	var sim := NightSim.new(tuning, skill, 1, 3, 0.25)
	sim.rules.apply(RulesAction.start())
	sim._between_rounds()
	assert_bool(sim.rules.is_door_open(&"door_concession")).is_false()
	skill.saves_for.clear()
	var impatient := NightSim.new(tuning, skill, 1, 3, 0.25)
	impatient.rules.apply(RulesAction.start())
	impatient._between_rounds()
	assert_bool(impatient.rules.is_door_open(&"door_concession")).is_true()
