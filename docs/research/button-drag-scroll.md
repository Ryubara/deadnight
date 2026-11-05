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

- **Every button that sits in a scrolling card has the mouse filter `PASS`** (`UIButton`, `UICheckBox`, `UIToggle`, and
  the game's `MapCard`, `NightRow`, `ChallengeRow`, `MenuItemButton`, `PosterSetView`, `WardrobeCell`): it takes the
  press and passes the touch up. A new `Button` subclass that sits in a card needs the same line, and a place in the
  list of `test_button_scroll_drag.gd`.
- **A slip.** The engine's `scroll_deadzone` is 0: the first movement of the finger scrolls and takes the press. A
  thumb on a button always rolls a little, so a card would have lost presses it used to keep. `UIScroll.use_slip(scroll)`
  (every `UIScroll` does it itself; a plain `ScrollContainer` calls it, a test scans for the ones that forget) sets the
  deadzone at each touch: `TouchSlop.units` when the touch lands on a button, 0 elsewhere, so a drag from words or margin
  scrolls at once, exactly as before.
- **The slip is 10 CSS pixels** (`TouchSlop.CSS_PIXELS`), in units at the scale the window runs at: 14 on a phone's
  menu, 28 in a night (0.36 CSS px a unit), 10 on a desktop. Android scrolls after 8 dp, iOS after about 10 pt and
  Chromium counts a touch that moved under 15 CSS pixels as a click; 10 is the middle and a quarter of the 44 CSS px
  button a finger needs. Measured on the lobby's Start button (`phone_drag.py`, three steps, 40 ms apart): a slip of
  0, 3, 6, 8 and 9 px presses and does not scroll; 12, 16 and 24 px scroll the card and do not press. Before, a slip of
  24 px still pressed (the finger had stayed on the button), so a drag that long now scrolls rather than presses.
- The finger loses the slip's distance when it starts on a button (a 40 px drag moves the card 30), as on a phone's own
  lists; a drag from words or margin loses nothing.

## What did not change

A mouse press, a mouse drag across a button, the wheel over a button, and a controller's accept press act as before
(`phone_drag.py --desktop` on the old and the new export, and the same cases in `test_button_scroll_drag.gd`: a mouse
drag moves nothing, a click presses once, the wheel scrolls the card over a button).

## Not shown

A real phone's thumb (the slip is the browser's touches, sent by a script), iOS Safari, Discord's webview. A slider or
a text field in a card still takes its drag: it is not a button and a drag on it is its own.

## Why the unit test stops short

`DisplayServer.is_touchscreen_available()` is false headless and on most desktops, and the engine scrolls a card from
touch only on a touch screen. `test_button_scroll_drag.gd` therefore checks what the engine would be given (the card
receives every touch and drag step that starts on a button, and none with the old filter), the slip, and the presses;
`tools/web_smoke/phone_drag.py` is where the scroll itself is measured. CI does not run it.
