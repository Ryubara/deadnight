# Mouse sensitivity at every window size

The same hand turned the view different amounts in different windows (#928, found while measuring the look under lag
in #905). The general rules are in the kit page "Mouse look at any frame rate" (`docs/godot/mouse-look.md`).

## Cause

The project stretches the canvas to a 1920 x 1080 base (`window/stretch/mode="canvas_items"`, aspect `expand`). The
engine hands a mouse motion to the game in the **canvas's units**: `InputEventMouseMotion.relative` is the screen motion
times `1920 / window width`. `Player._unhandled_input` turned the view by `relative`, so the turn of one mouse pixel was
`0.0022 rad * 1920 / width`:

| Window width | Turn per mouse pixel, before | After |
| --- | --- | --- |
| 800 | 2.4 times | 1 |
| 1280 | 1.5 times | 1 |
| 1920 (the base) and fullscreen at 1920 | 1 | 1 |
| 2560 | 0.75 times | 1 |
| 64 (the headless test window) | 30 times | 1 |

`screen_relative` is the same motion in screen pixels, which the Godot docs recommend for mouse look.

## The fix

- `Player` turns by `MouseMotion.pixels(event)` (`game/gameplay/player/mouse_motion.gd`): `screen_relative`.
- **The default feels as it did at 1920 pixels wide** (the base width: the window that the old and new code agree on, a
  fullscreen 1920 x 1080 monitor). Where it was tuned is not recorded; `mouse_radians_per_pixel` is 0.0022 since the
  first controller (#72). A player in a 1280 window now turns 0.67 times as far as before, one at 2560 wide 1.33 times.
  Change the one number if the maintainer's usual window is another.
- **The web**: the runtime reports a pointer move in device pixels (the browser's `movementX` times `devicePixelRatio`).
  Before, the stretch happened to cancel the ratio (the canvas is `ratio` times as many device pixels wide), so a page
  felt the same on every screen of a given CSS width. Reading `screen_relative` alone doubled the turn on a screen with
  a ratio of 2 (probe: 0.66 rad for 300 CSS pixels at ratio 1, 1.32 at ratio 2), so `MouseMotion` divides the ratio
  (`DisplayServer.screen_get_scale()`, the browser's `devicePixelRatio` on the web, ignored elsewhere).
- **Touch** sends its own motion (`TouchLook.DEVICE`) in mouse pixels already; `TouchControls._turn_view` sets
  `screen_relative = look` besides the stretched `relative`, and `MouseMotion` does not divide it. The touch total
  (`tests/ui/touch/test_touch_player.gd`: 100 units are 8.5 degrees) is unchanged.
- Not changed: UI drags that read `relative` in canvas units on purpose (the bot wheel's pointer, the look preview and
  the menu turntable).

## Proof

- `tests/player/test_look_window_size.gd` sends one seeded path of whole pixels the way the system does (both fields in
  window pixels, through `Input.parse_input_event`, which maps `relative` through the stretch) at six window sizes
  (1280x720, 1920x1080, 2560x1440, 1000x1400, 800x450, 64x64) and the three stretch modes (`canvas_items`, `viewport`,
  disabled) and checks the rig turned `pixels * 0.0022 * sensitivity`. A second test checks the engine really hands the
  game a `relative` that depends on the window (twice as big at 1280 as at 2560) and a `screen_relative` that does
  not, so the first cannot pass by accident. A third replays the touch look at every size. With the old line in
  `Player` 10 assertions fail (turns of -3.09, -1.54, 2.33, 1.35 and 1.12 rad for the same path); with the fix none.
- `tools/web_smoke/look_size.py` runs a night in headless Chromium, resizes the page (1280x720, 1920x1080, 800x450,
  1000x1400 CSS pixels) and sends 20 pointer moves of 15 pixels at each, at ratios 1 and 2: the yaw turn is the same
  at every size and ratio (see the pull request for the numbers).
