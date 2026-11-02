extends GdUnitTestSuite
## `NightTuning` is a `.tres` the night loads (`night_tuning_default.tres`), not a table built in
## code, so a value edited in the inspector is the value the night plays with.


func test_the_shipped_table_is_the_file_the_night_loads() -> void:
	var file := load(NightTuning.SHIPPED_PATH) as NightTuning
	assert_object(file).is_not_null()
	var night: Night = await NightFixture.start(self, Night.Mode.MANUAL)
	assert_float(night.server.tuning.use_reach).is_equal(file.use_reach)
	assert_float(night.server.tuning.repair_interval).is_equal(file.repair_interval)
	assert_int(night.server.tuning.command_ticks).is_equal(file.command_ticks)
	assert_object(night.night_tuning).is_same(night.server.tuning)
	await NightFixture.settle_bake(night)


func test_a_copy_is_private_and_the_file_is_never_changed() -> void:
	var file := load(NightTuning.SHIPPED_PATH) as NightTuning
	var before := file.use_reach
	var copy := NightTuning.shipped()
	copy.use_reach = before + 5.0
	assert_float(file.use_reach).is_equal(before)
	assert_float(NightTuning.shipped().use_reach).is_equal(before)


func test_the_bots_camera_reads_its_numbers_from_the_tuning() -> void:
	var tuning := NightTuning.shipped()
	tuning.spectator_fov = 90.0
	var night: Night = await NightFixture.start(self, Night.Mode.AUTOPILOT, null, 7, null, tuning)
	assert_float(night.get_viewport().get_camera_3d().fov).is_equal(90.0)
	await NightFixture.settle_bake(night)
