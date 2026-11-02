# What a client does with the ticks around a freeze of its own loop (#483): the first one resyncs,
# the ones the engine runs to catch up are skipped, then play goes on as before.
extends GdUnitTestSuite

const TICK_MS := 16.7


func _run_ticks(guard: StallGuard, from_ms: float, count: int) -> float:
	var at := from_ms
	for _i in count:
		at += TICK_MS
		assert_int(guard.check(at)).is_equal(StallGuard.Verdict.RUN)
	return at


func test_a_steady_loop_is_never_stopped() -> void:
	var guard := StallGuard.new()
	_run_ticks(guard, 0.0, 600)
	assert_int(guard.stalls).is_equal(0)
	assert_int(guard.skipped).is_equal(0)


func test_a_slow_frame_that_is_not_a_freeze_is_run_as_it_comes() -> void:
	var guard := StallGuard.new()
	var at := _run_ticks(guard, 0.0, 10)
	# A 30 fps client runs two ticks a frame: 33 ms, then 0.5 ms.
	for _i in 20:
		at += 33.0
		assert_int(guard.check(at)).is_equal(StallGuard.Verdict.RUN)
		assert_int(guard.check(at + 0.5)).is_equal(StallGuard.Verdict.RUN)
		at += 0.5
	assert_int(guard.stalls).is_equal(0)


func test_after_a_freeze_the_first_tick_resyncs_and_the_catch_up_ticks_are_skipped() -> void:
	for freeze_ms in [300.0, 500.0, 2000.0, 5000.0]:
		var guard := StallGuard.new()
		var at := _run_ticks(guard, 0.0, 10)
		at += freeze_ms
		assert_int(guard.check(at)).is_equal(StallGuard.Verdict.RESYNC)
		for i in 7:
			assert_int(guard.check(at + 0.2 * (i + 1))).is_equal(StallGuard.Verdict.SKIP)
		at += 20.0
		assert_int(guard.check(at)).is_equal(StallGuard.Verdict.RUN)
		_run_ticks(guard, at, 30)
		assert_int(guard.stalls).is_equal(1)
		assert_int(guard.skipped).is_equal(7)
		assert_float(guard.longest_ms).is_greater_equal(freeze_ms)
