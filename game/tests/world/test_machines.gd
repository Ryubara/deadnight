# The lot's two machines are drawn from fixed steps: a re-cut lays the weapon on the cradle, drops
# the press, strikes once with a flash and lifts the weapon; a pour fills the tumbler and drains it
# at the gulp. Nothing here reads a clock.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0


func _run(machine: Node, seconds: float) -> void:
	for _i in roundi(seconds / STEP):
		machine.advance(STEP)


func _bench() -> RecutMachine:
	var machine := auto_free(RecutMachine.new()) as RecutMachine
	add_child(machine)
	return machine


func _fountain() -> SodaFountain:
	var machine := auto_free(SodaFountain.new()) as SodaFountain
	add_child(machine)
	return machine


func test_an_idle_bench_has_its_press_up_and_no_weapon_on_the_cradle() -> void:
	var bench := _bench()
	_run(bench, 1.0)
	assert_bool(bench.is_playing()).is_false()
	assert_float(bench.ram_height()).is_equal_approx(RecutMachine.RAM_UP, 0.001)
	assert_str(String(bench.shown_weapon())).is_empty()


func test_every_weapon_that_can_be_re_cut_has_a_model_for_the_cradle() -> void:
	for id in UpgradeTuning.new().weapons:
		(
			assert_bool(MachineParts.WEAPON_MODELS.has(id))
			. override_failure_message(String(id))
			. is_true()
		)
		var model := MachineParts.weapon_model(id, 1.4)
		assert_object(model).override_failure_message(String(id)).is_not_null()
		model.free()


func test_a_re_cut_drops_the_press_strikes_once_and_lifts_the_weapon() -> void:
	var bench := _bench()
	var strikes := [0]
	bench.pressed.connect(func() -> void: strikes[0] += 1)
	bench.play(&"rifle")
	assert_str(String(bench.shown_weapon())).is_equal("rifle")
	_run(bench, RecutMachine.STRIKE - 0.1)
	assert_float(bench.ram_height()).is_greater(RecutMachine.RAM_DOWN + 0.05)
	assert_int(strikes[0]).is_equal(0)
	_run(bench, 0.15)
	assert_int(strikes[0]).is_equal(1)
	assert_float(bench.ram_height()).is_equal_approx(RecutMachine.RAM_DOWN, 0.02)
	assert_float(bench.flash()).is_greater(0.5)
	_run(bench, 0.6)
	assert_float(bench.flash()).is_less(0.1)
	assert_float(bench.ram_height()).is_greater(RecutMachine.RAM_DOWN + 0.1)
	_run(bench, RecutMachine.DURATION)
	assert_bool(bench.is_playing()).is_false()
	assert_str(String(bench.shown_weapon())).is_empty()
	assert_int(strikes[0]).is_equal(1)


func test_a_second_re_cut_starts_over() -> void:
	var bench := _bench()
	bench.play(&"pistol")
	_run(bench, 1.2)
	bench.play(&"smg")
	assert_str(String(bench.shown_weapon())).is_equal("smg")
	assert_float(bench.flash()).is_less(1.0)
	_run(bench, RecutMachine.STRIKE + 0.05)
	assert_float(bench.flash()).is_greater(0.5)


func test_the_reels_turn_faster_during_a_re_cut() -> void:
	var bench := _bench()
	var idle_before := bench._reel_angle
	_run(bench, 0.5)
	var idle_turn := bench._reel_angle - idle_before
	bench.play(&"pistol")
	var cut_before := bench._reel_angle
	_run(bench, 0.5)
	assert_float(bench._reel_angle - cut_before).is_greater(idle_turn * 3.0)


func test_a_pour_fills_the_tumbler_then_drains_it_at_the_gulp() -> void:
	var fountain := _fountain()
	var poured := [0]
	fountain.poured.connect(func() -> void: poured[0] += 1)
	assert_float(fountain.fullness()).is_equal(0.0)
	fountain.play()
	_run(fountain, SodaFountain.FILL + 0.03)
	assert_float(fountain.fullness()).is_greater(0.7)
	assert_int(poured[0]).is_equal(0)
	_run(fountain, SodaFountain.GULP - SodaFountain.FILL + 0.05)
	assert_int(poured[0]).is_equal(1)
	assert_float(fountain.flash()).is_greater(0.5)
	assert_float(fountain.fullness()).is_less(0.05)
	_run(fountain, SodaFountain.DURATION)
	assert_bool(fountain.is_playing()).is_false()
	assert_int(poured[0]).is_equal(1)
