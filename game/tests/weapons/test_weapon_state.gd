extends GdUnitTestSuite
## Fire rate, magazine and reload on one carried weapon.

const STEP := 1.0 / 60.0


func _hold_the_trigger(state: WeaponState, seconds: float) -> int:
	var shots := 0
	for _i in ceili(seconds / STEP):
		if state.fire_block() == &"":
			state.fire()
			shots += 1
		state.tick(STEP)
	return shots


func test_it_starts_full() -> void:
	var state := WeaponState.new(WeaponsFixture.def(&"pistol"))
	assert_int(state.ammo).is_equal(10)
	assert_int(state.reserve).is_equal(40)
	assert_str(state.fire_block()).is_equal("")


func test_fire_rate_follows_the_interval() -> void:
	var smg := WeaponsFixture.def(&"smg")
	var state := WeaponState.new(smg)
	state.ammo = 999
	var shots := _hold_the_trigger(state, 2.0)
	# 13.3 a second on paper; a 60 Hz step lands a shot every fifth step, 12 a second.
	var on_paper := 2.0 * smg.rounds_per_second()
	assert_int(shots).is_between(int(on_paper) - 4, ceili(on_paper))


func test_a_slow_weapon_cannot_be_fired_faster() -> void:
	var state := WeaponState.new(WeaponsFixture.def(&"rifle"))
	var shots := _hold_the_trigger(state, 2.0)
	assert_int(shots).is_between(3, 4)


func test_a_shot_inside_the_interval_is_blocked() -> void:
	var state := WeaponState.new(WeaponsFixture.def(&"pistol"))
	state.fire()
	assert_str(state.fire_block()).is_equal("cooldown")
	state.tick(0.1)
	assert_str(state.fire_block()).is_equal("cooldown")
	state.tick(0.2)
	assert_str(state.fire_block()).is_equal("")


func test_every_shot_spends_a_round_until_it_is_empty() -> void:
	var state := WeaponState.new(WeaponsFixture.def(&"pistol"))
	for _i in 10:
		state.fire()
		state.tick(1.0)
	assert_int(state.ammo).is_equal(0)
	assert_str(state.fire_block()).is_equal("empty")


func test_reload_takes_its_time_and_fills_from_the_reserve() -> void:
	var pistol := WeaponsFixture.def(&"pistol")
	var state := WeaponState.new(pistol)
	state.ammo = 3
	assert_str(state.reload_block()).is_equal("")
	state.start_reload()
	assert_str(state.fire_block()).is_equal("reloading")
	assert_bool(state.tick(pistol.reload_time - 0.1)).is_false()
	assert_int(state.ammo).is_equal(3)
	assert_bool(state.tick(0.2)).is_true()
	assert_int(state.ammo).is_equal(10)
	assert_int(state.reserve).is_equal(40 - 7)
	assert_bool(state.is_reloading()).is_false()


func test_a_reload_takes_only_what_the_reserve_has() -> void:
	var state := WeaponState.new(WeaponsFixture.def(&"pistol"))
	state.ammo = 0
	state.reserve = 4
	state.start_reload()
	state.tick(5.0)
	assert_int(state.ammo).is_equal(4)
	assert_int(state.reserve).is_equal(0)


func test_a_reload_that_makes_no_sense_is_refused() -> void:
	var state := WeaponState.new(WeaponsFixture.def(&"pistol"))
	assert_str(state.reload_block()).is_equal("full")
	state.ammo = 5
	state.reserve = 0
	assert_str(state.reload_block()).is_equal("no_reserve")
	state.reserve = 5
	state.start_reload()
	assert_str(state.reload_block()).is_equal("reloading")
	assert_str(WeaponState.new(WeaponsFixture.def(&"crowbar")).reload_block()).is_equal("melee")


func test_a_cancelled_reload_gives_nothing() -> void:
	var state := WeaponState.new(WeaponsFixture.def(&"pistol"))
	state.ammo = 0
	state.start_reload()
	state.tick(0.5)
	state.cancel_reload()
	state.tick(5.0)
	assert_int(state.ammo).is_equal(0)


func test_reserve_never_passes_its_limit() -> void:
	var pistol := WeaponsFixture.def(&"pistol")
	var state := WeaponState.new(pistol)
	assert_int(state.add_reserve(1000)).is_equal(pistol.reserve_max - 40)
	assert_int(state.reserve).is_equal(pistol.reserve_max)


func test_a_melee_weapon_never_runs_dry() -> void:
	var state := WeaponState.new(WeaponsFixture.def(&"crowbar"))
	for _i in 20:
		assert_str(state.fire_block()).is_equal("")
		state.fire()
		state.tick(1.0)
