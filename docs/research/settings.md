# Settings

The settings screen (`game/ui/screens/settings_screen.tscn`), the `Settings` autoload (`game/core/settings.gd`) and the
widgets they needed (`UISlider`, `UIToggle`, `UIOptionSelector`, `UIRow` in `game/addons/gds_ui/`). The addon still names
nothing Deadnight: the screen and the service are the game's.

## The service

`SettingsService` (autoload `Settings`) holds one value per key (`section/name`), each with a default and a range.
`set_value` clamps and type-checks, applies at once, emits `changed` and schedules a write 0.6 s after the last change
(a slider drag is one write; closing the window flushes). `load_from_disk` starts from the defaults and takes only
entries of the right type, so a hand-edited or old file cannot break anything. The file is `user://settings.cfg`
(`ConfigFile`); on the web build that lives in the browser's storage.

| Key | Default | Applied as |
| --- | --- | --- |
| `video/window_mode` | windowed | `DisplayServer.window_set_mode` (skipped on the web, where the page owns the window) |
| `video/resolution_scale` | 100 | root `Viewport.scaling_3d_scale` (3D only: the interface stays sharp) |
| `video/vsync` | on | `DisplayServer.window_set_vsync_mode` |
| `audio/master`, `music`, `effects`, `ui` | 100, 80, 100, 80 | bus volume (`linear_to_db`), muted at 0; buses in `game/default_bus_layout.tres` |
| `accessibility/reduced_motion` | off | `UIMotion.reduced` |
| `accessibility/ui_scale` | 1.0 | root `Window.content_scale_factor` (0.8, 1.0, 1.25) |
| `controls/mouse_sensitivity`, `invert_y` | 1.0, off | nothing: gameplay reads them and listens to `changed` |

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

- A `PlaceholderTexture2D` as the "invisible" grabber is drawn in game as a magenta and black square. Use a transparent
  `ImageTexture` of the right size.
- A wrapping (`autowrap_mode`) hint label gives a tall minimum size while a container is still sizing it. Going from
  interface size Large back to Normal left the whole screen's column 1425 px tall and pushed off centre. Hints now trim
  with an ellipsis instead, and a test round-trips the scale.
- `content_scale_factor` does resize the router's stage and every anchored control. With `canvas_items` stretch the
  visible area is 1920 / scale wide, so at Large (1.25) a screen has 1536 x 864 to fit in.
- Movie Maker writes frame N after the scripted code for that moment ran: to see the state before a change, read N - 1.

## Proof

`game/tests/core/test_settings.gd` (defaults, round trip, file layout, bad entries, clamping, `changed`, reset, buses,
reduced motion, both scales, startup apply) and `game/tests/ui/test_settings_screen.gd` (controls bound both ways,
wrapping, reset, tabs, the scale round trip). Run them with GdUnit4 (`--ignoreHeadlessMode` for the headless command
line). `game/tests/captures/settings_tour.tscn` is the scripted capture of every tab.
