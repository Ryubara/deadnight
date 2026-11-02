# Main menu and the drive-in skin

How the main menu is built on the `gds_ui` addon ([UI foundation](ui-foundation.md)) and what we learned doing it. The
skin lives in `game/ui/skin/` and the screens in `game/ui/screens/`; the addon is untouched.

## Parts

| Part | What it is |
| --- | --- |
| `deadnight_tokens.tres` | A `UITokens` resource set in the project setting `gds_ui/tokens`: darker surfaces, a neon red `hot`, a bigger display size. Everything else is the addon's default palette |
| `NeonSign` | The title: hollow glass tubes drawn with `draw_string_outline` (three wide low-alpha strokes for glow, a coloured tube, a white-hot core, a radial halo texture). Ignition and the failing tube are pure functions of an accumulated clock, so captures repeat |
| `NightSky` + `drive_in_night.gdshader` | The lot at night in one procedural pass: stars, treeline, the big screen throwing light, parked cars, the projector's beam. Colours come from the tokens; one backdrop for every screen |
| `FilmOverlay` + `film_grain.gdshader` | Grain, vignette, flicker and a scratch, on a `CanvasLayer` (110) above the router (100) so it covers screens and transitions alike |
| `MainMenu` | Play irises open, Settings slides, Credits burns; Quit is left out when `OS.has_feature("web")` |
| `CreditsList` | A resource of lines (`# Heading`, then names) that the credits screen reads |

## What we learned

- **A grain and a vignette in one shader must be composited, not mixed.** Mixing the speck colour towards black by the
  vignette amount turned the corners into heavy speckle; the grain has to be its own layer under "over" blending.
- **Do not hash with `sin` on large arguments.** `fract(sin(dot(p, k)) * 43758.5)` of a pixel coordinate plus a frame
  offset showed as diagonal stripes on an RTX card; a sine-free hash (Hoskins' `hash12`) has no such pattern.
- **Write `smoothstep(a, b, x)` with `a < b`.** The reversed form (`smoothstep(0.35, 0.0, d)`) is undefined in GLSL; it
  worked on desktop but is not safe on WebGL2 drivers.
- **Neon is an outline, not a fill.** A bold fill with a glow looked like glowing text; hollow strokes with a white-hot
  core on a coloured tube read as glass at once.
- **Movie Maker and the frame count.** `--quit-after N` counts engine frames; with `--fixed-fps 12` N frames are N/12
  seconds. Use a low fps for looks, and 15 to 20 for transitions.
- **Container children and entrances.** `UIMotion.stagger_in` moves children of a container: it works because it reads
  the position after the container has sorted them, so call it from `screen_enter`, not `_ready`.

## Gamepad, reduced motion and the web build

- **Godot 4.7.2 gives `ui_accept` and `ui_cancel` no gamepad button.** `ui_accept` is Enter, Kp Enter and Space;
  `ui_cancel` is Escape; only the focus directions have joypad events. `project.godot` now has an `[input]` section that
  lists those defaults again and adds joypad A and Start to accept and B to cancel, for any device (-1). Writing an
  action in `[input]` replaces its defaults, so keep the keys in the list. `test_gamepad_navigation.gd` sends real
  `InputEventJoypadButton` events through `Input.parse_input_event` (that works in the headless runner): D-pad moves
  focus, A opens Credits, B goes back, Start accepts, B on the root screen does nothing.
- **Reduced motion is live.** `UIMotion.reduced` is a static var with a setter; `UIMotion.changed()` returns a signal
  (a static var cannot declare one, so a small `RefCounted` bus holds it). `FilmOverlay`, `NightSky` and `NeonSign`
  connect in `_ready`. Reduced stops the overlay's flicker, scratch and changing grain (its shader clock stands still),
  the sky's flicker, white-outs and twinkle, and the sign's buzz and failing tube: the sign is lit, not redrawn per
  frame. Turned off again, a sign that was still carries on as an already lit one. `test_reduced_motion_skin.gd`.
- **Undefined GLSL ES 3.0 math, removed.** `pow(x, 2.0)` of a negative base became `d * d`; the projector beam's
  `smoothstep` edges are ordered (`spread = max(along * 0.17, 0.001)`); the iris `atan` has its x nudged so it is
  defined at the exact origin. One sine-free hash (`addons/gds_ui/shaders/gds_hash.gdshaderinc`, `hash11` and `hash21`)
  is included with `#include` by the sky, the film grain and the burn. The include works in the web export.
- **The burn held the screen on char for about 0.15 s.** At 20 fps the old timing gave 3 frames of pure char between
  the close and the reveal. The close now stops at `progress = 0.97` (the front already covers every corner) and the
  reveal starts at `0.27` (the first progress at which the front has reached the noisy origin); both halves keep their
  speed, so the whole burn is shorter. Now 1 char frame and 1 with only a speck of fire at 20 fps.

### What the web run showed

Exported with the pinned templates (`web_nothreads_release`, so single-threaded, no cross-origin headers needed), served
from a local web server, and run in Chrome 156 headless over the DevTools protocol, which uses the real GPU
(ANGLE D3D11, an RTX 5080) and reports `WebGL 2.0 (OpenGL ES 3.0 Chromium)`.

- **No shader or script error in the console** (three lines: version, driver, build). The menu, the iris to Play, the
  slide to Settings and the burn to Credits all render; no black frame other than the burn's one char frame, no white or
  NaN pixels in any captured frame. Quit is absent, as designed.
- **Frame time at 1920x1080** on that GPU: the browser ran at about 5.4 ms a frame (p95 8.4 ms) on the menu and in
  the transitions; the worst frames (33 to 140 ms) are the first use of each transition, shader compile plus the
  screenshot itself. With Chrome's software renderer (SwiftShader, a CPU, far slower than any phone GPU) the menu runs
  at about 124 ms a frame at 1080p: the sky plus the overlay is the cost, so a weak GPU could feel it. The sky was not
  moved into a shared low-resolution SubViewport because the real GPU is nowhere near the budget; do it when a phone
  or integrated-GPU number says so.
- **Not run:** a mobile GPU (see the skin tour below); a gamepad cannot be injected into a headless Chrome, so
  the web gamepad path is the same Godot input mapping as the desktop test, not a separate browser run.
- **How:** a preset `Web` in `export_presets.cfg` (not committed), then `godot --headless --path game --export-release Web`
  into the scratch folder; Chrome is driven with `--remote-debugging-port` and a Node script using the built-in
  `WebSocket` (`Page.captureScreenshot`, `Page.startScreencast`, `Input.dispatchKeyEvent`).

## Polish: the entrance, the credits scroll, placeholder focus, the cars (#85)

- **Transparent is not out of reach.** During the 0.55 s entrance the items were `modulate.a = 0` but still focusable
  and clickable: a key press made the router focus Play, and Enter opened it unseen (the capture shows the iris to Play
  at 0.2 s). `MainMenu` now sets each item's `mouse_filter` to ignore and `focus_mode` to none when it hides them, keeps
  what they were, and gives them back in `finish_entrance()`. `focus_initial()` does nothing until the items have
  risen, so a key pressed too early is swallowed (the router handles it) instead of calling `grab_focus()` on a control
  that cannot take it. A menu covered by another screen still brings its items in at once (`screen_pause`).
- **Credits scroll.** The card is as tall as the window allows (a margin of `space_lg` round it): the title above, the
  list in a `ScrollContainer` (`Scroll`), Back below it, so Back is on screen however long the list is (checked with 40
  lines at 1280 x 720 pixels, the unstretched, tighter case). Back is the only control that takes focus, so Up and Down
  have no neighbour to move to: `CreditsScreen._input` scrolls the list by two caption lines (Page Up and Page Down by
  most of a page), on the keyboard and the D-pad alike, and marks the event handled. The mouse wheel scrolls it too.
- **Placeholder focus** is a reference (`first_action`), not `box.get_child(3)`; with no actions Back takes it.
- **Cars.** A parked car is now a body with the wheel arches cut out of it, a tyre in each arch (a thin ring of lit
  gravel shows round it), and a cabin whose windscreen and rear window are cut slantwise, so the roofline and the wheels
  read even as a dark shape. The near row stands at `0.975` instead of `1.04`, so its wheels are on screen and the row
  is no longer cropped by the bottom edge (the near cars at the corners still run off the sides, as a lot does).
- **Tests.** `test_main_menu_input.gd` sends real key and mouse events: Down and Up walk the items and stop at the ends,
  Enter and a click open an item, hovering takes the focus, Esc does nothing at the root, and during the entrance a key,
  a click and a hover change nothing. `test_credits_screen.gd` and `test_placeholder_screen.gd` cover the other two.
  The entrance tests fail on the old code (`Failed first`).
- **Headless mouse.** The GdUnit window in headless mode is 64 x 64 pixels while the UI is laid out at the stretched
  size, so a mouse event sent with `Input.parse_input_event` lands outside the window and nothing is hovered. Send it
  with `get_viewport().push_input(event, true)` (viewport coordinates, `in_local_coords`), then
  `gui_get_hovered_control()` and `mouse_entered` work. Keys still go through `Input.parse_input_event`.
- **Capture.** `tests/captures/menu_polish_tour.tscn` saves a PNG per beat at the window's real pixels (Movie Maker
  always records 1920 x 1080 and ignores `--resolution`), with a caption naming the focus. Await each beat's
  `_note()`: a coroutine called without `await` carries on and the PNG is taken a few frames late.

### The skin tour in Chrome and Firefox, at 1080p (#82)

`tools/web_smoke/skin_tour.py` opens the export, walks the menu with the keyboard (Settings: the slide; Credits: the
burn; Play: the iris), takes eight shots through each transition and one of each screen, and fails on a console error,
a page error, or a shot that is nearly all black or all white. It measures the page's frames in a pass of its own
(a screenshot stalls the page, so the shot pass says nothing about frame times). The export is the head of `main` with
the new `car()` of #380. Three browsers, 1920 x 1080:

| Browser | GL | Menu p50 / p95 | Slide p95 (max) | Burn p95 (max) |
| --- | --- | --- | --- | --- |
| Chrome 156, `--unpaced` | ANGLE D3D11, RTX 5080 | 3.7 / 4.2 ms | 4.5 (73) ms | 5.7 (109) ms |
| Firefox 157, paced to the display | ANGLE D3D11, an NVIDIA GPU | 4.2 / 8.3 ms | 8.3 (58) ms | 8.3 (100) ms |
| Chromium headless shell | SwiftShader, the CPU | 83 / 100 ms | 100 (150) ms | 150 (150) ms |

- **No shader error, no console error, no black or white frame** in any of the three: the console held the engine's
  start-up lines and warnings only (Chrome: "GPU stall due to ReadPixels"; Firefox: 32 `getBufferSubData` stall warnings
  and the deprecated WebAssembly `try` instruction, both from the engine, not from a skin shader).
- **The worst frames are first use**, 58 to 109 ms: the first slide, burn and iris link their programs. They are one
  frame each, and the loading screen of Play hides the iris's.
- **Sky cost.** Unpaced, a 1080p menu frame costs about 3.7 ms on an RTX 5080, with the sky, the grain overlay and the
  neon sign all in it; the rest of the frame budget is the display's. A CPU renderer takes 83 ms for the same frame,
  which is the worst case anyone could meet, not a phone. So the sky stays one `ColorRect` per screen: the shared
  low-resolution `SubViewport` the issue asked for "if over budget" is not built, because no measured machine is over
  budget. **Still not run: a mobile GPU.** When a phone number says the sky costs too much, the SubViewport is the next
  step.
- **How to run it:** export the web build (`godot --headless --path game --export-release Web`), then
  `uv run --with playwright==1.64.1 --with pillow python tools/web_smoke/skin_tour.py build/web <out> --browser
  chromium|chrome|firefox [--size 1920x1080] [--unpaced]`. Firefox needs `playwright install firefox` once. The CI `web`
  job runs the Chromium tour at 1280 x 720 after the smoke run.
- **A key is lost on a slow frame.** Godot reads input once per frame, and the runner's software renderer draws a frame
  in 200 to 250 ms, so the 150 ms key hold the smoke run uses can fall between two frames: the first CI runs of the tour
  walked to the wrong item and waited for a screen that never opened. The tour holds each key for `--hold-ms` (500 in
  CI), gives each a moment to land, and when the wrong screen opens (or none) goes back with Escape and walks again,
  up to three times. `--throttle 6` slows a local Chromium to reproduce a slow runner (it still passes).
- **Keys on the menu:** a screen you came back from remembers its focused item (since #380), so a script that walks the
  menu presses Up six times first (the focus stops at the ends) and then Down to the item it wants.
