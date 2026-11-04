extends GdUnitTestSuite
## Every menu screen and tab fits its own area at the sizes people play at: nothing a screen shows
## crosses the footer, the header or the screen's edge, and nothing is cut off instead of
## scrolled (#980: the Loadout tab ran under the key hints and off the right edge, the Settings
## and Play together screens were taller than a phone's 540 units, and nobody had measured).
##
## The check is `UiFit` (the same the capture tour `ui_fit_tour` prints); the screens are opened
## by `UiFitRun`. Text is measured with the game's own fonts even headless, so a height here is the
## player's height. A phone held upright is covered by the "turn your phone" prompt, which has its
## own test below.

const TEST_PATH := "user://ui_fit_test.cfg"
## The interface sizes people choose (Settings, Accessibility): a desktop window can use all of
## them, a phone's 540 unit canvas only the first two (at Large it is 432 units high).
const DESKTOP_SCALES: Array[float] = [0.8, 1.0, 1.25]
const PHONE_SCALES: Array[float] = [0.8, 1.0]

var _run: UiFitRun
var _saved_path: String
var _saved_touch: Variant


func before_test() -> void:
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	_saved_touch = TouchMode.device_is_touch
	await RouterFixture.clear(get_tree())
	_run = UiFitRun.new(get_tree())
	_run.begin()


func after_test() -> void:
	await _run.close()
	_run.restore()
	TouchMode.device_is_touch = _saved_touch
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


## The window sizes and interface sizes to sweep, as [size, scale] pairs: every size at the usual
## interface size, and each interface size at the sizes where it can be chosen.
func _cases() -> Array:
	var cases: Array = []
	for size in UiFitRun.SIZES:
		cases.append([size, 1.0])
	for scale in DESKTOP_SCALES:
		if scale != 1.0:
			cases.append([Vector2i(1280, 720), scale])
	for scale in PHONE_SCALES:
		if scale != 1.0:
			cases.append([Vector2i(844, 390), scale])
			cases.append([Vector2i(667, 375), scale])
	return cases


func _assert_fits(problems: Array[String]) -> void:
	(
		assert_array(problems)
		. override_failure_message("%d fit problems:\n%s" % [problems.size(), "\n".join(problems)])
		. is_empty()
	)


func test_every_menu_tab_fits_its_panel_between_the_header_and_the_footer() -> void:
	var problems: Array[String] = []
	for entry: Array in _cases():
		await _run.set_window(entry[0], entry[1])
		for tab: MenuTab.Id in MenuTab.ORDER:
			# The usual rows, and the rows with the longest words and numbers a goal can have.
			for extreme in [false, true]:
				var subject := await _run.open_tab(tab, extreme)
				problems.append_array(_run.problems(subject))
				problems.append_array(_run.chrome_problems(subject))
	_assert_fits(problems)


func test_every_screen_fits_the_canvas() -> void:
	var problems: Array[String] = []
	for entry: Array in _cases():
		await _run.set_window(entry[0], entry[1])
		for screen_name in UiFitRun.screen_names():
			problems.append_array(_run.problems(await _run.open(screen_name)))
	_assert_fits(problems)


## A phone held upright is not a size the menus are laid out for: the prompt covers it and asks for
## the turn, so a layout test of the menus at 390 x 844 would test what nobody sees.
func test_a_phone_held_upright_is_covered_by_the_turn_prompt() -> void:
	TouchMode.device_is_touch = true
	await _run.set_window(Vector2i(390, 844))
	var layer := CanvasLayer.new()
	layer.layer = TouchRotatePrompt.LAYER
	add_child(layer)
	var prompt := TouchRotatePrompt.new()
	layer.add_child(prompt)
	await get_tree().process_frame
	await get_tree().process_frame
	var canvas := _run.canvas()
	assert_bool(canvas.size.y > canvas.size.x).is_true()
	assert_bool(prompt.showing()).is_true()
	assert_int(prompt.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	# Held sideways it gets out of the way.
	await _run.set_window(Vector2i(844, 390))
	await get_tree().process_frame
	assert_bool(prompt.showing()).is_false()
	layer.free()


# ------------------------------------------------------------------- the check has teeth


func _holder(canvas_size: Vector2) -> Control:
	var holder: Control = auto_free(Control.new())
	holder.size = canvas_size
	add_child(holder)
	return holder


func _column(rows: int, row_height: float, wide := 200.0) -> VBoxContainer:
	var column := VBoxContainer.new()
	for i in rows:
		var row := Button.new()
		row.custom_minimum_size = Vector2(wide, row_height)
		column.add_child(row)
	return column


func _check(root: Control, area := Rect2(), zones: Array[UiFit.Zone] = []) -> Array[String]:
	return UiFit.check(root, Rect2(Vector2.ZERO, Vector2(400.0, 300.0)), area, zones)


## A column taller than its area runs under the footer: named once, as the column (not once for
## each of its rows), with the rules it breaks.
func test_a_column_taller_than_its_area_is_reported_under_the_footer() -> void:
	var holder := _holder(Vector2(400.0, 300.0))
	var panel := Control.new()
	panel.position = Vector2(0.0, 40.0)
	panel.size = Vector2(300.0, 200.0)
	holder.add_child(panel)
	var column := _column(6, 50.0)
	panel.add_child(column)
	await get_tree().process_frame
	var footer := UiFit.Zone.make("footer", Rect2(0.0, 240.0, 400.0, 60.0))
	var found := _check(panel, panel.get_global_rect(), [footer])
	assert_int(found.size()).is_equal(3)
	(
		assert_bool(found.any(func(line: String) -> bool: return line.contains("under the footer")))
		. is_true()
	)
	(
		assert_bool(found.any(func(line: String) -> bool: return line.contains("outside its area")))
		. is_true()
	)
	(
		assert_bool(found.any(func(line: String) -> bool: return line.contains("off the screen")))
		. is_true()
	)
	(
		assert_bool(found.all(func(line: String) -> bool: return line.begins_with("VBoxContainer")))
		. is_true()
	)


## The same column in a scroll area that is as tall as the panel is fine: what is scrolled out of
## sight is not on the screen.
func test_the_same_column_in_a_scroll_area_fits() -> void:
	var holder := _holder(Vector2(400.0, 300.0))
	var panel := Control.new()
	panel.position = Vector2(0.0, 40.0)
	panel.size = Vector2(300.0, 200.0)
	holder.add_child(panel)
	var scroll := UIScroll.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(scroll)
	var column := _column(6, 50.0, 100.0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	await get_tree().process_frame
	await get_tree().process_frame
	var footer := UiFit.Zone.make("footer", Rect2(0.0, 240.0, 400.0, 60.0))
	assert_array(_check(panel, panel.get_global_rect(), [footer])).is_empty()


## Content wider than a clipping control that cannot scroll sideways is cut, not scrolled.
func test_content_wider_than_a_clipping_box_is_reported_as_cut() -> void:
	var holder := _holder(Vector2(400.0, 300.0))
	var box := Control.new()
	box.clip_contents = true
	box.size = Vector2(150.0, 200.0)
	holder.add_child(box)
	box.add_child(_column(2, 40.0, 220.0))
	await get_tree().process_frame
	var found := _check(box)
	(
		assert_bool(
			found.any(func(line: String) -> bool: return line.contains("cut, not scrolled"))
		)
		. is_true()
	)


## The footer's own parts are not asked to keep clear of it.
func test_a_zone_does_not_ask_its_own_parts_to_keep_clear() -> void:
	var holder := _holder(Vector2(400.0, 300.0))
	var hints := Label.new()
	hints.text = "Enter Select"
	hints.position = Vector2(10.0, 250.0)
	holder.add_child(hints)
	await get_tree().process_frame
	var footer := UiFit.Zone.make("footer", Rect2(0.0, 240.0, 400.0, 60.0), [hints])
	assert_array(_check(holder, Rect2(), [footer])).is_empty()
