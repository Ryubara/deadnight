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
| Look | the rest of the screen | a drag turns the view; one swipe across the screen's height turns about 92 degrees at sensitivity 1 (100 px on a 390 px tall phone is 23 degrees), a fast flick gains up to 1.6 times; the view follows the finger a few frames behind, evenly (`LookSmoother`, 40 ms, [why](../research/touch-look-smoothness.md)) |
| Fire | big, right thumb (a bullet) | `fire` held, wherever the player aims (hip, aimed, auto-fire on or off); a drag that starts on it also looks, at the look sensitivity (#497) |
| Aim | a scope, up and to the left of Fire | `aim`, **held** with auto-fire on (the default), a **toggle** with auto-fire off: a tap aims, the next tap leaves the aim, so the player can aim and shoot by hand. The button stays lit while the toggle is on. A drag that starts on it also looks, held or toggled (#497), so one thumb can aim and turn |
| Reload | a circle of arrow, right next to Fire on its left, in Fire's row | `reload` (#1277) |
| Jump | two chevrons up, above Fire | `jump`. A press while crouched stands the body up first, and the jump goes on |
| Crouch | a chevron down onto a floor line, below and left of Fire | `crouch`, a **toggle** (#1277): a tap crouches and stays, the next tap or a Jump stands. The button stays lit while it is on |
| Weapons and grenades | the HUD's own strip in the bottom corner of the stick's side, under the players' column (a left hand flips it); not buttons of the layer | #1280. There is no Swap button and no Grenade button: a tap on a weapon's place takes that weapon (`weapon_slot_1`..`3`, the key's action), and the grenades' place after the weapons, with their count, is held while the pin is out (`throw_grenade`) and lets go to throw; a drag that starts on it also looks (#599), because the right thumb is on it for the whole hold and the left has the stick, so the throw can be aimed. Every place is at least 44 CSS px wide and high (`MenuScale.tap_units`). The layer asks the HUD where the places are (`TouchControls.zones`, `HudSlots.touch_zones`) and presses the action of the one a finger lands on; a finger that starts on a weapon's place only picks it, it never fires or looks |
| Shoulder swap (a person, an arrow each way) | small, on the arc round Fire, outside the middle of the screen | `swap_shoulder`: the camera moves to the other shoulder, to see round a corner |
| Melee (a blade) | small, on the far right edge below Fire and above the ammo card (60 left, 310 up) | `quick_melee` (#588): a tap is one blow with whatever is in hand, at once; the server's 0.6 s cooldown holds a thumb that taps again and a finger that stays down is still one blow ([quick melee](weapons.md#quick-melee)) |
| Bots' order (a tag) | the HUD's own tag at the inner end of the weapon strip, only while the room has a bot (a left hand flips it); not a button of the layer | #1286. The tag says the standing order in a word and the order's colour (FOLLOW amber, ROAM cream, HOLD red-orange: three that differ in light as well as hue) under a small BOTS, and a tap gives the next order of Follow, Roam, Hold (`bot_order_next`, through the same command the wheel uses, `BotWheelDriver`). The feed says the bots' state once the server's frame shows it (`BOTS: FOLLOWING YOU`, `ROAMING`, `HOLDING POSITION`), so an order the server refused (a second tap inside its half second) changes nothing and says nothing. At least 44 CSS px wide and high; a finger that starts on it only taps it: it never starts the stick or a look. The layer tries the tag's place before the weapons' (`HudSlots.touch_zones`: the first zone that holds the point wins), so a place laid over the same ground (a hold on the players' column, #1287) never takes its taps. The first time bots are in the room a first-run label says "TAP TO ORDER BOTS" beside it, until it is used. The hold-and-drag wheel is the keyboard's and the pad's (`bot_wheel`); there is no wheel button on the glass ([bot wheel](../research/bot-wheel.md)) |
| Ping (a pin) | small, straight under Pause, 56 CSS px (9 mm and a little) from its centre or more, with 2 mm of air between the rims (`TouchLayout.ping_drop`, #1289; it was beside Pause, 27 CSS px away) | `ping` (#642): a tap marks what the crosshair is on for the team, as Z, the middle mouse button and the pad's d-pad right do; the server's one mark a second per player holds a thumb that taps again |
| Interact | one thumb-length left of Fire, only with a HUD prompt | `interact`; a tap mark over its word, which says what it does (OPEN, BUY, HOLD for a broken fence, which keeps nailing boards while held, FUEL, SWITCH, TAKE, REVIVE) ([hold at a broken fence](rounds.md#the-fences-boards)) |
| Pause | top, beside the round card (two bars) | `pause` |
| Scoreboard | right of Pause, the same length from it as Ping is (rows of a table); the players' column takes it over in #1287 | `scoreboard` while a finger is on it |

**Every control shows an icon and no words** (`TouchIcons`, drawn in code, no file). The one word left is the interact
button's verb: it is a different thing nine ways (OPEN, BUY, AMMO, PLAY, TAKE, FUEL, HOLD, SWITCH, REVIVE) at a different
price, the card above it names the object, and a word is read faster than nine new pictures to learn.

**Every button of the right thumb is a right button** (`TouchLayout.looks_when_dragged`): a finger that starts on any of
them presses it and also turns the view for the rest of its drag, so Reload and Jump fire on the press and hand the drag
to the look, as Fire and Aim always did. A finger that
starts on free ground beside a button looks, and does not press the button it later drags across.

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

The HUD's weapon slot strip (#682) is over the ammo card on a keyboard, where the right thumb's corner is empty. With the
touch controls up (`TouchControls.active_changed`, which the night screen hands to `Hud.touch_layout`) it moves under the
health card, as wide as it, because Fire and Melee sit where it would; `slots` is one of the kept cards the buttons are
tested against. The stick's resting ring is 60 units higher so it clears the players' column and the strip under it.

## First run and key hints

- **No keycap on a phone.** `UIInputMode.touch` is true while a finger was the last input (and when the layer comes up
  with nothing else used yet); wherever a glyph is drawn then it is a round tap mark (rings round a dot) and no letter.
  The night's prompt card has no glyph at all while the touch layer is up (`HudPrompt.touch_layout`, #1275): the Interact
  button is the control and says the verb, so a key or a mark on the card pointed at nothing and held 64 units of the
  words' room. A key or a gamepad button brings the keycap back where there is no touch layer, and so does a real mouse
  click; mouse *motion* does not, because the layer sends its look as motion, and the engine's touch copies are marked
  as emulated. The health card likewise drops `GRENADES xN` (the strip's grenade place counts them). What each other
  control does and why is [the phone audit](touch-audit.md).
- **Hints once per control** (`TouchHints`, a child of the layer): "DRAG TO MOVE" over the stick's resting ring, "DRAG TO
  LOOK" in the look area and "TAP TO USE" ("HOLD TO REPAIR" at a fence) beside the Interact button while it shows. Each
  goes the moment its control is used: a finger on the stick, the first look drag (also one that started on Fire), a
  press of Interact. The Interact hint waits for the first prompt, and a prompt that goes unused brings it back with the
  next one. What was used is a bit in the setting `controls/touch_hints_seen`, so a player sees each hint once ever;
  restoring the defaults in Settings shows them again. A test checks the labels against the safe area, the buttons and
  the HUD cards on every phone canvas.
- **The look hint stands beside the popup lane**, not over it ([popup lane](../research/popup-lane.md)): the cards
  stand in the middle of the screen under the round banner, so the hint takes the look area's side of their column. It
  steps down past any button that climbs up to it on a short screen, and on a small canvas the stick's hint steps aside
  from the column too. A level up in a first minute is read with its hint, and neither waits for the other (a card held
  until the hint was used would never come to a player who plays without a look drag). `test_popup_lane.gd` checks that
  no hint meets a card at its canvases, both hands, with and without a boss bar.

## Settings

Touch controls (Auto, On, Off), button size (0.8 to 1.4), opacity at rest (0.3 to 1.0), left-handed layout, vibration
on touch, **aim assist** (Off, On; default On at strength 1.0, issue 1279) and **auto-fire** (Off, On; default
On, the maintainer's decision, see issue 470). The assist slows the look drag near a zombie, pulls the view a little
toward its chest while Aim or Fire is held, and auto-fire holds the trigger with the crosshair on a zombie while the
player aims (with it off, Aim is a toggle and nothing fires by itself); all of it only while a finger was the last
input ([Touch aim assist](../research/aim-assist.md)).

## Not done yet

Gyro, a layout editor
and asking Discord for landscape. Each is an open question on the research page.

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
