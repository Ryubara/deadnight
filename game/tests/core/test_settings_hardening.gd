extends GdUnitTestSuite
## The settings service on its edges: a write while the tree is paused, the flush when focus is
## lost, `nan` and `inf` entries, and the window mode left alone in a browser. Each test uses its
## own file under user://, so the player's real settings are never read or written.

var _test_path := QuietSettings.test_path("settings_hardening_test")

var _settings: QuietSettings
var _made: Array[QuietSettings] = []


func before_test() -> void:
	_remove_file()
	_settings = _make()


func after_test() -> void:
	get_tree().paused = false
	_settings.reset_defaults()
	_settings.apply_all()
	# A service with an unsaved change writes the file as it is freed: free them first, then the file.
	for service in _made:
		if is_instance_valid(service):
			service.free()
	_made.clear()
	_remove_file()


func test_the_debounced_write_runs_while_the_tree_is_paused() -> void:
	_settings.set_value(SettingsService.VOLUME_MUSIC, 33)
	get_tree().paused = true
	# A timer that ignores the pause: the test runner's own waits would stall with the tree.
	await get_tree().create_timer(SettingsService.SAVE_DELAY + 0.5, true).timeout
	var file := ConfigFile.new()
	assert_int(file.load(_test_path)).is_equal(OK)
	assert_int(file.get_value("audio", "music")).is_equal(33)


func test_losing_focus_flushes_a_pending_change() -> void:
	_settings.set_value(SettingsService.VOLUME_UI, 12)
	_settings.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var file := ConfigFile.new()
	assert_int(file.load(_test_path)).is_equal(OK)
	assert_int(file.get_value("audio", "ui")).is_equal(12)


func test_nan_and_infinite_entries_fall_back_to_the_default() -> void:
	var file := ConfigFile.new()
	file.set_value("accessibility", "ui_scale", NAN)
	file.set_value("audio", "master", INF)
	file.set_value("audio", "music", -INF)
	file.set_value("controls", "mouse_sensitivity", INF)
	file.save(_test_path)
	var loaded := _make()
	assert_float(loaded.get_value(SettingsService.UI_SCALE)).is_equal_approx(1.0, 0.001)
	assert_int(loaded.get_value(SettingsService.VOLUME_MASTER)).is_equal(100)
	assert_int(loaded.get_value(SettingsService.VOLUME_MUSIC)).is_equal(80)
	assert_float(loaded.get_value(SettingsService.MOUSE_SENSITIVITY)).is_equal_approx(1.0, 0.001)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master"))).is_false()


func test_set_value_refuses_nan_and_infinity() -> void:
	_settings.set_value(SettingsService.UI_SCALE, NAN)
	_settings.set_value(SettingsService.VOLUME_EFFECTS, INF)
	assert_float(get_tree().root.content_scale_factor).is_equal_approx(1.0, 0.001)
	assert_int(_settings.get_value(SettingsService.VOLUME_EFFECTS)).is_equal(100)


func test_window_mode_is_left_alone_in_a_browser() -> void:
	var spy := _make()
	spy.is_web = true
	spy.set_value(SettingsService.WINDOW_MODE, SettingsService.WindowMode.FULLSCREEN)
	assert_array(spy.window_calls).is_empty()
	assert_int(spy.get_value(SettingsService.WINDOW_MODE)).is_equal(
		SettingsService.WindowMode.FULLSCREEN
	)


func test_window_mode_reaches_the_window_on_the_desktop() -> void:
	var spy := _make()
	spy.is_web = false
	spy.set_value(SettingsService.WINDOW_MODE, SettingsService.WindowMode.FULLSCREEN)
	spy.set_value(SettingsService.WINDOW_MODE, SettingsService.WindowMode.EXCLUSIVE)
	spy.set_value(SettingsService.WINDOW_MODE, SettingsService.WindowMode.WINDOWED)
	(
		assert_array(spy.window_calls)
		. is_equal(
			[
				DisplayServer.WINDOW_MODE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_WINDOWED,
			]
		)
	)


func _make() -> QuietSettings:
	var service := QuietSettings.make(self, _test_path)
	_made.append(service)
	return service


func _remove_file() -> void:
	if FileAccess.file_exists(_test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_path))
