extends GdUnitTestSuite
## Settings on a phone's page (#1290): no hint cut with "...", a gap between a value and the
## scrollbar, and the look settings on the Touch tab in words that name no mouse. The pages are the
## real ones, 844 x 390 and 667 x 375 CSS pixels at the ratio of 2 (`UiFitRun.PAGES`), in touch
## mode; a desktop keeps its Controls tab and its words.

const TEST_PATH := "user://settings_phone_test.cfg"
## What a value keeps from the scrollbar, in units.
const BAR_GAP := 12.0

var _run: UiFitRun
var _saved_path: String


func before_test() -> void:
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	await RouterFixture.clear(get_tree())
	_run = UiFitRun.new(get_tree())
	_run.begin()


func after_test() -> void:
	await _run.close()
	_run.restore()
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


## Every tab of the screen on every phone page: the rows shown, as the screen lays them out.
func _each_tab(check: Callable) -> void:
	for entry: Array in UiFitRun.PAGES:
		await _run.set_window(entry[0], 1.0, entry[1])
		var screen := (await _run.open("settings 0"))["root"] as SettingsScreen
		for tab in screen._pages.size():
			screen.select_tab(tab, false)
			await _run.frames()
			check.call(screen, "%s tab %d" % [entry[0], tab])


func test_no_hint_is_cut_on_any_tab_of_a_phone_page() -> void:
	var problems: Array[String] = []
	await _each_tab(
		func(screen: SettingsScreen, where: String) -> void:
			for row in screen._pages[screen._current].get_children():
				if row is UIRow and (row as UIRow).hint_cut():
					problems.append("%s: the hint of %s is cut" % [where, (row as UIRow).title])
	)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_a_value_keeps_its_gap_from_the_scrollbar() -> void:
	var problems: Array[String] = []
	var bars := [0]
	await _each_tab(
		func(screen: SettingsScreen, where: String) -> void:
			var scroll := screen._rows_scroll
			var bar := scroll.get_v_scroll_bar()
			if not bar.visible:
				return
			bars[0] += 1
			for row in screen._pages[screen._current].get_children():
				var label := (row as UIRow)._value_label
				if label.text == "":
					continue
				var gap := bar.get_global_rect().position.x - label.get_global_rect().end.x
				if gap < BAR_GAP:
					problems.append(
						"%s: %s is %s units from the bar" % [where, (row as UIRow).title, gap]
					)
	)
	assert_int(bars[0]).override_failure_message("no tab showed a bar").is_greater(0)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func _screen(touch: bool) -> SettingsScreen:
	var screen := (load(UiFitRun.SETTINGS) as PackedScene).instantiate() as SettingsScreen
	screen.touch_device = touch
	add_child(screen)
	auto_free(screen)
	return screen


func _titles(screen: SettingsScreen, tab: int) -> Array[String]:
	var titles: Array[String] = []
	for row in screen._pages[tab].get_children():
		titles.append((row as UIRow).title)
	return titles


func _tab_names(screen: SettingsScreen) -> Array[String]:
	var names: Array[String] = []
	for button in screen._tab_buttons:
		names.append(button.text)
	return names


func _row_of(screen: SettingsScreen, key: StringName) -> UIRow:
	for binding in screen._bindings:
		if binding["spec"]["key"] == key:
			return binding["row"] as UIRow
	return null


func test_a_phone_has_no_controls_tab_and_its_look_settings_are_on_the_touch_tab() -> void:
	var screen := _screen(true)
	assert_array(_tab_names(screen)).is_equal(["Video", "Audio", "Accessibility", "Touch"])
	assert_int(screen._pages.size()).is_equal(4)
	assert_array(_titles(screen, 3)).contains(["Look sensitivity", "Invert vertical look"])
	assert_array(_titles(screen, 3).slice(0, 3)).is_equal(
		["Touch controls", "Look sensitivity", "Invert vertical look"]
	)


func test_a_phone_names_no_mouse_anywhere_in_its_settings() -> void:
	var screen := _screen(true)
	var found: Array[String] = []
	for binding in screen._bindings:
		var row := binding["row"] as UIRow
		for words in [row.title, row.hint, binding["spec"].get("phone_hint", "")]:
			if "mouse" in (words as String).to_lower():
				found.append("%s: %s" % [row.title, words])
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


func test_a_desktop_keeps_the_controls_tab_with_the_mouse_words() -> void:
	var screen := _screen(false)
	assert_array(_tab_names(screen)).is_equal(
		["Video", "Audio", "Accessibility", "Controls", "Touch"]
	)
	assert_array(_titles(screen, 3)).is_equal(["Mouse sensitivity", "Invert Y axis"])
	assert_str((screen._pages[3].get_child(1) as UIRow).hint).is_equal(
		"Push the mouse forward to look down."
	)
	# The Touch tab is what it was: no look rows on it.
	assert_int(screen._pages[4].get_child_count()).is_equal(7)
	assert_array(_titles(screen, 4)).not_contains(["Look sensitivity", "Invert vertical look"])


func test_the_phones_look_rows_and_the_desktops_are_the_same_two_settings() -> void:
	var phone := _screen(true)
	var desktop := _screen(false)
	var sensitivity := _row_of(phone, SettingsService.MOUSE_SENSITIVITY)
	var invert := _row_of(phone, SettingsService.INVERT_Y)
	# A move on the phone's rows lands on the settings the mouse look reads (`PlayerSettings`)...
	(sensitivity.control as UISlider).value = 2.0
	(invert.control as UIToggle).button_pressed = true
	assert_float(Settings.get_value(SettingsService.MOUSE_SENSITIVITY)).is_equal_approx(2.0, 0.001)
	assert_bool(Settings.get_value(SettingsService.INVERT_Y)).is_true()
	# ...and a desktop's rows show them, and write them back, the same way.
	desktop._sync_all()
	var mouse := _row_of(desktop, SettingsService.MOUSE_SENSITIVITY)
	assert_float((mouse.control as UISlider).value).is_equal_approx(2.0, 0.001)
	(
		assert_bool((_row_of(desktop, SettingsService.INVERT_Y).control as UIToggle).button_pressed)
		. is_true()
	)
	assert_str(sensitivity.title).is_not_equal(mouse.title)
	(
		assert_array(
			[sensitivity.control.min_value, sensitivity.control.max_value, sensitivity.control.step]
		)
		. is_equal([mouse.control.min_value, mouse.control.max_value, mouse.control.step])
	)


func test_reset_to_defaults_restores_the_look_settings_on_a_phone() -> void:
	var screen := _screen(true)
	var sensitivity := _row_of(screen, SettingsService.MOUSE_SENSITIVITY)
	var invert := _row_of(screen, SettingsService.INVERT_Y)
	(sensitivity.control as UISlider).value = 2.5
	(invert.control as UIToggle).button_pressed = true
	screen._on_reset()
	assert_float((sensitivity.control as UISlider).value).is_equal_approx(1.0, 0.001)
	assert_bool((invert.control as UIToggle).button_pressed).is_false()
	assert_float(Settings.get_value(SettingsService.MOUSE_SENSITIVITY)).is_equal_approx(1.0, 0.001)
	assert_bool(Settings.get_value(SettingsService.INVERT_Y)).is_false()
	assert_str(sensitivity._value_label.text).is_equal("1.00x")


func test_a_row_hands_a_drag_to_the_card_it_scrolls_in() -> void:
	# The buttons of a row pass the touch up to the card (`UIScroll.pass_touch_in_scroll`), so a drag
	# that begins on a row still scrolls it: the Settings card is a `UIScroll` that stops the pointer.
	var screen := _screen(true)
	await await_idle_frame()
	assert_int(screen._rows_scroll.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	for tab in screen._pages.size():
		for row in screen._pages[tab].get_children():
			var control := (row as UIRow).control
			var buttons: Array[Node] = []
			if control is BaseButton:
				buttons.append(control)
			buttons.append_array(control.find_children("*", "BaseButton", true, false))
			for node in buttons:
				(
					assert_int((node as BaseButton).mouse_filter)
					. override_failure_message(
						"%s: a button of the row holds the touch" % [row.title]
					)
					. is_equal(Control.MOUSE_FILTER_PASS)
				)


func test_a_desktop_window_keeps_the_hints_and_the_widths_it_had() -> void:
	await _run.set_window(Vector2i(1920, 1080), 1.0, 1.0)
	var screen := (await _run.open("settings 0"))["root"] as SettingsScreen
	var video := _row_of(screen, SettingsService.RESOLUTION_SCALE)
	assert_str(video.hint).is_equal("Draws the 3D world smaller; the interface stays sharp.")
	assert_bool(video.hint_cut()).is_false()
	var wide := video._slot.custom_minimum_size.x
	assert_float(wide).is_equal(float(UITokens.active().control_width))
	# The same screen on a phone's page, then back: the phone's copy and width, then the desktop's.
	await _run.set_window(UiFitRun.PAGES[3][0], 1.0, UiFitRun.PAGES[3][1])
	await _run.frames()
	assert_str(video.hint).is_equal("Smaller 3D world; the menu stays sharp.")
	assert_float(video._slot.custom_minimum_size.x).is_equal(
		float(SettingsScreen.PHONE_CONTROL_WIDTH)
	)
	await _run.set_window(Vector2i(1920, 1080), 1.0, 1.0)
	await _run.frames()
	assert_str(video.hint).is_equal("Draws the 3D world smaller; the interface stays sharp.")
	assert_float(video._slot.custom_minimum_size.x).is_equal(wide)
