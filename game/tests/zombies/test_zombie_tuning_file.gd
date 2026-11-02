extends GdUnitTestSuite
## The zombies play the numbers of `zombie_tuning_default.tres`, the file you edit in the inspector.


func test_a_sim_with_no_tuning_plays_the_files_numbers() -> void:
	var file := load(ZombieTuning.SHIPPED_PATH) as ZombieTuning
	var sim := ZombieSim.new(null, 1)
	assert_float(sim.tuning.reach).is_equal(file.reach)
	assert_int(sim.tuning.hard_cap).is_equal(file.hard_cap)


func test_a_copy_is_private_and_the_file_is_never_changed() -> void:
	var file := load(ZombieTuning.SHIPPED_PATH) as ZombieTuning
	var before := file.reach
	var copy := ZombieTuning.shipped()
	copy.reach = before + 3.0
	assert_float(file.reach).is_equal(before)
	assert_float(ZombieTuning.shipped().reach).is_equal(before)
	assert_float(ZombieSim.new(null, 1).tuning.reach).is_equal(before)
