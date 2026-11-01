extends GdUnitTestSuite
## `fuel_changed` is announced per whole unit, not per tick; the thresholds are not throttled.


func test_ten_seconds_of_ticks_announce_a_handful_of_fuel_changes() -> void:
	var rules := RulesFixture.make_rules(1)
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 10.0)
	# 0.09 a second burns under one unit in ten seconds: at most one announcement.
	assert_int(log.count(&"fuel_changed")).is_less_equal(1)


func test_an_announcement_carries_the_exact_fuel_and_a_whole_unit_delta() -> void:
	var rules := RulesFixture.make_rules(1)
	rules.apply(RulesAction.set_circuit(&"booth", true))
	rules.apply(RulesAction.set_circuit(&"concession", true))
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 12.0)
	var changes := log.of(&"fuel_changed")
	assert_int(changes.size()).is_between(1, 4)
	assert_float(changes.back()["fuel"]).is_not_equal(floorf(changes.back()["fuel"]))
	for change in changes:
		assert_float(change["delta"]).is_equal(-1.0)
	assert_int(floori(changes.back()["fuel"])).is_equal(100 - changes.size())


func test_a_long_run_announces_about_once_per_unit_burnt() -> void:
	var rules := RulesFixture.make_rules(1)
	rules.apply(RulesAction.set_circuit(&"booth", true))
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	var start := rules.generator.fuel
	RulesFixture.run(rules, 120.0)
	var burnt := start - rules.generator.fuel
	assert_int(log.count(&"fuel_changed")).is_between(floori(burnt), ceili(burnt) + 1)


func test_buying_fuel_is_announced_once() -> void:
	var rules := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(rules)
	rules.generator.fuel = 50.0
	rules.apply(RulesAction.tick(RulesFixture.STEP))
	rules.apply(RulesAction.grant_points(1, 1000))
	var log := RulesFixture.record(rules)
	RulesFixture.buy(rules, 1, &"fuel_can")
	assert_int(log.count(&"fuel_changed")).is_equal(1)
	assert_float(log.of(&"fuel_changed")[0]["fuel"]).is_greater(74.9)


func test_low_empty_and_restored_still_fire_when_fuel_crosses_them() -> void:
	var rules := RulesFixture.make_rules(1)
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	rules.generator.fuel = 25.01
	rules.apply(RulesAction.tick(RulesFixture.STEP))
	var ticks := 0
	while log.count(&"fuel_low") == 0 and ticks < 1000:
		rules.apply(RulesAction.tick(RulesFixture.STEP))
		ticks += 1
	assert_int(log.count(&"fuel_low")).is_equal(1)
	assert_float(rules.generator.fuel).is_less_equal(25.0)
	assert_float(rules.generator.fuel).is_greater(24.99)
	rules.generator.fuel = 0.05
	RulesFixture.run(rules, 2.0)
	assert_int(log.count(&"fuel_empty")).is_equal(1)
	RulesFixture.buy(rules, 1, &"fuel_can")
	assert_int(log.count(&"fuel_restored")).is_equal(1)


func test_a_restored_copy_does_not_repeat_the_last_announcement() -> void:
	var original := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(original)
	original.generator.fuel = 40.4
	var copy := GameRules.new(RulesFixture.tuning(), 1)
	assert_str(copy.from_bytes(original.to_bytes())).is_equal("")
	var log := RulesFixture.record(copy)
	RulesFixture.run(copy, 1.0)
	assert_int(log.count(&"fuel_changed")).is_equal(0)
