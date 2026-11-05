class_name WindowFixture
extends RefCounted
## Gives a suite a window that draws, so a night's warm-up can finish in a windowed run.
##
## GdUnit minimizes the window when a run starts and again after every suite
## (`GdUnitTestSuiteAfterStage`), and a minimized window draws no frame: the engine skips the draw
## and `RenderingServer.frame_post_draw` never comes. `NightWarmup` draws the lot a few times
## behind the loading screen and waits for each of those frames, so the night of the second suite in
## one windowed session never reached `ready_to_play` and its first test ran into the five minute
## limit (#1207). The first suite of a session finds the window as the game left it (the settings
## put it in the windowed mode), which is why every suite passed alone. A headless run has no
## window and no warm-up, so CI never met it.
##
## A suite that opens a night with its warm-up (or runs the warm-up itself) calls this from
## `before()`; `test_windowed_suites_restore_the_window` fails a suite that forgets it.

## How long a restored window may take to draw again, in real seconds.
const DRAW_WAIT_SECONDS := 5.0
## How many frames must be drawn for the window to count as drawing again.
const DRAWN_FRAMES := 2


## Whether this run has a window to draw into (a headless run has the dummy display).
static func has_window() -> bool:
	return DisplayServer.get_name() != "headless"


## Minimizes the window as GdUnit does at the end of a suite.
static func minimize() -> void:
	if has_window():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


## Puts a minimized window back and waits until it has drawn again; false (and an error, in place
## of a hang) when it does not. A headless run has nothing to restore.
static func make_drawable(tree: SceneTree) -> bool:
	if not has_window():
		return true
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var target := Engine.get_frames_drawn() + DRAWN_FRAMES
	var began := Time.get_ticks_msec()
	while Engine.get_frames_drawn() < target:
		if (Time.get_ticks_msec() - began) / 1000.0 > DRAW_WAIT_SECONDS:
			push_error("WindowFixture: the window drew no frame in %s s" % DRAW_WAIT_SECONDS)
			return false
		await tree.process_frame
	return true
