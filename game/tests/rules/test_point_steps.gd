extends GdUnitTestSuite
## The rounding rule of points (`PointSteps`, Deadnight #916): awards to the nearest 5 and never
## below 5, prices up to the next 5, losses down to 5. And every number the tuning holds sits on
## the step already, so the rule only acts on what a multiplier made.


func test_an_award_rounds_to_the_nearest_five_and_never_below_one_step() -> void:
	assert_int(PointSteps.award(4.0)).is_equal(5)
	assert_int(PointSteps.award(1.0)).is_equal(5)
	assert_int(PointSteps.award(0.4)).is_equal(5)
	assert_int(PointSteps.award(7.4)).is_equal(5)
	assert_int(PointSteps.award(7.5)).is_equal(10)
	assert_int(PointSteps.award(72.0)).is_equal(70)
	assert_int(PointSteps.award(84.0)).is_equal(85)
	assert_int(PointSteps.award(156.0)).is_equal(155)
	assert_int(PointSteps.award(130.0)).is_equal(130)
	assert_int(PointSteps.award(0.0)).is_equal(0)
	assert_int(PointSteps.award(-3.0)).is_equal(0)


func test_a_price_rounds_up_so_a_part_purchase_never_costs_less_than_its_share() -> void:
	assert_int(PointSteps.price(1.0)).is_equal(5)
	assert_int(PointSteps.price(5.0)).is_equal(5)
	assert_int(PointSteps.price(5.01)).is_equal(10)
	assert_int(PointSteps.price(90.0 * 7.0 / 20.0)).is_equal(35)
	assert_int(PointSteps.price(1500.0)).is_equal(1500)
	assert_int(PointSteps.price(0.0)).is_equal(0)


func test_a_float_that_is_a_step_up_to_noise_is_not_pushed_a_step_further() -> void:
	assert_int(PointSteps.price(15.000000001)).is_equal(15)
	assert_int(PointSteps.loss(14.999999999)).is_equal(15)


func test_a_loss_rounds_down_and_may_be_nothing() -> void:
	assert_int(PointSteps.loss(4.5)).is_equal(0)
	assert_int(PointSteps.loss(9.9)).is_equal(5)
	assert_int(PointSteps.loss(125.5)).is_equal(125)
	assert_int(PointSteps.loss(0.0)).is_equal(0)


func test_every_number_in_the_shipped_tuning_is_a_multiple_of_five() -> void:
	var failures: Array[String] = []
	for tuning in _tunings():
		var economy := tuning.economy
		for field in [
			"start_points",
			"hit",
			"headshot_hit",
			"kill",
			"headshot_kill",
			"melee_kill",
			"repair",
			"repair_cap_per_round",
			"round_bonus_base",
			"round_bonus_per_round"
		]:
			if not PointSteps.is_step(int(economy.get(field))):
				failures.append("economy.%s = %d" % [field, economy.get(field)])
		if not PointSteps.is_step(tuning.explosives.explosion_kill):
			failures.append("explosives.explosion_kill")
		if not PointSteps.is_step(tuning.revive.reviver_points):
			failures.append("revive.reviver_points")
		for special in tuning.specials.rounds:
			for round_number in range(1, 41):
				if not PointSteps.is_step(special.reward_at(round_number)):
					failures.append("%s reward at %d" % [special.id, round_number])
		for item in economy.items:
			if not PointSteps.is_step(item.price) or not PointSteps.is_step(item.price_per_round):
				failures.append(
					"item %s price %d + %d" % [item.id, item.price, item.price_per_round]
				)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_every_price_at_every_round_and_every_part_is_a_multiple_of_five() -> void:
	var failures: Array[String] = []
	for tuning in _tunings():
		for item in tuning.economy.items:
			for round_number in range(1, 41):
				var whole := item.price_at(round_number)
				if not PointSteps.is_step(whole):
					failures.append("%s at round %d costs %d" % [item.id, round_number, whole])
				if item.amount > 0.0:
					for part in range(1, int(item.amount) + 1):
						var cost := item.part_price(round_number, part)
						if not PointSteps.is_step(cost) or cost < PointSteps.STEP:
							failures.append(
								"%s at %d, part %d: %d" % [item.id, round_number, part, cost]
							)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_every_type_pays_in_fives_whatever_its_multiplier() -> void:
	var failures: Array[String] = []
	for tuning in _tunings():
		var rules := GameRules.new(tuning, 1)
		for type: ZombieType in tuning.roster.types:
			for base in [
				tuning.economy.hit,
				tuning.economy.headshot_hit,
				tuning.economy.kill,
				tuning.economy.headshot_kill,
				tuning.economy.melee_kill,
				tuning.explosives.explosion_kill
			]:
				var pay := rules._scaled(base, type)
				if not PointSteps.is_step(pay) or pay < PointSteps.STEP:
					failures.append(
						"%s: %d x %s = %d" % [type.id, base, type.points_multiplier, pay]
					)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func _tunings() -> Array[RulesTuning]:
	var out: Array[RulesTuning] = [RulesFixture.tuning()]
	var overlay := load("res://world/smallmap/smallmap_tuning.tres") as MapTuning
	out.append(overlay.apply(RulesFixture.tuning()))
	return out
