# Main menu and the drive-in skin

How the main menu is built on the `gds_ui` addon ([UI foundation](ui-foundation.md)) and what we learned doing it. The
skin lives in `game/ui/skin/` and the screens in `game/ui/screens/`; the addon is untouched.

## Parts

| Part | What it is |
| --- | --- |
| `deadnight_tokens.tres` | A `UITokens` resource set in the project setting `gds_ui/tokens`: darker surfaces, a neon red `hot`, a bigger display size. Everything else is the addon's default palette |
| `NeonSign` | The title: hollow glass tubes drawn with `draw_string_outline` (three wide low-alpha strokes for glow, a coloured tube, a white-hot core, a radial halo texture). Ignition and the failing tube are pure functions of an accumulated clock, so captures repeat |
| `NightSky` + `drive_in_night.gdshader` | The lot at night in one procedural pass: stars, treeline, the big screen throwing light, parked cars, the projector's beam. Colours come from the tokens; one backdrop for every screen |
| `FilmOverlay` + `film_grain.gdshader` | Grain, vignette, flicker and a scratch, the last node of the router's own `CanvasLayer` (100), after its screens and its transition, so it covers both (a layer of its own was a canvas pass and a fence the web page kept, #883) |
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
- **How:** a preset `Web` in `export_presets.cfg` (not committed), then `godot --headless --path game --export-release
  Web`
  into the scratch folder; Chrome is driven with `--remote-debugging-port` and a Node script using the built-in
  `WebSocket` (`Page.captureScreenshot`, `Page.startScreencast`, `Input.dispatchKeyEvent`).

## The rework: the player in a live drive-in (#397)

The menu stops being a column of buttons over a painted sky and becomes a place: the player's own Soldier stands in the
lot at night, a tab bar runs along the top, the panels of the tab sit on one side, and the camera moves when the tab
does. The maintainer's reference is a character-centred console menu (the character large in a lit 3D scene, a top tab
bar, progress panels at the sides, level and currency top right, input hints at the bottom). We took that **layout and
feel only**: the scene, names, art, type and text are Deadnight's own (the drive-in, the Marquee, stubs, Billing).
Three steps: this design, [the live stage](menu-stage.md) and
[the tab shell with its panels](menu-shell.md).

### Structure

```text
MainMenu (UIScreen)
  MenuStageView        the 3D stage in its own viewport, full screen, never takes the mouse
  scrim                a soft darkening on the panel side only (the text rule below)
  TabBar               Play  Loadout  Shop  Challenges  More          name  Billing  stubs
  TabPanel             one panel scene per tab, the one on show
  InputHints           the active device's glyphs, bottom
```

One list of tabs (`MenuTab`) feeds the camera, the bar and the panels. A tab switch sends the camera to the tab's pose
(`StagePose`) and slides the panel; the router is not used between tabs (a tab is not a screen), only to leave the menu
(Play, Join, Settings, Credits). Quit is on More and absent on the web, as today.

### Layout per tab

The picture is 1920 x 1080 design units (the canvas stretch). The soldier stands where the panels are not.

| Tab | Soldier at | Panel zone | Panels | What the player does there |
| --- | --- | --- | --- | --- |
| **Play** | left, 30% across, aiming into the lot | right column, 600 wide | **Play together**, **Quick join**, **Solo** (Play together opens its screen; Quick join joins from the menu itself, see [the lobby](../design/lobby.md#quick-join-from-the-menu)); **Today's challenges** under them: the three dailies, each with its progress and the time to the next refresh | start a night, see what today asks |
| **Loadout** | centre-left, 36%, turning | right column, 700 wide | the wardrobe's content in this layout: preset, part selectors, colour strips, Randomize (every choice is kept in memory while the tab is open and written once on leaving it); a **showcase weapon** row (the weapons that have a model) with that weapon's mastery steps | dress the soldier and see it turn; drag, right stick, or the turn keys |
| **Shop** | left, 27% | right, 1100 wide | the prize counter: stub balance, categories (costumes, finishes, flashlight housings, reels, horn and emotes), a grid of items, each locked, owned or priced | browse and buy cosmetics; **placeholders until the economy exists** (marked "coming" on the screen, not hidden) |
| **Challenges** | right, 74% | left, 1060 wide | the **dailies** with the time to the next refresh, the **Concession Orders** (three open), the **milestones**; a family filter (Light, Night, Together, Craft, Place) | see all progress, swap an order, browse by family |
| **More** | left, 30%, small, wide shot | right column, 560 wide | Settings, Credits, Quit (not on the web), the account line (name; sign-in when the platform has it) | everything that is not a night or a look |

Top right on every tab: the **name**, the **Billing level** with a ring of progress to the next, and the **stubs**.
Bottom on every tab: the input hints for the device in use (below).

### Camera per tab

All poses look at the soldier from the lot's side so the screen and the dead are in the shot; the numbers are
`StagePose` (azimuth in degrees round the soldier, distance and height in metres, vertical field of view, where the
soldier sits across the picture, how he is turned).

| Tab | Azimuth | Distance | Height | Fov | Soldier across | Soldier turn | Why |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Play | 16 | 5.0 | 1.45 | 32 | 0.30 | 78 | wide enough for the screen and the dead, soldier side-on, looking down the lot |
| Loadout | -10 | 4.8 | 1.30 | 30 | 0.36 | 8, then by hand | the whole body, turning |
| Shop | 32 | 5.0 | 1.35 | 32 | 0.27 | 80 | the ticket booth behind: the prize counter |
| Challenges | -28 | 5.2 | 1.30 | 32 | 0.74 | -82 | the lamp and the lot on the left of the list |
| More | 6 | 9.5 | 2.60 | 34 | 0.30 | 70 | pulled back and up: the whole lot |

Moves are critically damped springs (about 0.85 s, the same at any frame rate), a cut with reduced motion, and a slow
sway of 5 cm keeps the picture alive. Good character-centred menus keep the character off the centre line and give the
panels the free side
([framing](https://gamedeveloper.com/design/framing-and-centering-directing-player-attention-in-open-3d-worlds));
the shift is computed for at most 16:9 so the soldier stays beside the same panels on a wider window.

### What each panel reads

Nothing in the menu invents data; every number has a source, and an empty source shows the starting value.

| Panel | Reads | From | Until it exists |
| --- | --- | --- | --- |
| Soldier, Loadout | the saved look, the showcase weapon | `character/look` and `loadout/weapon` in the settings file (`LookStore`, `Settings`) | built |
| Top right | name, Billing level and progress, stubs | the cached profile (`xp`, `stubs`, display name; the level is derived, `150 + 30 x level` XP to the next, see [progression](../design/progression.md#xp-and-the-ladder-of-55); the approved plan replaces the curve with the 55-level table and drops stubs) | a small `MenuProfile` reader over the settings key `profile/cache` (JSON, read-only, no network): level 1 and 0 stubs when empty |
| Challenges and Today's challenges | active dailies with progress and the time to the next refresh, the three open orders, the milestones | the challenge tracker's read API (#399, one small class) | a stub with the same shape feeds the screen and the tests until #399 lands |
| Loadout, weapon mastery | mastery level and points of the showcase weapon | the cached profile | zero levels, labelled |
| Shop | stub balance, owned and priced cosmetics, locks | the cached profile and the look catalogue's gates (`LookCatalog`: a Billing level, stubs or an order) | catalogue entries from `LookCatalog`; **prices are placeholders** and say so |
| Play | nothing saved | the flow seam | today's two routes |

Rules that hold on every panel: **the client shows, the server awards** (rule 9 of progression: the menu never writes
XP, stubs or progress), a late or missing profile never blocks Play (rule 10), and a number has one home (the Billing
level is in the top right and nowhere else, the stub balance likewise).

Dailies change a rule of the progression design (rule 6, "nothing expires"): the maintainer wants them and #399 records
the change. The menu shows what the tracker says, with the refresh time as a plain countdown ("next reel in 6:12:44");
nothing on the menu is worded as a loss, and a daily left unfinished is not scolded (the streak research below).

### How it scales

| Window | Handling |
| --- | --- |
| 1280 x 720, 1920 x 1080, 2560 x 1440 | one layout, the project's canvas stretch (`canvas_items`, expand, 1920 x 1080 base): the panels keep their design size, the stage fills the window |
| Wider than 16:9 | the soldier keeps his place beside the panels (the camera shift is worked out for 16:9); panels stay at the screen's edge |
| Narrower than 16:9 | the shift uses the real aspect, panels stay at least 5% inside the edge |
| **Phone landscape** (shorter side under 500 px) | the **design height is 540 units** (a UI factor of 2 on the base), not 1080: at 844 x 390 one unit is 0.72 px. Minimums in real pixels: caption 14, body 18, a tap target 44 high ([WCAG 2.2 target size](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html)), so 61 units. The panel is 520 units wide; the tab bar shows the label of the active tab only; the dailies show two rows and the rest are on the Challenges tab; side margins follow the display's safe area |
| Phone portrait | not a layout: the existing "turn your phone" prompt stays |

The first mocks (a factor of 1.8) had 9 px captions on a 390 px phone, which is why the minimums are written here. The
stage drops to half resolution or a still when frames run long ([menu stage](menu-stage.md)), so the panels never wait
on the 3D.

### Input per device

| Device | Tabs | Inside a panel | Soldier (Loadout) | Hints show |
| --- | --- | --- | --- | --- |
| Keyboard | Q and E, or Ctrl+Tab and Ctrl+Shift+Tab | arrows, Enter, Esc back to the tab bar | Left and Right turn keys | key caps |
| Mouse | click a tab; hover moves focus | click, wheel scrolls lists | drag the soldier | the same caps; the menu never captures or confines the pointer, and nothing in it does when `GDS_QUIET=1` |
| Gamepad | **LB and RB** | D-pad and left stick move focus, A accepts, B goes back to the tab bar, Y is the tab's own action (Randomize, Swap order) | right stick | the pad's glyphs |
| Touch | tap a tab; swipe sideways on the stage to turn the soldier in Loadout | tap, drag to scroll | swipe | none |

The hints follow the last device used (`UIInputMode`, which ignores a few pixels of pointer noise) and name what a press
does now, not every key. Every tab is reachable by every device; a test per device walks all five.

### Text over a 3D picture

A lit moving scene is the worst background for type, so the panels do not rely on it:

- a **scrim**, a horizontal gradient on the panel side (up to 78% of the dark surface colour), plus a darkened strip
  behind the tab bar and the hints; paper and amber surfaces carry their own contrast;
- text is held to a **contrast ratio of 4.5 to 1** against what is behind it ([Game Accessibility
  Guidelines](https://gameaccessibilityguidelines.com/provide-high-contrast-between-text-ui-and-background));
  a test samples the stage behind the scrim and checks it, and a grayscale screenshot must still separate text from
ground;
- panels sit on the free side of the stage: the soldier is never behind a panel, and a panel never covers his face;
- a gradient behind text is the standard remedy for text over moving pictures ([Amazon's APL
  guidance](https://developer.amazon.com/en-US/alexa/alexa-haus/visual-design/apl-components/apl-background)).

### Visual direction

Two directions were mocked over the live stage (the captures are in the first pull request): **A, the program**
(paper tickets with notches, a punch card of holes for progress, the Billing level as a ring on a name plate) and **B,
the letterboard** (dark hairline panels, film-frame strips). **The maintainer picked A.** The rules it sets:

- **Surfaces are paper.** A ticket (a cream stub with a half-round notch cut in each side and a perforation) is the one
  surface for a button, a plate and a challenge stub; the Challenges tab is one sheet of paper, "the program". Dark
  surfaces are the stage and the scrim only; the wardrobe's pickers keep the game's dark components beside a paper
  heading.
- **Progress is a punch card:** a row of ten holes, punched from the left as the goal fills (a hole is a tenth of the
  goal, rounded). The count beside it ("14/20", "1,850/3,000") is real type and the only place the exact number lives.
- **One accent, red** (`hot`) on the primary ticket and on tags; amber only for the refresh countdown on the dark.
- Type does the rest: Bungee Inline for titles and numbers, Barlow Condensed in wide-tracked capitals for labels.
  No glow, no icons for their own sake, no cards in a grid.
- **Numbers never clip.** A count sits in a container with the text beside it, never at a fixed offset: the text
  takes what is left and is cut with an ellipsis, the count takes what it needs (the longest is `1,000,000/1,000,000`
  in the display face, 331 units). The first mock placed counts by hand and ran off the paper; a test now fills a
  row with the longest value on every canvas and checks the count is inside its row.

### Open questions

- Dailies: how many a day and the reset hour. **They expire at each reset** (the maintainer chose that over
  banking), so the menu shows no "banked" or "leaves soon" state, only the time to the reset.
- The showcase weapon is cosmetic. Should the Loadout tab also pick the weapon a night starts with, once the starter
  program lets a player choose a sidearm (progression, Billing 4)?
- Shop prices and the shape of the economy are not designed; the Shop tab is a labelled placeholder.
- A weak GPU or a phone is not measured; the stage's governor is the guard until someone has one.

### Sources

- Layout reference: the maintainer's five screenshots of a console game's menus (layout only, none of its details used).
- [Game Accessibility Guidelines, high contrast between text and
  background](https://gameaccessibilityguidelines.com/provide-high-contrast-between-text-ui-and-background) (the 4.5
  to 1 ratio, outlines and shadows).
- [EA's thesis topic, text readability in 3D
  worlds](https://ea.gr8people.com/jobs/154560/master-thesis-text-readability-in-3d-worlds) (a job listing, not a
  study: it says only that a full-screen drop shadow was what shipped when text fought bright backgrounds).
- [Amazon, APL
  background](https://developer.amazon.com/en-US/alexa/alexa-haus/visual-design/apl-components/apl-background) (a
  bottom gradient overlay as the safe zone for text, the same 4.5 to 1).
- [Framing and centering: directing player attention in 3D
  worlds](https://gamedeveloper.com/design/framing-and-centering-directing-player-attention-in-open-3d-worlds)
  (off-centre placement gives the eye room).
- [Designing a streak system: the UX and psychology of
  streaks](https://shop.smashingmagazine.com/2026/02/designing-streak-system-ux-psychology/) (streaks work through
  progress, pride and fear of missing out; read from its search summary only, not in full): the reason the menu counts
  down to a refresh and never shows a loss.
- [WCAG 2.2, target size (enhanced)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html) (44 px
  targets).
- [Godot, multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)
  (the canvas stretch and its aspect modes).

What the searches did not give: a published recipe for a scrim over a live 3D menu. The numbers above are ours, to be
checked on screenshots at 720p, 1080p, 1440p and a phone-sized window with the panels in place.

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
  `uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 --with pillow python
  tools/web_smoke/skin_tour.py build/web <out> --browser chromium|chrome|firefox [--size 1920x1080]
  [--unpaced]`. Firefox needs `playwright install firefox` once. The CI `web`
  job runs the Chromium tour at 1280 x 720 after the smoke run.
- **A key is lost on a slow frame.** Godot reads input once per frame, and the runner's software renderer draws a frame
  in 200 to 250 ms, so the 150 ms key hold the smoke run uses can fall between two frames: the first CI runs of the tour
  walked to the wrong item and waited for a screen that never opened. The tour holds each key for `--hold-ms` (500 in
  CI), gives each a moment to land, and when the wrong screen opens (or none) goes back with Escape and walks again,
  up to three times. `--throttle 6` slows a local Chromium to reproduce a slow runner (it still passes).
- **Keys on the menu:** the menu is a tab shell now ([menu shell](menu-shell.md)): a script walks it with
  `smoke.menu_item(page, tab, steps)`, which presses E until the game reports the tab, so the first control of the tab has
  the focus whatever the menu remembered, and then presses Down `steps` times.
