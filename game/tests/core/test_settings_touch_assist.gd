extends GdUnitTestSuite
## The touch aim assist setting (#1279): a toggle that is on by default, and what a file saved when
## it was a slider (a number from 0 to 1) becomes. Each test uses its own file under user://, so the
## player's real settings are never read or written.

var _test_path := QuietSettings.test_path("settings_touch_assist_test")

var _made: Array[QuietSettings] = []


func before_test() -> void:
	_remove_file()


func after_test() -> void:
	# A service with an unsaved change writes the file as it is freed: free them first, then the file.
	for service in _made:
		if is_instance_valid(service):
			service.free()
	_made.clear()
	_remove_file()


func test_it_is_a_toggle_that_is_on_by_default() -> void:
	assert_bool(SettingsService.DEFAULTS[SettingsService.TOUCH_AIM_ASSIST] is bool).is_true()
	assert_bool(_make().get_value(SettingsService.TOUCH_AIM_ASSIST)).is_true()


func test_a_file_saved_with_the_slider_loads_as_off_for_0_and_on_for_the_rest() -> void:
	var expected := {0.0: false, 0: false, 0.05: true, 0.5: true, 1.0: true, 1: true}
	for saved: Variant in expected:
		_write(saved)
		(
			assert_bool(_make().get_value(SettingsService.TOUCH_AIM_ASSIST))
			. override_failure_message("a saved %s" % str(saved))
			. is_equal(expected[saved])
		)


func test_a_saved_toggle_is_kept_and_a_wild_entry_is_the_default() -> void:
	_write(false)
	assert_bool(_make().get_value(SettingsService.TOUCH_AIM_ASSIST)).is_false()
	_write(true)
	assert_bool(_make().get_value(SettingsService.TOUCH_AIM_ASSIST)).is_true()
	for wild: Variant in ["off", NAN, INF, -INF]:
		_write(wild)
		assert_bool(_make().get_value(SettingsService.TOUCH_AIM_ASSIST)).is_true()


func test_an_old_value_is_written_back_as_the_toggle() -> void:
	_write(0.0)
	var loaded := _make()
	assert_int(loaded.save()).is_equal(OK)
	var file := ConfigFile.new()
	assert_int(file.load(_test_path)).is_equal(OK)
	assert_bool(file.get_value("controls", "touch_aim_assist")).is_false()


func _write(saved: Variant) -> void:
	var file := ConfigFile.new()
	file.set_value("controls", "touch_aim_assist", saved)
	file.save(_test_path)


func _make() -> QuietSettings:
	var service := QuietSettings.make(self, _test_path)
	_made.append(service)
	return service


func _remove_file() -> void:
	if FileAccess.file_exists(_test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_path))
