extends GdUnitTestSuite
## Switching the generator's circuits through the rules, the way the night's breaker posts do:
## what a switch costs in fuel, what it announces, what it refuses, and that the answer is the same
## on every run.

## Seconds of round 1 each cost is measured over.
const SPAN := 100.0


func _round_one() -> GameRules:
	var rules := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(rules)
	return rules


## Fuel the tank loses over `SPAN` seconds of round 1 with `circuit_id` set as given.
func _burn_with(circuit_id: StringName, on: bool) -> float:
	var rules := _round_one()
	rules.apply(RulesAction.set_circuit(circuit_id, on))
	var before := rules.generator.fuel
	RulesFixture.run(rules, SPAN)
	return before - rules.generator.fuel


func test_every_circuit_costs_fuel_while_it_is_on() -> void:
	var fuel: FuelTuning = RulesFixture.tuning().fuel
	var base := _burn_with(&"screen_lot", true)
	for circuit_id: StringName in fuel.circuit_drain:
		if circuit_id == &"screen_lot":
			continue
		var extra := _burn_with(circuit_id, true) - base
		# The strain of round 1 is nil, so the cost is the circuit's draw over the span.
		assert_float(extra).is_equal_approx(fuel.circuit_drain[circuit_id] * SPAN, 0.05)
		assert_float(extra).is_greater(0.0)


func test_switching_a_circuit_off_saves_its_fuel() -> void:
	var fuel: FuelTuning = RulesFixture.tuning().fuel
	var lit := _burn_with(&"screen_lot", true)
	var dark := _burn_with(&"screen_lot", false)
	assert_float(lit - dark).is_equal_approx(fuel.circuit_drain[&"screen_lot"] * SPAN, 0.05)


func test_a_switch_announces_itself_once_and_only_when_it_changes_something() -> void:
	var rules := _round_one()
	var recorder := RulesFixture.record(rules)
	rules.apply(RulesAction.set_circuit(&"concession", true))
	rules.apply(RulesAction.set_circuit(&"concession", true))
	rules.apply(RulesAction.set_circuit(&"concession", false))
	var changes := recorder.of(&"circuit_changed")
	assert_int(changes.size()).is_equal(2)
	assert_str(changes[0]["circuit_id"]).is_equal("concession")
	assert_bool(changes[0]["on"]).is_true()
	assert_bool(changes[1]["on"]).is_false()
	assert_int(recorder.count(&"action_rejected")).is_equal(0)


func test_a_circuit_that_is_not_there_is_refused_and_changes_nothing() -> void:
	var rules := _round_one()
	var recorder := RulesFixture.record(rules)
	var before := rules.generator.circuits.duplicate()
	rules.apply(RulesAction.set_circuit(&"mains", true))
	rules.apply(RulesAction.set_circuit(&"nope", true))
	assert_int(recorder.count(&"action_rejected")).is_equal(2)
	assert_str(recorder.of(&"action_rejected")[0]["reason"]).is_equal("unknown_circuit")
	assert_int(recorder.count(&"circuit_changed")).is_equal(0)
	assert_dict(rules.generator.circuits).is_equal(before)


func test_a_circuit_can_be_switched_with_the_tank_dry_and_lights_when_fuel_comes() -> void:
	var rules := _round_one()
	rules.generator.fuel = 0.0
	rules.apply(RulesAction.set_circuit(&"concession", true))
	assert_bool(rules.generator.circuits[&"concession"]).is_true()
	assert_bool(rules.generator.is_lit(&"concession")).is_false()
	rules.generator.add_fuel(20.0)
	assert_bool(rules.generator.is_lit(&"concession")).is_true()


func test_switches_survive_a_snapshot() -> void:
	var rules := _round_one()
	rules.apply(RulesAction.set_circuit(&"booth", true))
	rules.apply(RulesAction.set_circuit(&"screen_lot", false))
	var copy := RulesFixture.make_rules(1)
	assert_str(copy.from_dict(rules.to_dict())).is_equal("")
	assert_dict(copy.generator.circuits).is_equal(rules.generator.circuits)


func test_the_same_switching_burns_the_same_fuel_every_time() -> void:
	var fuels: Array[float] = []
	for _run in 2:
		var rules := _round_one()
		rules.apply(RulesAction.set_circuit(&"concession", true))
		RulesFixture.run(rules, 30.0)
		rules.apply(RulesAction.set_circuit(&"booth", true))
		rules.apply(RulesAction.set_circuit(&"concession", false))
		RulesFixture.run(rules, 30.0)
		fuels.append(rules.generator.fuel)
	assert_float(fuels[0]).is_equal(fuels[1])
