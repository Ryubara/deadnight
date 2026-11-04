extends GdUnitTestSuite
## The seconds a look's blow and board-tearing take are read from the roster, as `Night` read
## them before they moved into `LookTimings`.


func _tuning() -> RulesTuning:
	return load(GameRules.DEFAULT_TUNING_PATH)


func test_a_telegraphing_type_gives_each_of_its_looks_its_seconds() -> void:
	var tuning := _tuning()
	var telegraphs := LookTimings.telegraphs(tuning)
	var count := 0
	for type in tuning.roster.types:
		if type.telegraph_seconds > 0.0:
			for look in type.looks:
				assert_float(telegraphs[look]).is_equal(type.telegraph_seconds)
				count += 1
	assert_int(count).is_greater(0)
	assert_int(telegraphs.size()).is_equal(count)


func test_a_board_tearing_type_takes_a_board_in_the_barricades_pace_over_its_speed() -> void:
	var tuning := _tuning()
	var seconds := LookTimings.board_seconds(tuning)
	var count := 0
	for type in tuning.roster.types:
		if type.barrier_speed > 0.0:
			for look in type.looks:
				var wanted := tuning.barricades.seconds_per_board / type.barrier_speed
				assert_float(seconds[look]).is_equal_approx(wanted, 0.0001)
				count += 1
	assert_int(count).is_greater(0)
	assert_int(seconds.size()).is_equal(count)
