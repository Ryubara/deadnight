extends GdUnitTestSuite
## `UiFitRun` makes a window a phone's page for a suite and puts it back. What it leaves behind is
## read by every later suite in the shard: a device left as touch stopped mouse look in
## `test_night_mouse_look` (#1251).

const TEST_PATH := "user://ui_fit_run.cfg"

var _saved_path: String


func before_test() -> void:
	_saved_path = Settings.path
	Settings.path = TEST_PATH


func after_test() -> void:
	Settings.reset_defaults()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_a_phone_page_leaves_the_device_as_it_found_it() -> void:
	var found: Variant = TouchMode.device_is_touch
	var run := UiFitRun.new(get_tree())
	run.begin()
	await run.set_window(Vector2i(1688, 780), 1.0, 2.0)
	assert_bool(TouchMode.device_is_touch == true).is_true()
	run.restore()
	assert_bool(TouchMode.device_is_touch == found).is_true()
