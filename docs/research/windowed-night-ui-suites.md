# The night UI suites that failed in a window and passed headless

CI runs every GdUnit suite headless; a suite run in a window (`gds godot -- ... GdUnitCmdTool.gd -a <suite>`) saw a
different game. #1187 fixed three suites for the menu shell's phone layout, the helicopter drop and the loading
screen (the method and the first table are in [windowed vs headless tests](windowed-vs-headless-tests.md)). #1195 is the
other three, found by deciding per failure whether the game or the test was wrong, by running the real path:

| Suite | Windowed on main | Cause | Whose |
| --- | --- | --- | --- |
| `test_night_mouse_look` | 3 of 4 fail | the drop holds the look (motion and pad turn the camera by 0); the loading screen's box still catches the mouse in its fade | the test (no drop due), the game (overlay) |
| `test_night_screen` | 3 of 8 fail | the drop hides the reticle; the HUD test read the night's first frame after two physics frames | the test, twice |
| `test_night_menu` | 12 of 13 fail, 7 errors | the loading screen's box over the menu took every click and tap of the first frames | the game |

## The loading screen caught the mouse in its fade

`LoadingOverlay.finish()` sets the overlay's own filter to `IGNORE` and fades it for 0.35 s, but the `VBoxContainer`
inside it (default `PASS`) and the bar's `ColorRect` (default `STOP`) kept theirs. A control whose rect holds the
cursor is the one the viewport hands the event to, so for 0.35 s after a night opened the click on a pause-menu button
(or a tap on Resume) went to the box and nothing else saw it. A headless run has no loading screen
(`NightScreen.warm_up_enabled`), so CI never saw it. A probe listing the controls under a button
(`is_visible_in_tree()`, rect holds the point, filter not `IGNORE`) named it at once; the rest of `test_night_menu`
failed because its first click failed (the touch case leaves a Resume that never closes, and the later ones wait for
a menu that is still open). Fixed in the game: the overlay's box and bar are `IGNORE`, only its root holds the mouse
while the night loads. `test_loading_overlay` asserts it, before and after `finish`.

## Exit 105 is not a crash

GdUnit exits 105 (`RETURN_ERROR_SCRIPT_ERRORS_DETECTED`) when a script error is printed while it discovers the tests,
so it is a test file that does not parse, not the game stopping. The windowed run of `test_night_menu` on main exits
100 (tests failed), and every run after the fixes here exits 0.

## A frame count that depends on the machine

`test_the_hud_is_on_the_night_and_hears_it` compared the HUD's points with the night's after two physics frames. The
HUD hears the start events as the night begins (200 points); `night.state.points()` is read from the server's first
frame, which came at the third physics frame in a window and later headless, where both read 0 and the line was
true for nothing. The test waits for the first frame and compares both with the tuning's `start_points`.

## Starting a night with no drop

A suite that is about something other than the drop sets `NightScreen.arrival_enabled = false` in `before_test` and
puts it back in `after_test` (`--noarrival`, what a headless run always has); `test_arrival_night` and
`test_night_crosshair` are the ones that play it.

## The second suite of a windowed session hung (#1207)

`test_night_screen` passed alone in a window and timed out on its first test ("Test timed out after 5min") when it ran
after `test_night_crosshair` in one session; the reverse order hung the same way (crosshair, 7 tests, 25 s, then the
hang). It was on `main`; headless (CI) never saw it.

| Await | Result |
| --- | --- |
| `UIRouter.idle` (reset and push) | returns |
| `screen.night.ready_to_play` | never: `NightWarmup` is inside its lot pass |
| `await RenderingServer.frame_post_draw` in `NightWarmup._shots` | the one that hangs: `Engine.get_frames_drawn()` stands still |

The state left behind is not a static of the game but the window: GdUnit minimizes it after every suite
(`GdUnitTestSuiteAfterStage`), and a minimized window draws no frame, so the warm-up's frame never comes. A print of
`DisplayServer.window_get_mode()` before the await gave `0` (windowed) in the first suite of a session and `1`
(minimized) in the second. The first suite finds the window as the game's `Settings` left it, which is why every suite
passed alone. The game is right to wait for a frame (a player who minimizes a loading game finds it finishing when the
window returns), so the suites fix it: `WindowFixture.make_drawable` (`tests/ui/window_fixture.gd`) puts a minimized
window back and waits for two drawn frames, and 21 suites that open a night with its warm-up call it from `before()`.
`test_window_fixture` has the cause on the real window (a minimized window draws 0 frames in 30; after the fixture the
frames come; without the restore the fixture's own error names it after 5 s) and a headless guard that lists a suite
that opens a night (`night_screen.tscn`, or `warm_up = true`) and does not call the fixture (21 listed before the fix).
The kit's page is [A minimized window draws nothing](https://ryubara.github.io/gdstudio/engines/godot/minimized-window/).

Windowed, with the fix: crosshair then screen 15 of 15 in 54.7 s, screen then crosshair 15 of 15 in 53.6 s, no
failures, no timeout changed. Before: both orders killed at 200 s and 150 s.

## The end board under the drop (`test_night_screen_end`)

`test_the_board_replaces_the_hud_and_the_clock_ends_on_the_play_screen_with_its_rules` failed windowed with two lines
(and passed headless): `screen._hud.visible` was false on the night's first frame (the drop hides the HUD, the test
started its night from the Play screen with the drop due) and true after the night ended. The first is the test's: the
suite is about the end, so it starts with no drop due, as the others do (windowed 3 of 3 pass, from 1 of 2).

The second is the game's. When a night ends, `NightScreen._on_night_over` hides the HUD and puts the board up, then
`Night._on_over` closes a show still playing (`arrival_show.skip_now()`), which emits `arrival_ended`, and
`_on_arrival_ended` showed the HUD again, with the reticle and touch layer live, over the board. Now it does nothing
when the board is up. The rules cannot end a night under a person's drop (the dropping player is shielded, so
"everyone is down" cannot hold, and the cap is 12 s), so no player has met it; the test ends the night under the drop on
purpose (`test_the_night_ending_under_the_drop_leaves_the_board_alone`; it fails on the old screen with the same line).
Signal order is the lesson: two handlers of one signal that touch the same node run in connect order, and the screen
connects before the night's own.

`skip_now` emits `arrival_ended` inside the call, so a script that skips the show and then awaits `arrival_ended` waits
for ever (Deadnight #1278: a capture recorded 3000 frames of the wait). After `skip_now` the show is over; read
`is_arriving()` instead, and give every capture its own frame limit (`auto_reload_capture.gd` counts frames in
`_process` and quits).
