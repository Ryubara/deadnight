# Typing on a phone: the keyboard and the room code (#1183)

The maintainer could not type a room code on a phone in the Discord Activity. Every text field of the game
(`LineEdit`) was unusable on a phone in the web build: no keyboard came up.

## The cause, reproduced

`tools/web_smoke/phone_keyboard.py` loads the web export in Chromium as a phone (844 x 390 CSS pixels, a pixel ratio of
3, touch, a mobile user agent), walks to Play together and taps the code field with a finger.

- **`html/experimental_virtual_keyboard=false` was the cause.** The engine opens a phone's keyboard by focusing a hidden
  `<input>` that exists only when that export option is on (`GodotDisplayVK.available()`; Godot 4.7.2
  `platform/web/js/libs/library_godot_display.js`). With it off the page had no input and no `focus()` call at all; the
  game's `LineEdit` had the focus and nothing could type. The same build with only `experimentalVK` flipped to true in
  `index.html` raised the input, took typed text, and Enter submitted: the option is the whole of the cause in Chrome.
- The option alone is not enough for a phone: the engine focuses its input from the first touch event (`touchstart`),
  which iOS does not count as a tap for raising a keyboard; its input has the browser's default 13 px type, which makes
  iOS zoom the page in; nothing moves the field above a keyboard that takes half a phone held sideways (the code field
  sits at 59 % of the page's height); and nothing gives the canvas the focus back when the keyboard closes.

## What the game does now

| Piece | What it does |
| --- | --- |
| `html/experimental_virtual_keyboard=true` | The engine opens its input for every `LineEdit` a finger focuses. |
| `WebKeyboard` (`game/core/web_keyboard.gd`) | A page layer. Holds the engine's input focus from `touchstart` until the finger lifts (`touchend`, `pointerup`, `click`), the events iOS takes as a tap; sets the input's type to 16 px; gives the canvas the focus and the page its top back when the keyboard closes; says how much of the page the keyboard covers (`visualViewport` against `innerHeight`). |
| `KeyboardLift` (`game/core/keyboard_lift.gd`) | Moves the router's canvas layer up by what the focused field needs to clear the keyboard or the keypad, never off the top, waits while a finger is down (a button's press takes the field's focus and the keyboard; the scene sliding back under the finger made the lift of it miss the button), and comes back when nothing covers the page. Nothing is resized, so there is no layout to come back from. |
| `CodeKeypad` (`game/ui/components/code_keypad.gd`) | The room code on a phone, on the game's own keypad: letters, digits, Delete and Join in a canvas layer of its own. It needs nothing from the browser. Its keys take no focus: the field keeps it, so Ctrl+V and a hardware keyboard work meanwhile. Sized in the window's pixels. |
| `TouchField` | A text field is as tall as a button (it was 19 CSS pixels). |

The code field uses the keypad and not the system keyboard (the system keyboard cannot be proved to open in Discord's
webview or iOS without a real phone; the keypad does not depend on it). The player's name (Play together and More) and
the server address (Join) use the system keyboard through the pieces above. The room lobby's `CopyField` is read-only
and opens nothing.

## Every text field

| Field | Where | Keyboard | Shown in an emulated phone |
| --- | --- | --- | --- |
| Room code | Play together | The game's keypad; no system keyboard | Tap opens the keypad, the field is lifted above it, the keys type, Delete deletes, Join submits; the whole join against the local backend; also inside an iframe of another origin |
| Your name | Play together (the prompt Join opens) | System | Tap raises the input inside the tap, the field is lifted, typed text lands, an empty tap closes it and puts the scene back |
| Your name | The menu's More tab | System | The same four |
| Server address | The Join screen (`?dev`, developers) | System | The same four. Known: the field selects all on focus, which a phone's input does not show, so a typed letter lands at the caret |
| The code of a lobby | Lobby (`CopyField`) | None: read-only | Not a text entry |

## What an emulated browser shows, and what it does not

Chromium draws no keyboard. The probe reads "a keyboard is up" as: an editable `<input>` has the browser's focus after
the tap, and the focus was made inside a tap's own event. It stands in for the keyboard's height by shrinking
`visualViewport` (`--mode visual`, what Chrome and iOS do) or by resizing the page (`--mode resize`, a webview that
resizes for the keyboard: the whole game then shrinks to the small page, which is legible but small). It does not show
a real keyboard, iOS Safari (Playwright's WebKit is a desktop one), or Discord's webview.

## The phone factor is not applied on a phone's page

`MenuScale.is_phone` asks for a window under 500 px on the short side. The page reports a pixel ratio of at most 2
(`PhoneRender.PIXEL_RATIO_CAP`), so an 844 x 390 page is a canvas of 1688 x 780: not a phone, factor 1. Play together
then runs at one unit = 0.36 CSS pixels (a field 19 px tall, body text 9 px). The keypad is sized in window pixels for
that reason. Captures at the factor 2 (a Godot window of 844 x 390) show a layout a phone page does not have.

## The probes

Both run through `gds quiet` on a web export (`godot --headless --path game --export-release Web`); the web job of CI
runs them.

- `tools/web_smoke/phone_keyboard.py <web> <out> [--mode visual|resize] [--keyboard N] [--query touch=1]`: the checks
  above, on the code field (keypad) and the name field (system keyboard's path). The same build with only
  `experimentalVK` set to false in its `index.html` fails the name field's checks: that is the cause shown.
- `tools/web_smoke/phone_join.py <web> <out>`: the whole flow against the local platform backend (`npm ci --prefix
  spikes/backend`): a host makes a night, the phone types its code on the keypad, answers the name prompt and joins.
- `tools/web_smoke/touch_look.py ... --after-keyboard`: the night's touch controls after a player has typed on both.

The game publishes `fields` (the editable text fields, as fractions of the window, where they are drawn) and `lift`
(how far the keyboard lifted the screens) next to `spots` for a probe to find a field by its name.

A field's box is where it is drawn, which on a 390 px page may be below the fold: the Together card scrolls (#980) and,
with the server browser's note and button above it (#1232), the code field rests at 101 % of the page height. A probe
that taps the box taps off the page. The probes drag the card up with a finger first (`scroll_into_view`: a drag that
starts on a button is the button's, so it starts in the scroll area's margin) and tap an empty spot
(`EMPTY_SPOT`) to give the keyboard back: the corner (40, 40) is the menu's Play tab since the phone layout (#1225).

## What nobody has shown

A real keyboard appearing on a real phone: Android Chrome, iOS Safari, the Discord Activity's webview on each. The
pull request carries the steps for the one check.
