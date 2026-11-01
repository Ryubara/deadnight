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
- **Not run:** Firefox (not installed here) and a mobile GPU; a gamepad cannot be injected into a headless Chrome, so
  the web gamepad path is the same Godot input mapping as the desktop test, not a separate browser run.
- **How:** a preset `Web` in `export_presets.cfg` (not committed), then `godot --headless --path game --export-release Web`
  into the scratch folder; Chrome is driven with `--remote-debugging-port` and a Node script using the built-in
  `WebSocket` (`Page.captureScreenshot`, `Page.startScreencast`, `Input.dispatchKeyEvent`).
