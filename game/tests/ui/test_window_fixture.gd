# A minimized window draws no frame. GdUnit minimizes the window after every suite, so the second
# windowed suite that opens a night (its warm-up waits for drawn frames) hung on its first test
# (#1207). The first two tests are that cause on the real window (a headless run has none and skips
# them); the last is a headless guard: every suite that opens a night with its warm-up restores the
# window in `before()`, so a suite added later cannot bring the hang back.
extends GdUnitTestSuite

const SKIP_WHY := "needs a window: a headless run has the dummy display and no warm-up"
## Frames of the main loop to watch a minimized window for.
const WATCHED_FRAMES := 30
## What a suite that opens a night with its warm-up has: the night screen, or the warm-up on.
const OPENS_A_NIGHT := "night_screen.tscn"
const WARM_UP_ON := "warm_up(_enabled)? = true"
const RESTORES := "WindowFixture.make_drawable"


func after_test() -> void:
	# Leave the window as the suites after this one expect it.
	await WindowFixture.make_drawable(get_tree())


func test_a_minimized_window_draws_no_frame(
	_do_skip := not WindowFixture.has_window(), _skip_reason := SKIP_WHY
) -> void:
	WindowFixture.minimize()
	await get_tree().process_frame
	var before := Engine.get_frames_drawn()
	for _i in WATCHED_FRAMES:
		await get_tree().process_frame
	# The main loop goes on, the picture does not: the warm-up's `frame_post_draw` would not come.
	assert_int(Engine.get_frames_drawn()).is_equal(before)


func test_making_the_window_drawable_brings_the_drawn_frames_back(
	_do_skip := not WindowFixture.has_window(), _skip_reason := SKIP_WHY
) -> void:
	WindowFixture.minimize()
	await get_tree().process_frame
	var back: bool = await WindowFixture.make_drawable(get_tree())
	assert_bool(back).is_true()
	assert_int(DisplayServer.window_get_mode()).is_equal(DisplayServer.WINDOW_MODE_WINDOWED)
	# What the warm-up waits for, with the engine's own limit in place of the five minutes.
	# (A lambda copies a plain variable, so the flag is an element of an array.)
	var drawn: Array[bool] = [false]
	RenderingServer.frame_post_draw.connect(func() -> void: drawn[0] = true, CONNECT_ONE_SHOT)
	for _i in WATCHED_FRAMES:
		if drawn[0]:
			break
		await get_tree().process_frame
	assert_bool(drawn[0]).is_true()


func test_a_headless_run_has_nothing_to_restore() -> void:
	if WindowFixture.has_window():
		return
	assert_bool(await WindowFixture.make_drawable(get_tree())).is_true()


func test_windowed_suites_restore_the_window() -> void:
	var opens := RegEx.create_from_string(WARM_UP_ON)
	var missing: Array[String] = []
	for path in _suites("res://tests"):
		if path.ends_with("test_window_fixture.gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		if not (text.contains(OPENS_A_NIGHT) or opens.search(text) != null):
			continue
		if not text.contains(RESTORES):
			missing.append(path)
	(
		assert_array(missing)
		. override_failure_message(
			(
				"these suites open a night with its warm-up and do not call %s in before(): %s"
				% [RESTORES, missing]
			)
		)
		. is_empty()
	)


func _suites(folder: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(folder):
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		found.append_array(_suites(folder.path_join(sub)))
	return found
