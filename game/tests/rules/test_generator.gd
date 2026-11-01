extends GdUnitTestSuite
## The generator: the draw of each circuit, the strain of later rounds, the break, the warnings,
## running dry.

var _gen: GeneratorState
var _fuel: FuelTuning
var _events: Array[StringName] = []


func before_test() -> void:
	_fuel = RulesFixture.tuning().fuel
	_gen = GeneratorState.new(_fuel)
	_events.clear()
	_gen.fuel_low.connect(func() -> void: _events.append(&"low"))
	_gen.fuel_empty.connect(func() -> void: _events.append(&"empty"))
	_gen.fuel_restored.connect(func() -> void: _events.append(&"restored"))


func test_the_tank_starts_full_with_the_screen_lot_lit() -> void:
	assert_float(_gen.fuel).is_equal(100.0)
	assert_bool(_gen.is_lit(&"screen_lot")).is_true()
	assert_bool(_gen.is_lit(&"booth")).is_false()


func test_the_draw_is_the_idle_burn_plus_each_circuit_on() -> void:
	assert_float(_gen.drain_per_second(1, false)).is_equal_approx(0.09, 0.0001)
	_gen.set_circuit(&"booth", true)
	assert_float(_gen.drain_per_second(1, false)).is_equal_approx(0.17, 0.0001)
	_gen.set_circuit(&"screen_lot", false)
	assert_float(_gen.drain_per_second(1, false)).is_equal_approx(0.11, 0.0001)


func test_every_circuit_on_burns_the_whole_tank_in_the_documented_time() -> void:
	for circuit_id in _fuel.circuit_drain:
		_gen.set_circuit(circuit_id, true)
	var draw := _gen.drain_per_second(1, false)
	assert_float(draw).is_equal_approx(0.29, 0.0001)
	assert_float(100.0 / draw).is_equal_approx(344.8, 0.1)


func test_later_rounds_strain_the_generator() -> void:
	var round_one := _gen.drain_per_second(1, false)
	assert_float(_gen.drain_per_second(11, false)).is_equal_approx(round_one * 1.3, 0.0001)


func test_a_break_burns_at_half_rate() -> void:
	assert_float(_gen.drain_per_second(1, true)).is_equal_approx(0.045, 0.0001)


func test_ticking_burns_fuel_by_the_draw() -> void:
	_gen.tick(10.0, 1, false)
	assert_float(_gen.fuel).is_equal_approx(99.1, 0.0001)


func test_unknown_circuits_are_refused() -> void:
	assert_bool(_gen.set_circuit(&"nope", true)).is_false()
	assert_bool(_gen.set_circuit(&"booth", true)).is_true()


func test_switching_a_circuit_emits_only_on_a_change() -> void:
	var changes: Array = []
	_gen.circuit_changed.connect(func(id: StringName, on: bool) -> void: changes.append([id, on]))
	_gen.set_circuit(&"booth", true)
	_gen.set_circuit(&"booth", true)
	_gen.set_circuit(&"booth", false)
	assert_array(changes).is_equal([[&"booth", true], [&"booth", false]])


func test_the_low_warning_comes_once_when_the_tank_crosses_a_quarter() -> void:
	_gen.fuel = 26.0
	_gen.tick(20.0, 1, false)  # 26 - 1.8 = 24.2
	_gen.tick(20.0, 1, false)
	assert_array(_events).is_equal([&"low"])


func test_running_dry_darkens_every_circuit_and_stops_the_burn() -> void:
	_gen.fuel = 0.05
	_gen.tick(10.0, 1, false)
	assert_float(_gen.fuel).is_equal(0.0)
	assert_array(_events).contains([&"empty"])
	assert_bool(_gen.is_powered()).is_false()
	assert_bool(_gen.is_lit(&"screen_lot")).is_false()
	assert_float(_gen.drain_per_second(1, false)).is_equal(0.0)
	assert_array(_events.filter(func(e: StringName) -> bool: return e == &"empty")).has_size(1)
	_gen.tick(10.0, 1, false)
	assert_array(_events.filter(func(e: StringName) -> bool: return e == &"empty")).has_size(1)


func test_fuel_brings_the_lights_back() -> void:
	_gen.fuel = 0.05
	_gen.tick(10.0, 1, false)
	assert_float(_gen.add_fuel(25.0)).is_equal(25.0)
	assert_array(_events).contains([&"restored"])
	assert_bool(_gen.is_lit(&"screen_lot")).is_true()


func test_the_tank_cannot_overfill() -> void:
	_gen.fuel = 90.0
	assert_float(_gen.add_fuel(25.0)).is_equal(10.0)
	assert_float(_gen.fuel).is_equal(100.0)
	assert_float(_gen.add_fuel(25.0)).is_equal(0.0)


func test_the_lights_fade_in_the_last_tenth_of_the_tank() -> void:
	assert_float(_gen.power_level()).is_equal(1.0)
	_gen.fuel = 10.0
	assert_float(_gen.power_level()).is_equal(1.0)
	_gen.fuel = 5.0
	assert_float(_gen.power_level()).is_equal_approx(0.5, 0.0001)
	_gen.fuel = 0.0
	assert_float(_gen.power_level()).is_equal(0.0)


func test_the_rules_burn_fuel_in_rounds_and_in_breaks() -> void:
	var rules: GameRules = RulesFixture.make_rules(1)
	rules.apply(RulesAction.start())
	RulesFixture.run(rules, 10.0)  # intro break: 0.045 per second
	assert_float(rules.generator.fuel).is_equal_approx(100.0 - 0.45, 0.01)
	rules.apply(RulesAction.skip_break())
	RulesFixture.run(rules, 10.0)  # round 1: 0.09 per second
	assert_float(rules.generator.fuel).is_equal_approx(100.0 - 0.45 - 0.9, 0.01)


func test_the_rules_relay_the_generators_signals() -> void:
	var rules: GameRules = RulesFixture.make_rules(1)
	var recorder := RulesFixture.record(rules)
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.set_circuit(&"concession", true))
	rules.generator.fuel = 20.0
	RulesFixture.run(rules, 1.0)
	assert_int(recorder.count(&"circuit_changed")).is_equal(1)
	assert_int(recorder.count(&"fuel_low")).is_equal(1)
	assert_int(recorder.count(&"fuel_changed")).is_greater(0)
