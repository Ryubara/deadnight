# "Super zoomed in" on a real phone (#1310)

The maintainer played on a phone and found the game larger than it should be. The cause is **not yet known**: nothing
that headless Chrome can do to a phone page reproduces it. This page is what was measured, what was ruled out, what is
left, and how to read the answer off the phone (`?viewcheck`).

## What a phone page must show

| Quantity | Must be | Why |
| --- | --- | --- |
| Canvas box | the page (`innerWidth` x `innerHeight`) | `canvas_resize_policy=2`; the engine polls the size every frame |
| Visual viewport | the page, scale 1, offset 0,0 | nothing zoomed, nothing panned |
| Pixel ratio the page reports | `min(real, 2)` | `PhoneRender.PIXEL_RATIO_CAP`, `html/head_include` |
| Canvas pixels | page times that ratio | a 844 x 390 page is 1688 x 780 |
| CSS px to a unit, menu on a phone | page height / 540 | `MenuScale` factor 2 |
| CSS px to a unit, in a night | page height / 1080 | interface size 1, base stretch 1920 x 1080 |

`tools/web_smoke/phone_view.py` holds a page to all of it (and to the `?viewcheck` readout saying the same numbers) in
Chromium as a phone, then pulls two fingers apart, double taps, turns the page upright and back, and changes its
height (an address bar). Run on main's export, six pages, 0 problems (one with a night, one in an iframe of another
origin):

| Page (CSS px) @ real ratio | Canvas | Menu: CSS px a unit | Night: CSS px a unit |
| --- | --- | --- | --- |
| 844 x 390 @ 3 | 1688 x 780 | 0.722 | 0.361 |
| 932 x 430 @ 3 | 1864 x 860 | 0.796 | |
| 667 x 375 @ 2 | 1334 x 750 | 0.694 | |
| 915 x 412 @ 2.625 | 1830 x 824 | 0.763 | |
| 844 x 340 @ 3 (address bar showing) | 1688 x 680 | 0.630 | |
| 740 x 360 @ 4 (capped to 2) | 1480 x 720 | 0.667 | |
| 844 x 390 turned upright (390 x 844) | 780 x 1688 | 0.406 | |

Visual viewport scale 1 and offset 0,0 on every row, before and after the pinch and the double tap.

## Ruled out, with the measure

- **Chrome's page zoom (pinch, double tap).** Raw two-finger touch events zoom a plain page to scale 5 in the same
  emulation (control); `user-scalable=no` alone and `touch-action: none` alone each hold it at 1; the game page stays at
  1 after a pinch and after a double tap on its ground. (`Input.synthesizePinchGesture` does nothing in headless
  emulation, even on a plain page: send `Input.dispatchTouchEvent` with two points.)
- **The address bar and `100vh`.** There is no `vh` in the page. The engine reads `innerWidth` and `innerHeight` every
  frame (`_godot_js_display_size_update`), so a page that changes height follows on the next frames: 412, 390 and 340
  high gave canvases of 824, 780 and 680 pixels and units of 540 tall in the menu.
- **Turning.** Loaded upright and turned to landscape, and loaded in landscape, turned upright and back: the canvas
  followed each time (no stale size). The upright page shows the "turn your phone" prompt over a menu laid out on 960 x
  2077 units.
- **A pixel ratio above the cap.** 3, 2.625 and 4 are held to 2 (`window.deadnightPixels`); the layout does not depend
  on the ratio (`phone-page-scale.md`).
- **The world camera.** A night at 844 x 390 and at 1280 x 720: the soldier is 55 % and 50 % of the page's height. The
  camera keeps its height (`fov` 60, `KEEP_HEIGHT`), so a wider page shows more to the sides, not less.
- **Discord's frame, as an iframe of another origin.** The same numbers (an iframe's own `innerWidth`).

## Not reproduced, and not testable here

- **iOS Safari and WKWebView.** iOS ignores `user-scalable=no` (since iOS 10); `touch-action: none` and the
  `gesturestart` handler in the page are what hold it, and only a device can say they do. iOS also zooms the page in to
  a focused text field whose type is under 16 px and leaves it zoomed after the field closes. Main creates no focused
  field in the page today (`html/experimental_virtual_keyboard=false`); the Activity's copy button makes a read-only
  text box off screen in the frame (`WebClipboard`). The phone keyboard change (#1200) turns the engine's own input
  on: its inputs must be `font-size: 16px` (kit `docs/godot/web-export.md`).
- **Playwright's WebKit** is not Safari: its pointer is not `coarse`, so the game runs the desktop path.
- **Discord's own webview.** Whatever scale Discord gives the frame is its own; the iframe stands in.
- **By design, not a fault:** the menu on a phone is a canvas 540 units tall (`MenuScale.PHONE_FACTOR` 2), so it is two
  times the desktop layout's size: 0.72 CSS px a unit at 844 x 390 against 0.67 on a 1280 x 720 window, and it shows
  1169 x 540 units against the desktop's 1920 x 1080 (three rows of the Play tab, "Server Browser" cut to "Server
  Brows"). If "zoomed in" is the menu, the lever is that factor (text floor 14 CSS px, taps 44: `test_phone_floor`);
  it is the maintainer's call, so it is not changed here.

## Reading it off a phone: `?viewcheck`

Open the page with `?viewcheck` added (`.../index.html?viewcheck`, or `&viewcheck` after other parameters; in a Discord
Activity the page is the one Discord opens, so a browser tab on the same phone is the first thing to read). A green
readout covers the top left corner of the page (it ignores touches), refreshed twice a second:

```text
page 844 x 390 css px, screen 844 x 390
visual 844 x 390 scale 1 (seen 1 to 1) at 0,0
pixel ratio real 3 used 2 cap 2
canvas box 844 x 390 px 1688 x 780
css px per unit: night 0.36 phone menu 0.72
touch 1 coarse true framed false scroll 0,0
```

What to send back: a screenshot of the menu and one of a night, and the device and browser (Safari, Chrome, Discord).

- `visual ... scale` above 1, or `seen` showing a range, or `at` not 0,0: the page is zoomed or panned by the browser
  (iOS: pinch, double tap, a field's focus zoom). The readout's own text is 11 CSS px, so zoom also shows as big text.
- `page` smaller than `screen`: the browser's bars, or a webview that is not full screen (that is fine); `page` far
  smaller than a phone's usual 390 to 430 short side: the device's "display size" setting.
- `canvas box` not equal to `page`, or `canvas px` not `box` times `used`: the canvas is not the page.
- `css px per unit` far from 0.36 (night) or 0.72 (menu) at a page of about 844 x 390.
- `pixel ratio real` against `used`: `used` must be 2 or less on a phone (`cap`), unless `?dprcap=` is on the page.

All of these are plain numbers of the page, so the answer says which of the guesses above is the one, or that none
is and "zoomed in" is the design.

## What only a real phone proves

iOS Safari's behaviour with `touch-action`, `user-scalable=no` and a focus; Discord's webview and the scale it gives the
frame; the device's own display size and text size; whether the picture is the size the maintainer meant by "should be".
