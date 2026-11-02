# The soldier seen from the side while strafing must not step: the body is drawn where the
# engine's physics interpolation puts it, the camera where its own blend puts it, and the two
# agree to a fraction of a pixel at any frame rate (docs/research/physics-interpolation.md).
#
# Each measure runs in a child process (`side_on_probe.tscn`) at a frame rate fixed with
# `--fixed-fps`, so the frames fall over the physics ticks the same way on every machine. In this
# process the frame lengths and the blend fraction come from the real clock: the camera's spring
# lags the body by half a frame, so a loaded machine's uneven frames moved the soldier 3 to 55
# pixels on the screen with nothing wrong in the blend, and a test that waited for calm frames
# failed on a busy one. The two controls prove the measure still sees the faults it exists for.
extends GdUnitTestSuite

const PROBE := "res://tests/player/side_on_probe.tscn"
## The same measure in the real night, under a screen as in the game (issues #344 and #353).
const NIGHT_PROBE := "res://tests/player/night_side_on_probe.tscn"
## Frame rates that are not multiples of the 60 Hz tick (frames per tick: 1.7, 2.4, 2.75), so
## every fraction of a tick is drawn.
const FRAME_RATES: Array[int] = [100, 144, 165]
## The most the soldier may wander on the screen in a window, in pixels of a 1920x1080 view (the
## engine's own blend adds up to half a pixel at the tick where a frame crosses it; measured
## 0.0001 to 0.002).
const MAX_WANDER := 2.0
## The least the faults must show, so the measure is known to see them (measured: a body drawn at
## its tick 38 to 44 pixels, a rig blended twice 10 to 11).
const MIN_FAULT_WANDER := 5.0
## The most the soldier's path may be uneven in the real night: the RMS of the second difference
## of its screen x, in pixels of a 1920x1080 view (measured 0.07 to 0.19; drawn at the last tick
## 41 to 44).
const MAX_NIGHT_UNEVEN := 1.0
const MIN_NIGHT_FAULT_UNEVEN := 10.0


## Runs the probe at `fps` in `mode` and returns the pixels the soldier wandered.
func _wander(fps: int, mode: String) -> float:
	var output: Array = []
	var arguments := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--fixed-fps",
			str(fps),
			PROBE,
			"--",
			"--mode=" + mode,
		]
	)
	OS.execute(OS.get_executable_path(), arguments, output, true)
	var text := "\n".join(PackedStringArray(output))
	var pattern := RegEx.create_from_string("WANDER (-?[0-9.]+) FRAMES ([0-9]+) TICKS ([0-9]+)")
	var found := pattern.search(text)
	(
		assert_object(found)
		. override_failure_message("the probe printed no result:\n" + text)
		. is_not_null()
	)
	if found == null:
		return INF
	# The measure only means something with a full stretch of frames over the ticks.
	assert_int(int(found.get_string(3))).is_equal(60)
	assert_float(float(found.get_string(2))).is_greater(float(found.get_string(3)) * 1.5)
	return float(found.get_string(1))


func test_the_soldier_holds_still_on_the_screen_while_strafing_at_any_frame_rate() -> void:
	for fps in FRAME_RATES:
		assert_float(_wander(fps, "blended")).override_failure_message("at %d fps" % fps).is_less(
			MAX_WANDER
		)


func test_a_body_drawn_at_its_last_tick_wanders_on_the_screen() -> void:
	for fps in FRAME_RATES:
		(
			assert_float(_wander(fps, "body-still"))
			. override_failure_message("at %d fps" % fps)
			. is_greater(MIN_FAULT_WANDER)
		)


func test_a_rig_the_engine_blends_a_second_time_wanders_on_the_screen() -> void:
	for fps in FRAME_RATES:
		(
			assert_float(_wander(fps, "rig-engine"))
			. override_failure_message("at %d fps" % fps)
			. is_greater(MIN_FAULT_WANDER)
		)


func test_second_differences_of_a_steady_series_are_zero_and_of_a_sawtooth_are_not() -> void:
	var steady := PackedFloat64Array([0.0, 2.0, 4.0, 6.0, 8.0])
	assert_float(FrameJudder.peak(FrameJudder.second_differences(steady))).is_equal(0.0)
	var steps := PackedFloat64Array([0.0, 10.0, 10.0, 20.0, 20.0, 30.0])
	assert_float(FrameJudder.peak(FrameJudder.second_differences(steps))).is_equal(10.0)
	assert_float(FrameJudder.peak_to_peak(steps)).is_equal(30.0)


## Runs the real-night probe at `fps` in `mode` and returns the RMS second difference of the
## soldier's screen x, in pixels.
func _night_unevenness(fps: int, mode: String) -> float:
	var output: Array = []
	var arguments := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--fixed-fps",
			str(fps),
			NIGHT_PROBE,
			"--",
			"--mode=" + mode,
		]
	)
	OS.execute(OS.get_executable_path(), arguments, output, true)
	var text := "\n".join(PackedStringArray(output))
	var found := RegEx.create_from_string("UNEVEN (-?[0-9.]+)").search(text)
	(
		assert_object(found)
		. override_failure_message("the night probe printed no result:\n" + text)
		. is_not_null()
	)
	return float(found.get_string(1)) if found != null else INF


func test_the_soldier_is_even_on_the_screen_in_the_real_night_at_any_frame_rate() -> void:
	for fps in FRAME_RATES:
		(
			assert_float(_night_unevenness(fps, "shipped"))
			. override_failure_message("at %d fps" % fps)
			. is_less(MAX_NIGHT_UNEVEN)
		)


func test_a_night_that_leaves_interpolation_to_its_screen_steps_on_the_screen() -> void:
	assert_float(_night_unevenness(144, "inherit")).is_greater(MIN_NIGHT_FAULT_UNEVEN)
