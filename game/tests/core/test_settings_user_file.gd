# Tests and captures never touch the person's own options file (#418): a suite that left
# `camera_shake=0` in it once failed the next run and played the game with the shake off. A service
# built in a test run, a capture or an agent's run keeps its values in memory; a child Godot does
# what the suites did and the real file stays byte for byte the same.
extends GdUnitTestSuite

const PROBE := "res://tests/core/settings_leak_probe.gd"
const CONTROL_FILE := "user://leak_probe_control.cfg"


## The bytes of the person's file, or an empty array when there is none.
func _real_file() -> PackedByteArray:
	var file := FileAccess.open(SettingsService.DEFAULT_PATH, FileAccess.READ)
	return file.get_buffer(file.get_length()) if file != null else PackedByteArray()


func _run_probe(extra: PackedStringArray = []) -> String:
	var output := []
	var arguments := PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", PROBE]
	)
	if not extra.is_empty():
		arguments.append("--")
		arguments.append_array(extra)
	OS.execute(OS.get_executable_path(), arguments, output, true)
	return "\n".join(PackedStringArray(output))


func test_a_test_run_keeps_the_options_in_memory() -> void:
	assert_bool(SettingsService.is_harness_run()).is_true()
	assert_str(SettingsService.default_path()).is_equal(SettingsService.HARNESS_PATH)
	assert_str((auto_free(SettingsService.new()) as SettingsService).path).is_empty()
	assert_str(Settings.path).is_empty()


func test_a_changed_service_freed_with_a_change_pending_leaves_the_real_file_alone() -> void:
	var before := _real_file()
	var service := SettingsService.new()
	service.set_value(SettingsService.CAMERA_SHAKE, 0)
	service.free()
	assert_array(_real_file()).is_equal(before)


func test_the_settings_screen_saving_after_a_suite_leaves_the_real_file_alone() -> void:
	var before := _real_file()
	Settings.set_value(SettingsService.INVERT_Y, not Settings.get_value(SettingsService.INVERT_Y))
	assert_int(Settings.save()).is_equal(OK)
	Settings.set_value(SettingsService.INVERT_Y, not Settings.get_value(SettingsService.INVERT_Y))
	assert_array(_real_file()).is_equal(before)


func test_a_child_godot_that_changes_and_frees_the_options_leaves_the_real_file_alone() -> void:
	var before := _real_file()
	var text := _run_probe()
	assert_str(text).override_failure_message("the probe said: " + text).contains(
		"PROBE path=<> wrote=0"
	)
	assert_array(_real_file()).is_equal(before)


func test_the_probe_does_write_a_file_it_is_pointed_at() -> void:
	DirAccess.remove_absolute(CONTROL_FILE)
	var before := _real_file()
	var text := _run_probe(["--file"])
	assert_str(text).override_failure_message("the probe said: " + text).contains(
		"PROBE path=<%s> wrote=1" % CONTROL_FILE
	)
	assert_array(_real_file()).is_equal(before)
	DirAccess.remove_absolute(CONTROL_FILE)
