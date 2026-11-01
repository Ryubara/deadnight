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
	assert_int(_screen._pages.size()).is_equal(5)
	assert_int(_screen._tab_buttons.size()).is_equal(5)


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


func test_a_value_between_two_options_shows_the_nearest() -> void:
	Settings.set_value(SettingsService.UI_SCALE, 1.1)
	_screen._sync_all()
	assert_int(_selector(2, 1).selected).is_equal(1)
	Settings.set_value(SettingsService.UI_SCALE, 0.95)
	_screen._sync_all()
	assert_int(_selector(2, 1).selected).is_equal(1)
	Settings.set_value(SettingsService.UI_SCALE, 0.84)
	_screen._sync_all()
	assert_int(_selector(2, 1).selected).is_equal(0)
	Settings.set_value(SettingsService.UI_SCALE, 1.22)
	_screen._sync_all()
	assert_int(_selector(2, 1).selected).is_equal(2)


func test_window_mode_is_shown_on_the_desktop_and_hidden_in_a_browser() -> void:
	assert_int(_screen._pages[0].get_child_count()).is_equal(3)
	var web := _make_screen(true)
	assert_int(web._pages[0].get_child_count()).is_equal(2)
	for row in web._pages[0].get_children():
		assert_bool((row as UIRow).title == "Window mode").is_false()


func test_a_tab_switch_from_a_row_keeps_focus_on_the_new_tab() -> void:
	_slider(0, 1).grab_focus()
	assert_object(_focus()).is_same(_slider(0, 1))
	_press(&"ui_tab_next")
	assert_int(_screen._current).is_equal(1)
	assert_object(_focus()).is_same(_screen._tab_buttons[1])
	# Focus still works from there: down reaches the first row of the new page.
	_slider(1, 0).grab_focus()
	_press(&"ui_tab_prev")
	assert_int(_screen._current).is_equal(0)
	assert_object(_focus()).is_same(_screen._tab_buttons[0])


func test_focus_on_the_tab_strip_follows_the_selected_tab() -> void:
	_screen._tab_buttons[0].grab_focus()
	for tab in range(1, 4):
		_press(&"ui_tab_next")
		assert_object(_focus()).is_same(_screen._tab_buttons[tab])
	_press(&"ui_tab_prev")
	assert_object(_focus()).is_same(_screen._tab_buttons[2])


func test_the_shoulder_buttons_switch_tabs() -> void:
	_screen._tab_buttons[0].grab_focus()
	_press_button(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(_screen._current).is_equal(1)
	_press_button(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(_screen._current).is_equal(2)
	_press_button(JOY_BUTTON_LEFT_SHOULDER)
	assert_int(_screen._current).is_equal(1)
	assert_object(_focus()).is_not_null()


func test_keyboard_and_gamepad_reach_every_tab_with_focus_kept() -> void:
	for action: StringName in [&"ui_tab_next", &"ui_tab_prev"]:
		var steps := _screen._pages.size() - 1
		for i in steps:
			_first_row_control().grab_focus()
			_press(action)
			(
				assert_object(_focus())
				. override_failure_message(
					"no focus after %s from tab %d" % [action, _screen._current]
				)
				. is_not_null()
			)
			assert_bool(_screen._pages[_screen._current].visible).is_true()
		# At the end of the strip the press changes nothing and focus stays.
		_press(action)
		assert_object(_focus()).is_not_null()


func test_arrow_keys_lead_from_the_tab_strip_through_the_rows_to_the_footer() -> void:
	# `find_valid_focus_neighbor` is what an arrow key or the d-pad asks the engine; it needs a layout.
	for tab in _screen._pages.size():
		_screen.select_tab(tab, false)
		await await_idle_frame()
		await await_idle_frame()
		var page: VBoxContainer = _screen._pages[tab]
		var here: Control = _screen._tab_buttons[tab]
		for row in page.get_children():
			here = here.find_valid_focus_neighbor(SIDE_BOTTOM)
			assert_object(here).is_same((row as UIRow).control)
		here = here.find_valid_focus_neighbor(SIDE_BOTTOM)
		assert_object(here).is_same(_screen._footer_buttons[0])
		for i in page.get_child_count() + 1:
			here = here.find_valid_focus_neighbor(SIDE_TOP)
		assert_object(here).is_same(_screen._tab_buttons[tab])


func test_a_mouse_user_without_focus_is_not_given_focus_by_a_tab_switch() -> void:
	get_viewport().gui_release_focus()
	_press(&"ui_tab_next")
	assert_int(_screen._current).is_equal(1)
	assert_object(_focus()).is_null()


func _focus() -> Control:
	return _screen.get_viewport().gui_get_focus_owner()


## The first control on the page being shown, the way a player reaches it with the arrow keys.
func _first_row_control() -> Control:
	return (_screen._pages[_screen._current].get_child(0) as UIRow).control


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_screen.get_viewport().push_input(event)


func _press_button(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	_screen.get_viewport().push_input(event)


func _make_screen(web: bool) -> SettingsScreen:
	var screen := (load(SCREEN) as PackedScene).instantiate() as SettingsScreen
	screen.is_web = web
	add_child(screen)
	auto_free(screen)
	return screen


func _row(tab: int, row: int) -> UIRow:
	return _screen._pages[tab].get_child(row) as UIRow


func _slider(tab: int, row: int) -> UISlider:
	return _row(tab, row).control as UISlider


func _toggle(tab: int, row: int) -> UIToggle:
	return _row(tab, row).control as UIToggle


func _selector(tab: int, row: int) -> UIOptionSelector:
	return _row(tab, row).control as UIOptionSelector


func test_the_touch_tab_sets_the_touch_mode_and_size() -> void:
	_selector(4, 0).select(TouchMode.Choice.OFF, true)
	assert_int(Settings.get_value(SettingsService.TOUCH_CONTROLS)).is_equal(TouchMode.Choice.OFF)
	_slider(4, 1).value = 1.2
	assert_float(Settings.get_value(SettingsService.TOUCH_SCALE)).is_equal_approx(1.2, 0.001)
