extends GdUnitTestSuite
## The helicopter drop as a function of time (#1057, `ArrivalPlan`): black at both ends, the
## helicopter
## coming in and over the spot, the rope paying out, the Soldier reaching the ground before the
## fade,
## and no fly-in for a late join. The plan is pure: asking twice is asking once.

var _t: ArrivalTuning


func before_test() -> void:
	_t = (load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).arrival.duplicate() as ArrivalTuning


func test_the_show_is_the_tunings_length() -> void:
	assert_float(ArrivalPlan.new(_t, true).seconds()).is_equal(_t.night_seconds)
	assert_float(ArrivalPlan.new(_t, false).seconds()).is_equal(_t.late_seconds)
	assert_float(_t.late_seconds).is_less(_t.night_seconds)


func test_the_picture_is_black_at_both_ends_and_clear_between() -> void:
	for fresh in [true, false]:
		var plan := ArrivalPlan.new(_t, fresh)
		assert_float(plan.sample(0.0).fade).is_equal(1.0)
		assert_float(plan.sample(plan.seconds()).fade).is_equal(1.0)
		assert_float(plan.sample(plan.seconds() * 0.5).fade).is_equal(0.0)


func test_the_helicopter_comes_in_from_afar_and_hovers_over_the_spot() -> void:
	var plan := ArrivalPlan.new(_t, true)
	var far := plan.sample(0.0).heli
	assert_float(Vector2(far.x, far.z).length()).is_greater(_t.approach_distance * 0.9)
	var over := plan.sample(plan.fly_in_end() + 0.5).heli
	assert_float(absf(over.x)).is_less(1.0)
	assert_float(absf(over.z)).is_less(1.0)
	assert_float(over.y).is_equal_approx(_t.hover_height, 0.5)
	# It is nearer to the spot at every sample of the fly-in than the one before (the hover's own sway
	# only begins in its last part).
	var last := INF
	for i in range(0, 7):
		var at := plan.sample(plan.fly_in_end() * i / 10.0).heli
		var apart := Vector2(at.x, at.z).length()
		assert_float(apart).is_less_equal(last + 0.01)
		last = apart


func test_a_late_join_has_no_fly_in() -> void:
	var plan := ArrivalPlan.new(_t, false)
	assert_float(plan.fly_in_end()).is_equal(0.0)
	var heli := plan.sample(0.0).heli
	assert_float(Vector2(heli.x, heli.z).length()).is_less(1.0)
	assert_float(heli.y).is_equal_approx(_t.hover_height, 0.5)


func test_the_rope_pays_out_and_the_soldier_rides_it_to_the_ground() -> void:
	for fresh in [true, false]:
		var plan := ArrivalPlan.new(_t, fresh)
		var last_rope := -1.0
		var last_height := INF
		for i in range(0, 101):
			var at := plan.sample(plan.seconds() * i / 100.0)
			assert_float(at.rope_length).is_greater_equal(last_rope - 0.001)
			last_rope = at.rope_length
			if at.shown:
				assert_float(at.soldier_height).is_less_equal(last_height + 0.001)
				last_height = at.soldier_height
		var down := plan.sample(plan.stand_start())
		assert_float(down.soldier_height).is_equal_approx(0.0, 0.05)
		# Hanging from the rope's end before he lets go, standing after.
		assert_float(plan.sample(plan.slide_start() - 0.1).stood).is_equal(0.0)
		assert_float(plan.sample(plan.stand_start() + 0.5).stood).is_equal(1.0)
		# The rope is all the way down before he starts to slide, and the slide has time to take.
		assert_float(plan.rope_end()).is_less(plan.slide_start())
		assert_float(plan.stand_start() - plan.slide_start()).is_greater(1.0)


func test_the_soldier_is_on_the_ground_before_the_fade_begins() -> void:
	for fresh in [true, false]:
		var plan := ArrivalPlan.new(_t, fresh)
		assert_float(plan.stand_start()).is_less(plan.seconds() - _t.fade_out_seconds)


func test_the_lamp_is_lit_while_the_helicopter_is_over_the_spot() -> void:
	var plan := ArrivalPlan.new(_t, true)
	assert_float(plan.sample(plan.fly_in_end() + 0.2).lamp).is_greater(0.9)
	assert_float(plan.sample(plan.seconds()).lamp).is_equal(0.0)


func test_the_helicopter_is_heard_before_it_is_seen_and_closes_in() -> void:
	var plan := ArrivalPlan.new(_t, true)
	assert_float(plan.sample(0.0).sound).is_greater(0.0)
	assert_float(plan.sample(plan.fly_in_end()).sound).is_greater(plan.sample(0.0).sound + 0.5)
	assert_float(plan.sample(plan.seconds()).sound).is_equal(0.0)


func test_the_camera_looks_down_from_the_sky_at_the_spot() -> void:
	for fresh in [true, false]:
		var plan := ArrivalPlan.new(_t, fresh)
		for i in range(0, 11):
			var at := plan.sample(plan.seconds() * i / 10.0)
			assert_float(at.camera.y).is_greater(at.target.y + 4.0)
			# The camera is angled down: it looks at the spot from above and to a side.
			var down := rad_to_deg(
				atan2(at.camera.y - at.target.y, Vector2(at.camera.x, at.camera.z).length())
			)
			assert_float(down).is_between(20.0, 70.0)


func test_asking_twice_is_asking_once() -> void:
	var plan := ArrivalPlan.new(_t, true)
	var a := plan.sample(3.3)
	var b := plan.sample(3.3)
	assert_vector(a.heli).is_equal(b.heli)
	assert_float(a.rope_length).is_equal(b.rope_length)
	assert_vector(a.camera).is_equal(b.camera)
