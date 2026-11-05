# Mobile controls

What makes touch controls good for a landscape, third-person shooter, and what that means for Deadnight's web build
and Discord Activity. This is a design summary from public guidance; other games are studied for design only (no
layouts, art or names are copied). Claims marked *common practice* are widely repeated rules of thumb we could not tie
to one primary source; claims marked *unverified* need a device test before the build relies on them. The player verbs
are in [Player controller](player-controller.md), the screen is in [HUD](hud.md) and [HUD design](../design/hud.md).

## What the input map has to cover

`game/project.godot` has these actions: `move_*`, `sprint`, `crouch`, `jump`, `aim`, `swap_shoulder`, `fire`, `reload`,
`interact`, `swap_weapon`, `throw_grenade`, `toss_grenade` and `pause`, plus `look_*` (the gamepad's right stick). There
is no melee action (the crowbar is a weapon). That is 12 verbs against a mouse and keyboard; a touchscreen has two
thumbs, so most of the work is deciding what to remove, fold into another control or show only when it matters.

## Findings

### Movement stick: floating, with a dead zone

- A **fixed** stick is predictable but the thumb must find it; a **floating** stick appears where the thumb lands in
  its zone (usually the left half), which is easier on the hand and leaves the screen clear when unused. Add a small
  dead zone to stop drift ([Cursa](https://cursa.app/en/page/touch-controls-for-mobile-games-input-patterns-and-feedback)).
- Common practice: the stick's base re-centres where the touch began, the knob is clamped to a radius, and the output
  is the offset divided by that radius, so the same drag feels the same on every screen size.
- **Sprint by pushing the stick to its edge** (past about 90 percent of the radius) removes a button. Common practice
  in shooters on touch; keep it a held state with a little hysteresis so it does not flicker at the threshold.

### Look: drag on the right half

- Dragging anywhere in the right half to turn the camera is the usual touch scheme for a shooter; the fire button is
  a separate touch that may also drag, so a player can shoot and turn with one thumb (*common practice*).
- Sensitivity is in **degrees per screen-height of drag** (or per millimetre), never per pixel, so a phone and a tablet
  turn alike. Thumb aiming is less precise than a mouse or a stick, and guides advise lower look sensitivity on small
  screens to avoid over-swiping ([Pistol Arena](https://pistol-arena.pages.dev/controls/mobile/), a player guide).
- Keep a **separate ADS sensitivity** (a multiplier of the hip one, lower) and a **dead zone of a few millimetres** so a
  resting thumb does not turn the view. Acceleration (faster flicks turn further) helps cover a small screen but makes
  aim harder to learn; make it a gentle curve, off in a first version, and an option.
- **Gyro** aiming is an optional extra: guides disagree on its value (some switch it off, some call it a matter of
  taste), so it is a setting, off by default
  ([GGRecon on CoD Mobile](https://www.ggrecon.com/guides/best-call-of-duty-mobile-season-9-settings-guide/)). The
  Game Developer article below lists a built-in gyroscope as a touch-tuned aim option. On the web, motion sensors need
  a permission prompt on iOS and are *unverified* inside a Discord Activity.

### Aim assist and auto-fire

- "Aim assist and auto shoot reduce the burden of tracking and acquiring targets"
  ([Game Developer, "UX Deep Dive: Painful reality of building FPS experiences on mobile", 2016](https://www.gamedeveloper.com/game-platforms/ux-deep-dive-painful-reality-of-building-fps-experiences-on-mobile---part-1)).
  The same article names finger **occlusion** (the thumb covers what it aims at) and a coarse finger hit area as the
  basic problems, and says the game it studied offered three control schemes and a HUD editor with opacity from 0 to
  100 percent.
- Call of Duty: Mobile ships a "simple" mode that fires when the crosshair is on an enemy and an "advanced" mode with a
  fire button; guides note simple mode wastes ammunition and recommend moving on to advanced
  ([GGRecon](https://www.ggrecon.com/guides/best-call-of-duty-mobile-season-9-settings-guide/)). Lesson for us: **auto-
  fire is an option, not the default**, and with limited ammunition it must not spend it on its own without the player
  choosing.
- Common practice for aim assist: a slight slowdown of the look speed while the crosshair is over a target (friction)
  and a small pull toward it while ADS (magnetism), strongest on touch, off for sniping. It is tuned by play, so make
  the strength a number in settings (built in #286: [Touch aim assist](aim-assist.md)).

### Buttons: size, place and opacity

| Source | Minimum | Notes |
| --- | --- | --- |
| [Apple HIG, Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | 44 x 44 pt | The 44 pt figure is repeated by every secondary source; we could not read it on the page itself (unverified wording) |
| [Android accessibility](https://developer.android.com/design/ui/mobile/guides/foundations/accessibility) | 48 dp | "Ensure all touch targets are at least 48 dp, even if this extends past the UI element visual." |
| Game Developer (above) | 40 px | A finger is a coarse pointer; small, far targets are hard by Fitts's law |

- 48 dp is about 9 mm. These are **floors for ordinary buttons**; a fire button in a shooter is much larger (common
  practice: 12 to 18 mm), and a thumb needs 2 to 3 mm of space between neighbours to avoid mis-taps.
- Thumb reach: in a one-hand portrait grip the thumb reaches an arc, and bottom corners are easy. Hoober's 2013 street
  study found 49 percent one-handed grips, 36 percent cradled and 15 percent two-handed, and the right thumb on the
  screen 67 percent of the time one-handed
  ([UXmatters](https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php)). He
  later revised his guidance, and the study is about portrait use. For **landscape, two-handed** play we rely on
  common practice: both thumbs rest at the lower sides, the easy zone is the lower third near each edge, and the
  centre of the screen must stay free because it is the view.
- Draw controls **semi-transparent** (about 40 to 60 percent at rest, brighter while held) and let the player lower it
  (the opacity range above). Pressed buttons need instant feedback (a scale and brightness change, plus a haptic).
- Keep the **middle 40 percent of the width clear** of anything that is touched or that hides the world.

### Fewer buttons, contextual buttons

- Fold verbs: sprint into the stick, crouch and prone out, reload into the ammo card tap (or auto at empty), aim into
  a toggle or a hold on a button next to fire. Shooters on touch (Call of Duty: Mobile, PUBG Mobile, Fortnite) keep
  fire, aim, jump, crouch and reload visible and hide the rest in settings; action games with few verbs (Genshin Impact,
  Brawl Stars) show an attack and two or three abilities. These are design observations from playing and guides, not
  sourced here.
- A **context-sensitive Interact** button that appears only near something usable, and **names the action** and price
  ("BUY  Concession stand  350"), costs no screen space the rest of the time and teaches the player what the world
  offers. It is the touch twin of `HudPrompt`, which already holds that text.
- Let the player move controls (a layout editor) in a later pull request; a first version needs a sensible default.

### Safe areas and notches

- `env(safe-area-inset-top|right|bottom|left)` gives the distance to keep clear of notches, rounded corners and the
  home indicator; it is `0` unless the page asks for the full display with `viewport-fit=cover` in the viewport meta
  tag (that part is not on the
  [MDN `env()` page](https://developer.mozilla.org/en-US/docs/Web/CSS/env); common practice).
  In landscape the notch sits at a **side**, so the left and right insets matter most.
- Discord's mobile guide shows the same: CSS variables `--sail`, `--sair`, `--sait`, `--saib`, each
  `--discord-safe-area-inset-*` with `env(safe-area-inset-*)` as the fallback
  ([Discord, mobile guide](https://docs.discord.com/developers/activities/development-guides/mobile.md)).
- In Godot, `DisplayServer.get_display_safe_area()` returns a `Rect2i`
  ([DisplayServer](https://docs.godotengine.org/en/stable/classes/class_displayserver.html)); whether it returns real
  values in a **web** export is *unverified* (the page does not say), so the web page should pass the CSS insets to the
  game (`JavaScriptBridge`) and the game should place touch controls and the HUD margins from them.

### Multi-touch

- Every finger is its own `InputEventScreenTouch` / `InputEventScreenDrag` with an `index`. Each control claims the
  index that pressed it and ignores the rest until that index lifts or is cancelled; a stick and a look-drag and the
  fire button are held at the same time (common practice, and the Godot touch events are built for it).
- With `emulate_mouse_from_touch` on (the default,
  [Input](https://docs.godotengine.org/en/stable/classes/class_input.html)) a touch also sends a mouse event, and
  `Button`s and `GUI` still work; it also means a second source of the same press. Our touch layer should read the
  touch events itself and mark them handled, and leave the emulation on for menus.
- A touch that ends in `canceled` (a system gesture, a call) must release everything it held, or the stick sticks.

### Keeping the browser out of the way

- `touch-action: none` on the canvas stops the browser panning and pinch-zooming from the gesture; it is read when the
  gesture starts and applies down from the ancestors, so set it in CSS, not mid-touch
  ([MDN `touch-action`](https://developer.mozilla.org/en-US/docs/Web/CSS/touch-action)). It also disables
  browser zoom for the page, which is an accessibility cost to state in the settings.
- `overscroll-behavior: none` on `html` and `body` stops pull-to-refresh and bounce
  ([MDN `overscroll-behavior`](https://developer.mozilla.org/en-US/docs/Web/CSS/overscroll-behavior)).
- Common practice for the rest: `user-select: none` and `-webkit-touch-callout: none` on the page, a `contextmenu`
  listener that calls `preventDefault()` (a long press otherwise opens the image or link menu), `-webkit-tap-highlight-
  color: transparent`, and a viewport meta of `width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no,
  viewport-fit=cover`. iOS Safari has ignored `user-scalable=no` since iOS 10, so `touch-action` is the real lock
  (*unverified here*, check on a device).
- Godot's web page: audio and fullscreen both need a user gesture
  ([Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)), so a
  "Tap to start" splash is also where we start audio, request fullscreen and read the orientation. Canvas focus is not
  covered by the docs; on a touchscreen a tap on the canvas focuses it, but a tap in the Discord iframe around it may
  not, so the page should call `canvas.focus()` on the first touch (*unverified*).

### Haptics

- `navigator.vibrate()` needs sticky user activation and is not Baseline: Safari does not offer it (MDN gives
  "Limited availability" and we take the Safari part from common knowledge)
  ([MDN `vibrate`](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/vibrate)). It does nothing in Silent or
  Do Not Disturb on some devices.
- Godot: `Input.vibrate_handheld(duration_ms, amplitude)` works on Android, iOS and Web; on the **web the amplitude
  cannot be changed**, and Safari and Firefox for Android do not support it
  ([Input](https://docs.godotengine.org/en/stable/classes/class_input.html)). Use it for short feedback (a shot is
  about 10 ms, a hurt blow 30 to 40 ms, a down 150 ms) and treat it as a bonus: no gameplay information may
  depend on it.

### Landscape, orientation and fullscreen

- `screen.orientation.lock()` rejects unless the page is fullscreen and is limited to mobile
  ([MDN `ScreenOrientation.lock()`](https://developer.mozilla.org/en-US/docs/Web/API/ScreenOrientation/lock)); we take
  "not on iOS Safari" from common knowledge. In a plain web page, show a **"turn your phone" prompt** in portrait and
  pause the touch layer until it is landscape.
- **Discord Activity:** the Embedded App SDK has `setOrientationLockState({ lock_state, ... })` (values `UNLOCKED` 1,
  `PORTRAIT` 2, `LANDSCAPE` 3) for iOS and Android, not Web, and an `ORIENTATION_UPDATE` event with `screen_orientation`
  (0 portrait, 1 landscape)
  ([Embedded App SDK](https://docs.discord.com/developers/developer-tools/embedded-app-sdk)). So inside Discord the
  game can ask for landscape without fullscreen; the Developer Portal default for phones and tablets is mentioned in
  secondary results but we could not read it (unverified). Mobile platforms are off until enabled in the Developer
  Portal under Activities, Settings; Discord also reports a thermal state (`THERMAL_STATE_UPDATE`, 0 to 3) to lower
  the load on a hot phone ([Discord, mobile guide](https://docs.discord.com/developers/activities/development-guides/mobile.md)).

### First run, settings, accessibility

- First run: show the controls once, as short labels pointing at the real buttons ("drag to move", "drag to look"),
  dismissed by the first use of each, never a wall of text. Hide desktop key hints (`E`, `R`) when the last input was a
  touch (the HUD already picks keycap or round button by `UIInputMode`; touch is a third mode).
- Settings the player can reach from pause: look sensitivity (hip and ADS), invert Y, control opacity, control size
  (80 to 130 percent), left-handed layout (mirror the two zones), haptics on or off, auto-fire, aim assist strength,
  gyro. Each is a number in `settings.md`'s store, not a constant.
- Accessibility: a left-handed swap is a mirror of the layout, not a second layout; offer a hold-or-toggle for ADS and
  sprint (holding a button while dragging is the hardest touch gesture); keep every control reachable without a second
  finger on one place.

## Recommended design for Deadnight

Positions are the control's centre as `x x y` percentages of the **safe area** (landscape, origin top left); sizes are
millimetres on the device, converted to canvas units from the DPI and multiplied by the UI scale, with a floor of 48
dp. Buttons are drawn at 50 percent opacity at rest and 90 percent while held, with a 2 mm hit padding beyond the art.

| Control | Where | Size | Behaviour |
| --- | --- | --- | --- |
| Move stick | floating, anywhere in the left 40 percent, below the top 20 percent | base 22 mm, knob 10 mm | appears under the thumb; 8 percent dead zone; past 90 percent of the radius = `sprint` held |
| Look | the right 60 percent not covered by a button | whole area | drag turns the camera; default 180 degrees per screen-height hip, 60 percent of that ADS; no acceleration |
| Fire | 88 x 62 | 17 mm | `fire` held; a drag that started on it also looks |
| Aim (ADS) | 74 x 44, above-left of Fire | 12 mm | hold (toggle option) |
| Jump | 93 x 36, above Fire | 12 mm | `jump` |
| Reload | 76 x 80, beside Fire | 11 mm | `reload`; also a tap on the ammo card |
| Swap weapon | 63 x 70 | 10 mm | `swap_weapon`; a tap cycles |
| Grenade | 63 x 56 | 10 mm | `throw_grenade`; hidden at zero grenades |
| Interact | 50 x 62, centre bottom | 15 mm wide pill | appears only when `HudPrompt` has a target; shows the verb and price; `interact` |
| Pause | 50 x 4, top centre, under the banner | 9 mm | `pause`; the banner moves when a touch is held |
| Crouch, shoulder swap | in settings | | not on the screen; shoulder swap is a camera setting (see "What the build showed": a button was built) |

- Keep the HUD where it is: the stick is a transient overlay under the thumb, and the point and health cards in the
  lower left are not touched. The ammo card (bottom right) and the prompt (bottom centre) sit under the Fire and
  Interact zones, so on touch the cards move up and the buttons sit beside them; an engineer must check overlap with the
  worst-case HUD layout test at 16:9, 19.5:9 and 4:3 canvases.
- Left-handed: mirror x. Tablets: same percentages, larger millimetres only up to a cap.
- Deliberately left out: melee (the crowbar is a weapon), crouch, prone, lean, a separate sprint button, a D-pad, an
  on-screen map, a layout editor (later), pinch gestures, tap-to-shoot, and gesture swipes (they conflict with the
  system's own edge gestures).

## Open questions for the maintainer

1. **Auto-fire:** off by default (ammunition is limited), or on while ADS on a target? (Answered in #470: on, while
   aiming; off makes Aim a toggle.)
2. **Aim assist strength:** none, light friction, or friction plus magnetism? The touch player faces the same zombies
   as a mouse player; a gentle default keeps co-op fair.
3. **Gyro:** offer it, given the iOS permission prompt and that it is unverified in a Discord Activity?
4. **Orientation lock in the Activity:** call `setOrientationLockState` to landscape on iOS and Android, and show the
   prompt only on the plain web page?
5. **Left-hand layout:** a setting from the first release, or later?
6. **Haptics default:** on where supported (Android), off on first run?
7. **Desktop key hints on touch:** hide them as soon as one touch is seen, or when no keyboard has been used?
8. **Touch detection policy:** a phone with a Bluetooth keyboard, a laptop with a touchscreen. Show touch controls on
   the first touch, hide them on the first key or mouse event, and let a setting force either?

## What the build showed

The first build (`game/ui/touch/`, [design page](../design/touch-controls.md), pull request #279) followed the
recommendation, then the tests, captures and a browser run changed some of it. What the page recommended, and what the
game does now:

| Recommended | Built | Why |
| --- | --- | --- |
| Places in percent of the safe area, sizes in mm | Offsets from the safe area's bottom right corner and radii in canvas units (`TouchLayout`); a 1080 unit tall canvas is 60 to 70 mm on a phone, so Fire is about 12 mm across and no hit area is under about 9 mm | The HUD already lives in canvas units and the UI scale divides them; one unit system means the buttons scale with the HUD and a test can compare rectangles |
| Interact, a pill at bottom centre | A round button left of Fire, captioned with the verb (OPEN, BUY, REPAIR, FUEL, SWITCH, TAKE, REVIVE) | The prompt card is at bottom centre and stays (it names the object and the price); the thumb reaches the button without leaving Fire |
| Jump above Fire | Jump below and left of Fire, Reload and Aim above it | The ammo card fills the bottom right corner: the first layout put Jump 26 units into it and Fire's rim touched it, found in the captures, so the arc moved up and left (Fire 350 units up, Jump 360 left) |
| Stick: dead zone 8 percent, sprint past 90 percent | Dead zone 10 percent, sprint on at 95 percent and off at 75 percent | Hysteresis, or sprint flickers at the rim; the base follows a thumb that goes past the rim, so travel never runs out |
| Look: 180 degrees per screen height, no acceleration | 1.6 radians (92 degrees, a little under 200 degrees for one width of a phone; it was 3.2 until #470, when a thumb flew round) per screen height at sensitivity 1, a flick gain rising from 1 to 1.6 between 450 and 2400 units per second, and the mouse sensitivity setting on top | A turn of 180 degrees in one swipe needs more than a slow drag gives; the slow range stays 1:1 for aiming. The ADS slow-down is the camera's own, not a separate 60 percent |
| Rest opacity 50 percent | 70 percent (setting 30 to 100), 100 percent while held | At 60 the Fire label was hard to read on a lit ground |
| Grenade hidden at zero | Always shown | The HUD state has no grenade count for the local player in a shape the layer reads yet |
| Reload also on the ammo card | Not built | The card is a read-out; a second target next to the Fire arc invites mis-taps |
| Shoulder swap in settings, not on the screen | A small "SIDE" button above Swap, 565 units from the Fire side's edge | `swap_shoulder` is a fight verb (a corner, a wall), not a one-time choice: the camera changes shoulder in play, so it needs a button. Placed outside the middle 40 percent, clear of the arc, the look hint and the top-right feed |
| Crouch left out | Left out, no button | The simulation does not act on `crouch` yet (#73); a button that sets a flag nothing reads is worse than none |
| Left-handed: mirror x | A setting, `controls/left_handed`; buttons, stick and the HUD's corner columns flip | Mirroring only the buttons put Fire over the points and health cards and the stick over the ammo card, so the HUD columns swap with them (a test checks every canvas, both hands) |
| Pause at the top centre | Top, beside the round card | The banner takes the centre; the left column is narrow and the top left corner is not reachable by the right thumb, so it cannot be hit by accident |

- **Edges need a minimum press.** The player reads `reload`, `interact` and `jump` once per physics tick by polling; a
  tap can start and end between two ticks. A press lasts at least 90 ms, then releases.
  `test_a_quick_tap_still_lasts...` sends press and lift in one frame and checks the action is still down.
- **One finger, one job** held up: stick, look, Fire, Aim and Interact at the same time in the tests (three fingers)
  and in Chromium (the stick pushed to the rim sprints while a second finger fires, the ammo counter fell 10 to 2).
- **Touch-to-mouse emulation has to be off while playing.** The engine makes every touch a left click, which is
  `fire`, and mouse motion, which looks a second time. The layer turns `Input.emulate_mouse_from_touch` off while it
  is up and on for the menus, so the pause menu's buttons still take a tap.
- **Injected events run through the stretch backwards.** A look sent with `Input.parse_input_event` is in window
  pixels: the first look turned the view 8.8 times too far in a test window. The layer multiplies by the viewport's
  final transform first.
- **Key hints and first-run labels (#283):** the prompt card now shows a tap mark when a finger was the last input and a
  keycap again after a key, a pad or a real mouse click (the answer to question 7: hide them as soon as the touch
  layer is up or a touch is seen, bring them back on any other device, never a timer). Hints are three short labels
  (move, look, interact), each gone when its control is first used, remembered in the settings. Found while building:
  the layer handles touches before the HUD sees them, and its own look is mouse motion, so mouse motion cannot be what
  ends touch mode.
- **Detection is `pointer: coarse` plus touch points**, read as a number (a boolean `eval` answer compared equal to
  `true` never matched in Chromium, which hid the controls on every phone until the browser run caught it). A laptop
  with a touchscreen does not turn them on by itself; the setting and `?touch=1` do. Open question 8 stays open for
  hybrids.
- **The safe area** comes from CSS `env(safe-area-inset-*)` on the web (needs `viewport-fit=cover`, set in the export
  preset's head include) and from the display server on a phone build; the HUD cards move in with the controls (capture
  with a 96 unit notch). The overlays that are the screen itself do not: the reticle, hit marker, damage numbers and
  world markers stay on the full screen (`Hud.set_safe_insets`). With the HUD inset as a whole the reticle sat in the
  middle of the inset rectangle, 14.5 units above where the shots go on an iPhone held sideways (insets 59, 0, 59, 21 CSS
  pixels; #601). `test_shot_on_crosshair.gd` and `tools/web_smoke/shot_on_crosshair.py` hold it.
- **Browser checks that passed** (Chromium, mobile and touch emulation, 844 x 390): no scroll (0, 0), no zoom (scale
  1), `overscroll-behavior: none`, `touch-action: none`, no console errors, the portrait page shows the rotate prompt.
  Not testable there: haptics, `screen.orientation.lock`, a real notch, Discord's webview.
- **Layout test**: every button inside the safe area, hit radius at least 66 units, no two buttons touching, and none
  over the ammo, prompt, health, points or round cards, on 16:9, 19.5:9, 20:9 and a browser with bars (25 touch tests
  in all). The feed and notice columns at the top right are not checked: a long list can reach the Aim and Reload
  buttons.

Still open from the questions below: 3 (gyro) and 4 (Discord orientation, issue #287). Answered by #286: 1 (auto-fire is
off by default, and a setting turns it on while Aim is held or always) and 2 (aim assist is friction plus magnetism at a
gentle 0.5 by default, a slider from 0 to 1); how it works and what it is worth are in
[Touch aim assist and auto-fire](aim-assist.md).
Answered by the build: 5 (left hand: a setting from the first release, off by default, a full mirror of the buttons, the
stick and the HUD's corner columns), 6 (haptics default is on, a setting turns it off; the web vibrates only on
Android), 7 (keyboard glyphs hide on the first touch and return on a key, pad or real click) and 8 (auto detects a
coarse pointer; On and Off force it).

## Tap targets in a night (#1192)

A phone's page is 844 x 390 CSS px with a pixel ratio of 2 (the page caps it, `PhoneRender`), so the engine's window is
**1688 x 780** and the canvas 2337 x 1080 units. A night runs at the interface size alone (no phone factor,
`NightScreen._ready`): one unit is 0.72 window px, **0.36 CSS px**, and a finger meets CSS px. Do not read a night's
sizes in window px, and do not detect a phone by the window's short side there (`MenuScale.is_phone` is false for 780).

- **The size:** `MenuScale.TAP_PIXELS` is 44 CSS px; `MenuLook.TAP_TARGET` (62 units at the menu's phone factor,
  0.72 CSS px a unit) is the same 44.8 CSS px. `MenuScale.tap_units(window, touch)` turns it into units at the screen's
  own factor: 122 units at the night's factor, 98 at an interface size of 1.25, 153 at 0.8. It is zero when
  `TouchMode.wanted` is false, so a desktop keeps the theme's size, and never more than a fifth of the canvas's height
  (a headless test's 64 x 64 window would ask for 1320 units).
- **What was under it, on main, in a real `NightScreen` with the router's theme at 1688 x 780:** the end board's Leave
  (Back alone) 149 x 79 units, 53.8 x 28.5 CSS px, and the pause card's Resume, Settings and Leave night 79 units,
  28.5 CSS px. (The issue read about 14 px off a capture; the router's theme gives 28.5, which is what the tests
  read. The cause of the 14 was not found.) Now 122 units, 44.1 CSS px, in the
  engine's capture and in the exported page (`tools/web_smoke/night_taps.py`, a real touch just inside the top edge of
  Leave night leaves the night).
- **Touch layer hit areas** (`TouchLayout`: radius plus 24, never under 66 units): 47.7 CSS px at the night's factor and
  at 1.25; at 0.8 the Pause, Ping, Scoreboard, Bot wheel and Melee circles are 38 to 39 CSS px, and Pause, Ping and
  Scoreboard overlap their neighbours. Left as it is (its own issue).
- **The objective's words** (`HudMarkers`) slide to the nearest place that is on the screen and under no corner card
  (`Hud.corner_cards`): they were drawn under the health card (`SSION STAND 30 m`).

## World markers on a phone's night (#1218)

- **Words at 14 CSS px.** The marker words were 20 units, 7 CSS px. `MenuScale.text_units(window, touch, 20)` is 14
  CSS px in the screen's units (39 at the night's factor on a 1688 x 780 or a 2532 x 1170 page, 49 at an interface
  size of 0.8, 32 at 1.25), never under the 20 a desktop has, never more than 6 % of the canvas's height, and the 20
  itself when `TouchMode.wanted` is false: a desktop's scale does not change. `Hud._fit_markers` hands it to
  `HudMarkers.label_size` (on `resized`, and when the touch layer comes up).
- **The shapes grow with the words** (`HudMarkers._grown()`: the size over 20, 1.95 on the phone): the diamond, the
  pointer over a teammate, the ring of a body, the arrow, the level icon and its gaps, and the outline of the letters.
  The words alone at 39 units beside a 26 unit diamond read as a caption with no mark. A capture with the words alone
  is kept as the option in the pull request.
- **A marker whose shape, words or arrow would be under a card or a touch button is moved** (`HudMarkers._settle`) to
  the nearest place where its whole rectangle is under none. An arrow beside it points back at the place it marks (a
  pinned marker's arrow already did that), on the side of the shape that faces the place or, when that would be over
  the words, a card or a marker moved before it, on a flank or under or over the shape. The touch buttons are in the
  same list (`TouchControls.button_boxes`, `layout_changed`, set by `NightScreen`): a diamond moved off the ammo card
  landed under Fire in the first capture. The resting ring of the stick is not in it (a faint ring over a name still
  reads). `HudMarkers.shown` tells where each marker was drawn (its box is what it draws: shape, words and arrow) and
  whether it moved; `placed` is where it points.
- **Markers moved off neighbouring cards keep clear of each other** when there is room (the objective off the health
  card and a teammate down on the round card both took the pocket between the cards).

## The search for a place, and the smallest page (#1230)

The first search (#1218) tried the places beside each side of each card and then once more from the nearest four: a
column of the screen between the cards and the buttons was out of its reach, and the grid test left the page out
(`CRAMPED`). A rectangle that is clear can be slid left, then up, until it rests on an obstacle or the screen, so a place
exists only on lines where its left edge is on either side of an obstacle and its top the same.
`HudMarkers._nearest_clear` tries those columns nearest first, and in each `_clear_y` takes the nearest `y` from the
obstacles' edges; once a place is found a farther column is not looked at. The rectangle is measured in the middle of
the screen (nothing clamps it there) and the place found is looked at as it is drawn. `MAX_TRIES` (800) caps the
columns a draw tries for all its markers.

- **Every marker is clear of every card and button on every page the grid names**, the 667 x 375 CSS px page at 1.25
  (a 1536 x 864 canvas) included: `CRAMPED` is gone from `test_hud_marker_cards.gd`, whose grid now also has the
  prompt of a door and the card of a level gained up (the lane of the progression's cards, `Hud.centre_cards`).
- **The banner, the prompt and the popup cards are cards a marker keeps clear of** (`Hud.centre_cards`: banner,
  marquee, boss bar, prompt, popup lane), while they are up. A marker is not drawn over them and goes back to its place
  when they leave.
- **A tag at the top edge stays on the screen**: when the tag over a teammate would start above the screen
  (`TEXT_MARGIN`) it is drawn under the pointer or the ring (`_ally_baseline`).
- **Markers moved to the same side of a card keep clear of each other more often**: a moved marker keeps its drawn
  rectangle (shape, words and the arrow where it stands), not the room for an arrow on every side, and the next marker
  keeps clear of that. How many markers a page holds with none meeting another (a diamond and teammates, one on each
  card; `test_markers_one_on_each_card_keep_clear_of_the_cards_and_of_each_other`): 10 or more on every phone page at
  0.8 and 1.0, 8 with three diamonds at 1.0 on the 667 x 375 page, 9 at 1.25 on the 1688 x 780 and 2532 x 1170 pages
  (6 with three diamonds), and **4 at 1.25 on the 667 x 375 page** (3 with three diamonds): the one column left between
  its cards and its buttons is 344 units wide and a diamond's words are 319. More than that are still kept off every
  card and button (`test_the_smallest_page_keeps_eight_markers_off_every_card_and_button`) but meet each other. This
  page's night has one next door and a few teammates under the cards at a time; the deliberate replacement for
  "no room" is "meet another marker", never "stay under a card".
- **Cost.** No node (`test_moving_markers_adds_no_canvas_item`). A frame on the busiest case, eight markers under the
  cards moved by a pixel every frame (a draw each frame; headless, the whole frame): 7.2 ms on the smallest page against
  37 ms with the old search (worst 16 ms against 83 ms), and 7.8 ms against 12.7 ms on a 1688 x 780 page at 1.0.

## Sources

- [Apple HIG, Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Android accessibility, touch targets](https://developer.android.com/design/ui/mobile/guides/foundations/accessibility)
- [Hoober, "How Do Users Really Hold Mobile Devices?" (UXmatters, 2013)](https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php)
- [Game Developer, UX Deep Dive: FPS on mobile, part 1 (2016)](https://www.gamedeveloper.com/game-platforms/ux-deep-dive-painful-reality-of-building-fps-experiences-on-mobile---part-1)
- [Cursa, Touch controls for mobile games](https://cursa.app/en/page/touch-controls-for-mobile-games-input-patterns-and-feedback)
- [GGRecon, Call of Duty: Mobile settings guide](https://www.ggrecon.com/guides/best-call-of-duty-mobile-season-9-settings-guide/)
- [Pistol Arena, mobile controls](https://pistol-arena.pages.dev/controls/mobile/)
- MDN: [`touch-action`](https://developer.mozilla.org/en-US/docs/Web/CSS/touch-action),
  [`overscroll-behavior`](https://developer.mozilla.org/en-US/docs/Web/CSS/overscroll-behavior),
  [`env()`](https://developer.mozilla.org/en-US/docs/Web/CSS/env),
  [`Navigator.vibrate()`](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/vibrate),
  [`ScreenOrientation.lock()`](https://developer.mozilla.org/en-US/docs/Web/API/ScreenOrientation/lock)
- Godot: [DisplayServer](https://docs.godotengine.org/en/stable/classes/class_displayserver.html),
  [Input](https://docs.godotengine.org/en/stable/classes/class_input.html),
  [Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- Discord: [Embedded App SDK](https://docs.discord.com/developers/developer-tools/embedded-app-sdk),
  [Activities, mobile guide](https://docs.discord.com/developers/activities/development-guides/mobile.md)
