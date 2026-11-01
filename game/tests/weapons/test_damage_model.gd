extends GdUnitTestSuite
## What a hit is worth: falloff, hit zone, penetration, blast, and that every shipped weapon file
## loads with sane numbers.


func test_full_damage_up_to_the_falloff_start() -> void:
	var pistol := WeaponsFixture.def(&"pistol")
	assert_float(DamageModel.falloff(pistol, 0.0)).is_equal(1.0)
	assert_float(DamageModel.falloff(pistol, pistol.falloff_start)).is_equal(1.0)


func test_damage_slides_to_the_floor_at_the_falloff_end_and_stays_there() -> void:
	var pistol := WeaponsFixture.def(&"pistol")
	var middle := (pistol.falloff_start + pistol.falloff_end) / 2.0
	var expected := lerpf(1.0, pistol.min_damage_fraction, 0.5)
	assert_float(DamageModel.falloff(pistol, middle)).is_equal_approx(expected, 0.0001)
	assert_float(DamageModel.falloff(pistol, pistol.falloff_end)).is_equal_approx(
		pistol.min_damage_fraction, 0.0001
	)
	assert_float(DamageModel.falloff(pistol, pistol.falloff_end + 20.0)).is_equal_approx(
		pistol.min_damage_fraction, 0.0001
	)


func test_a_pistol_headshot_at_close_range_kills_a_round_one_zombie() -> void:
	var pistol := WeaponsFixture.def(&"pistol")
	var round_one_health := 60.0
	assert_float(DamageModel.damage(pistol, 5.0, Hitbox.HEAD)).is_greater_equal(round_one_health)
	assert_float(DamageModel.damage(pistol, 5.0, Hitbox.BODY)).is_less(round_one_health)


func test_zones_scale_the_damage() -> void:
	var pistol := WeaponsFixture.def(&"pistol")
	var body := DamageModel.damage(pistol, 1.0, Hitbox.BODY)
	assert_float(DamageModel.damage(pistol, 1.0, Hitbox.HEAD)).is_equal_approx(body * 2.5, 0.001)
	assert_float(DamageModel.damage(pistol, 1.0, Hitbox.LIMB)).is_equal_approx(body * 0.6, 0.001)


func test_a_zone_a_weapon_does_not_list_counts_one() -> void:
	var bare := WeaponDef.new()
	assert_float(bare.zone_multiplier(&"tail")).is_equal(1.0)


func test_each_body_a_shot_passes_through_weakens_it() -> void:
	var rifle := WeaponsFixture.def(&"rifle")
	var first := DamageModel.damage(rifle, 10.0, Hitbox.BODY, 0)
	var second := DamageModel.damage(rifle, 10.0, Hitbox.BODY, 1)
	var third := DamageModel.damage(rifle, 10.0, Hitbox.BODY, 2)
	assert_float(second).is_equal_approx(first * rifle.penetration_falloff, 0.001)
	assert_float(third).is_equal_approx(first * pow(rifle.penetration_falloff, 2), 0.001)


func test_a_shotgun_is_deadly_close_and_weak_far() -> void:
	var shotgun := WeaponsFixture.def(&"shotgun")
	var close := DamageModel.damage(shotgun, 2.0, Hitbox.BODY) * shotgun.pellets
	var far := DamageModel.damage(shotgun, 25.0, Hitbox.BODY) * shotgun.pellets
	assert_float(close).is_greater(80.0)
	assert_float(far).is_less(close * 0.4)


func test_a_blast_hurts_most_at_the_centre_and_not_at_all_past_the_radius() -> void:
	var flare := WeaponsFixture.def(&"flare_gun")
	assert_float(DamageModel.splash(flare, 0.0)).is_equal(flare.splash_damage)
	assert_float(DamageModel.splash(flare, flare.splash_radius)).is_equal_approx(
		flare.splash_damage * flare.splash_min_fraction, 0.001
	)
	assert_float(DamageModel.splash(flare, flare.splash_radius + 0.1)).is_equal(0.0)
	assert_float(DamageModel.splash(WeaponsFixture.def(&"pistol"), 0.0)).is_equal(0.0)


func test_every_shipped_weapon_loads_with_sane_numbers() -> void:
	for id in WeaponsFixture.IDS:
		var def := WeaponsFixture.def(id)
		assert_object(def).is_not_null()
		assert_str(def.id).is_equal(id)
		assert_float(def.damage).is_greater(0.0)
		assert_float(def.fire_interval).is_greater(0.0)
		assert_float(def.zone_multiplier(Hitbox.HEAD)).is_greater_equal(
			def.zone_multiplier(Hitbox.LIMB)
		)
		if not def.is_melee():
			assert_int(def.magazine_size).is_greater(0)
			assert_float(def.reload_time).is_greater(0.0)
			assert_int(def.reserve_start).is_less_equal(def.reserve_max)
		assert_float(def.falloff_start).is_less_equal(def.falloff_end)


func test_the_kinds_are_what_the_design_says() -> void:
	assert_bool(WeaponsFixture.def(&"pistol").is_hitscan()).is_true()
	assert_bool(WeaponsFixture.def(&"shotgun").is_hitscan()).is_true()
	assert_int(WeaponsFixture.def(&"shotgun").pellets).is_greater(1)
	assert_bool(WeaponsFixture.def(&"flare_gun").is_projectile()).is_true()
	assert_bool(WeaponsFixture.def(&"crowbar").is_melee()).is_true()
	assert_int(WeaponsFixture.def(&"rifle").penetration).is_greater(0)
