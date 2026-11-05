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
- **Sprint by pushing the stick past its edge** removes a button. Common practice in shooters on touch. Deadnight's
  first version sprinted at 95 percent of the radius, which a thumb reaches without meaning to; the maintainer's
  rework (#1276) makes the edge a full walk and the sprint a latch past it (see "The stick's sprint latch" below).

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
| Move stick | floating, anywhere in the left 40 percent, below the top 20 percent | base 22 mm, knob 10 mm | appears under the thumb (nothing is drawn without a finger); 8 percent dead zone; past the edge by a margin = `sprint` held until the finger lifts (#1276) |
| Look | the right 60 percent not covered by a button | whole area | drag turns the camera; default 180 degrees per screen-height hip, 60 percent of that ADS; no acceleration |
| Fire | 88 x 62 | 17 mm | `fire` held; a drag that started on it also looks |
| Aim (ADS) | 74 x 44, above-left of Fire | 12 mm | hold (toggle option) |
| Jump | 93 x 36, above Fire | 12 mm | `jump` |
| Reload | 76 x 80, beside Fire | 11 mm | `reload`; also a tap on the ammo card |
| Swap weapon | 63 x 70 | 10 mm | `swap_weapon`; a tap cycles (removed in #1280: a tap on the weapon on the HUD) |
| Grenade | 63 x 56 | 10 mm | `throw_grenade`; hidden at zero grenades (moved to the HUD strip in #1280, dim at zero) |
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
| Stick: dead zone 8 percent, sprint past 90 percent | Dead zone 10 percent; the edge is a full walk and a drag 18 CSS px past it latches the sprint until the finger lifts (#1276; it was on at 95 percent and off at 75 percent) | Sprinting too easily was the maintainer's complaint, and a hysteresis band still flickered under a nervous thumb; once latched the base follows the thumb, so travel never runs out |
| Look: 180 degrees per screen height, no acceleration | 1.6 radians (92 degrees, a little under 200 degrees for one width of a phone; it was 3.2 until #470, when a thumb flew round) per screen height at sensitivity 1, a flick gain rising from 1 to 1.6 between 450 and 2400 units per second, and the mouse sensitivity setting on top | A turn of 180 degrees in one swipe needs more than a slow drag gives; the slow range stays 1:1 for aiming. The ADS slow-down is the camera's own, not a separate 60 percent |
| Rest opacity 50 percent | 70 percent (setting 30 to 100), 100 percent while held | At 60 the Fire label was hard to read on a lit ground |
| Grenade hidden at zero | Always shown | The HUD state has no grenade count for the local player in a shape the layer reads yet |
| Reload also on the ammo card | Not built | The card is a read-out; a second target next to the Fire arc invites mis-taps |
| Shoulder swap in settings, not on the screen | A small "SIDE" button above Swap, 565 units from the Fire side's edge | `swap_shoulder` is a fight verb (a corner, a wall), not a one-time choice: the camera changes shoulder in play, so it needs a button. Placed outside the middle 40 percent, clear of the arc, the look hint and the top-right feed |
| Crouch left out | Left out, no button, until #1277 (now a toggle on the ring round Fire) | The simulation did not act on `crouch` (#73); it does now |
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
gentle 0.5 by default, a slider from 0 to 1; since #1279 an On/Off toggle, On by default at strength 1.0); how it
works and what it is worth are in
[Touch aim assist and auto-fire](aim-assist.md).
Answered by the build: 5 (left hand: a setting from the first release, off by default, a full mirror of the buttons, the
stick and the HUD's corner columns), 6 (haptics default is on, a setting turns it off; the web vibrates only on
Android), 7 (keyboard glyphs hide on the first touch and return on a key, pad or real click) and 8 (auto detects a
coarse pointer; On and Off force it).

## The right side: one ring round Fire, every button a looking button (#1277)

The maintainer (2026-11-05): "We really just need a Fire, Aim, and Jump, maybe a crouch button, and a reload button.
But it needs to be more intuitively placed. Like the reload button needs to be right next to the fire button. Each
individual button on the right side should be classified as a right button, and any time that a user is holding down a
right button (basically anytime the user is holding down on right side of screen), they should still be able to look
around", and "All of the mobile touch controls icons must be icons instead".

- **Before** (the real page, 844 x 390): Aim, Reload, Jump, Grenade, Swap, Shoulder, Melee and Bots round Fire, Reload
  up and right of it with Aim between, Jump low and left. Only Fire, Aim and Grenade turned the view when dragged:
  a thumb dragged off Reload turned it 0.000 rad (`tools/web_smoke/touch_right_side.py --before`).
- **Placement from thumb reach.** The right thumb rests on Fire (205 left, 350 up of the corner: 74 CSS px, 12 mm, from
  the edge on a 6 CSS px per mm phone). Four more buttons stand on a ring round Fire with 42 units of air between the
  rims (15 CSS px, 2.5 mm: "a thumb needs 2 to 3 mm" above): Reload on Fire's left in its row (8 degrees above
  straight left), Aim up and left (56), Jump nearly straight up (104), Crouch down and left (-40). Each centre is
  **11.8 to 12.9 mm from Fire's centre** on both phone pages (667 x 375 and 844 x 390): a roll of the thumb, no reach.
  The ring buttons keep at least 30 units (11 CSS px) of air from each other (`test_touch_layout`). Interact, which shows
  only at something to use, is one thumb-length out (21 to 22 mm: 367 units), up and left of Reload.
- **Why this ring, in this order.** Fire is held for the whole fight and the thumb that holds it also looks, so what is
  used while Fire is held goes nearest: Reload (the same row, a slide to the left), Aim (the hold that auto-fires: a
  short roll up). Jump is used while the left thumb walks, so it is straight above where the thumb already is, not
  low in the corner where it has to leave the look. Crouch is the least used and the only one that could be
  mistaken for a press made by the thumb's heel, so it takes the low corner under Reload.
- **Crouch stayed, as a toggle.** The simulation acts on `crouch` held now (`PlayerSimulation._next_stance`), and a held
  button would take the right thumb off Fire and the look for as long as the player is down. A tap crouches and stays
  (lit), the next tap stands; a Jump stands the body first, since a crouching body cannot jump (the jump goes on in
  the same tick). It costs one circle of the same size as its neighbours and no extra cluster.
- **Every right button looks.** `TouchLayout.looks_when_dragged(id)` is true for every button of the table but the bot
  wheel (its drag picks the order), so a new button is a looking one unless it says otherwise. Reload and Jump fire
  on the press (the action goes down on the touch, before any drag) and hand the rest of the drag to the look. A
  finger that begins on free ground beside Reload, outside its hit area, is a look and presses nothing when it drags
  across Reload: only the touch-down picks a button, a drag never presses one. A finger that lands in the margin
  the fingertip floor adds round a button presses it and looks. Measured with real touches on both pages
  (`touch_right_side.py`): a 90 CSS px drag from Fire, Aim, Reload, Jump, Crouch, Swap, Grenade, Side and Melee turns
  the view 0.26 to 0.37 rad with the button held the whole way; from the bot wheel 0.0.
- **Icons, no words** (`TouchIcons`): drawn in code as triangles and lines, one canvas command for all of them
  (`HudShapes`), so there is no art file to license and a redraw while the stick moves costs one command more, not forty.
  Fire a bullet, Aim a scope, Jump two chevrons up, Crouch a chevron down onto a floor line, Reload a circle of arrow,
  Swap two arrows across, the Grenade a grenade, Side a person with an arrow each way, Melee a blade, Bots a wheel of
  orders, Ping a pin, Pause two bars, Scoreboard the rows of a table. **Interact keeps its word** under a tap mark:
  OPEN, BUY, AMMO, PLAY, TAKE, FUEL, HOLD, SWITCH, REVIVE are nine different things at different prices that a
  picture would have to teach one by one, and the prompt card above names the object.
- **What waits for a home.** (Swap and the Grenade have theirs since #1280, the HUD's weapon strip below.)
  Shoulder, Melee and the Bots stay reachable where they were (Swap and Shoulder moved a little so Interact has
  room) until the audit's homes are built (#1275); they look when
  dragged too, except the Bots.
- **Interact is out of the markers' way until it shows.** `button_boxes` listed the hidden Interact, and at its new
  place it took the column the world markers need between the cards and the buttons on the smallest page (344 units
  for 319 of words): it is left out while hidden and the markers settle again when it comes (`layout_changed`).
- **Not measurable without a hand.** Whether 12 mm is comfortable for every hand (small hands, a case, a tablet) is a
  real-device question; the numbers above are from the layout and the 6 CSS px per mm of a 460 ppi phone.

## The audit (#1275)

The maintainer (2026-11-05): "we're not prioritizing a unique set of touch controls for our game, we're still
treating the users as if they're playing the desktop version but just with touch controls", and "stuff that touch
players can be taking advantage of on existing components without adding too many bloat controls (basically
duplicates)". The table of every action and every element, with a verdict each, is
[the phone audit](../design/touch-audit.md); this is what it rests on.

- **What phone shooters do (design only, nothing copied).** Call of Duty: Mobile's own guide numbers 23 elements in its
  multiplayer HUD, gives the player a layout editor for "the size and opacity of everything on-screen", and shows the
  knife only when it applies: "When an enemy gets within striking distance, a big knife icon will appear here"
  ([Activision, Getting a Grip on the Call of Duty: Mobile Controls, 2019](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls)).
  A context-only melee is therefore the precedent for Strike, and it is what the game's own Interact button already
  does. A search summary of a TechRadar review of Apex Legends Mobile says its touch layout is crowded and that pings
  sometimes fire when the player did not mean them (the page text could not be read here, so this is *unverified*):
  enough to keep Ping a deliberate button and out of the look surface.
- **Three rules came out of the review of this game's screen.** One thumb, one job at a time (the right thumb holds Fire
  and looks, so only what a fight needs is under it). A touch goes to the element that already shows the thing before
  a control is added (the weapon strip for weapons and grenades, #1284; the players' column for the scoreboard; a tag
  for the bots' order). A control that shows only when it applies costs no screen the rest of the time (Interact,
  Strike).
- **Findings in the code, by what a phone assumed a keyboard for.** The bot order showed for two seconds in the feed
  and nowhere else (a wheel can be driven blind, a cycle cannot be read blind: the tag shows the state). The Controls
  tab of Settings holds the phone's own look sensitivity under "Mouse sensitivity". The prompt card kept a 48 unit key
  and a 16 unit gap for a mark that pointed at nothing, in a card that is 64 units short of room for the words on a
  phone. The health card said `GRENADES x3` and the strip beside the weapons said `x3`.
- **Built in the audit's own pull request:** the prompt card without a key while the touch layer is up
  (`HudPrompt.touch_layout`; a capture from a script is not in touch mode, so it followed "a finger was the last input"
  and could show "E"), the health card without the grenade count, and bot order notices that say the bots' state
  rather than a line that reads as an order to the player (`BOTS: HOLD HERE` became `BOTS: HOLDING POSITION`).
- **Markers.** At 667 x 375 and an interface size of 1.0 the screen held eight markers before two met, six with the
  Interact button up. With only the ring, Reload and Pause on the glass it holds ten or more either way, and at 1.25
  it goes from 3 to 5 (three diamonds) and 4 to 7 (one). Measured with the helpers of `test_hud_marker_cards.gd`; the
  table is in the audit page. The remaining limit at 1.25 is the cards, not the buttons.
- **Not proved.** Comfort of Strike's place (21 mm from Fire) on a real hand; the double tap against a thumb's own
  taps; the tag's tap against the stick's zone. Each is in the issue that builds it with a test that sends real touches
  to the real page.

## Tap targets in a night (#1192)

A phone's page is 844 x 390 CSS px with a pixel ratio of 2 (the page caps it, `PhoneRender`), so the engine's window is
**1688 x 780** and the canvas 2337 x 1080 units. A night runs at the interface size alone (no phone factor,
`NightScreen._ready`): one unit is 0.72 window px, **0.36 CSS px**, and a finger meets CSS px. Do not read a night's
sizes in window px, and do not detect a phone by the window's short side there (`MenuScale.is_phone` is false for 780).

- **The size:** `MenuScale.TAP_PIXELS` is 44 CSS px; `MenuLook.TAP_TARGET` (64 units at the menu's phone factor:
  46.2 CSS px at 0.72 a unit on an 844 x 390 page, 44.4 at 0.694 on 667 x 375) is the same.
  `MenuScale.tap_units(window, touch)` turns it into units at the screen's own factor: 122 units at the night's
  factor, 98 at an interface size of 1.25, 153 at 0.8. It is zero when `TouchMode.wanted` is false, so a desktop
  keeps the theme's size, and never more than a fifth of the canvas's height (a headless test's 64 x 64 window would
  ask for 1320 units).
- **What was under it, on main, in a real `NightScreen` with the router's theme at 1688 x 780:** the end board's Leave
  (Back alone) 149 x 79 units, 53.8 x 28.5 CSS px, and the pause card's Resume, Settings and Leave night 79 units,
  28.5 CSS px. (The issue read about 14 px off a capture; the router's theme gives 28.5, which is what the tests
  read. The cause of the 14 was not found.) Now 122 units, 44.1 CSS px, in the
  engine's capture and in the exported page (`tools/web_smoke/night_taps.py`, a real touch just inside the top edge of
  Leave night leaves the night).
- **Touch layer hit areas** (`TouchLayout`: radius plus 24, never under 66 units, and now never under a fingertip, #1217):
  before, at 0.8 the Pause, Ping, Scoreboard and Bot wheel circles were 38.1 CSS px across and Melee 39.3 (Swap
  shoulder 43.9); at 1.0 and 1.25 all were 47.7 or more. `NightScreen` gives `TouchControls.finger_units`
  (`MenuScale.tap_units`: 153 units at 0.8, 122 at 1.0, 98 at 1.25), the layout never makes a hit area narrower than
  that, so the five are 44.2 CSS px at 0.8 and nothing else changes at 1.0 and 1.25. The drawn buttons are unchanged;
  only the area a touch counts for grew (a ring 8 to 10 units, about 3 CSS px, at 0.8).
- **Who wins a touch where hit areas overlap** (`TouchLayout.button_at`), decided on purpose: (1) inside the area a
  button had before, the first in order wins exactly as it always did (Pause, Ping, Scoreboard, then the table: Interact
  first, Fire, Aim, Reload, Swap, Jump, Grenade, Side, Melee, Bots); so a touch that pressed a button before presses the
  same one now; (2) in the new ring nobody owned, the nearest centre wins (a tie goes to the first in order). Growing a
  button therefore takes no touch from a neighbour, and the only touches that change meaning are ones that fell to the
  stick or the look inside a 3 CSS px ring. Left as they were, so a person can see them: Pause beats Ping and
  Scoreboard in the overlap (their centres are 96 and 98 units apart, 27 CSS px at 0.8), and Melee beats the Bot wheel
  (95 apart) even when the finger is nearer the wheel. At 0.8 Ping and Scoreboard (137 apart) now touch in the ring
  only, where the nearest centre decides. `test_touch_hit_areas` holds all of it with real touch events and a sweep of
  every point of the page at three interface sizes and both hands.
- **Measured in the exported page** (`tools/web_smoke/night_taps.py --ui 0.8|1.0|1.25`, 1688 x 780 canvas, ratio 2): the
  probe reports every circle; a touch 1 CSS px inside the edge of Ping, Scoreboard, Melee, the Bot wheel and Pause
  presses that button, and one 1.5 CSS px outside presses none. The interface size is written into the page's saved
  settings (IndexedDB `/userfs`) and the page reloaded.
- **Still for a real phone:** thumb reach and accidental presses of the larger Pause and Ping next to each other
  (27 CSS px apart at 0.8) are not something an emulated touch can judge; a real device is needed to say whether 44 CSS
  px is enough there or whether the buttons should be spread (a layout change, not made here).
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
  landed under Fire in the first capture. The stick's ring is not in it (it is drawn only under a finger,
  #1276). `HudMarkers.shown` tells where each marker was drawn (its box is what it draws: shape, words and
  arrow) and whether it moved; `placed` is where it points.
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

## Weapons and grenades on the HUD (#1280)

The maintainer: "Why do we have a swap weapons button when we clearly have a UI showing the weapons, the user could
just click between both of them", and grenades "next to the weapons ... pressed and held to throw". The weapon strip of
the HUD is the phone's weapon control; the Swap and Grenade buttons are gone from the layer (`TouchLayout.BUTTONS`).

- **The trap, and how it is crossed.** The HUD's root and nearly all of its nodes ignore the pointer, and the touch
  layer takes every finger itself with the engine's touch-to-mouse emulation off, so a `Button` on a cell would never
  get a tap. The layer asks the HUD where the places are (`TouchControls.zones`, a callable set by `NightScreen`
  to `HudSlots.touch_zones`: the action and the global box of each) and presses that action like a button of its own
  (`_touch_down`, after `TouchLayout.button_at`: a button wins where the two meet, and the tests keep them apart).
  The HUD nodes keep ignoring the pointer. `button_boxes()` (the world markers' keep-clear list, #1218) holds the
  boxes, and the HUD says when they move (`Hud.slots_moved`, once a frame at most) so the night screen hands the
  markers the new list.
- **A weapon's place** presses `weapon_slot_N`, the key's own action, held for the layer's minimum so a tick sees a tap;
  a finger that starts there only picks the weapon (it is not in `LOOKING_BUTTONS`): it never fires or looks, however
  far it drags. **The grenades' place** presses `throw_grenade`, held while the thumb is down (the server's cook),
  looks while it drags (#599) and throws on the lift; it is lit while the pin is out and shows `x3`. There is no cancel
  to carry over: none exists today (a cook ends by a throw or in the hand).
- **Layout.** Under a finger the strip leaves the ammo column for a column of its own at the bottom of the players'
  column's corner (the stick's side; a left hand flips it), the players' column lifted by its height. Each place is
  `MenuScale.tap_units` high (44 CSS px; 122 units at the night's factor, 98 at an interface size of 1.25, 153 at 0.8),
  the weapons a quarter wider, the grenades as wide as high; with the perk's third slot the row is 3 x 1.25 + 1 fingers
  and three gaps, 599 units at 1.0 (two weapons: 450; the prompt card's edge is at 750 on a 1920 canvas, and the stick's
  resting ring far above). At 1.25 on the smallest page (1536 x 864) it is 485 units (366) and the prompt starts at 558.
- **Measured in the exported page** (`tools/web_smoke/touch_weapon_places.py`, real touches through the DevTools
  protocol, pages of 844 x 390 and 667 x 375 CSS px at a ratio of 2, both hands, interface sizes 0.8, 1.0 and 1.25):
  the weapons' places are 55.2 to 55.6 x 44.1 to 44.3 CSS px and the grenades' 44.1 to 44.3 square (a fingertip is 44);
  all are on the hand's side of the page, inside it and clear of every button's hit area; a finger on a weapon's place
  takes it (the pistol and the crowbar, tapped three times: slot 1, 2, 1) and the lit slot follows; a drag of 120 CSS px
  from a weapon's place turns the view 0.000 rad and holds no other button; a finger on the grenades' place holds
  `throw_grenade`, the server says the pin is out (1 s later and after a drag of 120 CSS px), the drag turns the view 0.51
  to 0.53 rad, and the lift ends the cook and takes one from the count (3 to 2). Six runs, no problem. In the engine
  `test_touch_weapon_places` holds the same with real touch events at every page, interface size and hand.
- **Two things the strip's size showed.** (1) The search for a place clear of the cards (`HudMarkers._nearest_clear`)
  rests a marker against a card's edge, and the marker is measured again where it stands: its box is 1e-4 taller than
  the model's, so on the 667 x 375 page at 1.0 with eight players, the lifted column and the strip, every candidate
  at an exact edge counted as touching and the marker stayed under the players' card (`test_hud_marker_cards`). A place
  now rests `EDGE_EPSILON` (0.05 units) past the card. (2) A window that is no phone's (a test's 64 pixels) asks
  `tap_units` for a fifth of the screen: the HUD takes a fingertip of at most 12 percent of its height and 160 units
  (`Hud.FINGER_SHARE_MAX`, `FINGER_UNITS_MAX`; a phone's is 11.3 percent and 153 at most), or the strip fills it.
- **After #1283 (the ring round Fire, the icons).** The strip's places hold their size and clearance with the new right
  side: the suite's clearance test runs over the ring's buttons (Crouch and Reload on the left of Fire), `TouchIcons` lost
  its Swap and Grenade drawings with their rows, and the grenades' place looks while it drags like every right button
  (`TouchControls`, `GRENADE`, as `looks_when_dragged` reads only the layer's own table).
  One number moved: on the 667 x 375 page at the usual interface size, eight markers (one on every card) no longer all
  clear each other, as the ring's buttons and the strip leave less free ground in the corner, so
  `test_markers_one_on_each_card_keep_clear_of_the_cards_and_of_each_other` holds six there (`CROWDED_HOLDS`); every
  marker still stays off every card and button.
- **The stick's resting ring** (`TouchLayout.STICK_REST`, #1276's) now overlaps the top of the points card by about
  20 units: the column is a strip's height higher. It is a faint ring and the stick floats to wherever the thumb lands,
  and the move hint is placed from it (`TouchHints`), so moving it moved the hint over the round card and the scoreboard
  button on the smallest canvas (`test_touch_hints` failed): left for the stick's own issue, with the clearance test
  (done there: "The stick's resting place" below).
- **Not done here:** a first-run hint for the places (the hints label the stick, the look and Interact only); a cancel
  for a cooking grenade (the throw's other action `toss_grenade` has no touch control either).

## Strike: a button that shows only while a dead is in reach (#1285)

The audit (`docs/design/touch-audit.md`) made the Melee circle a contextual button: a sixth permanent circle is the
bloat the maintainer named, and Call of Duty: Mobile shows its knife only when an enemy is within striking distance
([Activision](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls),
design only).

- **The rule** is `StrikeReach` (`game/gameplay/night/`), the rule the bots strike by (`BotMotor`): a living dead
  (not `DYING`) within the quick melee's `melee_range` (1.6 m) on the ground from the player, read from the client's
  own picture of the night (`ClientState`), so it costs no traffic and runs the same on a game server. It goes at 0.3 m
  past the reach, so a dead that shuffles on the edge does not flicker it and a thumb on the button is not dropped by
  a step back; a downed player has no blow. The night screen hands it to the layer as `TouchControls.strike_ready`.
- **Facing is not part of it.** The blow goes along the view, from the head (`NightServer._quick_melee`), so a dead at
  the player's side or back brings the button and a tap swings at air: a real run (below) made seven blows for no
  kill with the dead beside the crosshair. The issue's rule is reach, as the audit's, and a facing gate would copy the
  server's hit shapes into the client; left as a decision (a follow-up issue).
- **It is a hidden state in every suite that lists the buttons.** The first blow kills a round-one dead in a test
  night and the button goes with it, so a cooldown test holds the button up by hand
  (`test_night_touch_melee.gd`); the fixture has a switch (`TouchFixture.strike_up`) and the marker, hint, box-count,
  hit-area and input-matrix suites each had an assumption (kit lesson
  `2026-11-05-a-button-that-shows-only-sometimes-broke-seven-suites-that-listed-it.md`).
- **The hint is one word.** "TAP TO STRIKE" is 407 units wide and met the Perks card of the 667 x 375 page at 1.25
  with the notch's insets (`test_popup_lane` caught it); "STRIKE" is 268 and stands 22 units above its button's row
  (`TouchHints.STRIKE_LIFT`) to clear the Perks column, which starts 3 units under the row's line there.
- **`TouchControls` is at gdlint's limit of 20 public methods,** so the layer says whether Strike shows with a property
  (`strike_up`), not a method.
- **Markers.** Strike stands in the one column the markers use: with it up the 667 x 375 page at 1.25 holds two
  markers before two meet (four with Interact up); the table is in the audit page. Every marker is still off every
  card and button.

## The stick's sprint latch (#1276)

The maintainer, 2026-11-05: nothing on the left until the screen is pressed; the edge of the circle is the top
speed of a walk; "if they drag above the top of the circle, it should vibrate and start sprinting until the finger is
let go (even if they drag finger back into the circle)". What was built:

- **No resting ring.** `TouchControls._draw_stick` draws nothing without a finger. A faint outer line at the sprint
  edge shows where it starts; once latched the ring turns to the accent colour with SPRINT over the knob.
- **The edge is in CSS pixels of the page** (`TouchTuning.stick_radius_px` 40, `sprint_margin_px` 18, turned into
  canvas units by `MenuScale.css_per_unit`, so it is the same movement of the thumb at 667 x 375 and 844 x 390: both
  measured in a browser at 40.0 and 40 + 18 CSS px). The ring was 38 CSS px on a phone before.
- **The latch is the finger's.** `TouchStick` is made on the press, kept in that finger's touch entry
  (`_touches[index][&"pad"]`) and dies with it. It clears on the lift, when the layer goes down
  (`_release_everything`: a menu, the result, portrait, the setting off) and when the same index presses again
  without a lift (`_touch_down` lifts the old touch first). A different finger never inherits it.
  Before the latch the base stays where the finger landed, so the edge is one place for the whole drag; after it the base
  follows the finger one radius behind, as the old stick did, so "back inside the circle" is the moved ring.
- **Any direction past the edge sprints**, not only the top: the body sprints in every direction
  (`PlayerSimulation._sprint_allowed`, the body turns to face the way it goes), and a cone would make the stick behave
  differently by direction. A drag to the edge sideways or backward walks at full speed like the top.
- **One buzz** when it latches (`TouchTuning.sprint_haptic_ms` 40, silenced by the haptics setting). `sprint_started`
  is the signal a test counts. The on-stick cue is there with or without a buzz. iOS Safari is thought to have no
  `navigator.vibrate` (MDN: "Limited availability"; not verified on a device); Discord's webview was not checked
  (no Discord client to run: Godot only prints that vibration is unsupported when the function is missing).
- **What cancels a sprint, and what that does to the latch.** The latch only says the `sprint` action is held; the
  body decides (`_sprint_allowed`): the stick finger lifting ends it and clears the latch; losing the layer and a
  reused index clear it; holding Aim (button or toggle) stops the body sprinting but keeps the latch, and the sprint
  returns when the aim is let go with the finger still down; a push under half (`sprint_min_input`) walks, latch kept;
  a Crouch tap (a toggle since #1277) stops the body sprinting too, with the latch kept, and the sprint returns when a
  second tap (or a Jump) stands it with the finger still down; being airborne after a jump keeps a sprint going.
- **The stick's resting place.** With no ring on the screen the resting place is only where the first-run "DRAG TO
  MOVE" hint stands. It was a corner offset (330 right, 390 up, times the touch scale), and the column of the HUD, a
  strip's height higher since #1280, reached into it (the points card by 26 units with one player at 1.0, and the perk
  badges beside the column). It cannot be put above the column: the column grows up the side with the party (the points
  card's top is at 769 units with one player, 607 with four and 503 with eight, on the 1080 unit canvas). So it is
  **beside** the column: `STICK_REST_CLEAR` is where the ring's left edge stands (right of the column, the perk badges
  and a gap, 496 units) and where its bottom edge stands (271 units up, above the tallest strip: 196), whatever the
  touch scale, and the ring's top at a scale of 1 stays 495 units up, where it always was, so the hint above it stays
  put. `STICK_RADIUS` is the drawn ring (40 CSS px = 111.1 units on every page and interface size), it was 105.
  `test_touch_stick_rest` holds the ring clear of every card, every place of the strip and every button, and a finger at
  its centre starting the stick, for both hands, the two phone pages, interface sizes 0.8, 1.0 and 1.25, touch scales
  0.8, 1.0 and 1.4, and parties of one, four, eight and eight with seven bots (it fails with the old numbers: the ring
  was over the points card and the perk badges).
- **What happens where a finger lands.** The ring is drawn where the finger lands, anywhere in the stick's zone (the
  left 45 percent below the top fifth, or below Ping's hit area where that is lower: #1289), and the zone is over the
  players' column: a finger that lands there makes a
  ring over the cards, and the cards (which ignore the pointer) are under the touch layer. The ring is a translucent
  disc and the finger is on it, so the words under it are covered by the thumb in any case; it goes with the finger.
  Nothing moves for it: the HUD does not know where the ring is. A new player is not asked to land there, because the
  hint points at the resting place beside the column. The hint itself stands at the resting place, between the column
  and the popup lane; on the smaller canvases it cannot be wholly right of the column (the lane takes the room), so it
  is over the column's x range at the height of the ring's top, as it always was: clear of the cards for a party of up
  to four, over the points card for eight on the 1.0 and 1.25 canvases for the moment it is up (it goes on the first
  drag). The objective card is under it at an interface size of 1.25 on the smallest canvas, and was before.
- **Measured** in a web export (`tools/web_smoke/touch_sprint.py`, real touches through the DevTools protocol): the
  edge walks at 4.80 m/s (`run_speed`) on both pages, a drag 15 CSS px past the ring still walks with no buzz, the
  latch sprints at 7.0 m/s (`sprint_speed`) on every side, one buzz, and stays on at a 0.67 push and at the middle
  of the ring until the lift (4.09 m/s at 0.67 after one second: the stick is analog, so a latched sprinter who relaxes
  the thumb slows down but is still sprinting); a new press walks. Run again after #1280, #1281 and #1283 on the merged
  game (844 x 390 and 667 x 375 at a pixel ratio of 3, CSS px per unit 0.3611 and 0.3472): the ring is 40.0 CSS px and
  the sprint starts at 58.0 on both; the edge walks at 4.80 m/s with 0 buzzes; a drag 15 CSS px past the ring walks, 0
  buzzes; past the line one buzz of 40 ms (`navigator.vibrate` replaced by a counter, 10 buzzes in the whole run: one
  per sprint start); 7.0 m/s to the right, down and up-right; a finger put back in the ring and at its middle keeps the
  latch (at the middle no push, so the body walks off the sprint with the latch kept); the lift clears it; the pause
  menu with a latched stick leaves nothing held and a press after it walks. Sideways at the edge: 4.67 m/s (the
  diagonal's share of the push) and no latch. Ending the body's sprint with the latch kept, second finger held on the
  stick finger: Aim held 1.71 m/s (the aimed walk) then 7.0 m/s again when it lifts; one Crouch tap 2.4 m/s, the
  second tap 7.0 m/s again, the sprint cue on the ring the whole time. (The speeds that read 0.0 in the log are the
  player's face against the wall after the first push: the edge's 4.8 is the peak of the first second.)
- **Where the cue is.** With the phone's buzz missing the ring is the cue: accent colour, thicker, a tinted disc and
  SPRINT above the knob (captures in the pull request; the web build cannot tell the game whether the phone buzzes).
  iOS Safari is believed to have no `navigator.vibrate` (not checked on a device), Discord's webview was not checked.

## Ping under Pause, a thumb apart (#1289)

On the top edge Pause and Ping were 27 CSS px apart at the usual interface size (96 units, 0.36 CSS px a unit), a
thumb's width: a tap meant for one could pause the night. Ping stays one small button (the phone audit keeps it: the
one verb no element on screen already shows) and gets the room two controls need.

- **Where.** Straight under Pause, in the same column. How far is a length on the glass, so it is computed from the
  fingertip (`TouchLayout.ping_drop`, the units of 44 CSS px, `MenuScale.tap_units`): the most of 56 CSS px (9 mm at
  6 CSS px a millimetre, and a little over), both hit areas with 6 CSS px between them, and 150 units where no fingertip
  is known (a desktop, a test). A fixed number of units cannot do it: a unit is 0.29 CSS px at 0.8 and 0.45 at 1.25, so
  a length that is 9 mm at one interface size is 7 or 11 mm at the others.
- **The Scoreboard button** stood under Pause. #1287 takes it away (the players' column holds the board); until it
  lands it stands right of Pause, the same length from it, so it is reachable and clear of Ping (the three hit areas
  share no margin). Its place goes with #1287.
- **The stick's zone** starts below the bottom of Ping's hit area (`TouchLayout.stick_zone(safe, mirrored, below)`,
  `TouchControls._stick_zone`) where that is lower than the fifth of the height it always began at (0.8 on an 844 page:
  81 units, 23 CSS px, lower): a thumb that starts the stick never lands on the button above it.
- **The move hint** (`TouchHints`) is put through the same search for a free place as the look hint, and the search
  reads the layer's own circles (with the fingertip rule) instead of laying the buttons out again: on a short canvas
  (864 units) Ping's circle reached the hint's pill.
- **Measured in the exported page** (`tools/web_smoke/touch_ping_place.py`, real touches through the DevTools
  protocol, a solo night, `?touch=1`, ratio 2): the centres are 56.1 to 56.3 CSS px apart at 0.8 and 1.0 and 65.1 to
  67.7 at 1.25 (the 66 unit hit area floor of every small button is wider than the fingertip there), the hit areas have
  7.8 to 12.1 CSS px between them, and a finger walked down the line from just under Pause to below Ping, every 4 CSS px,
  holds Ping inside its hit area and nothing in the gap and never pauses; a finger on the edge of Pause that faces Ping
  pauses the night and holds no Ping. Nine runs (844 x 390 and 667 x 375, both hands, interface sizes 0.8, 1.0 and
  1.25), no problem. `test_touch_ping_place` holds the layout (distance, air, top edge, clear of the HUD's parts and the
  popup lane, the stick zone) at every page, interface size, touch size and hand, and the real touches at the edges.
- **Marker capacity** (`test_hud_marker_cards.gd`'s procedure, one marker on each card, the most of 1 to 10 that none
  meet each other, a card or a button), the 667 x 375 page, with Ping at its old place and its new one: the same at every
  row, the right side of the screen being what bounds it. 0.8: 10+ for 3 and 1 diamonds, Interact up or not. 1.0: 3
  diamonds 6 (6 with Interact up), 1 diamond 10+. 1.25: 3 diamonds 3 (3), 1 diamond 5 (4). On the 844 x 390 page one
  row moved: at 1.25 with 3 diamonds the page held 10+ and holds 8 (with Interact up, 10+ as before); the test's own
  count there is eight (`EIGHT`), so it still passes. The numbers in the audit page's table
  (docs/design/touch-audit.md, #1291) are the 667 rows of this list; its "today" row for 1.0 with 3 diamonds, 8, was
  taken before the weapon strip (#1284), which made it 6.

## Sources

- [Apple HIG, Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Android accessibility, touch targets](https://developer.android.com/design/ui/mobile/guides/foundations/accessibility)
- [Hoober, "How Do Users Really Hold Mobile Devices?" (UXmatters, 2013)](https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php)
- [Game Developer, UX Deep Dive: FPS on mobile, part 1 (2016)](https://www.gamedeveloper.com/game-platforms/ux-deep-dive-painful-reality-of-building-fps-experiences-on-mobile---part-1)
- [Cursa, Touch controls for mobile games](https://cursa.app/en/page/touch-controls-for-mobile-games-input-patterns-and-feedback)
- [GGRecon, Call of Duty: Mobile settings guide](https://www.ggrecon.com/guides/best-call-of-duty-mobile-season-9-settings-guide/)
- [Pistol Arena, mobile controls](https://pistol-arena.pages.dev/controls/mobile/)
- [Activision, Getting a Grip on the Call of Duty: Mobile Controls (2019)](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls)
- [TechRadar, Apex Legends Mobile has learned a great lesson from Call of Duty Mobile][techradar] (summary only)
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

[techradar]: https://techradar.com/au/news/apex-legends-mobile-has-learned-a-great-lesson-from-call-of-duty-mobile
