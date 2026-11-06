extends GdUnitTestSuite
## The phone's keyboard on the web (Deadnight #1183). The browser is stood in for by `eval_js`;
## `tools/web_smoke/phone_keyboard.py` runs the real page.


func _layer(answers: Dictionary) -> WebKeyboard:
	var layer := auto_free(WebKeyboard.new()) as WebKeyboard
	layer.eval_js = func(js: String) -> Variant: return answers.get(js, 0)
	layer.installed = true
	add_child(layer)
	return layer


func test_the_export_asks_for_the_engines_virtual_keyboard() -> void:
	# Without the option the engine never opens the field a phone's keyboard comes up for: no text
	# field of the game could open one, in a browser or in a Discord Activity.
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_str(presets).contains("html/experimental_virtual_keyboard=true")


func test_nothing_is_covered_off_the_web() -> void:
	var layer := auto_free(WebKeyboard.new()) as WebKeyboard
	add_child(layer)
	assert_bool(layer.installed).is_false()
	assert_float(layer.covered_units(get_viewport())).is_equal(0.0)
	assert_dict(layer.report()).is_empty()


func test_the_cover_is_the_pages_pixels_in_the_views_units() -> void:
	var layer := _layer(
		{
			"window.deadnightKeyboard.covered()": 220,
			"window.deadnightKeyboard.height()": 390.0,
		}
	)
	var units := get_viewport().get_visible_rect().size.y
	assert_float(layer.covered_units(get_viewport())).is_equal_approx(220.0 * units / 390.0, 0.01)


func test_no_keyboard_means_no_cover() -> void:
	var layer := _layer(
		{"window.deadnightKeyboard.covered()": 0, "window.deadnightKeyboard.height()": 390.0}
	)
	assert_float(layer.covered_units(get_viewport())).is_equal(0.0)


func test_a_page_with_no_height_covers_nothing() -> void:
	var layer := _layer(
		{"window.deadnightKeyboard.covered()": 220, "window.deadnightKeyboard.height()": 0.0}
	)
	assert_float(layer.covered_units(get_viewport())).is_equal(0.0)


func test_the_report_is_what_the_page_counted() -> void:
	var layer := _layer(
		{"JSON.stringify(window.deadnightKeyboard)": '{"deferred":2,"opened":2,"closed":1}'}
	)
	assert_int(int(layer.report()["opened"])).is_equal(2)


func test_the_page_script_holds_the_focus_for_the_lift_of_the_finger() -> void:
	var script := WebKeyboard.PAGE_SCRIPT
	# Held from the first touch event, made in the one that lifts the finger.
	assert_str(script).contains("'touchstart'")
	for lifted in ["touchend", "pointerup", "click"]:
		assert_str(script).contains("'%s'" % lifted)
	# No zoom for a field under 16 px of type (iOS), and the canvas gets the focus back.
	assert_str(script).contains("font-size:16px")
	assert_str(script).contains("canvas.focus()")
