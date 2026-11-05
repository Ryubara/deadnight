# The level's digits and its icon on one centre

The maintainer, on #1115 (the level and icon beside each name): "the level number and the icons aren't really aligned
vertically, that needs to be fixed, otherwise it looks good" (#1161). This page is what was measured, the cause and the
fix. The test is `game/tests/ui/test_level_ink.gd`; the arithmetic is `LevelTag` and `LevelIcons.body_centre`.

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
The lobby's framed seat also keeps the frame's room above and below, so the border no longer covers the top and bottom
of the icon (it did, by 2 to 3 units: the icon is as tall as the row).

## How it is measured

`test_level_ink.gd` draws a place, then draws it again with the digits in flat magenta (no outline, no shadow) and the
icon's silhouette in flat magenta (the atlas with its colours replaced and its alpha kept), and reads the rows each
covers from the pixels. A first version differenced the picture against the ground and was blind to the icon's dark
outline on a dark card: it reported 1 unit errors that were not there. A flat colour no other thing uses is the reading
that works. Two readings of every place:

- **exact**: a viewport four times the canvas: the geometry, with no pixel rounding in it. Tolerance 0.75 units (half a
  unit is the best a place can do, since the glyphs land on whole units).
- **real**: the game's own window, 1920 x 1080 at the three interface sizes (0.8, 1.0, 1.25) and a phone held sideways
  (844 x 390 at the menu's phone factor 2: a unit is 0.72 px), rows of whole pixels. Tolerance 1 px at one pixel to the
  unit, 1.5 px otherwise.

Each with a one-digit and a two-digit level of each of the three frames (3, 7, 12, 55), and a framed plate (card,
emblem, frame) beside the bare one, in the tag, the box (four players, and eight for the compact box), the scoreboard,
the end board, the night report and the lobby seat. Pixel tests skip in a headless run, so **CI does not run them**:
run `gds godot -- --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ui/test_level_ink.gd -c
--ignoreHeadlessMode`; `LEVEL_INK_SHOTS=<folder>` keeps the pictures and the numbers. The headless suite
(`test_level_tags.gd`) checks the layout's own arithmetic.

## Numbers

The gap of the digits' centre below the icon body's centre, worst of four levels, before the fix and after: in units
for the exact reading, in pixels for the real 1920 x 1080 window and the phone.

| Place | Exact before | Exact after | 1080p before | 1080p after | Phone before | Phone after |
| --- | --- | --- | --- | --- | --- | --- |
| Name tag over a head | -0.50 | +0.13 | -0.50 | +0.50 | -0.50 | +0.50 |
| Player box (yours 66 high, a friend's 48) | +9.50 | -0.50 | +9.50 | +0.50 | +6.50 | 0.00 |
| Player box with a plate | +6.88 | -0.50 | +7.00 | +0.50 | +5.50 | +0.50 |
| Compact player box (32 high) | +3.50 | -0.50 | +3.50 | +0.50 | +2.50 | -0.50 |
| Scoreboard (and with a plate) | +0.38 | +0.25 | +0.50 | +0.50 | +1.00 | +1.00 |
| End board (and with a plate) | +0.38 | +0.25 | +0.50 | +0.50 | +1.00 | +1.00 |
| Night report, level row | +0.63 | +0.63 | +1.00 | +1.00 | +1.00 | 0.00 |
| Lobby seat | +1.38 | +0.25 | +1.50 | +0.50 | +1.50 | +1.00 |
| Lobby seat with a plate | +1.13 | +0.25 | +1.00 | +0.50 | +1.50 | +1.50 |

The scoreboard, the end board, the tag and the report were within the tolerance before the fix (their tests pass
without it; they guard the helper); the boxes and the lobby were not. What the maintainer saw was the box.
