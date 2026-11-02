extends GdUnitTestSuite
## Load, save and apply for the settings service. Each test uses its own file under user://, so the
## player's real settings are never read or written.

var _test_path := QuietSettings.test_path("settings_test")

var _settings: QuietSettings
var _made: Array[QuietSettings] = []


func before_test() -> void:
	_remove_file()
	_settings = _make()


func after_test() -> void:
	# Put the engine back the way the suite found it.
	_settings.reset_defaults()
	_settings.apply_all()
	# A service with an unsaved change writes the file as it is freed: free them first, then the file.
	for service in _made:
		if is_instance_valid(service):
			service.free()
	_made.clear()
	_remove_file()


func test_defaults_without_a_file() -> void:
	for key: StringName in SettingsService.DEFAULTS:
		assert_that(_settings.get_value(key)).is_equal(SettingsService.DEFAULTS[key])


func test_save_then_load_round_trips() -> void:
	_settings.set_value(SettingsService.VOLUME_MUSIC, 35)
	_settings.set_value(SettingsService.INVERT_Y, true)
	_settings.set_value(SettingsService.MOUSE_SENSITIVITY, 1.75)
	_settings.set_value(SettingsService.WINDOW_MODE, SettingsService.WindowMode.FULLSCREEN)
	assert_int(_settings.save()).is_equal(OK)
	var again := _make()
	assert_int(again.get_value(SettingsService.VOLUME_MUSIC)).is_equal(35)
	assert_bool(again.get_value(SettingsService.INVERT_Y)).is_true()
	assert_float(again.get_value(SettingsService.MOUSE_SENSITIVITY)).is_equal_approx(1.75, 0.001)
	assert_int(again.get_value(SettingsService.WINDOW_MODE)).is_equal(
		SettingsService.WindowMode.FULLSCREEN
	)


func test_file_uses_the_documented_sections() -> void:
	_settings.set_value(SettingsService.VSYNC, false)
	_settings.save()
	var file := ConfigFile.new()
	assert_int(file.load(_test_path)).is_equal(OK)
	assert_bool(file.get_value("video", "vsync")).is_false()
	assert_bool(file.has_section_key("audio", "master")).is_true()
	assert_bool(file.has_section_key("controls", "invert_y")).is_true()


func test_the_touch_hints_seen_mask_round_trips_and_a_wild_value_is_clamped() -> void:
	_settings.set_value(SettingsService.TOUCH_HINTS_SEEN, 5)
	_settings.save()
	assert_int(_make().get_value(SettingsService.TOUCH_HINTS_SEEN)).is_equal(5)
	_settings.set_value(SettingsService.TOUCH_HINTS_SEEN, 9000)
	assert_int(_settings.get_value(SettingsService.TOUCH_HINTS_SEEN)).is_equal(255)
	_settings.reset_defaults()
	assert_int(_settings.get_value(SettingsService.TOUCH_HINTS_SEEN)).is_equal(0)


func test_bad_entries_fall_back_or_clamp() -> void:
	var file := ConfigFile.new()
	file.set_value("audio", "master", 900)
	file.set_value("video", "vsync", "yes")
	file.set_value("controls", "mouse_sensitivity", "fast")
	file.set_value("accessibility", "ui_scale", 0.1)
	file.save(_test_path)
	var loaded := _make()
	assert_int(loaded.get_value(SettingsService.VOLUME_MASTER)).is_equal(100)
	assert_bool(loaded.get_value(SettingsService.VSYNC)).is_true()
	assert_float(loaded.get_value(SettingsService.MOUSE_SENSITIVITY)).is_equal_approx(1.0, 0.001)
	assert_float(loaded.get_value(SettingsService.UI_SCALE)).is_equal_approx(0.8, 0.001)


func test_unreadable_file_leaves_defaults() -> void:
	var handle := FileAccess.open(_test_path, FileAccess.WRITE)
	handle.store_string("[[ not a config")
	handle.close()
	var loaded := _make()
	assert_int(loaded.get_value(SettingsService.VOLUME_MUSIC)).is_equal(80)


func test_set_value_coerces_and_ignores_unknown_keys() -> void:
	_settings.set_value(SettingsService.VOLUME_UI, 250)
	assert_int(_settings.get_value(SettingsService.VOLUME_UI)).is_equal(100)
	_settings.set_value(&"nope/nothing", 1)
	assert_that(_settings.get_value(&"nope/nothing")).is_null()


func test_changed_signal_carries_key_and_value() -> void:
	var seen := []
	_settings.changed.connect(
		func(key: StringName, value: Variant) -> void: seen.append([key, value])
	)
	_settings.set_value(SettingsService.VOLUME_MASTER, 40)
	_settings.set_value(SettingsService.VOLUME_MASTER, 40)
	assert_array(seen).is_equal([[SettingsService.VOLUME_MASTER, 40]])


func test_reset_defaults_restores_every_value() -> void:
	_settings.set_value(SettingsService.VOLUME_EFFECTS, 10)
	_settings.set_value(SettingsService.REDUCED_MOTION, true)
	_settings.reset_defaults()
	assert_int(_settings.get_value(SettingsService.VOLUME_EFFECTS)).is_equal(100)
	assert_bool(_settings.get_value(SettingsService.REDUCED_MOTION)).is_false()


func test_bus_layout_has_every_bus_a_volume_drives() -> void:
	for key: StringName in SettingsService.BUSES:
		assert_int(AudioServer.get_bus_index(SettingsService.BUSES[key])).is_greater_equal(0)


func test_volume_applies_to_its_bus() -> void:
	_settings.set_value(SettingsService.VOLUME_MUSIC, 50)
	var bus := AudioServer.get_bus_index(&"Music")
	assert_float(AudioServer.get_bus_volume_db(bus)).is_equal_approx(linear_to_db(0.5), 0.01)
	assert_bool(AudioServer.is_bus_mute(bus)).is_false()


func test_zero_volume_mutes_the_bus() -> void:
	_settings.set_value(SettingsService.VOLUME_EFFECTS, 0)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Effects"))).is_true()
	_settings.set_value(SettingsService.VOLUME_EFFECTS, 100)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Effects"))).is_false()


func test_reduced_motion_drives_the_ui_switch() -> void:
	_settings.set_value(SettingsService.REDUCED_MOTION, true)
	assert_bool(UIMotion.reduced).is_true()
	_settings.set_value(SettingsService.REDUCED_MOTION, false)
	assert_bool(UIMotion.reduced).is_false()


func test_ui_scale_and_resolution_scale_apply_to_the_root_window() -> void:
	_settings.set_value(SettingsService.UI_SCALE, 1.25)
	_settings.set_value(SettingsService.RESOLUTION_SCALE, 75)
	var root := get_tree().root
	assert_float(root.content_scale_factor).is_equal_approx(1.25, 0.001)
	assert_float(root.scaling_3d_scale).is_equal_approx(0.75, 0.001)


func test_startup_applies_the_saved_file() -> void:
	var file := ConfigFile.new()
	file.set_value("audio", "ui", 20)
	file.set_value("accessibility", "reduced_motion", true)
	file.save(_test_path)
	var started := _make()
	started.apply_all()
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"UI"))).is_equal_approx(
		linear_to_db(0.2), 0.01
	)
	assert_bool(UIMotion.reduced).is_true()


## A service on the test file, in the tree so it can reach the root window; its window calls go to
## a list, never to the display this runs on.
func _make() -> QuietSettings:
	var service := QuietSettings.make(self, _test_path)
	_made.append(service)
	return service


func _remove_file() -> void:
	if FileAccess.file_exists(_test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_path))


func test_a_suite_file_is_named_by_the_process_so_two_runs_do_not_share_it() -> void:
	var path := QuietSettings.test_path("settings_test")
	assert_str(path).starts_with("user://settings_test_")
	assert_str(path).contains("_%d." % OS.get_process_id())
	assert_str(path).is_not_equal(QuietSettings.test_path("other_test"))
