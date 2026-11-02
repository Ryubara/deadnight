extends GdUnitTestSuite
## When the settings file is written: not before `SAVE_DELAY` has passed since the last change, once
## for a burst of changes, at once on a close request, and as the service is freed. The clock is
## the test's own: it calls `_process` with the seconds that passed, so nothing waits and nothing
## depends on the machine's speed. Each test uses its own file under user://.

const TEST_PATH := "user://settings_saving_test.cfg"

var _settings: QuietSettings


func before_test() -> void:
	_remove_file()
	_settings = QuietSettings.make(self, TEST_PATH)


func after_test() -> void:
	if is_instance_valid(_settings):
		_settings.free()
	_remove_file()


func _written(key_section: String, key_name: String) -> Variant:
	var file := ConfigFile.new()
	if file.load(TEST_PATH) != OK:
		return null
	return file.get_value(key_section, key_name)


func test_nothing_is_written_before_the_delay() -> void:
	_settings.set_value(SettingsService.VOLUME_MUSIC, 33)
	_settings._process(SettingsService.SAVE_DELAY * 0.5)
	assert_int(_settings.saves).is_equal(0)
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()


func test_the_change_is_written_once_the_delay_has_passed() -> void:
	_settings.set_value(SettingsService.VOLUME_MUSIC, 33)
	_settings._process(SettingsService.SAVE_DELAY * 0.6)
	_settings._process(SettingsService.SAVE_DELAY * 0.6)
	assert_int(_settings.saves).is_equal(1)
	assert_int(_written("audio", "music")).is_equal(33)
	assert_bool(_settings.is_processing()).is_false()


func test_a_burst_of_changes_is_one_write_of_the_last() -> void:
	# A slider drag: every step restarts the wait, so nothing is written until it stops.
	var half := SettingsService.SAVE_DELAY * 0.7
	_settings.set_value(SettingsService.VOLUME_MASTER, 90)
	_settings._process(half)
	_settings.set_value(SettingsService.VOLUME_MASTER, 80)
	_settings._process(half)
	_settings.set_value(SettingsService.VOLUME_MASTER, 70)
	_settings._process(half)
	assert_int(_settings.saves).is_equal(0)
	_settings._process(half)
	assert_int(_settings.saves).is_equal(1)
	assert_int(_written("audio", "master")).is_equal(70)


func test_a_close_request_writes_a_pending_change_at_once_and_only_once() -> void:
	_settings.set_value(SettingsService.INVERT_Y, true)
	_settings.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(_settings.saves).is_equal(1)
	assert_bool(_written("controls", "invert_y")).is_true()
	_settings.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(_settings.saves).is_equal(1)


func test_nothing_pending_means_nothing_written_on_close() -> void:
	_settings.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(_settings.saves).is_equal(0)
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()


func test_freeing_the_service_writes_a_pending_change() -> void:
	_settings.set_value(SettingsService.VOLUME_UI, 12)
	var service := _settings
	_settings = null
	service.free()
	assert_int(_written("audio", "ui")).is_equal(12)


func test_a_saved_service_has_nothing_left_to_write_as_it_is_freed() -> void:
	_settings.set_value(SettingsService.VOLUME_UI, 12)
	_settings.save()
	_remove_file()
	var service := _settings
	_settings = null
	service.free()
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()


func _remove_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
