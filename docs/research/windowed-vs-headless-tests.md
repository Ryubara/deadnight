# Where a windowed GdUnit run and a headless one see different games

CI runs every GdUnit suite headless (`--headless ... --ignoreHeadlessMode`); an agent that runs a suite in a window
(`gds godot -- ... GdUnitCmdTool.gd -a <suite>`) can see it fail when CI is green. Three UI suites did on `main`
(#1187), each for a reason that is the game's own switch, not the engine:

| What differs | Headless | Windowed | Where |
| --- | --- | --- | --- |
| The menu shell's phone layout | never: a headless window is 64 pixels, so `MenuShell._is_compact` is `false` | on when the window's short side is under 500 pixels (`MenuScale.is_phone`) | `ui/menu/menu_shell.gd` |
| The helicopter drop that opens a person's night (#1057) | off (`NightScreen.arrival_enabled`) | on: the look is held, the touch layer and the HUD are the show's, the reticle is away until it ends | `ui/screens/night_screen.gd` |
| The loading screen (`NightScreen.warm_up_enabled`) | off | on | `ui/screens/night_screen.gd` |

What each did:

- **`test_hover_room`, the Plate button.** The suite's "phone" canvas set the window to 844 x 390 and the factor to 2,
  but a headless shell still built the desktop layout, so CI never measured the phone's Loadout tab. In a window it is
  the phone's: the strip that holds the Plate button is 99 units high, the button was 79 (the theme's size 34 text),
  and its ring and hover growth made 100.4. The button is now at the body size on a phone (68 high), and the suite builds
  `MenuShell` with `phone_mode` from `MenuScale.is_phone(window size)`, as `UiFitRun` does, and asserts the phone
  canvas saw buttons at all. The same suite headless failed on the old game with the same line before the fix.
- **`test_bot_wheel_input` and `test_night_crosshair`.** A window plays the drop on the first night, so the suites'
  first running frame is the show's: no reticle, no look, no touch. They now start a night with no drop due, as
  `--noarrival` and every headless run do, and the crosshair suite also runs the drop and asserts the reticle is away
  under it and back when it ends (solo and joined, a Resume under it, a drop that ends under the pause card). The game
  was right: a player has a reticle from the moment the drop ends.

## The other three

`test_night_mouse_look`, `test_night_screen` and `test_night_menu` (#1195) are in
[the night UI suites](windowed-night-ui-suites.md): the drop explained part of them, the loading screen's fade the
rest of the menu's, and a frame count the last line of the HUD test.

## Frame time (#1202)

Two more suites failed in a window with the game right: a window with no frame cap runs a frame in about 4 ms, where
the headless run and a 60 Hz screen take 16 ms, so a number of frames is a different length of time.

- **`test_hud_idle_redraws`, the low-fuel pulse.** The pulse is `0.65 + 0.35 * sin(5 t)` on the generator's clock, so
  its period is 1.26 s. The test read 60 frames, which is 0.25 s in a window, and saw 0.085 of swing, not the 0.2 it
  asks of a quarter of a turn. It now reads one whole period of frame time (`get_process_delta_time()` summed), with a
  frame cap so a stuck clock fails. The idle-redraw check is unchanged (a mutation that redraws the layer per pulse
  still fails it), and a second test holds the pulse's alpha equal after the same time in steps of 30, 60, 144 and 240
  a second (it fails if the clock counts frames).
- **`test_ui_check_box`, the fill spring.** `UISpring` steps on a fixed 1/240 s, so it ends in the same place at any
  frame rate (`test_a_spring_ends_in_the_same_place_at_any_frame_rate`); the test read it after 90 frames, which is
  0.36 s in a window and the spring was mid-swing at 0.96. It now waits until the spring has settled (at most 5 s of frame
  time) and asserts the exact end value, so the bounds are tighter than before.

### One frame is not a length of time either (#1215)

The same spring test still failed at its release line (`Expecting to be less than: 1.0 but was 1.0`), headless, with
no load at all, and passed in a 60 Hz window. `UISpring.step` adds the frame's delta to a carry and integrates one
step for each whole 1/240 s in it, so a frame shorter than 4.17 ms moves nothing: the box's `_process` had already
set the target to 0.0 on the frame the test read, but the value stayed at 1.0 until the carry reached a step.
A probe printed frames of 0.19 ms to 20 ms in one headless run. The game is right (sub-step lag is by design, and the
spring ends in the same place at any rate); the test asserted a movement after one frame. It now asserts what one
frame does settle (the target), waits in time for the value to leave its start, checks it is strictly between the
ends (so it is a spring, not a snap), and settles for the exact end value.

`--fixed-fps N` makes every frame the same length, which turns the frame-time claim into a sweep (passed to
`GdUnitCmdTool.gd` runs, headless or through `gds godot`): the old test failed at 1000 and 480 frames a second and
passed at 240 and below, the new one passes at 1000, 480, 240, 120, 60 and 10. Use it on any test that reads a
`delta`-driven value. `UISpring` has a unit test for the sub-step frame and its carry
(`test_a_frame_shorter_than_one_step_moves_nothing_and_is_not_lost`).

## The first scheduled run (#1348)

The first scheduled `ui-windowed` run (2026-11-06) failed four suites that pass headless. None was a fault of the game,
and none was one cause: three were tests that read something a window changes, and one is a limit of the runner.

- **`test_night_tap_targets`: the drop.** The suite opens its nights through the Play screen, so the guard that
  looked for a push of the night scene never saw it, and a window played the drop: the touch layer is the show's until it
  ends, so `touch_active()` was false and the hit areas were never measured. It failed the same way in a window on a
  GPU, so a local window run shows it. The suite now starts its nights with no drop due, and the guard also reads
  `play.start()` (it found `test_night_screen_credits` and `test_night_screen_report` too, which now say so). With the
  layer up, every Pause, Ping and button circle is 44 CSS px or more at the three interface sizes: the tap targets are
  right.
- **`test_hud_challenge`: the card's clock.** `HudChallenge._process` adds the real length of each frame to the card's
  clock, and the test let 40 frames run while it measured. A canvas of 2340 to 2880 units costs a software renderer
  0.1 to 1 s a frame, so the card had held, faded and slid off by the time it was read ("the card is not shown", and
  once "leaves the canvas" at x -19.6, mid-slide). The test steps the card by hand (`_run`, `_settle`), so its own
  `_process` is now off in the test. The new case runs the same check at 5 frames a second (`Engine.max_fps`) in every
  run, headless too: it failed before the change and passes after. Not a fault of the HUD: a card that holds for seconds
  of real time is the design.
- **`test_level_ink`: the marquee's chase.** The lobby's panel runs a chase of bulbs (`UIPanel`, a step every 0.15 s,
  the lit set again every three), and the reading takes a place's picture three times (as it is, with the badges
  clear, in flat colour). A bulb lit in one picture and not in the next is brighter in the direction of the
  marker, so a bulb row under the digits was read as digit ink (`digits 660..711` for a glyph that is 32 rows tall).
  Whether the row fell inside the digits' area, and which picture caught which bulbs, depended on the frame times: the
  runner failed 1688 x 780 (all four levels) on the first run and 844 x 390 level 3 on the next three, the same
  suite passed in another run, and a GPU window passes. The suite now holds the chase still (reduced motion, which stops
  `UIPanel`'s `_process`), and a case checks that no marquee panel of the lobby is running one. The digits'
  and the icon's own checks are unchanged (same tolerances).
- **`test_window_fixture`: no window manager.** `test_a_minimized_window_draws_no_frame` needs the window to be
  minimized, and `xvfb-run` starts no window manager, so the request is ignored: measured on the runner, `window_get_mode`
  stays windowed after `WINDOW_MODE_MINIMIZED` and 30 frames are drawn in 30. The three other cases pass there, and
  all four pass in a real window. It is in `tools/ui_windowed_known.json` with an `xvfb:` reason, as the unjudged
  suites are ([the schedule](windowed-ui-ci.md)). The same fact is why the hang of #1207 cannot appear under `xvfb-run`.
