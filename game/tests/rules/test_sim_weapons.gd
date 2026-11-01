extends GdUnitTestSuite
## The balance simulator shoots the game's own weapons and plays only what the game does: these
## pin that `SimWeapons` reads the definitions, and that the night model carries no invented
## tonic effects and pays fuel for its light.


func test_a_pull_is_the_definitions_damage_times_pellets_with_falloff_and_zone() -> void:
	var rifle := WeaponCatalog.get_def(&"rifle")
	assert_float(SimWeapons.damage(&"weapon_rifle", &"body", 0.0)).is_equal(rifle.damage)
	assert_float(SimWeapons.damage(&"rifle", &"head", 0.0)).is_equal(
		rifle.damage * rifle.zone_multiplier(&"head")
	)
	var shotgun := WeaponCatalog.get_def(&"shotgun")
	assert_float(SimWeapons.damage(&"weapon_shotgun", &"body", 0.0)).is_equal(
		shotgun.damage * float(shotgun.pellets)
	)
	# Past the end of the falloff a pull is worth the weapon's minimum.
	assert_float(SimWeapons.damage(&"pistol", &"body", 500.0)).is_equal_approx(
		(
			WeaponCatalog.get_def(&"pistol").damage
			* WeaponCatalog.get_def(&"pistol").min_damage_fraction
		),
		0.001
	)


func test_a_weapons_timing_is_the_definitions() -> void:
	for id in [&"pistol", &"weapon_smg", &"weapon_rifle", &"weapon_shotgun", &"weapon_flare_gun"]:
		var weapon := SimWeapons.def(id)
		assert_float(SimWeapons.interval(id)).is_equal(weapon.fire_interval)
		assert_int(SimWeapons.magazine(id)).is_equal(weapon.magazine_size)
		assert_float(SimWeapons.reload_seconds(id)).is_equal(weapon.reload_time)


func test_sustained_damage_counts_the_reload_and_picks_the_smg_over_the_rifle() -> void:
	var pistol := SimWeapons.def(&"pistol")
	var cycle := float(pistol.magazine_size) * pistol.fire_interval + pistol.reload_time
	assert_float(SimWeapons.sustained_dps(&"pistol")).is_equal_approx(
		pistol.damage * float(pistol.magazine_size) / cycle, 0.001
	)
	var owned: Array[StringName] = [&"weapon_rifle", &"weapon_smg", &"weapon_shotgun"]
	assert_str(SimWeapons.best(owned)).is_equal("weapon_smg")
	var none: Array[StringName] = []
	assert_str(SimWeapons.best(none)).is_equal("pistol")


func test_only_a_flare_has_a_blast() -> void:
	assert_float(SimWeapons.splash(&"weapon_rifle", 0.0)).is_equal(0.0)
	var flare := SimWeapons.def(&"weapon_flare_gun")
	assert_float(SimWeapons.splash(&"weapon_flare_gun", 0.0)).is_equal(flare.splash_damage)
	assert_float(SimWeapons.splash(&"weapon_flare_gun", flare.splash_radius + 1.0)).is_equal(0.0)


func test_players_have_the_nights_health_whatever_they_buy() -> void:
	var sim := NightSim.new(RulesFixture.tuning(), SimSkill.named(SimSkill.STRONG), 1, 9, 0.25)
	sim.run(6)
	var night := NightTuning.new()
	for player: NightSim.SimPlayer in sim._players.values():
		assert_float(player.max_health).is_equal(night.max_health)
		assert_float(player.regen_delay).is_equal(night.regen_delay)


func test_the_light_a_player_keeps_on_costs_fuel() -> void:
	var tuning := RulesFixture.tuning()
	var sim := NightSim.new(tuning, SimSkill.named(SimSkill.STRONG), 1, 9, 0.25)
	assert_bool(sim.rules.generator.circuits[&"booth"]).is_true()
	assert_bool(sim.rules.generator.circuits[&"back_lot"]).is_false()
	var idle_only := tuning.fuel.start_fuel
	sim.run(4)
	# Four rounds of strong play burn much more than the idle draw alone would.
	var minimum_idle_burn := tuning.fuel.idle_drain * 60.0
	assert_float(idle_only - sim.rules.generator.fuel).is_greater(minimum_idle_burn * 2.0)
