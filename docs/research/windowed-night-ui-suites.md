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
