# The players' column on a phone (#1301)

With the touch layout up the players' column (the points boxes and the bots' chips, then the health card) stands over a
fingertip-high weapon strip, and under the round and objective cards. At the largest interface size a room of eight
people stood over the objective.

## What was measured

`HudFixture` over the real HUD, `hud.touch_layout = true`, notch insets, 8 people, the objective on its two lines, every
perk, on the two phone pages (844 x 390 and 667 x 375 CSS px, ratio 2). The column's top against the objective's bottom
(325 units; the round is 36 to 196, the objective 202 to 325 on every page and size):

| Interface size | Canvas (667 page) | Fingertip | Column top, 8 people | With 7 bots (chips) | Before |
| --- | --- | --- | --- | --- | --- |
| 0.8 | 2401 x 1350 | 159 | 711 | 646 | clear |
| 1.0 | 1921 x 1080 | 127 | 474 | 409 | clear (by 84 at the least) |
| 1.25 | 1537 x 864 | 102 | 284 | 219 | over by 41 and 106 |

The 844 page is the same within 6 units. A canvas is always 1350, 1080 or 864 units high whatever the page (the project
stretches to the height), so these three rows are every phone: only the largest size, which is the end of the setting's
range (0.8 to 1.25), is in trouble. The column was 332 units of boxes (66 + 7 x 32 + 7 x 6 of gap), 59 of chips (their
rows are 28 units, not the 25 of `HudBotChips.CHIP_HEIGHT`: a label's own line) and the health card 75 with its gap.

## The options, by what they save at 1.25 on the 667 page (the points and the health card have 366 units)

| Option | Saves | Verdict |
| --- | --- | --- |
| A shorter strip | 0 | The strip is a fingertip (`MenuScale.tap_units`, 44 CSS px): the weapon places are the phone's weapon control (#1280). |
| Gaps of 3 between the compact rows | 21 | Not enough alone (47 to 112 are needed), and the boxes' shadows touch. |
| The round card on one row | 70 | Enough with the gaps for eight people, not for the chips; a card the issue did not name. Done in #1305: [below](#the-round-card-on-one-row-1305). |
| The health card on one row | about 26 | Same. |
| The teammates two to a row | 120 | Takes the column from 478 to 283 with the chips: **chosen**. |
| The objective on one row, or elsewhere | 24 to 123 | It carries the area and what to do next; the issue says it cannot move out beside the column the way the challenge card does. |

Two to a row cuts the rows from seven to four, and a row is as tall as a compact box. What a half row (155 units: the
portrait is 32 and the box 117) cannot hold is the name (`NAME_ROOM` alone is 72 beside a number of 40 to 70), the level
badge and the emblem: a box in a pair shows the points alone, at the same type as before (24 units, `HudStyle.TEXT`),
`DOWN` or `DEAD` in the danger colour where the points are while the person is down. The seat's colour, the portrait,
the card and the frame stay. The names are on the scoreboard, which a finger held on the column opens (#1295).

## How it decides

`Hud._fit_players` gives `HudPoints.room`, the most height the column may take: from a gap under the round at its
minimum and the objective at its tallest (`HudObjective.max_height`, an area line and two lines of words, so the column
does not move when the words change) to the top of the health card. It is `INF` without the touch layout, so a desktop
and a pad never change. `HudPoints.refresh` measures the boxes and the chips one to a row (`HudPointsStack.height_at`,
from the children's own minimum sizes: the first version added the heights up from constants and was 6 units short of
the chips) and sets `HudPointsStack.mate_columns` to 2 when that is taller than the room and there are two teammates
or more. `HudPointsStack` is a container that lays the rows out itself, the same node count as the box container it
replaces (the late-round canvas-item budget counts nodes). Pairs are used where the boxes do not fit and nowhere else:
up to about 1.1 with the chips and 1.18 without, names and one box to a row stay.

## The round card on one row (#1305)

With the touch layout up `HudRound.compact` puts the reels on the left and the caption over the detail on the right,
one row of 66 unit reel tiles (a tenth smaller than the desktop's 72, the digits 55 units instead of 60) in a card 90
units high instead of 160. The detail ("400 LEFT", "NEXT IN 30", "THE END", "DOORS OPEN SOON") has what the reels leave
of the card's text line (173 units with two reels, 122 with three), at 24 units and shrinking toward the 20 unit floor
before anything is cut. The row and the box of words are made when the touch layout comes up and freed when it
goes, so a desktop's HUD holds neither. `Hud._fit_players` already read the round card's own height, so the
70 units flow into the column's room with no new rule: the room at 1.25 is 355 (667 page) and 358 (844 page), it was
285 and 288.

How often the names come back (one box to a row, a party of 3 to 8 people, with 0 and with 7 bots, measured by
`test_the_card_on_one_row_only_ever_brings_the_names_back`, the card in three lines against the card on one row):

| Interface size | 12 parties, card in three lines | Card on one row |
| --- | --- | --- |
| 0.8 | 12 keep their names | 12 |
| 1.0 | 12 | 12 |
| 1.25 | 6 | **10** (not 7 and 8 people with the seven bots) |

The same on both pages. At 1.25 the column one to a row needs 174 to 332 units without the bots' chips and 239 to 397
with them, against a room of 355 and 358: eight people alone now fit (332), seven people and eight with the seven bots
(359 and 397) are the only parties that still go in pairs.

## What is left

The room is a measure, so what a card of the column takes away shows at once. Before the round card took one row, at
1.25 with eight people and seven bots the column ended 2 units short of the room on the 667 page and 5 on the 844 page.
With it the column, in pairs, ends **72 units short on the 667 page and 75 on the 844 page** (room 355 and 358, column
283), and `test_the_room_left_for_the_bots_tag_at_the_busiest_case` pins it. The bots' tag of #1300 is a fingertip and a
gap (102 + 6 on the 667 page, 98 + 6 on the 844 page at 1.25), so it still cannot move into the column at 1.25 with a
full room: it is 30 to 36 units too tall for what is left. Without the chips 59 more are free, with fewer people more;
nothing else is left to take without making the type smaller.

The type is the one thing this change could not make bigger: a teammate's points are 24 units, which is 6.7 CSS px at
0.8, 8.3 at 1.0 and 10.4 at 1.25 on the 667 page (the same numbers as before: the compact box already used them).

## Proof

`tools/web_smoke/players_column_phone.py` exports the capture scene
(`game/tests/captures/players_column_phone.tscn`) and runs it in Chrome as a phone on both pages and both hands at the
three sizes, with 8 people, 7 bots and two people down; it checks the column against the round, the objective, the
health card, the perk badges and the strip in the scene's own rectangles and takes the pictures. After: 0 faults in 12
cases. Before (`--nofit`: the room taken away once the layout has settled): the column over the objective at 1.25 on
both pages and both hands, by 103 to 106 units with the chips (38 to 41 without them).
`test_players_column_phone.gd` does the same without a browser, for 3, 5
and 8 people.
