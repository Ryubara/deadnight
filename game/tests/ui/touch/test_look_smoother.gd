# The look smoother (#598): a finger's samples, arriving at the touch screen's rate, turn the view
# evenly in frames drawn at another rate. The shapes here are the ones measured in the web build:
# a 175 Hz page against a 60 Hz finger (2 of 3 frames turned nothing), and a 40 Hz page against a
# 120 Hz finger (2 samples in one frame, 3 in the next).
extends GdUnitTestSuite

const SAMPLE_PX := 1.0
## The first and last stretch of a drag are the view settling in and out.
const TRIM_S := 0.3


## Runs a steady drag: a sample of `SAMPLE_PX` every `sample_s`, a frame every `frame_s` (plus
## `wobble_s` either way on alternate frames, as a page that is not quite regular). Returns
## `{"steps": Array[float], "dts": Array[float]}`, per frame, without the first and last `TRIM_S`.
func _drag(smoother: LookSmoother, sample_s: float, frame_s: float, wobble_s := 0.0) -> Dictionary:
	var steps: Array[float] = []
	var dts: Array[float] = []
	var clock := 0.0
	var next_sample := sample_s
	var frame := 0
	var length := 2.4
	while clock < length:
		var dt := frame_s + (wobble_s if frame % 2 == 0 else -wobble_s)
		clock += dt
		frame += 1
		while next_sample <= clock:
			smoother.add(Vector2(SAMPLE_PX, 0.0))
			next_sample += sample_s
		var out := smoother.step(dt)
		if clock >= TRIM_S and clock <= length - TRIM_S:
			steps.append(out.x)
			dts.append(dt)
	return {"steps": steps, "dts": dts}


func _rates(drag: Dictionary) -> Array[float]:
	var rates: Array[float] = []
	for i in drag["steps"].size():
		rates.append(drag["steps"][i] / drag["dts"][i])
	return rates


## The standard deviation of the values over their mean.
func _cv(values: Array[float]) -> float:
	var mean := 0.0
	for value in values:
		mean += value
	mean /= values.size()
	var variance := 0.0
	for value in values:
		variance += (value - mean) * (value - mean)
	return sqrt(variance / values.size()) / absf(mean)


func _zero_frames(steps: Array[float]) -> int:
	return steps.filter(func(step: float) -> bool: return step <= 0.0).size()


func _back_steps(steps: Array[float]) -> int:
	return steps.filter(func(step: float) -> bool: return step < 0.0).size()


func _smoother(time_constant := TouchTuning.shipped().look_smoothing) -> LookSmoother:
	var smoother := LookSmoother.new()
	smoother.time_constant = time_constant
	return smoother


func test_everything_the_finger_made_turns_the_view_in_the_end() -> void:
	var smoother := _smoother()
	smoother.add(Vector2(10.0, -4.0))
	smoother.add(Vector2(2.5, 1.0))
	var total := Vector2.ZERO
	for frame in 400:
		total += smoother.step(1.0 / 120.0)
	assert_vector(total).is_equal_approx(Vector2(12.5, -3.0), Vector2(0.001, 0.001))
	assert_bool(smoother.is_idle()).is_true()


func test_a_page_drawn_faster_than_the_finger_turns_the_view_in_every_frame() -> void:
	# 175 Hz page, 60 Hz finger: until now 2 of 3 frames turned nothing, the third all of it.
	var drag := _drag(_smoother(), 1.0 / 60.0, 1.0 / 175.0)
	assert_int(_zero_frames(drag["steps"])).is_equal(0)
	assert_int(_back_steps(drag["steps"])).is_equal(0)
	assert_float(_cv(drag["steps"])).is_less(0.15)


func test_a_page_drawn_slower_than_the_finger_turns_the_view_evenly() -> void:
	# 120 Hz finger, a page at about 40 Hz that is not quite regular: 2 samples in a frame, then 3.
	var drag := _drag(_smoother(), 1.0 / 120.0, 0.025, 0.004)
	assert_int(_zero_frames(drag["steps"])).is_equal(0)
	assert_int(_back_steps(drag["steps"])).is_equal(0)
	assert_float(_cv(_rates(drag))).is_less(0.15)


func test_a_slow_irregular_page_still_turns_evenly() -> void:
	# A phone's browser at about 30 fps, its frames 21 or 45 ms: 3 or 5 samples of a 120 Hz finger in
	# each. The window grows with the frames (`look_smoothing_frames`) or the ripple stays.
	var drag := _drag(_smoother(), 1.0 / 120.0, 0.033, 0.012)
	assert_int(_zero_frames(drag["steps"])).is_equal(0)
	assert_float(_cv(_rates(drag))).is_less(0.25)
	var short_window := _smoother()
	short_window.frames = 1.0
	assert_float(_cv(_rates(_drag(short_window, 1.0 / 120.0, 0.033, 0.012)))).is_greater(
		_cv(_rates(drag))
	)


func test_without_the_smoothing_the_same_drags_were_uneven() -> void:
	# What the smoothing replaces, so the two tests above cannot pass by accident.
	var fast_page := _drag(_smoother(0.0), 1.0 / 60.0, 1.0 / 175.0)
	assert_int(_zero_frames(fast_page["steps"])).is_greater(100)
	assert_float(_cv(fast_page["steps"])).is_greater(1.0)
	var slow_page := _drag(_smoother(0.0), 1.0 / 120.0, 0.025, 0.004)
	assert_float(_cv(_rates(slow_page))).is_greater(0.1)


func test_a_step_is_mostly_turned_within_a_tenth_of_a_second() -> void:
	var smoother := _smoother()
	smoother.add(Vector2(20.0, 0.0))
	var turned := 0.0
	for frame in 6:
		turned += smoother.step(1.0 / 60.0).x
	assert_float(turned).is_greater(20.0 * 0.85)


func test_a_time_constant_of_zero_turns_the_view_at_once() -> void:
	var smoother := _smoother(0.0)
	smoother.add(Vector2(7.0, 3.0))
	assert_vector(smoother.step(1.0 / 60.0)).is_equal(Vector2(7.0, 3.0))
	assert_bool(smoother.is_idle()).is_true()


func test_a_long_frame_does_not_turn_more_than_was_made() -> void:
	var smoother := _smoother()
	smoother.add(Vector2(5.0, 0.0))
	var out := smoother.step(2.0)
	assert_float(out.x).is_between(4.99, 5.0)
