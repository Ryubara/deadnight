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

## Ruled out in Chromium, with the measure

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

## WebKit as an iPhone (the maintainer's was Safari on an iPhone)

Playwright's WebKit with the iPhone device descriptors (`phone_view.py --engine webkit`: iPhone 14, 13 Pro Max and SE,
landscape) is the nearest engine to iOS Safari here, **and it is not Safari**: no real toolbars, no pinch, no safe
areas, a software GL. Its `navigator.maxTouchPoints` is 0 where an iPhone's is 5, and `TouchMode.detect` asks for more
than 0, so the page is given 5 (`WEBKIT_INIT`); without it the game runs its desktop path (an earlier version of this
page said WebKit's pointer was not `coarse`: it is, `matchMedia('(pointer: coarse)')` is true there).

| Page (CSS px) @ real ratio | Canvas | Ratio used | Menu: CSS px a unit | Night |
| --- | --- | --- | --- | --- |
| iPhone 14 750 x 340 @ 3 | 1500 x 680 | 2 | 0.630 | 0.315 |
| iPhone 13 Pro Max 832 x 380 @ 3 | 1664 x 760 | 2 | 0.704 | |
| iPhone SE 568 x 320 @ 2 | 1136 x 640 | 2 | 0.592 | |
| iPhone 14 turned upright (340 x 750) | 680 x 1500 | 2 | 0.354 | |

Visual viewport scale 1 and offset 0,0 on every row, after a double tap, a turn and a change of height; 0 problems. The
menu and the night look as in Chromium (captures in the pull request).

- **The ratio cap applies in WebKit.** `Object.getOwnPropertyDescriptor(window, 'devicePixelRatio')` is an own
  accessor with a getter, configurable, on all three descriptors, and `(pointer: coarse)` is true: the script in
  `head_include` installs, the page reports 2 where the device has 3 (`window.deadnightPixels`), and the canvas is the
  page times 2. The "no own getter" and "not coarse" early returns do not happen there (the readout says `getter own`).
- **If it did not apply** (`?dprcap=3` loads that page): the canvas is 2250 x 1020 (2.3 million pixels against 1.0),
  and a unit is still 0.630 CSS px in the menu and 0.354 upright: the layout does not depend on the ratio, so the
  picture is the same size, only dearer to draw (a frame twice as long at ratio 3 as at 2 in `phone-frames.md`, #689).
  A ratio that failed to cap is a slow page, not a zoomed one.

## What iOS Safari does that nothing here shows (candidates, not findings)

Read from WebKit's documented behaviour and the page; each is separated by a line of the readout, and none is
measured on a device.

| Candidate | Why it could make a page look zoomed in | The readout line that separates it |
| --- | --- | --- |
| Pinch or double tap zoom stuck | iOS ignores `user-scalable=no` since iOS 10 ([eBay on disabling pinch zoom](https://opensource.ebay.com/evo-web/accessibility/anti-patterns/disabling-pinch-to-zoom)); `touch-action` and `gesturestart` hold it, and the page sets `touch-action` on `html` and `body` (none), not on the canvas (auto) | `visual ... scale` and `seen`; `touch-action` (computed, as the browser accepted it); `gestures N last scale S, two-finger touches M` (a pinch reached the page when N or M is more than 0) |
| Visual viewport not the page (iOS 26: after a keyboard closes `visualViewport.height` stays under `innerHeight`, [WebKit bug 297779](https://bugs.webkit.org/show_bug.cgi?id=297779), [Apple forum](https://developer.apple.com/forums/thread/800125)) | the engine sizes the canvas from `innerWidth` and `innerHeight` every frame, so a canvas taller than what shows is cut off and the game looks bigger than the screen | `check:` says `visual viewport is not the page` or `page panned`; `visual` and `root` against `page` |
| `100vh` against the visible height | no `vh` in the page, and the engine ignores it, but the readout shows the difference | `vh svh dvh lvh` against `page` (Safari's toolbars: `vh` is the tallest, `svh` the shortest) |
| Safari's page zoom (the aA menu) or the phone's Display Zoom | the page is fewer CSS px than the model's usual (844 x 390 on an iPhone 14) and every CSS px is bigger; the game is normalised to the page's height, so it looks the same size relative to the screen, but a finger-sized thing is larger | `page` and `screen` against the model; `physical` (the longer side times the real ratio: 2532 for an iPhone 14) |
| Safe-area insets in landscape (`viewport-fit=cover`) | the HUD is inset by the notch and the home bar, never scaled | `safe top right bottom left` |
| `text-size-adjust` | only DOM text is inflated, and the page has none (the readout opts out) | not a candidate for the canvas |
| The ratio cap not installing | a slow page, not a zoomed one (above) | `ratio real used cap getter` |
| The phone menu being 2x the desktop layout (by design) | `MenuScale.PHONE_FACTOR` 2: 0.72 CSS px a unit at 844 x 390 against 0.67 on a 1280 x 720 window, 1169 x 540 units against 1920 x 1080 (three rows of the Play tab, "Server Browser" cut to "Server Brows") | `check: all as designed` with the numbers a normal page has |

Also not testable here: Discord's own webview (an iframe of another origin stands in), and the Activity's copy button
(`WebClipboard` makes a read-only text box off screen in the frame; iOS zooms to a focused field under 16 px). Main has
no focused field in the page (`html/experimental_virtual_keyboard=false`); #1200 turns the engine's own input on, whose
inputs must be `font-size: 16px` (kit `docs/godot/web-export.md`), and which brings the keyboard, so the iOS 26 visual
viewport bug above becomes reachable with it.

If "zoomed in" is the menu, the lever is the factor (text floor 14 CSS px, taps 44: `test_phone_floor`); it is the
maintainer's call, so it is not changed here.

## Reading it off a phone: `?viewcheck`

Open the page with `?viewcheck` added (`.../index.html?viewcheck`, or `&viewcheck` after other parameters; in a Discord
Activity the page is the one Discord opens, so Safari on the same phone is the first thing to read). A green readout
covers the top left corner of the page (it ignores touches), refreshed twice a second. The first line is the verdict:
`check: all as designed`, or what is wrong (`page zoomed`, `visual viewport is not the page`, `page panned`,
`canvas is not the page`, `canvas pixels are not box x ratio`). The lines under it:

```text
check: all as designed
page 844 x 390 css px, root 844 x 390, outer 844 x 390
screen 844 x 390 avail 844 x 390 turn 90
visual 844 x 390 scale 1 (seen 1 to 1) at 0,0 top 0
vh 390 svh 390 dvh 390 lvh 390
safe 0px 0px 0px 0px
ratio real 3 used 2 cap 2 getter own physical 2532 px
canvas box 844 x 390 px 1688 x 780 css 844px x 390px
css px per unit: night 0.36 phone menu 0.72
touch 1 coarse true framed false scroll 0,0
touch-action html none body none canvas auto
gestures 0 last scale 0, two-finger touches 0
```

What to send back: a screenshot of the menu and one of a night, and what the first line says; and, after pinching the
page on purpose, the `gestures` and `scale` lines (does Safari zoom it, and does the page see the pinch).

- `visual ... scale` above 1, or `seen` showing a range, or `at` not 0,0: the page is zoomed or panned by the browser.
- `page` smaller than a phone's usual 390 to 430 short side: Display Zoom or the page zoom; `physical` names the model.
- `visual` or `root` different from `page`, or `vh svh dvh lvh` far from `page`'s height: the toolbars and the engine
  disagree on the height (the canvas is the page's `innerHeight`).
- `canvas box` not equal to `page`, or `canvas px` not `box` times `used`: the canvas is not the page.
- `css px per unit` far from 0.36 (night) or 0.72 (menu) at a page of about 844 x 390.
- `ratio` `used` must be 2 or less on a phone (`cap`), unless `?dprcap=` is on the page.

All of these are plain numbers of the page, so the answer says which of the candidates above is the one, or that none
is and "zoomed in" is the design.

## What only a real phone proves

iOS Safari's behaviour with `touch-action`, `user-scalable=no`, a focus and the toolbars; Discord's webview and the
scale it gives the frame; the device's own display size, page zoom and text size; whether the picture is the size the
maintainer meant by "should be".
