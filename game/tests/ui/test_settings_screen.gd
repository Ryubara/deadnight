extends GdUnitTestSuite
## The settings screen bound to the real `Settings` autoload (pointed at a throwaway file): moving a
## control changes the value, Reset puts it back, and the widgets behave the way the screen needs.

const SCREEN := "res://ui/screens/settings_screen.tscn"
const TEST_PATH := "user://settings_screen_test.cfg"

var _screen: SettingsScreen
var _saved_path: String


func before_test() -> void:
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	_screen = (load(SCREEN) as PackedScene).instantiate() as SettingsScreen
	add_child(_screen)
	auto_free(_screen)


func after_test() -> void:
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_has_a_page_per_tab() -> void:
	assert_int(_screen._pages.size()).is_equal(4)
	assert_int(_screen._tab_buttons.size()).is_equal(4)


func test_controls_start_at_the_saved_values() -> void:
	assert_float(_slider(1, 1).value).is_equal(80.0)
	assert_bool(_toggle(0, 2).button_pressed).is_true()
	assert_int(_selector(2, 1).selected).is_equal(1)


func test_moving_a_slider_changes_the_setting() -> void:
	_slider(1, 0).value = 45
	assert_int(Settings.get_value(SettingsService.VOLUME_MASTER)).is_equal(45)


func test_a_toggle_changes_the_setting() -> void:
	_toggle(3, 1).button_pressed = true
	assert_bool(Settings.get_value(SettingsService.INVERT_Y)).is_true()


func test_option_selector_steps_and_wraps() -> void:
	var selector := _selector(2, 1)
	selector.step(1)
	assert_float(Settings.get_value(SettingsService.UI_SCALE)).is_equal_approx(1.25, 0.001)
	selector.step(1)
	assert_float(Settings.get_value(SettingsService.UI_SCALE)).is_equal_approx(0.8, 0.001)
	selector.step(-1)
	assert_float(Settings.get_value(SettingsService.UI_SCALE)).is_equal_approx(1.25, 0.001)
	Settings.set_value(SettingsService.UI_SCALE, 1.0)


func test_reset_puts_controls_and_values_back() -> void:
	_slider(1, 2).value = 10
	_toggle(3, 1).button_pressed = true
	_screen._on_reset()
	assert_float(_slider(1, 2).value).is_equal(100.0)
	assert_bool(_toggle(3, 1).button_pressed).is_false()
	assert_int(Settings.get_value(SettingsService.VOLUME_EFFECTS)).is_equal(100)


func test_selecting_a_tab_shows_only_its_page() -> void:
	_screen.select_tab(2, false)
	for i in _screen._pages.size():
		assert_bool(_screen._pages[i].visible).is_equal(i == 2)


func test_slider_value_text_follows_the_setting() -> void:
	_slider(3, 0).value = 2.0
	assert_str(_row(3, 0)._value_label.text).is_equal("2.00x")


func test_a_scale_round_trip_does_not_stretch_the_layout() -> void:
	var column := _screen.get_child(0).get_child(0).get_child(0) as Control
	await await_idle_frame()
	var before := column.get_combined_minimum_size().y
	Settings.set_value(SettingsService.UI_SCALE, 1.25)
	await await_idle_frame()
	await await_idle_frame()
	Settings.set_value(SettingsService.UI_SCALE, 1.0)
	_screen.select_tab(3, false)
	await await_idle_frame()
	await await_idle_frame()
	assert_float(column.get_combined_minimum_size().y).is_equal_approx(before, 1.0)


func _row(tab: int, row: int) -> UIRow:
	return _screen._pages[tab].get_child(row) as UIRow


func _slider(tab: int, row: int) -> UISlider:
	return _row(tab, row).control as UISlider


func _toggle(tab: int, row: int) -> UIToggle:
	return _row(tab, row).control as UIToggle


func _selector(tab: int, row: int) -> UIOptionSelector:
	return _row(tab, row).control as UIOptionSelector
