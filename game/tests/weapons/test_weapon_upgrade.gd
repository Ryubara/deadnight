extends GdUnitTestSuite
## A re-cut weapon: the numbers `UpgradeTuning` gives, filled to the new size, and what the combat
## server does with the action.

var _spec := UpgradeTuning.shipped()


func test_the_copy_has_the_numbers_of_the_tuning() -> void:
	for id in _spec.weapon_ids():
		if not WeaponCatalog.IDS.has(id):
			continue
		var base := WeaponCatalog.get_def(id)
		var cut := _spec.profile_of(id)
		var tuned := base.upgraded(_spec)
		assert_str(tuned.id).is_equal(String(id))
		assert_int(tuned.tier).is_equal(1)
		assert_int(base.tier).is_equal(0)
		assert_float(tuned.damage).is_equal(base.damage * cut.damage_multiplier)
		assert_float(tuned.splash_damage).is_equal(base.splash_damage * cut.damage_multiplier)
		assert_int(tuned.magazine_size).is_equal(
			ceili(base.magazine_size * cut.magazine_multiplier)
		)
		assert_int(tuned.reserve_max).is_equal(ceili(base.reserve_max * cut.reserve_multiplier))
		assert_str(tuned.display_name).is_equal(cut.name_of(base.display_name, _spec.name_prefix))
		assert_bool(tuned.element == cut.element).is_true()


func test_the_shipped_file_is_not_changed_by_a_re_cut() -> void:
	var before := WeaponCatalog.get_def(&"rifle").damage
	WeaponCatalog.get_def(&"rifle").upgraded(_spec)
	assert_float(WeaponCatalog.get_def(&"rifle").damage).is_equal(before)


func test_a_re_cut_fills_the_magazine_and_the_reserve() -> void:
	var state := WeaponState.new(WeaponCatalog.get_def(&"smg"))
	state.ammo = 3
	state.reserve = 4
	state.start_reload()
	state.upgrade(_spec)
	assert_int(state.tier()).is_equal(1)
	assert_int(state.ammo).is_equal(state.def.magazine_size)
	assert_int(state.reserve).is_equal(state.def.reserve_max)
	assert_bool(state.is_reloading()).is_false()
	assert_int(state.def.magazine_size).is_greater(30)


func test_the_server_re_cuts_a_carried_weapon_once() -> void:
	var server := WeaponsFixture.make_server()
	server.apply(CombatAction.give_weapon(1, &"pistol"))
	var events := server.apply(CombatAction.upgrade_weapon(1, &"pistol"))
	var done := WeaponsFixture.of(events, &"weapon_upgraded")[0]
	assert_int(done["tier"]).is_equal(1)
	assert_str(done["display_name"]).is_equal("Re-Cut Revolver")
	assert_float(done["damage"]).is_equal(
		WeaponCatalog.get_def(&"pistol").damage * _spec.profile_of(&"pistol").damage_multiplier
	)
	assert_int(done["ammo"]).is_equal(done["magazine"])
	var again := server.apply(CombatAction.upgrade_weapon(1, &"pistol"))
	assert_str(WeaponsFixture.of(again, &"action_rejected")[0]["reason"]).is_equal("not_upgradable")


func test_a_weapon_not_carried_or_a_crowbar_is_refused() -> void:
	var server := WeaponsFixture.make_server()
	server.apply(CombatAction.give_weapon(1, &"crowbar"))
	var missing := server.apply(CombatAction.upgrade_weapon(1, &"rifle"))
	assert_str(WeaponsFixture.of(missing, &"action_rejected")[0]["reason"]).is_equal("not_carried")
	var melee := server.apply(CombatAction.upgrade_weapon(1, &"crowbar"))
	assert_str(WeaponsFixture.of(melee, &"action_rejected")[0]["reason"]).is_equal("not_upgradable")


func test_a_re_cut_shot_hurts_by_the_multiplier() -> void:
	var rules := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(rules)
	var server := CombatServer.new(WeaponsFixture.all_defs(), rules, Callable(), 1)
	server.apply(CombatAction.give_weapon(1, &"rifle"))
	var plain := server.state_of(1, &"rifle").def
	server.apply(CombatAction.upgrade_weapon(1, &"rifle"))
	var tuned := server.state_of(1, &"rifle").def
	var spec := rules.tuning.upgrade.profile_of(&"rifle")
	assert_float(DamageModel.damage(tuned, 0.0, &"body")).is_equal(
		DamageModel.damage(plain, 0.0, &"body") * spec.damage_multiplier
	)
