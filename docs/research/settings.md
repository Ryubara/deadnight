# Settings

The settings screen (`game/ui/screens/settings_screen.tscn`), the `Settings` autoload (`game/core/settings.gd`) and the
widgets they needed (`UISlider`, `UIToggle`, `UIOptionSelector`, `UIRow` in `game/addons/gds_ui/`). The addon still names
nothing Deadnight: the screen and the service are the game's.

## The service

`SettingsService` (autoload `Settings`) holds one value per key (`section/name`), each with a default and a range.
`set_value` clamps and type-checks, applies at once, emits `changed` and schedules a write 0.6 s after the last change
(a slider drag is one write; closing the window, losing focus or hiding the browser tab flushes). The autoload runs
while the tree is paused (`PROCESS_MODE_ALWAYS`), because the settings screen is opened from a pause menu.
`load_from_disk` starts from the defaults and takes only
entries of the right type and a finite number (`nan` and `inf` fall back to the default), so a hand-edited or old file
cannot break anything. The file is `user://settings.cfg`
(`ConfigFile`); on the web build that lives in the browser's storage.

**Tests and captures never touch that file (#418).** `SettingsService.default_path()` is the one place that decides:
the person's file, except in the GdUnit runner, a scene of `res://tests/`, a `gds godot` run (`GDS_QUIET=1`) or a run
with `DEADNIGHT_NO_USER_FILES` set, where the path is empty: the defaults load and `save()` writes nothing. Before,
a service freed with a change pending saved itself (`NOTIFICATION_PREDELETE`), so `test_camera_shake` wrote
`camera_shake=0` into the real file, and the suites that restored the real path and called `save()` wrote their test
values there too; the next run read them back and a shake test failed. A suite that needs a file sets `path` to one
of its own under `user://`. `test_settings_user_file` runs a child Godot that does what those suites did and checks
the real file is byte for byte unchanged (with a control that the child does write a file it is pointed at). The only
other `user://` files are the captures' own `*_capture.cfg` and PNGs, which are named per capture.

| Key | Default | Applied as |
| --- | --- | --- |
| `video/window_mode` | windowed | `DisplayServer.window_set_mode` (skipped on the web, where the page owns the window) |
| `video/resolution_scale` | 100 | root `Viewport.scaling_3d_scale` (3D only: the interface stays sharp) |
| `video/vsync` | on | `DisplayServer.window_set_vsync_mode` |
| `audio/master`, `music`, `effects`, `ui` | 100, 80, 100, 80 | bus volume (`linear_to_db`), muted at 0; buses in `game/default_bus_layout.tres` |
| `accessibility/reduced_motion` | off | `UIMotion.reduced` |
| `accessibility/ui_scale` | 1.0 | root `Window.content_scale_factor` (0.8, 1.0, 1.25) |
| `accessibility/camera_shake` | 100 | nothing: the player reads it (`PlayerSettings.camera_shake`, off while reduced motion is on); [Camera shake](../design/camera-shake.md) |
| `accessibility/challenge_prompts` | 0 | nothing: `ChallengeHudLink` reads it and sets `HudChallenge.mode` (0 all, 1 finished challenges and milestone steps only, 2 off); [the prompt](../design/progression.md#the-progress-prompt-in-the-night) |
| `controls/mouse_sensitivity`, `invert_y` | 1.0, off | nothing: gameplay reads them and listens to `changed` |
| `controls/touch_controls` (0 auto, 1 on, 2 off), `touch_scale`, `touch_opacity`, `haptics` | 0, 1.0, 0.7, on | nothing: `TouchControls` reads them and listens to `changed` (the Touch tab) |
| `controls/touch_aim_assist` (0 to 1), `controls/touch_auto_fire` (0 off, 1 while aiming, 2 always) | 0.5, 0 | nothing: `TouchAimAssist` reads them and listens to `changed` (the Touch tab); [Touch aim assist](aim-assist.md) |
| `controls/left_handed` | off | nothing: `TouchControls` flips the layout and the night screen flips the HUD's corner columns (the Touch tab) |
| `controls/touch_hints_seen` | 0 | nothing: a bit per first-run hint that was used (`TouchHints`); no row on the screen, the defaults button clears it |

## The screen

- **Tabs** are switched with the actions `ui_tab_prev` and `ui_tab_next` (project settings: PageUp/PageDown and the
  left/right shoulder buttons), not the engine's `ui_page_*`, which have no gamepad button. A switch from a row or from
  the tab strip puts focus on the new tab's button; a mouse user with no focus is left without.
- **Focus links** are set by hand (`_link_focus`): from the tab strip the arrow keys would pick the nearest control by
  position, which is the footer, skipping every row. The strip leads down to the first row, the last row to the footer.
- **A value between two options** (a hand-edited `ui_scale` of 1.1) shows the nearest option. The value stays as written.
- **Web:** rows marked `desktop_only` (window mode) are not built in a browser; `is_web` on the screen and on the
  service is injectable for tests. On the web the service also writes on `visibilitychange` and `pagehide` (a
  `JavaScriptBridge` callback), the last event a page gets before it vanishes; that hook has no automated test.

## Widgets

All three are drawn, like `UIButton`: springs for hover, press, focus ring and the knob, the shared `UIFocusRing`, the
ring only after keyboard or gamepad input, hover also taking focus, and reduced motion snapping every spring.

- **UISlider** extends `HSlider`, so value, step, keyboard and mouse come from the engine. Its theme variation empties
  the styleboxes and gives the grabber an invisible texture as wide as the drawn thumb, so the engine's hit-testing
  matches the drawing: a real click at 60% of the travel gives 1.85 of 0.1 to 3.0 (the capture script prints it).
- **UIToggle** extends `Button` (`toggle_mode`); the knob rides a spring with 0.7 of the usual damping, so it settles
  with a little overshoot.
- **UIOptionSelector** is a `Control`: left/right, accept (forward) or a click on either end steps and wraps; the old
  text slides out and the new one in from the side it came from.
- **UIRow** lays out a title, an optional hint and a control column of `control_width`, so every control lines up.

New tokens (`UITokens`, group Controls): `control_height`, `control_width`, `track_height`, `knob_inset`. A new audio cue,
`&"tick"`, fires on each slider step.

## Things that bit

- Godot's key codes are not what memory says: `KEY_PAGEUP` is 4194323 and `KEY_PAGEDOWN` 4194324. A hand-written
  `project.godot` action with the wrong number loads without a warning and simply never fires (the gamepad half works,
  which hides it). Check with `InputMap.action_get_events` and `event.is_action_pressed` in a probe.
- A paused tree stalls GdUnit4's own `await_millis`; wait with `get_tree().create_timer(t, true)` (ignores pause).
- `find_valid_focus_neighbor` needs a layout: await two idle frames after building or switching pages.

- A `PlaceholderTexture2D` as the "invisible" grabber is drawn in game as a magenta and black square. Use a transparent
  `ImageTexture` of the right size.
- A wrapping (`autowrap_mode`) hint label gives a tall minimum size while a container is still sizing it. Going from
  interface size Large back to Normal left the whole screen's column 1425 px tall and pushed off centre. Hints now trim
  with an ellipsis instead, and a test round-trips the scale.
- `content_scale_factor` does resize the router's stage and every anchored control. With `canvas_items` stretch the
  visible area is 1920 / scale wide, so at Large (1.25) a screen has 1536 x 864 to fit in.
- **Rows collapsed onto one line, sometimes.** `UIMotion.stagger_in` read each row's `position` one `process_frame`
  after the tab was shown and tweened back to it. A container sorts its children in a deferred call that runs
  *after* `process_frame` is emitted; a click arrives earlier in the same frame, and only a physics step in that frame
  flushes the deferred calls first. On a fast display about every other frame has no step, so a page never shown before
  (its rows still at 0, 0 since hidden pages are not sorted) was read as "rest" and the rise ended there. `stagger_in`
  now waits two frames (the second is after the flush), stops an earlier rise of the same row, and has the container
  re-sort when the rise ends. `test_settings_layout.gd` clicks through every tab with real mouse events and one physics
  step a second, which makes the bad frames the common case; `settings_click_tour.tscn` captures it. Pointer-moving
  scripts in tests need window pixels: `viewport.get_final_transform() * control.get_global_transform_with_canvas()`.
- Movie Maker writes frame N after the scripted code for that moment ran: to see the state before a change, read N - 1.

## Resolution scale in the Compatibility renderer (#36)

Deadnight is Compatibility-only (desktop and the WebGL2 web build), and `video/resolution_scale` sets the root
viewport's `scaling_3d_scale`. It works in both, at every step the slider offers (50 to 100 in steps of 5), and exactly
0.5 is not a no-op:

| Scale | Mean absolute difference from 100 % (1280 x 720) | Detail along a row of the floor |
| --- | --- | --- |
| 100 % | 0 | 0.144 |
| 75 % | 0.117 | 0.135 |
| 50 % | 0.151 | 0.126 |

(A checker floor, a lit box and a sphere under one sun, bilinear scaling, Godot 4.7.2, RTX 5080.) At a 640 x 360 window
the difference of 0.5 is 0.178, against 0.151 at 75 % there too. The probe in #26 saw a byte-identical picture at exactly
0.5 and could not be reproduced with the real service, any number of frames after the change (0, 1, 2 and 6), any window
size tried, or the root viewport's own scaling mode left alone; it was most likely a probe that read the picture before
the viewport was resized. **The only way to get a picture from a change is to wait for the frame after it** (the capture
waits six, and `RenderingServer.frame_post_draw`).

- **The range stops at 50 on purpose.** The service clamps to `RANGES` (50 to 100); a 25 % request draws as 50 %.
- **Web:** `tools/web_smoke/resolution_scale.py` opens the export in Chrome (WebGL2, the machine's GPU) in two fresh
  contexts, lowers the slider with the keyboard to 50 % in one, starts a night in each and compares the middle of the
  lower half of the screenshots: the 50 % picture differs by 0.017 and has 9 % less detail from pixel to pixel; the HUD
  is as sharp in both (the interface is drawn at full size). Not in CI: starting a night in a software renderer takes
  minutes.
- **Guard:** `game/tests/captures/resolution_scale.tscn` (windowed, through the no-focus launcher) draws the scene at each
  scale through the real `Settings` service and fails its run when a lower scale does not change the picture or does not
  lose detail. It never touches the real display mode or the real mouse. A headless GdUnit test cannot do this: the
  headless renderer draws nothing.
- **Reading the numbers:** a mean difference of 0.01 or less means the picture did not change; the checks use that and
  "less detail than the step above".

## Proof

`game/tests/core/test_settings.gd` (defaults, round trip, file layout, bad entries, clamping, `changed`, reset, buses,
reduced motion, both scales, startup apply), `game/tests/core/test_settings_hardening.gd` (a write while paused,
focus-loss flush, `nan`/`inf`, the web skip) and `game/tests/ui/test_settings_screen.gd` (controls bound both ways,
wrapping, reset, tabs, the scale round trip, focus after a tab switch, shoulder buttons, focus links, off-grid scale,
the web layout), `game/tests/ui/test_settings_layout.gd` (every tab clicked in every order, fast and slow, at three
window sizes and scales, rows apart and inside the panel, one selected tab, no stale hover) and
`game/tests/ui/test_stagger_in.gd` (the entrance itself). Run them with GdUnit4 (`--ignoreHeadlessMode` for the
headless command line). `game/tests/captures/settings_tour.tscn` is the scripted capture of every tab; `settings_navigation.tscn`
drives the screen with key and gamepad events only and prints the focus owner at each step.

### The widgets, the save timer and the display in tests (#37)

- **The widgets have tests of their own** (`test_ui_slider.gd`, `test_ui_toggle.gd`, `test_ui_option_selector.gd`),
  driven with real events from `tests/ui/widget_events.gd`: the keyboard and the d-pad step a slider and stop at its
  ends, a click at 60 % of a slider's width lands at (x - thumb / 2) / (width - thumb) of its range (the invisible
  grabber the theme gives the engine matches the drawn thumb; this was only a capture printout before), a toggle flips on
  a click, the accept keys and the A button and not while disabled, an option selector steps with left, right, accept and
  the d-pad, wraps at both ends, steps back from a click on its left edge zone and forward from anywhere else, and
  reduced motion snaps every spring.
- **The save timer runs on the test's clock** (`test_settings_saving.gd`): the test calls `_process(seconds)` itself, so
  nothing waits and nothing depends on the machine. Nothing is written before `SAVE_DELAY`; a burst of changes (a slider
  drag) is one write of the last value, because every change restarts the wait; a close request writes a pending change
  at once and writes nothing when nothing is pending; freeing the service (`NOTIFICATION_PREDELETE`) writes the last
  change. `tests/core/quiet_settings.gd` counts `save` calls.
- **A service with an unsaved change writes the file as it is freed.** A test that removed its file and then let the
  service be freed (`auto_free` runs after `after_test`) left the file behind again. The suites now free their services,
  then remove the file.
- **No test changes the display it runs on.** `SettingsService.window_setter` (a `Callable`, empty in the game) takes the
  window mode instead of `DisplayServer.window_set_mode`; `QuietSettings` records the calls, and the screen suite sets
  one on the `Settings` autoload for its duration. `test_save_then_load_round_trips` used to put the running window in
  fullscreen in a windowed run.
- **A screen that starts from a saved file that is not the default** is tested (`test_settings_screen.gd`): the sliders,
  the toggle and the selector show the file's values, not the defaults they start with.
- **`UIButton` draws its ring with `UIFocusRing`**, like every other component (it had a copy of the same drawing).
  `test_ui_button_ring.gd`: the ring is the shared one; keyboard focus lights it and pointer focus does not. Buttons do
  not snap their springs under reduced motion (the other widgets do): the focus and hover springs of a button still
  settle over a few frames.
