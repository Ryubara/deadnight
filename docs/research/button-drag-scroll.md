# A drag that starts on a button scrolls the card (#1257)

On a phone page a card that scrolls could only be dragged from its words or its margin: the host's lobby is Start, Leave
and two copy buttons, and a finger that began on any of them moved nothing. Measured in the web export in Chromium as a
phone (844 x 390 CSS px, a 1688 x 780 canvas, real touches through `Input.dispatchTouchEvent`), `phone_drag.py`.

## Why

Godot's `Button` has the mouse filter `STOP`. A press on a stopping control is its alone: the engine hands every event of
that finger (the touch, each drag step and the lift, and the mouse the engine makes of them) to the button and to
nothing above it. The `ScrollContainer` scrolls from the touch events that reach it, so it never saw the finger.
Instrumented in the export: a drag from the words gave the card 2 touch, 12 drag and 14 mouse events; the same drag from
Start gave the card none and Start all of them. Changing nothing but `UIButton`'s mouse filter to `PASS` made the same
drag scroll the card (before and after in `phone_drag.py`), so it is not the button's drawing, its focus or the scroll's
theme.

The engine already has the cure for the other half: once the card starts to scroll it tells the buttons inside
(`NOTIFICATION_SCROLL_BEGIN`) and a button gives its press up. That only happens when the card sees the finger.

## What was done

- **A button passes the touch up only while a scroll area is above it** (`UIScroll.pass_touch_in_scroll(button)`, called
  by `UIButton`, `UICheckBox`, `UIToggle`, and the game's `MapCard`, `NightRow`, `ChallengeRow`, `MenuItemButton`,
  `PosterSetView`, `WardrobeCell`). It is decided each time the button enters the tree (`tree_entered`, which a
  reparent and a moved branch fire too): `PASS` under a `ScrollContainer` that stops the pointer, `STOP` everywhere
  else, so a button outside a card is what it always was. A button whose filter is `IGNORE` is left alone. A new
  `Button` subclass that sits in a card calls it too and gets a place in the list of `test_button_outside_scroll.gd`.
- **The area stops the pointer itself** (`UIScroll.take_touch(scroll)`). The engine's `ScrollContainer` has the filter
  `PASS`, not `STOP` (measured: `ScrollContainer.new().mouse_filter` is 1), and a press that reaches a `PASS` area goes
  on to whatever is above it. `take_touch` sets `STOP` (a `UIScroll` does it in `_init`, a plain `ScrollContainer` the game
  builds calls it before its buttons enter the tree; a test scans the game's code for one that does not). A button
  under a plain, `PASS` area stays `STOP`: no drag from it, and no leak.
- **A slip.** The engine's `scroll_deadzone` is 0: the first movement of the finger scrolls and takes the press. A
  thumb on a button always rolls a little, so a card would have lost presses it used to keep. `take_touch` (the same
  call) sets the deadzone at each touch: `TouchSlop.units` when the touch lands on a button, 0 elsewhere, so a drag from
  words or margin scrolls at once, exactly as before.
- **The slip is 10 CSS pixels** (`TouchSlop.CSS_PIXELS`), in units at the scale the window runs at: 14 on a phone's
  menu, 28 in a night (0.36 CSS px a unit), 10 on a desktop. Android scrolls after 8 dp, iOS after about 10 pt and
  Chromium counts a touch that moved under 15 CSS pixels as a click; 10 is the middle and a quarter of the 44 CSS px
  button a finger needs. Measured on the lobby's Start button (`phone_drag.py`, three steps, 40 ms apart): a slip of
  0, 3, 6, 8 and 9 px presses and does not scroll; 12, 16 and 24 px scroll the card and do not press. Before, a slip of
  24 px still pressed (the finger had stayed on the button), so a drag that long now scrolls rather than presses.
- The finger loses the slip's distance when it starts on a button (a 40 px drag moves the card 30), as on a phone's own
  lists; a drag from words or margin loses nothing.

## What went wrong first, and what was measured

The first version of this change set `PASS` on every button class, wherever it sat. A press on a `PASS` button with
nothing above it that stops the pointer goes on to `_unhandled_input`. Measured with the real classes through the
`Input` singleton, in `test_button_outside_scroll.gd` (a mouse click and a touch tap, on every class, each alone in a
host that ignores the pointer, as the end board's are), against that first version:

- A mouse click: the button is pressed 1 time, and 2 events (down, up) reach `_unhandled_input`.
- A touch tap (and the mouse the engine makes of it): pressed 1 time, and 4 events (mouse down, touch down, mouse up,
  touch up) reach `_unhandled_input`.

That is for each of the nine classes, and for the end board's Leave (`HudEndBoard.leave_button`, every ancestor
`IGNORE`). `player.gd` takes an unhandled mouse press (`_unhandled_input`, a click) to give the pointer lock back
(`set_controls_enabled(true)`, `grip.retry()`), so a click on Leave could have taken the lock as the player left; any
other `UIButton` with no stopping ancestor (the router's and shell's own screens read `_unhandled_input` too) had the
same leak, and a touch that goes unhandled is the touch look. The cause is the `PASS` filter alone: a `STOP` button
marks the event handled, a `PASS` one does not, and nothing above it did.

After the change (`STOP` outside a card, `PASS` in a `take_touch` area): each class, outside a card and in one, is
pressed exactly once by a click and once by a tap, and nothing reaches `_unhandled_input` (0 events); the end board's
Leave is pressed once by a click and once by a tap with 0 leaked events. `phone_drag.py` on the new export is unchanged
from the first version (the table in the pull request): the drag from Start moves the card 30 px, and the slips
press or scroll at the same sizes.

A note on a probe that said a `PASS` button is not pressed at all (pressed = 0): in a headless project the window is
64 x 64, and the probe's buttons sat at x = 200, outside it, so the click never reached them. The same probe with the
button at 0, 0 presses once and leaks the press. A probe of pointer input needs a window as large as what it puts in it.

## A button stayed lit after a scroll from it

Found in the capture: after a drag from Start that scrolled the card, Start was drawn paler and larger (its hover) in
the shot taken after the finger lifted and 1.2 s had passed. A finger that lifts sends no mouse exit, so the engine
keeps the button it lifted over hovered until the next mouse motion; before this change a drag from a button moved the
finger off it, so the button went back, but now the card moves with the finger and the finger lifts over the button.
Measured in the web export (`phone_drag.py`, the colour of the fill left of the words after the lift against the same
button after a touch elsewhere, in the sum of the three channels):

- before this change: Start 16 apart, Copy the link 6, Copy the code 3 (resting);
- this change without the fix: Start 95, Copy the link 68, Copy the code 81 (stays lit until the next touch);
- with the fix: Start 23 (the fill's own gradient and grain), Copy the link 2, Copy the code 7 (resting).

A tap leaves its button lit the same way before and after this change (Copy the link after a tap: 37, 34, 43 against
14, 11, 21 at rest, in both exports): the engine's behaviour, not touched here. The fix is for the press a scroll gave
up: a scroll area that took the touch (`take_touch`) notes `scroll_started`, and when the finger lifts it takes the hover
off the buttons that have it (`_drop_hover`: the filter is set to `IGNORE` and back, which makes the engine send the
mouse exit; hiding the button does the same but drops its focus, and a motion out of the window does it too but is an
event the player's `_unhandled_input` would see; measured in a headless run, all three clear it and none brings it back
by itself). The press itself needs nothing: the button gives it up when the scroll begins. The unit test tells the area
`scroll_started` by hand (headless is not a touch screen); `phone_drag.py` measures it for real and fails, with the
look of each button, when one stays lit (it fails on the export without the fix: 95, 68, 81).

## What did not change

A mouse press, a mouse drag across a button, the wheel over a button, and a controller's accept press act as before
(`phone_drag.py --desktop` on the old and the new export: a mouse drag over Start moves nothing, a click presses once,
the wheel scrolls the card 60 px, all the same before and after; and the same cases in `test_button_scroll_drag.gd`).
Outside a card every button is `STOP` again, exactly as before the change. The walk
`test_every_button_the_end_board_and_the_screens_build_follows_the_rule` checks the buttons the end board, the
customize, settings and credits screens build: `PASS` under an area that stops the pointer, `STOP` elsewhere. The pause
card's buttons sit under no scroll area of their own, so they stop the pointer (a pause card in a night was not built
in a test: its buttons are the same classes under the same rule).

## Not shown

A real phone's thumb (the slip is the browser's touches, sent by a script), iOS Safari, Discord's webview. A slider or
a text field in a card still takes its drag: it is not a button and a drag on it is its own.

## Why the unit test stops short

`DisplayServer.is_touchscreen_available()` is false headless and on most desktops, and the engine scrolls a card from
touch only on a touch screen. `test_button_scroll_drag.gd` therefore checks what the engine would be given (the card
receives every touch and drag step that starts on a button, and none with the old filter), the slip, and the presses;
`tools/web_smoke/phone_drag.py` is where the scroll itself is measured. CI does not run it.
