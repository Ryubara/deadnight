# Touch controls

Deadnight is played on a phone held sideways. The research and the reasons are in
[mobile controls](../research/mobile-controls.md); this page is what the game does.

## What shows

The layer (`game/ui/touch/`) shows when the setting `controls/touch_controls` says so: **Auto** (a phone or tablet in a
browser, an Android or iOS build), **On** or **Off** (Settings, Touch tab). To try it on a desktop pass `--touch`
after `--` on the command line, set `DEADNIGHT_TOUCH=1`, or open the page with `?touch=1`. Held upright, a "turn your
phone" screen covers the game and the controls wait. The HUD keeps inside the safe area (a notch, rounded corners).

## The controls

Each finger has one job until it lifts, tracked by its touch index, so move, look and a button work at once.

| Control | Where | Does |
| --- | --- | --- |
| Move | anywhere on the left, below the top fifth | a stick that floats under the thumb and follows it past the rim; the rim is a sprint |
| Look | the rest of the screen | a drag turns the view; one swipe across the screen's height turns about 183 degrees at sensitivity 1, a fast flick gains up to 1.6 times |
| Fire | big, right thumb | `fire` held; a drag that starts on it also looks |
| Aim, Jump, Reload, Swap, Grenade | an arc round Fire | `aim` (held), `jump`, `reload`, `swap_weapon`, `throw_grenade` |
| Interact | left of Fire, only with a HUD prompt | `interact`; its caption says what it does (OPEN, BUY, HOLD for a broken fence, which keeps nailing boards while held, FUEL, SWITCH, TAKE, REVIVE) ([hold at a broken fence](rounds.md#the-fences-boards)) |
| Pause | top, beside the round card | `pause` |

Everything presses the game's own input actions, so the player and the night read touch like a key. Look goes out as mouse
motion in mouse pixels, so the sensitivity setting, the ADS slow-down and invert Y apply. A press lasts at least 90 ms so
a quick tap is still seen by the next physics tick. Sizes and places are in `TouchLayout`; a test checks every button
against the safe area, a thumb-sized hit area, each other and the HUD cards that stay (ammo, prompt, health, points, round).

## First run and key hints

- **No keycap on a phone.** `UIInputMode.touch` is true while a finger was the last input (and when the layer comes up
  with nothing else used yet); the prompt card's glyph then draws a round tap mark (rings round a dot) and no letter
  ([HUD prompt](hud.md)). A key or a gamepad button brings the keycap back, and so does a real mouse click; mouse
  *motion* does not, because the layer sends its look as motion, and the engine's touch copies are marked as emulated.
- **Hints once per control** (`TouchHints`, a child of the layer): "DRAG TO MOVE" over the stick's resting ring, "DRAG TO
  LOOK" in the upper right of the look area and "TAP TO USE" ("HOLD TO REPAIR" at a fence) beside the Interact button
  while it shows. Each goes the moment its control is used: a finger on the stick, the first look drag (also one that
  started on Fire), a press of Interact. The Interact hint waits for the first prompt, and a prompt that goes unused
  brings it back with the next one. What was used is a bit in the setting `controls/touch_hints_seen`, so a player sees
  each hint once ever; restoring the defaults in Settings shows them again. A test checks the labels against the safe
  area, the buttons and the HUD cards on every phone canvas.

## Settings

Touch controls (Auto, On, Off), button size (0.8 to 1.4), opacity at rest (0.3 to 1.0) and vibration on touch.

## Not done yet

Crouch and shoulder swap (not on the screen), a left-handed layout, aim assist, gyro, and asking Discord for landscape.
Each is an open question on the research page.

## Gotchas found while building it

- **Touch-to-mouse emulation clicks Fire.** The engine turns every touch into a left click, which is `fire`, and into
  mouse motion, so the layer turns `Input.emulate_mouse_from_touch` off while it is up and back on for menus.
- **Injected events are in window pixels.** `Input.parse_input_event` runs the viewport's stretch backwards, so a look sent
  in canvas units is scaled by the window-to-canvas ratio; the layer multiplies by the final transform first. Tests state
  canvas units and convert the same way (`TouchFixture`), because the headless window is 64 x 36.
- **A full-screen `Control` with the default mouse filter eats injected mouse motion.** The test host sets Ignore.
  So does the router's `Stage` (`UIRouter/Stage`): `test_touch_player` sets it to Ignore, or the look never reaches the
  player on a desktop run (it did not on CI, by luck of what ran before).
- **The layer takes touches before the HUD.** It sits later in the tree, so its `_input` runs first and marks them
  handled: the HUD's `UIInputMode.track` never sees a finger. The layer feeds each touch to `UIInputMode.track` itself.
- **Under a `CanvasLayer` a `Control` has size zero.** `TouchControls` and the rotate prompt fall back to the viewport size.
- **The scene runner changes how input arrives**, so the suite that uses it (`test_touch_player`) is its own file.
- **A web `eval` may return a bool or a number**: `TouchMode.detect` asks for `1` or `0` and reads it with `int()`;
  comparing the answer with `true` was false in Chromium and hid the controls on every phone. `window.deadnight.touch`
  (the web probe) says whether the layer is up, for a browser run.
- **The web page** needs `viewport-fit=cover` for safe-area insets, `touch-action: none`, `overscroll-behavior: none`,
  no text selection and no context menu: the export preset's head include sets them.
