# The autopilot run measured from a browser (`?autopilot`, issue #171): the address it reads and
# the numbers it reports.
extends GdUnitTestSuite


func test_the_run_is_asked_for_by_one_word() -> void:
	assert_bool(AutopilotRun.requested(NetArgs.new(PackedStringArray(["--autopilot"])))).is_true()
	assert_bool(AutopilotRun.requested(NetArgs.new(PackedStringArray()))).is_false()


func test_the_night_plays_the_fixed_seed_unless_one_is_asked_for() -> void:
	var plain := NetArgs.new(PackedStringArray(["--autopilot"]))
	var asked := NetArgs.new(PackedStringArray(["--autopilot", "--seed=7"]))
	# A negative seed would be a fresh one at the night screen: a measured run must repeat.
	var negative := NetArgs.new(PackedStringArray(["--seed=-1"]))
	assert_int(AutopilotRun.seed_from(plain)).is_equal(Night.SEED)
	assert_int(AutopilotRun.seed_from(asked)).is_equal(7)
	assert_int(AutopilotRun.seed_from(negative)).is_equal(Night.SEED)


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


## The dailies an account is dealt when the machine's date is `machine_day`, with the bench's clock
## pinned (`pin`) or the machine's left on the accounts.
func _dailies_dealt(machine_day: int, pin: bool) -> Array[StringName]:
	var machine := ChallengeClock.fixed(float(machine_day) * ChallengeClock.DAY_SECONDS + 600.0)
	var xp := XpAward.new([&"fuel_can"], machine)
	var award := ChallengeAward.new(xp, [&"fuel_can"])
	award.catalog = ChallengeCatalog.load_default()
	award.clock = machine
	if pin:
		AutopilotRun.pin_clock(xp, award, AutopilotRun.bench_clock())
	assert_bool(award.seat(1, "bench-1")).is_true()
	award.arrived("bench-1", 404, ChallengeAward.NO_BOARD)
	var ids: Array[StringName] = []
	for daily in award.profile_of("bench-1").dailies:
		ids.append(daily["id"])
	return ids


func test_the_bench_deals_the_same_dailies_on_any_date_of_the_machine() -> void:
	# `challenge.advance` a tick (tools/perf/budget.json) follows which three dailies are dealt:
	# it read 0.13 on 2026-11-06 and 0.23 on 2026-11-07 on one commit (#1372).
	var yesterday := _dailies_dealt(20763, true)
	var today := _dailies_dealt(20764, true)
	var long_ago := _dailies_dealt(20401, true)
	assert_array(yesterday).has_size(3)
	assert_array(today).is_equal(yesterday)
	assert_array(long_ago).is_equal(yesterday)
	# The teeth: left on the machine's clock, the same two dates deal other dailies.
	assert_array(_dailies_dealt(20764, false)).is_not_equal(_dailies_dealt(20763, false))


func test_the_bench_clock_stands_still_on_the_bench_day() -> void:
	var clock := AutopilotRun.bench_clock()
	assert_int(clock.day()).is_equal(AutopilotRun.BENCH_DAY)
	assert_float(clock.local_seconds()).is_equal(clock.local_seconds())
	assert_int(AutopilotRun.bench_clock(20000).day()).is_equal(20000)
