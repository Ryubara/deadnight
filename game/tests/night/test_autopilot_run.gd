# The autopilot run measured from a browser (`?autopilot`, issue #171): the address it reads and
# the numbers it reports.
extends GdUnitTestSuite


func test_the_run_is_asked_for_by_one_word() -> void:
	assert_bool(AutopilotRun.requested(NetArgs.new(PackedStringArray(["--autopilot"])))).is_true()
	assert_bool(AutopilotRun.requested(NetArgs.new(PackedStringArray()))).is_false()


func test_the_arguments_become_match_settings_inside_their_bounds() -> void:
	var asked := NetArgs.new(
		PackedStringArray(["--autopilot", "--count=3", "--alive=24", "--break=5"])
	)
	var settings := AutopilotRun.settings_from(asked)
	assert_float(settings.count_multiplier).is_equal(3.0)
	assert_int(settings.max_alive).is_equal(24)
	assert_float(settings.break_seconds).is_equal(5.0)
	# What no one may ask for is pulled in: the ceiling of the crowd, the most of the multiplier.
	var wild := AutopilotRun.settings_from(
		NetArgs.new(PackedStringArray(["--count=999", "--alive=99999"]))
	)
	assert_float(wild.count_multiplier).is_less_equal(5.0)
	assert_int(wild.max_alive).is_less_equal(RoundTuning.new().alive_cap_ceiling)


func test_the_player_cannot_die_and_the_rest_of_the_rules_are_the_shipped_ones() -> void:
	var rules := AutopilotRun.tuning()
	var shipped: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH)
	assert_float(rules.health.max_health).is_greater(1000.0)
	assert_float(rules.rounds.count_base).is_equal(shipped.rounds.count_base)
	assert_float(shipped.health.max_health).is_less(1000.0)


func test_rounds_are_reported_in_order_with_their_percentiles() -> void:
	var rows: Array = []
	# Round 1: 100 frames of 10 ms; round 2: 90 of 10 ms and 10 of 50 ms (a crowd that hitches).
	for i in 100:
		rows.append([10.0, 1, 5])
	for i in 90:
		rows.append([10.0, 2, 20 + i % 5])
	for i in 10:
		rows.append([50.0, 2, 24])
	var report := AutopilotRun.summarize(rows)
	assert_int(report.size()).is_equal(2)
	assert_int(report[0]["round"]).is_equal(1)
	assert_float(report[0]["p95_ms"]).is_equal(10.0)
	assert_int(report[0]["alive_peak"]).is_equal(5)
	assert_float(report[1]["max_ms"]).is_equal(50.0)
	assert_float(report[1]["p50_ms"]).is_equal(10.0)
	assert_int(report[1]["frames_over_33ms"]).is_equal(10)
	assert_int(report[1]["alive_peak"]).is_equal(24)
	assert_float(report[1]["mean_ms"]).is_equal(14.0)


func test_the_dead_can_be_made_too_tough_to_clear_so_the_crowd_grows() -> void:
	var shipped: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH)
	var tough := AutopilotRun.tuning(NetArgs.new(PackedStringArray(["--tough=30"])))
	assert_float(tough.rounds.health_base).is_equal_approx(shipped.rounds.health_base * 30.0, 0.01)
	assert_float(AutopilotRun.tuning().rounds.health_base).is_equal(shipped.rounds.health_base)
	var crowd := AutopilotRun.tuning(NetArgs.new(PackedStringArray(["--crowd=60"])))
	assert_float(crowd.rounds.count_base).is_equal(60.0)
	assert_float(AutopilotRun.tuning(NetArgs.new()).rounds.count_base).is_equal(
		shipped.rounds.count_base
	)


func test_frames_are_also_reported_by_the_crowd_on_the_lot() -> void:
	var rows: Array = []
	for i in 50:
		rows.append([8.0, 1, 3])
	for i in 50:
		rows.append([12.0, 1, 25])
	for i in 50:
		rows.append([20.0, 2, 44])
	var report := AutopilotRun.summarize_by_alive(rows)
	assert_int(report.size()).is_equal(3)
	assert_int(report[0]["alive_from"]).is_equal(0)
	assert_float(report[0]["p50_ms"]).is_equal(8.0)
	assert_int(report[1]["alive_from"]).is_equal(20)
	assert_int(report[1]["alive_peak"]).is_equal(25)
	assert_int(report[2]["alive_from"]).is_equal(40)
	assert_float(report[2]["max_ms"]).is_equal(20.0)


func test_the_worst_second_is_the_slowest_run_of_a_second_of_frames() -> void:
	var frames: Array[float] = []
	# A second of 10 ms frames (100), then a second of 25 ms frames (40), then a second of 10 ms.
	for i in 100:
		frames.append(10.0)
	for i in 40:
		frames.append(25.0)
	for i in 100:
		frames.append(10.0)
	assert_float(AutopilotRun.worst_second(frames)).is_equal(25.0)
	# A round shorter than a second is one run.
	assert_float(AutopilotRun.worst_second([8.0, 12.0] as Array[float])).is_equal(10.0)
	assert_float(AutopilotRun.worst_second([] as Array[float])).is_equal(0.0)


func test_a_late_round_with_bots_is_asked_for_by_arguments() -> void:
	var asked := NetArgs.new(
		PackedStringArray(["--autopilot", "--bots=3", "--startround=12", "--ceiling=desktop"])
	)
	var settings := AutopilotRun.settings_from(asked)
	assert_int(settings.bots).is_equal(3)
	assert_int(AutopilotRun.settings_from(NetArgs.new(PackedStringArray())).bots).is_equal(0)
