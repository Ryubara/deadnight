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
| Look | the rest of the screen | a drag turns the view; one swipe across the screen's height turns about 92 degrees at sensitivity 1 (100 px on a 390 px tall phone is 23 degrees), a fast flick gains up to 1.6 times |
| Fire | big, right thumb | `fire` held, wherever the player aims (hip, aimed, auto-fire on or off); a drag that starts on it also looks |
| Aim | an arc round Fire | `aim`, **held** with auto-fire on (the default), a **toggle** with auto-fire off: a tap aims, the next tap leaves the aim, so the player can aim and shoot by hand. The button stays lit while the toggle is on |
| Jump, Reload, Swap, Grenade | an arc round Fire | `jump`, `reload`, `swap_weapon`, `throw_grenade` |
| Shoulder swap ("SIDE") | small, above Swap, outside the middle of the screen | `swap_shoulder`: the camera moves to the other shoulder, to see round a corner |
| Interact | left of Fire, only with a HUD prompt | `interact`; its caption says what it does (OPEN, BUY, HOLD for a broken fence, which keeps nailing boards while held, FUEL, SWITCH, TAKE, REVIVE) ([hold at a broken fence](rounds.md#the-fences-boards)) |
| Pause | top, beside the round card | `pause` |

Everything presses the game's own input actions, so the player and the night read touch like a key. Look goes out as mouse
motion in mouse pixels, so the sensitivity setting, the ADS slow-down and invert Y apply. A press lasts at least 90 ms so
a quick tap is still seen by the next physics tick. Sizes and places are in `TouchLayout`; a test checks every button
against the safe area, a thumb-sized hit area, each other and the HUD cards that stay (ammo, prompt, health, points, round).

## Left-handed layout

The setting `controls/left_handed` (Settings, Touch tab, off by default) flips the layout left to right. It is a mirror,
not a second layout: `TouchLayout.buttons(safe, scale, mirrored)` measures every offset from the bottom left corner
instead of the bottom right, the stick zone is the right 45 percent and its resting ring is bottom right, and Pause moves
to the right of the HUD's round card. The look area is still the rest of the screen. The HUD flips with it
(`Hud.mirrored`): the corner columns swap sides (round and objective, the fuel, event and notice lists, points and health,
ammo), so the cards that stay clear of the buttons still do; the banner, the prompt and the gains stay in the middle. The
night screen sets it from `TouchControls.mirrored_changed`, which holds while touch controls are wanted and the setting
is on (the HUD does not jump back under a pause menu), never on a keyboard and mouse. The first-run labels mirror too.
Tests check every rule of the layout for both hands: safe area, thumb-sized hit areas, no two buttons touching, none over
the kept HUD cards, the mirror equal to the flipped original, and the busiest and the longest HUD fit every canvas
mirrored without overlap.

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

Touch controls (Auto, On, Off), button size (0.8 to 1.4), opacity at rest (0.3 to 1.0), left-handed layout, vibration
on touch, **aim assist** (0 to 1, default 0.5) and **auto-fire** (Off, On; default On, the maintainer's decision, see
issue 470). The assist slows the look drag near a zombie, pulls the view a little toward its chest while Aim or Fire
is held, and auto-fire holds the trigger with the crosshair on a zombie while the player aims (with it off, Aim is a
toggle and nothing fires by itself); all of it only while a finger was the last input
([Touch aim assist](../research/aim-assist.md)).

## Not done yet

Crouch (the simulation does not act on `crouch` yet, issue #73, so there is no button), gyro, a layout
editor and asking Discord for landscape. Each is an open question on the research page.

## Gotchas found while building it

- **In a browser a finger is also a mouse motion (#470).** Godot's web runtime listens for `pointermove` on the
  window, and a touch pointer fires it too, with `movementX/Y` in device pixels. Every finger (the move stick too)
  therefore also turned the view as a mouse would, three times too far on a phone with a pixel ratio of 3, on top of
  the layer's own look. The export page stops touch pointer moves in the capture phase (`html/head_include`,
  `export_presets.cfg`), and the player ignores a mouse motion that is not the layer's own (`TouchLook.DEVICE`) while
  the layer is up and a finger was the last input (`TouchLook.is_stray`). `tools/web_smoke/touch_look.py` proves both
  on a phone-sized page with real touch events.
- **Touch-to-mouse emulation clicks Fire.** The engine turns every touch into a left click, which is `fire`, and into
  mouse motion, so the layer turns `Input.emulate_mouse_from_touch` off while it is up and back on for menus.
- **Injected events are in window pixels.** `Input.parse_input_event` runs the viewport's stretch backwards, so a look sent
  in canvas units is scaled by the window-to-canvas ratio; the layer multiplies by the final transform first. Tests state
  canvas units and convert the same way (`TouchFixture`), because the headless window is 64 x 36.
- **A full-screen `Control` with the default mouse filter eats injected mouse motion.** The test host sets Ignore.
- **The layer takes touches before the HUD.** It sits later in the tree, so its `_input` runs first and marks them
  handled: the HUD's `UIInputMode.track` never sees a finger. The layer feeds each touch to `UIInputMode.track` itself.
- **Under a `CanvasLayer` a `Control` has size zero.** `TouchControls` and the rotate prompt fall back to the viewport size.
- **The scene runner changes how input arrives**, so the suite that uses it (`test_touch_player`) is its own file.
- **A web `eval` may return a bool or a number**: `TouchMode.detect` asks for `1` or `0` and reads it with `int()`;
  comparing the answer with `true` was false in Chromium and hid the controls on every phone. `window.deadnight.touch`
  (the web probe) says whether the layer is up, for a browser run.
- **The web page** needs `viewport-fit=cover` for safe-area insets, `touch-action: none`, `overscroll-behavior: none`,
  no text selection and no context menu: the export preset's head include sets them.
