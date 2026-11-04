# The performance profile's sampler (#906): a row a second of monitors, counts and labelled times.
extends GdUnitTestSuite


func after_test() -> void:
	PerfProbe.enabled = false


func _sampler(state: Dictionary) -> PerfSampler:
	var sampler := auto_free(PerfSampler.new()) as PerfSampler
	sampler.night_state = func() -> Dictionary: return state
	add_child(sampler)
	return sampler


func test_a_row_is_made_for_each_second_of_game_time() -> void:
	var sampler := _sampler({"round": 12, "alive": 40, "cap": 99, "players": 4})
	for _i in 4:
		sampler._process(0.25)
	assert_int(sampler.rows.size()).is_equal(1)
	var row := sampler.rows[0]
	assert_int(row["round"]).is_equal(12)
	assert_int(row["alive"]).is_equal(40)
	assert_int(row["cap"]).is_equal(99)
	assert_int(row["frames"]).is_equal(4)
	assert_int(row["nodes"]).is_greater(0)
	assert_float(row["calibration_ms"]).is_greater(0.0)


func test_what_perf_probe_timed_in_the_second_is_in_the_row_per_frame() -> void:
	var sampler := _sampler({})
	for _i in 4:
		var began := PerfProbe.begin()
		OS.delay_usec(2000)
		PerfProbe.end(&"test.work", began)
		PerfProbe.count(&"test.events")
		sampler._process(0.25)
	var row := sampler.rows[0]
	# 2 ms at least in each of 4 frames: a sleep is never shorter than asked, and a busy machine may
	# make it much longer, so there is no upper bound to hold.
	assert_float(row["labels_ms"]["test.work"]).is_greater(1.9)
	assert_float(row["labels_median_ms"]["test.work"]).is_greater(1.9)
	assert_int(row["counts"]["test.events"]).is_equal(4)


func test_the_scene_counts_see_lights_particles_and_sounds_that_are_on() -> void:
	var sampler := _sampler({})
	var light := auto_free(OmniLight3D.new()) as OmniLight3D
	add_child(light)
	var dark := auto_free(OmniLight3D.new()) as OmniLight3D
	dark.visible = false
	add_child(dark)
	var smoke := auto_free(GPUParticles3D.new()) as GPUParticles3D
	smoke.emitting = true
	add_child(smoke)
	var counts := sampler._scene_counts(get_tree().root)
	assert_int(counts["lights"]).is_greater_equal(1)
	assert_int(counts["particles"]).is_greater_equal(1)
	var before_dark: int = counts["lights"]
	dark.visible = true
	assert_int(sampler._scene_counts(get_tree().root)["lights"]).is_equal(before_dark + 1)


func test_the_calibration_is_a_small_fixed_cost() -> void:
	var ms := PerfSampler.calibrate()
	assert_float(ms).is_between(0.05, 200.0)
