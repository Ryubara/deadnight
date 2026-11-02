# The stuck detector and its ladder (bots plan, phase 2) on synthetic position traces: a bot that
# walks is never stuck, one that is commanded to walk and goes nowhere is stuck after half a second
# and climbs a rung every second and a half, to a report on the sixth, and nothing here depends on
# a clock: a trace is a list of (step, speed, progress) samples.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0
const RUN := 4.8


## Feeds `seconds` of a bot that walks at `speed` and gains `gain` metres a second.
func _feed(stuck: BotStuck, seconds: float, speed: float, gain: float) -> void:
	for _i in roundi(seconds / STEP):
		stuck.feed(STEP, speed, gain * STEP)


func test_a_bot_that_makes_progress_is_never_stuck() -> void:
	var stuck := BotStuck.new()
	_feed(stuck, 20.0, RUN, RUN)
	assert_bool(stuck.stuck).is_false()
	assert_int(stuck.rung).is_equal(0)
	assert_float(stuck.stuck_seconds).is_equal(0.0)
	assert_float(stuck.walking_seconds).is_equal_approx(20.0, 0.02)


func test_a_slow_walk_over_the_threshold_is_not_stuck() -> void:
	var stuck := BotStuck.new()
	_feed(stuck, 10.0, RUN, BotStuck.MIN_PROGRESS * 1.2)
	assert_bool(stuck.stuck).is_false()
	_feed(stuck, 10.0, RUN, BotStuck.MIN_PROGRESS * 0.8)
	assert_bool(stuck.stuck).is_true()


func test_a_bot_that_stands_is_not_stuck_however_long() -> void:
	var stuck := BotStuck.new()
	_feed(stuck, 30.0, 0.0, 0.0)
	assert_bool(stuck.stuck).is_false()
	assert_float(stuck.walking_seconds).is_equal(0.0)
	# Nor one commanded to walk slower than the threshold speed (a nudge of the stick).
	_feed(stuck, 30.0, BotStuck.MIN_SPEED * 0.5, 0.0)
	assert_bool(stuck.stuck).is_false()


func test_a_bot_pressed_against_a_wall_is_stuck_after_half_a_second() -> void:
	var stuck := BotStuck.new()
	_feed(stuck, 0.45, RUN, 0.0)
	assert_bool(stuck.stuck).is_false()
	_feed(stuck, 0.1, RUN, 0.0)
	assert_bool(stuck.stuck).is_true()
	assert_int(stuck.rung).is_equal(1)
	assert_int(stuck.episodes).is_equal(1)


func test_the_ladder_climbs_a_rung_every_second_and_a_half_to_the_report() -> void:
	var stuck := BotStuck.new()
	var reached: Array[int] = []
	var reported_at := -1.0
	var clock := 0.0
	for _i in roundi(14.0 / STEP):
		clock += STEP
		stuck.feed(STEP, RUN, 0.0)
		if reached.is_empty() or reached.back() != stuck.rung:
			reached.append(stuck.rung)
		if stuck.report_due and reported_at < 0.0:
			reported_at = clock
	# Detected at 0.5 s, then a rung each 1.5 s: the sixth at 0.5 + 5 * 1.5 = 8 s. Then it starts
	# again from the first rung (the bot is still stuck), and never leaves the ladder.
	assert_array(reached.slice(0, 7)).is_equal([0, 1, 2, 3, 4, 5, 6])
	assert_float(reported_at).is_equal_approx(8.0, 0.12)
	assert_int(stuck.depth_max).is_equal(6)
	assert_int(reached[7]).is_equal(1)


func test_moving_again_ends_the_episode_and_remembers_its_length() -> void:
	var stuck := BotStuck.new()
	_feed(stuck, 3.0, RUN, 0.0)
	assert_bool(stuck.stuck).is_true()
	_feed(stuck, 1.0, RUN, RUN)
	assert_bool(stuck.stuck).is_false()
	assert_int(stuck.rung).is_equal(0)
	assert_float(stuck.longest_episode).is_between(3.0, 3.6)
	assert_float(stuck.stuck_seconds).is_between(3.0, 3.6)
	assert_bool(stuck.report_due).is_false()


func test_stopping_on_purpose_ends_the_episode_too() -> void:
	var stuck := BotStuck.new()
	_feed(stuck, 2.0, RUN, 0.0)
	assert_bool(stuck.stuck).is_true()
	# The ladder dropped the goal: the bot is commanded nothing.
	_feed(stuck, 0.1, 0.0, 0.0)
	assert_bool(stuck.stuck).is_false()
	assert_float(stuck.longest()).is_between(2.0, 2.6)


func test_a_trace_that_creeps_and_stalls_counts_only_the_stalls() -> void:
	var stuck := BotStuck.new()
	# One second of progress, one second against a corner, repeated: a second in two is stuck (the
	# half second it takes to notice counted, and the metre it must gain to be called free).
	for _i in 5:
		_feed(stuck, 1.0, RUN, RUN)
		_feed(stuck, 1.0, RUN, 0.0)
	assert_float(stuck.walking_seconds).is_equal_approx(10.0, 0.05)
	assert_float(stuck.stuck_seconds).is_between(4.0, 6.5)
	assert_float(stuck.longest()).is_less(1.8)
	assert_int(stuck.depth_max).is_less_equal(1)


func test_progress_measured_over_a_window_not_a_tick() -> void:
	var stuck := BotStuck.new()
	# A bot that moves in jerks (a tick of 0.2 m, then 9 ticks of nothing) averages 1.2 m/s.
	for _i in 120:
		stuck.feed(STEP, RUN, 0.2)
		for _j in 9:
			stuck.feed(STEP, RUN, 0.0)
	assert_bool(stuck.stuck).is_false()


func test_a_bot_that_shuffles_back_and_forth_along_a_wall_stays_stuck() -> void:
	var stuck := BotStuck.new()
	# Half a second one way (2 m a second of progress), half a second back (the same lost): every
	# window of half a second looks like progress or like loss, never like getting anywhere.
	for _i in 12:
		_feed(stuck, 0.5, RUN, 2.0)
		_feed(stuck, 0.5, RUN, -2.0)
	assert_bool(stuck.stuck).is_true()
	assert_int(stuck.depth_max).is_greater_equal(4)
	# Then it gets free: a metre and more of real progress ends the episode.
	_feed(stuck, 1.0, RUN, RUN)
	assert_bool(stuck.stuck).is_false()
