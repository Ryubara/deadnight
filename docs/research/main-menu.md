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
