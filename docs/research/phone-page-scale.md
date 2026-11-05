# A phone page's scale: the menu on a real page (#1197)

The menu's phone layout (`MenuScale`, factor 2: a 1169 x 540 canvas, 0.72 CSS px to the unit at 844 x 390) was tuned and
captured in a Godot window of 844 x 390, and never applied on a phone's web page. Measured in the web export in
Chromium as a phone (844 x 390 CSS px, pixel ratio 3, touch), a unit was 0.36 CSS px, body text 6.5 to 9.4 px and tap
targets 19 to 23 px.

## Why

A web page's window is its canvas in device pixels, and the page reports a pixel ratio of at most 2
(`PhoneRender.PIXEL_RATIO_CAP`, `head_include`): an 844 x 390 page is a 1688 x 780 window. `MenuScale.is_phone` asked for
a window whose short side is under 500, so no phone page was a phone. Every test (`test_ui_fit`, `test_level_ink`, the
lobby fit) and every capture made a window of 844 x 390, which no phone page has.

## The test for a phone

`MenuScale.is_phone(window)` is true when either holds:

1. the window's own short side is under 500 (a native window; a desktop browser window at ratio 1; as it was);
2. the device is a touch screen (`TouchMode.detect`: a coarse pointer) and the page's short side in CSS pixels is under
   500. `PageSize.css` reads the canvas element's `getBoundingClientRect()`, so an iframe (Discord's Activity) reports
   its own size.

The layout does not depend on the ratio: the factor multiplies the base stretch, so 844 x 390, 1688 x 780 (ratio 2),
2532 x 1170 (ratio 3, `?dprcap=3`) and 1864 x 860 (a 932 x 430 page) all lay the menu out on 1169 or 1170 x 540 units.

| Case | Phone? | Test (`test_page_size.gd`) |
| --- | --- | --- |
| Phone page 844 x 390 at ratio 1, 2, 3 | yes | `test_a_phone_page_is_a_phone_at_every_pixel_ratio` |
| Biggest and narrowest phones, upright | yes | `test_the_biggest_phones_and_the_narrowest_are_phones`, `test_a_phone_held_upright_is_a_phone_too` |
| The limit: 499 and 500 CSS px | yes / no | `test_the_limit_is_500_css_pixels_on_the_short_side` |
| Tablet 1024 x 768, 1133 x 744 | no (as before) | `test_a_tablet_keeps_the_desktop_layout` |
| Desktop browser window, any ratio | no (as before) | `test_a_desktop_browser_window_keeps_the_layout_it_had` |
| Small desktop window 800 x 450 at ratio 1 | yes (as before, by its canvas) | `test_a_small_desktop_browser_window_is_a_phone_by_its_canvas_as_before` |
| A native window (844 x 390, 1920 x 1080), a native phone build | by its own size | `test_a_native_window_is_read_by_its_own_size` |

## Turning, resizing, the night

- The check runs on `size_changed`. A page turned upright (390 x 844: factor 2, the "turn your phone" prompt covers it),
  back, resized to a tablet and to a bigger phone ended right on the real page (`phone_layout.py --section turn`).
- A screen over the menu (Settings, Play together) hides the shell, which used to be the one place the factor was set:
  a page that crossed the limit under it kept the old layout. `MenuShell._on_window_resized` now sets it there too
  (`test_menu_scale_cover.gd`); a night keeps its own.
- A night runs on the interface size alone (`NightScreen._ready`, left as it is: #1192 and #1189). Leaving it did not give
  the menu's factor back to the Play screen it returns to (the shell is hidden below it): on a real page the Play screen
  stayed at 0.36 CSS px to the unit until Back. `NightScreen._exit_tree` now restores it, a frame later
  (`test_night_scale.gd`; changing the factor in `_exit_tree` made the night's own parts, already out of the tree, answer
  `size_changed` with errors).

## What the ruler found once the layout was on

`UiAudit` measures the smallest text and the smallest thing a finger presses in CSS pixels (a node's rectangle and font
size times the window's stretch and the page's CSS pixels per window pixel). The web probe publishes it
(`window.deadnight_audit`, `tools/web_smoke/phone_layout.py`), `test_phone_floor.gd` fails under 14 and 44. Faults that
nobody had seen at a layout no page reached, all the same fix (`TapFloor`, 62 units on a phone's canvas) or a size:

- sliders, toggles, selectors and text fields: 37.6 CSS px (`control_height` is 52 units): `TapFloor.fit`, in the match
  rules panel, Settings, Play together, Join and the name field;
- the lobby's rules were not in the panel's phone form (the Play screen's is): `rules.set_compact` in the lobby;
- the plate screen's short tabs: 10 CSS px type (14 units) and 24 px high: 20 units and a tap target;
- the Play screen after Leave night (above);
- the Server Browser (#1232 keyed its layout to the canvas in units, under 700 tall): on a phone page it ran at 0.36
  CSS px to the unit until the factor came from `MenuScale` (a 22 unit caption is 7.9 CSS px; main has no ruler, so
  that is arithmetic, and the before picture shows it). Now it takes the phone layout without help, at ratio 2 and 3.
  Its rows draw their own words, so `UiAudit` asks a control that does (`drawn_text_sizes`, `NightRow`) for them: the
  smallest is 15.9 CSS px (a 22 unit caption), and the map's name, cut down to 20 units at the least, is 14.4.
  `phone_layout.py` answers for the backend itself (`StubBackend`) and shows the list, the empty list, the one still
  loading and the one that failed (`--section browser`).

## Play together and the lobby's rules (#1227)

Measured again on main after the Server Browser (#1180, PR #1232) replaced Quick join: the fold had not moved for the
better. On a 1688 x 780 page (a 1168 x 540 canvas) the card's view is 436 units high, a button is 79 units (57 CSS px)
and the code field 62. The overline, the title, a two-line note and Server browser filled it, with Create a night half
cut; the code field, Join and Back were three screens' worth of scrolling away, under a scrollbar only.

Chosen: everything visible, because a fold cannot be made plain on a canvas that small. Five controls of 79 units and a
title are 470 units against 436, so no ordering of one column shows the code field and Back without a scroll. Play
together on a phone's canvas (`TogetherScreen._fit_phone`) drops the overline, the note and the empty status line, and
puts its four choices two to a row (`GridContainer`: Server browser and Create a night, the code and Join), then Back.
The desktop keeps its column (one grid column). `test_phone_fold` checks that all five controls lie inside the scroll's
view on every page of `UiFitRun.PAGES`.

The lobby's "Break between ro..." was the row's title column: `UIRow` asks for a column `control_width * 0.5` (220 units)
and trims the title with an ellipsis, a label that trims asks for no width of its own, and the lobby's card is only as
wide as its rows' minimums. `UIRow.show_whole_title` stops the trimming on the phone's form
(`MatchSettingsPanel.set_compact(phone)`, whole titles by default), so the column grows to the longest title, and
`UIRow.title_cut` is what the test asks. The solo Play screen was not cut at 844 x 390 and was still cut at the
narrowest phone (667 x 375, a 960 unit canvas) until #1250: the widest row (the break between rounds: a 254 unit
title, a 440 unit control, a 78 unit value, two 24 unit gaps) is 820 units, the scroll adds its 48 unit bar, and the
card's column was left 848 (960 less two 16 unit margins and the card's 80). `test_ui_fit` failed by 20 units, and the
first try (`PlayScreen.WHOLE_TITLES_WIDTH`) kept the trimmed titles below 1100 units. The fix gives the room back
without touching a font: `UIRow.set_tight` (the panel's compact form) makes the gaps in a row 16 units (8 less each,
16 on the widest row), and the Play screen's margins are 8 units on every side of a phone (the top and bottom already
were), 16 less across. The widest row is then 788 and the card 836 of 848, with every title whole at every page of
`UiFitRun.PAGES` (`test_phone_fold`: the solo screen walks all four).

Not fixed here, filed: the night's pause card and Settings from a night (fixed in #1205, below), tablets and small desktop
windows (#1206).

## Numbers

Before and after, the web export, 844 x 390 CSS px on a screen of ratio 3 (the page reports 2 to the engine, so the
canvas is 1688 x 780; `phone_layout.py --section tour`). Settings is one row: the first run did not move between its
tabs (the later one did: every tab at 44.8 px targets and 18.8 px text or more).

| Screen | CSS px per unit | Smallest text (CSS px) | Smallest tap target (CSS px) |
| --- | --- | --- | --- |
| menu Play | 0.36 to 0.72 | 7.9 to 15.9 | 23.1 to 46.2 |
| menu Loadout | 0.36 to 0.72 | 7.9 to 15.9 | 20.2 to 44.8 |
| menu Shop | 0.36 to 0.72 | 7.9 to 15.9 | 23.1 to 46.2 |
| menu Challenges | 0.36 to 0.72 | 6.5 to 15.9 | 22.4 to 44.8 |
| menu More | 0.36 to 0.72 | 7.9 to 15.9 | 19.1 to 44.8 |
| together | 0.36 to 0.72 | 9.4 to 18.8 | 19.1 to 44.8 |
| Server Browser, a list | 0.72 (after only) | 15.9 | 57.1 |
| Server Browser, empty, loading, failed | 0.72 (after only) | 18.8 | 57.1 |
| play solo | 0.36 to 0.72 | 9.4 to 23.1 | 18.8 to 44.8 |
| settings tab 1 | 0.36 to 0.72 | 9.4 to 18.8 | 18.8 to 44.8 |
| credits | 0.36 to 0.72 | 9.4 to 18.8 | 28.5 to 57.1 |

Other pages, the same probe (CSS px per unit, factor, phone?):

| Page | Canvas | Factor | CSS px per unit | Phone? |
| --- | --- | --- | --- | --- |
| Phone 844 x 390, ratio 2 (the game's cap) | 1688 x 780 | 2 | 0.72 | yes |
| Phone 844 x 390, ratio 3 (`?dprcap=3`) | 2532 x 1170 | 2 | 0.72 | yes |
| The same page in an iframe of another origin (Discord's Activity) | 1688 x 780 | 2 | 0.72 | yes |
| Phone 932 x 430 | 1864 x 860 | 2 | 0.80 | yes |
| Phone held upright, 390 x 844 (the turn prompt covers it) | 780 x 1688 | 2 | 0.41 | yes |
| Tablet 1024 x 768, touch | 2048 x 1536 | 1 | 0.53 | no (#1206) |
| Desktop window 1280 x 720 | 1280 x 720 | 1 | 0.67 | no |
| Desktop window 800 x 450, ratio 1 | 800 x 450 | 2 | 0.83 | yes (by its canvas, as before) |
| Desktop window 900 x 450, ratio 2 | 1800 x 900 | 1 | 0.42 | no (as before, #1206) |
| A night (844 x 390 page), its HUD | 1688 x 780 | 1 | 0.36 | phone, HUD at the interface size (#1192, #1189) |
| A night's pause card and its Settings | 1688 x 780 | 1, drawn at 2 | 0.72 | phone, `PhoneScale` (#1205) |

On the real page the menu came back to the factor 2 after a night, and the Play screen under it did too once
`NightScreen._exit_tree` restored it (it stayed at 0.36 before).

## What this does not prove

A real phone, a real iOS Safari (Chromium in emulation is not one), Discord's own webview (an iframe of another origin
stands in, `--iframe`), text drawn by custom `_draw` (ticket titles, the plate), which `UiAudit` does not see, and the
night's HUD (#1192, #1189).

## The host's lobby on a page (#1186)

`phone_layout.py --section lobby` opens Create a night against the stand-in backend (`POST /lobbies`, the poll, the
rules, the visibility), reads the lobby on a 844 x 390 page at ratio 3 (a 1688 x 780 canvas, factor 2: text 18.8 CSS px,
targets 44.8) and taps the Private night switch with a finger (`window.deadnight.spots` names it `private`,
`lobby_private` reads it back), then taps it again; the script fails unless the stand-in was told `private`, then
`public`. Before `LobbyPrivateSwitch.reveal` the lobby came up scrolled to the end of its area (Start with the copy
buttons and the Server Browser under it) and the switch sat half out of the top: the fixture lobbies of the suites could
not show it (their scroll stops at Start), only the real page could. What it cannot show: a real backend (the lobby's own
suites `test_lobby_private_online` use one).

## The night's pause card and its Settings (#1205)

A night keeps the window's factor at the interface size (its HUD and touch layer are made for 1080 units), so the card
that opens over it was 0.36 CSS px to the unit: card text 11.6 px, Settings text 9.4 px and its controls 18.8 px.
Changing the window's factor for the pause would move the HUD behind the card, so the card is drawn at the phone
factor by a control instead: `PhoneScale` sits over the screen with `scale = 2` and a size of the screen over 2, so its
children lay out on the menu's 1169 x 540 canvas (0.72 CSS px a unit) while the window stays at 2337 x 1080 units.
Godot draws the scaled text sharp (a capture shows it).

- `PhoneScale.factor_for` asks `MenuScale.is_phone`, and asks again on `size_changed`: a page that turns or resizes under
  an open card follows. On a tablet or a desktop it is 1 and the card is what it was.
- What lays out by its own size (`SettingsScreen._fit`: compact under 600 units) now sees 540 and takes the phone form.
  What asked the window (`UIFitScroll` read the viewport's height) takes a `limit`: the Settings sets it to itself.
- A button's least size in units is `MenuScale.tap_units(window, touch, inner_scale)`: 44 CSS px over the units of the
  scaled part (61 here). `UiAudit` multiplies by the control's own global scale, so the ruler reads the card as drawn.
- The web probe's audit measures the card alone while it is open (`NightScreen.card_root`): the HUD behind is another
  page's (#1192). `phone_layout.py --section night` opens the card, then each Settings tab, and now fails on them.

Measured in the web export, 844 x 390 CSS px page, ratio 2 (1688 x 780 canvas) and ratio 3 (`?dprcap=3`, 2532 x 1170);
the numbers are the same at both:

| Screen | Before: text, target (CSS px) | After: text, target (CSS px) |
| --- | --- | --- |
| Pause card | 11.6, 44.1 | 23.1, 57.1 |
| Settings, Video | 9.4, 18.8 | 18.8, 44.8 |
| Settings, Audio | 9.4, 18.8 | 20.9, 44.8 |
| Settings, Accessibility | 9.4, 18.8 | 18.8, 44.8 |
| Settings, Controls | 9.4, 18.8 | 18.8, 44.8 |
| Settings, Touch | 9.4, 18.8 | 18.8, 44.8 |

The night itself stays at factor 1, 0.36 CSS px (`in the night`: 7.2 px, #1192 and #1189). Tests: `test_phone_floor` (the
card and every Settings tab on four pages; 48 problems on main, none now), `test_night_scale` (the factor, the card's
canvas, a page that stops being a phone).

## The tab bar and the Loadout card on the narrowest page (#1271)

Two faults a floor test on text and taps does not see, both on the 667 x 375 page (a 1334 x 750 canvas, 960 x 540
units) and read in the web export (`phone_layout.py --size 667x375 --dpr 2`), then walked on every screen of the tour
at 667 x 375, 844 x 390 and 932 x 430.

**The plate over MORE.** `MenuShell` sized the plate once, in `_build_chrome`, from `get_viewport_rect()`. A menu built
under a screen that is not shown yet (the router's) runs `_ready` before the phone factor is on the window
(`_apply_scale` does nothing while the shell is hidden), so the canvas was still 1920 units wide and the plate took its
whole 372: it stood at x = 560 over a bar that ends at 589, 29 units of MORE under it ("MOR"). `MenuPlate.fit` now
lays the plate out again whenever the canvas may have changed (`MenuShell._fit_plate`: the factor set, `resized`), and
`MenuShell.header_overlap()` is what the web probe publishes (`header_overlap`; `phone_layout.py` fails on more than
half a unit). The tests (`test_menu_header.gd`) build the shell the way the page does: hidden, on a window at the
interface size, shown a frame later. Every earlier test set the phone factor first, which is why none of them saw it.

- Where it goes up the page sizes: only where the canvas is narrower than 1005 units (28 + the bar's 561 + 16 + the
  plate's 372 + 28), that is a page whose width over its height is under 1.86: 667 x 375, 640 x 360, 568 x 320 and a
  960 x 540 window. 844 x 390 (1169 units) has the plate at 769 and 100 units to spare.
- A tap on the covered part still takes: the plate and everything in it are `MOUSE_FILTER_IGNORE`, so a click at the
  left edge, the middle and 3 units from the right end of MORE opened it on the code before the fix
  (`test_the_last_tab_takes_a_tap_along_its_whole_width`). The fault was what a person reads, not what they press.

**The Loadout card with nothing to choose from.** The card is 372 units (540 less the header's 104 and the footer's 64)
on every phone page, and its own chrome took almost all of it: 32 and 24 units of the theme's margin and 8 of the
inner one on each side, the tab strip (two rows of 62 on the narrowest card: ten tabs need 721 units and the card has
576), the detail line (36), a 79 unit Randomize row under the card and the gaps. What was left for the scroll area is
below, as the web probe and `test_menu_header` read it (the view's height; items whole inside it):

| Page (CSS px) | Canvas (units) | View before | Items whole before | View after | Items whole after |
| --- | --- | --- | --- | --- | --- |
| 667 x 375 | 960 x 540 | 33 | 0 | 187 | 2 (and the heading) |
| 844 x 390 | 1169 x 540 | 99 | 0 (the weapon row, the Plate button cut) | 187 | 2 |
| 932 x 430 | 1170 x 540 | 99 | 0 | 187 | 2 |

The weapon row sat first on the Body page, so the first thing in the view was the "Weapon" label cut through its
letters; at 844 x 390 the same ("weapon" and "Hunting rifle" cut at the top, the Plate button under the line). Now:

- the card's margins are 8 and 6 units on a phone (`CustomizeScreen.CARD_MARGIN_COMPACT`), the Randomize button and
  the detail line share the card's last row (`_fold_footer`; the saved line is kept and hidden), the strip is one row
  (21 units of type, 14.6 CSS px at 0.694 a unit, over the floor of 14; 5 units of padding and no gap, so the room
  between two words is the same 10; the ticket's notch is 4 units), and the weapon row is at the end of the Body
  page (`append_row`). Focus: `LoadoutPanel.first_focus` was the weapon selector, which `follow_focus` scrolled the
  card to the foot for (a key or bumper into the tab); on a phone it is the wardrobe's current tab now.
- `WardrobeTab` and `MenuTabBar.TabButton` draw their own words, so the ruler did not read them: they say their size
  (`drawn_text_sizes`) and `test_phone_floor` and the web probe count them.
- Not the same fault, measured: the other tabs at 667 x 375 keep their content in view (the scroll area's height; items
  whole inside it): Play 372 (6), Shop 233 (2 rows), Challenges 217 (7), More 372 (4). Their last row is cut at the bottom
  as a scroll area's is, and none opens on a label cut at the top.
- Open, not done: the key hints at the foot of the menu are hidden on a touch screen (`MenuHints`: "a finger sees
  nothing") but the panel still leaves the 64 units for them, so a phone has 372 units where it could have 436. That
  would give every tab room; it moves every panel, so it is its own change.
