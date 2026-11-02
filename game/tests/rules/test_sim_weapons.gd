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


func test_sustained_damage_counts_the_reload_and_the_health_the_blows_must_beat() -> void:
	var pistol := SimWeapons.def(&"pistol")
	var cycle := float(pistol.magazine_size) * pistol.fire_interval + pistol.reload_time
	assert_float(SimWeapons.sustained_dps(&"pistol")).is_equal_approx(
		pistol.damage * float(pistol.magazine_size) / cycle, 0.001
	)
	var owned: Array[StringName] = [&"weapon_rifle", &"weapon_smg", &"weapon_shotgun"]
	# Without a health it is raw damage a second. The shop weapons were stepped up (#254: the rifle
	# is 95 and the shotgun 152 a pull), so on raw damage alone they now beat the submachine gun.
	assert_str(SimWeapons.best(owned)).is_equal("weapon_shotgun")
	var none: Array[StringName] = []
	assert_str(SimWeapons.best(none)).is_equal("pistol")


func test_a_blow_that_overshoots_the_health_is_worth_no_more_than_the_health() -> void:
	# Shots land whole: 95 damage kills a 95 walker in one, a 96 one in two, so the second walker
	# is killed at half the rate (what the player really gets, and what the pick must count).
	assert_float(SimWeapons.sustained_dps(&"rifle", 96.0)).is_less(
		SimWeapons.sustained_dps(&"rifle", 95.0) * 0.6
	)
	# Against a round-1 walker (50) the rifle's 95 is mostly wasted and the submachine gun, with
	# its rate, is the better pick; against round 10's (117) the shotgun's whole blast beats both.
	var rounds := RulesFixture.tuning().rounds
	var owned: Array[StringName] = [&"weapon_rifle", &"weapon_smg", &"weapon_shotgun"]
	for spec: Array in [[1, &"weapon_smg"], [10, &"weapon_shotgun"]]:
		var health := rounds.health_for_round(spec[0])
		var best := &""
		var best_rate := -1.0
		for id in owned:
			var rate := SimWeapons.sustained_dps(id, health)
			if rate > best_rate:
				best_rate = rate
				best = id
		assert_str(best).is_equal(spec[1])


func test_only_a_flare_has_a_blast() -> void:
	assert_float(SimWeapons.splash(&"weapon_rifle", 0.0)).is_equal(0.0)
	var flare := SimWeapons.def(&"weapon_flare_gun")
	assert_float(SimWeapons.splash(&"weapon_flare_gun", 0.0)).is_equal(flare.splash_damage)
	assert_float(SimWeapons.splash(&"weapon_flare_gun", flare.splash_radius + 1.0)).is_equal(0.0)


func test_players_have_the_nights_health_whatever_they_buy() -> void:
	var sim := NightSim.new(RulesFixture.tuning(), SimSkill.named(SimSkill.STRONG), 1, 9, 0.25)
	sim.run(6)
	var health := RulesFixture.tuning().health
	for player: NightSim.SimPlayer in sim._players.values():
		assert_float(player.max_health).is_equal(health.max_health)
		assert_float(player.regen_delay).is_equal(health.regen_delay)


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


func _melee_arms(ids: Array[StringName]) -> Dictionary:
	var arms := {}
	for id in ids:
		arms[id] = NightSim.SimArm.of(id)
	return arms


func test_a_player_out_of_rounds_falls_back_on_the_melee_weapon_that_kills_fastest() -> void:
	var crowbar: Array[StringName] = [&"crowbar"]
	var all: Array[StringName] = [&"crowbar", &"baseball_bat", &"fire_axe"]
	# With only the crowbar, the crowbar, whatever the health.
	assert_str(String(SimWeapons.best_armed(_melee_arms(crowbar), 50.0))).is_equal("crowbar")
	# Against nothing in particular the heavy axe does the most a second; a round-1 walker (50) falls
	# to two quick bat blows sooner than to two crowbar blows or a slow axe; a round-10 one (121)
	# takes the crowbar three blows, the bat four and the axe two slow ones.
	assert_str(String(SimWeapons.best_armed(_melee_arms(all)))).is_equal("fire_axe")
	assert_str(String(SimWeapons.best_armed(_melee_arms(all), 50.0))).is_equal("baseball_bat")
	assert_str(String(SimWeapons.best_armed(_melee_arms(all), 121.0))).is_equal("crowbar")


func test_a_firearm_with_rounds_beats_any_melee_weapon_in_hand() -> void:
	var arms := _melee_arms([&"crowbar", &"fire_axe", &"pistol"])
	assert_str(String(SimWeapons.best_armed(arms, 50.0))).is_equal("pistol")
	arms[&"pistol"].mag = 0
	arms[&"pistol"].reserve = 0
	assert_str(String(SimWeapons.best_armed(arms, 0.0))).is_equal("fire_axe")
