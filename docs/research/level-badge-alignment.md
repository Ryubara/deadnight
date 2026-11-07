# The level's digits and its icon on one centre

The maintainer, on #1115 (the level and icon beside each name), pointed out that the level number and the icon were
not aligned vertically and asked for that fix, the rest being good (#1161). This page is what was measured, the
cause and the fix. The test is `game/tests/ui/test_level_ink.gd`; the arithmetic is `LevelTag` and
`LevelIcons.body_centre`.

## What is "the icon" and "the digits"

- **The digits** are the glyphs of `0` to `9` in the font and size the place draws them in. Their ink runs from the
  baseline up to the height of the font's digits (15 units at 20 px, 24 at 32 px in our faces), so their centre is half
  that above the baseline. It is read from the font's own outlines (`TextServer.font_get_glyph_contours`), once for a
  font and size, so a different face or size moves the icon with it.
- **The icon's body** is the badge's frame and glyph: its ink above the strip of five progress bulbs
  (`LevelIcons.BULBS_TOP`, which the test uses too: the bulbs are drawn at y 120, radius 5.2, stroke 2 in the 128 px
  source, so their top edge is 113.8 of 128). The bulbs are small dots under the badge, and a player reads the badge
  by its frame, so the frame is what has to meet the digits. A token and a sign rest right on the bulbs; a ticket has a
  gap above them. The whole ink (bulbs included) is reported beside it in `ink.txt` and sits 1.1 to 1.9 units lower, so
  an icon centred by its whole ink would sit above the digits. Choosing the body is a choice, and the test states it.

## Why they did not line up

Every place set the icon from a box and the digits from a baseline, and neither box is what is drawn:

| Part | What the box says | What is drawn |
| --- | --- | --- |
| The art | The cell's middle (0.5) | The body's middle is at 0.461 (a ticket, levels 1 to 5), 0.444 (a token) or 0.452 (a sign): the bulbs take the bottom of the cell |
| The digits | The middle of the line (ascent + descent) | Digits sit on the baseline and the line keeps room for a descender, so their centre is a font-dependent distance from the middle |
| The engine | A label's baseline is where the maths says | A label sets its line on a whole unit (a half is dropped), and the shaped line is not the font's height (`Font.get_ascent` counts the fallback face) |

The places differed in how they guessed: the bottom-left box centred the icon on the box while the digits sit on the
name's baseline, which is the numerals' baseline (the biggest error); a name tag over a head used a `0.3 * font size`
nudge; the scoreboard, the end board and the night report used a centring container; the lobby's seat used a
shrink-centre and a label that centred itself. Where the guess was right the cause hid (the scoreboard was within half
a unit); where it was not, it was 3 to 9 units.

## The fix: one helper, every place calls it

`LevelTag` now has the arithmetic and `LevelIcons.body_centre(level)` the art's. The export writes each icon's body
rows into the manifest from the atlas (`LevelIcons.body_rows`), the game reads them (the web build reads no pixels),
and a headless test checks the manifest against the atlas, so a redrawn icon moves its place with it:

- `digit_span(font, size)` and `digits_centre(font, size, baseline)`: where the digits' ink is.
- `icon_top(centre, level)`: the icon's top for a body centred on `centre`.
- `icon_top_in_line(block_top, font, size, level)` and `icon_top_in_row(row_height, font, size, level)`: the same for a
  label whose line starts at the top, or is centred in a row (`line_baseline` is the engine's baseline in a line).

The places: the name tag over a head (`HudMarkers`) and the bottom-left box (`HudPlayerBox`) pass their baseline (the
box's baseline is now a whole unit, so the glyphs are where the maths puts them); the scoreboard and the end board
(`HudLevelCell`), the night report's level row and the lobby's seat (`LobbyScreen`) pass their label's font and row.
The lobby's framed seat needs no more room than it had: the frame is drawn over the row's top and bottom 7 units and
the icon (24 units) sits 10 to 12 units in from each edge, so a framed seat is as tall as a plain one (45 units; see
"The lobby with eight framed seats").

## How it is measured

`test_level_ink.gd` draws a place, then draws it again with the digits in flat magenta (no outline, no shadow) and the
icon's silhouette in flat magenta (the atlas with its colours replaced and its alpha kept), and reads the rows each
covers from the pixels. A first version differenced the picture against the ground and was blind to the icon's dark
outline on a dark card: it reported 1 unit errors that were not there. A flat colour no other thing uses is the reading
that works. Two readings of every place:

- **exact**: a viewport four times the canvas: the geometry, with no pixel rounding in it. Tolerance 0.75 units (half a
  unit is the best a place can do, since the glyphs land on whole units).
- **real**: the game's own window, 1920 x 1080 at the three interface sizes (0.8, 1.0, 1.25) and a phone held sideways,
  rows of whole pixels. Tolerance 1 px at one pixel to the unit, 1.5 px otherwise. **The phone is read at the factor the
  place really runs at**: the menus and the lobby have the menu's phone factor 2 (a unit is 0.72 px), but a night has
  the interface size alone (`NightScreen._ready`), so the HUD (tag, boxes, scoreboard, end board, night report) is read
  at 0.36 px to the unit at 1.0 and 0.45 at 1.25. Not at 0.8 (0.29 px: the digits are one to four rows tall and a row
  reading cannot tell a half unit from a unit and a half; the exact reading covers every size). The tolerance is the
  same 1.5 px as for any reading where a unit is not a pixel: it is the reading's resolution (a whole-pixel row on each
  side), not a widened bound. At 0.36 px to the unit it is 4 units: the reading still fails the boxes before the fix
  (3.0 to 3.5 px) and two of the compact box's (2.0 px), but a gap of a unit or two is below its resolution, and the
  exact reading is the guard for that.
- **A lobby is built under the router's theme** (`reading.host.theme = UIThemeBuilder.build(...)`): without it the seats
  are set in Godot's default font and a row is 24 units instead of 45, which once made the frame look as if it covered
  the icon (a first reading; it did not, and a margin added for it cost 144 units of scrolling in a lobby of eight).
  On a phone the lobby scrolls and shows one seat, so a phone reading is one lobby for each level.

Each with a one-digit and a two-digit level of each of the three frames (3, 7, 12, 55), and a framed plate (card,
emblem, frame) beside the bare one, in the tag, the box (four players, and eight for the compact box), the scoreboard,
the end board, the night report and the lobby seat. Pixel tests skip in a headless run, so **CI does not run them**:
run `gds godot -- --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ui/test_level_ink.gd -c
--ignoreHeadlessMode`; `LEVEL_INK_SHOTS=<folder>` keeps the pictures and the numbers. The headless suite
(`test_level_tags.gd`) checks the layout's own arithmetic.

## Numbers

The gap of the digits' centre below the icon body's centre, worst of four levels (and of the interface sizes read for
the window), before the fix and after. Exact: canvas units. 1080p: pixels at the three interface sizes. Phone: pixels
at the factor the place runs at (a night, 0.36 to 0.45 px to the unit; the lobby, 0.72). Readings out of tolerance:
**121 of 262 before, 0 of 262 after**.

| Place | Exact before | Exact after | 1080p before | 1080p after | Phone before | Phone after |
| --- | --- | --- | --- | --- | --- | --- |
| Name tag over a head | 0.50 | 0.13 | 0.50 | 1.00 | 1.00 | 1.00 |
| Player box (yours 66 high, a friend's 48) | 9.50 | 0.50 | 12.00 | 1.00 | 3.50 | 1.00 |
| Player box with a plate | 6.88 | 0.50 | 9.50 | 1.00 | 3.00 | 1.00 |
| Compact player box (32 high) | 3.50 | 0.50 | 4.50 | 1.50 | 2.00 | 1.00 |
| Scoreboard (and with a plate) | 0.38 | 0.25 | 1.50 | 1.00 | 0.50 | 0.50 |
| End board (and with a plate) | 0.38 | 0.25 | 1.50 | 1.50 | 0.50 | 0.50 |
| Night report, level row | 0.63 | 0.63 | 2.00 | 1.00 | 1.50 | 1.00 |
| Lobby seat | 2.88 | 0.50 | 4.00 | 1.00 | 2.50 | 0.50 |
| Lobby seat with a plate | 2.88 | 0.50 | 4.50 | 1.00 | 2.50 | 0.50 |

The scoreboard, the end board, the tag and the report were within the tolerance before the fix (their tests pass
without it; they guard the helper); the boxes and the lobby were not. What the maintainer saw was the box. A 1 px gap
at a night's 0.36 px to the unit is 2.8 units: one row of the picture, and the exact reading says the geometry is within
half a unit.

## The lobby with eight framed seats

A lobby of eight seats, each with a card, emblem and frame, is as tall as one with none: `test_lobby_framed_fit.gd`
(headless, and it prints the numbers). Rows 360 units (45 each), everything in the scrolling area 1787, before and
after the fix and with or without frames:

| Window | Canvas | Scroll area | Left to scroll | Panel bottom |
| --- | --- | --- | --- | --- |
| 1920 x 1080, interface size 1.0 | 1920 x 1080 | 960 | 827 | 1044 of 1080 |
| 1920 x 1080, interface size 1.25 | 1536 x 864 | 744 | 1043 | 828 of 864 |
| 844 x 390, menu factor 2 | 1168 x 540 | 420 | 1367 | 504 of 540 |

The lobby scrolls at every one of them with eight seats (the rules and the buttons are in the same scroll), before and
after; `UiFit` finds nothing cut or under another control. A first version of the fix kept a margin of 9 units above
and below each framed seat (+18 per row, +144 over eight: 971 left to scroll at 1080p instead of 827); it answered a
problem the theme-less test lobby had made up, and it is gone.

## The words on a plated player box in a night (not changed here)

On a plated box the name and the level are drawn dark with a seat-coloured outline (`HALO`, 3 units, #1158) over the
card. Measured over all 23 cards in a party of four (the eight seat colours of a party of eight are in the same range;
`ink/halo` is 5.6 to 14.9, as designed), the strongest pixel of the words against the card under them, WCAG ratio
(4.5 is AA for text):

| Reading | Red seat (1) median / worst | Blue (2) | Yellow (3) | Green (4) |
| --- | --- | --- | --- | --- |
| 1080p | 3.25 / 2.49 | 4.28 / 3.59 | 5.19 / 4.17 | 5.47 / 4.03 |
| Phone in a night (0.36 px to the unit) | 4.22 / 2.43 | 2.96 / 1.97 | 2.88 / 2.39 | 3.23 / 1.96 |

At 1080p the outline is a visible ring in the seat's colour (a quarter of the word's pixels); in a night on a phone it
is about one pixel wide, as wide as the word's strokes, and none of the word's pixels is the seat's colour, so the
words are a smear of the ring and the dark ink (the capture shows "3 RUBY" and "7 MOE" as dark red and blue marks).
It is on main (the box code is the same before and after this change) and in a real night (the same `HudPlayerBox` and
plates the HUD gets from the server).
