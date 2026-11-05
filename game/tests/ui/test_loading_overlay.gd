# The loading screen over a night that is warming up.
extends GdUnitTestSuite


func test_it_shows_the_step_and_a_bar_that_follows_the_progress() -> void:
	var overlay := auto_free(LoadingOverlay.new()) as LoadingOverlay
	add_child(overlay)
	overlay.show_progress(0.5, "Loading the lot (3 of 6)")
	for _i in 120:
		overlay._process(1.0 / 60.0)
	assert_float(overlay.shown_fraction()).is_between(0.45, 0.5)
	assert_str((overlay.find_children("*", "Label", true, false)[1] as Label).text).is_equal(
		"Loading the lot (3 of 6)"
	)


func test_a_step_with_no_text_keeps_the_last_line() -> void:
	var overlay := auto_free(LoadingOverlay.new()) as LoadingOverlay
	add_child(overlay)
	overlay.show_progress(0.2, "Tuning the speakers")
	overlay.show_progress(0.3, "")
	assert_str((overlay.find_children("*", "Label", true, false)[1] as Label).text).is_equal(
		"Tuning the speakers"
	)


func test_finishing_fills_the_bar_and_lets_the_screen_through() -> void:
	var overlay := LoadingOverlay.new()
	add_child(overlay)
	overlay.finish()
	assert_float(overlay.shown_fraction()).is_equal(1.0)
	assert_int(overlay.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_array(_mouse_catchers(overlay)).is_empty()
	await await_idle_frame()
	overlay.queue_free()


## The screen holds the mouse while the night loads, and only it: the box and bar inside would
## otherwise go on catching clicks in the fade after `finish`, over a night the player already has
## (a windowed run of `test_night_menu` clicked Settings into them).
func test_only_the_screen_itself_holds_the_mouse_while_it_loads() -> void:
	var overlay := auto_free(LoadingOverlay.new()) as LoadingOverlay
	add_child(overlay)
	assert_int(overlay.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_array(_mouse_catchers(overlay)).is_empty()


func _mouse_catchers(overlay: LoadingOverlay) -> Array[String]:
	var found: Array[String] = []
	for node in overlay.find_children("*", "Control", true, false):
		if (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			found.append(str(overlay.get_path_to(node)))
	return found


func test_a_headless_run_skips_the_warm_up() -> void:
	# There is no renderer to warm up in a headless run, so the night screen does not wait for one.
	assert_bool(NightScreen.warm_up_enabled).is_equal(DisplayServer.get_name() != "headless")
