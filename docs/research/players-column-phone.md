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
| The round card on one row | about 70 | Enough with the gaps for eight people, not for the chips; a card the issue did not name, with a design of its own. Left as a follow-up. |
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

## What is left

The room is a measure, so what a card of the column takes away shows at once. At 1.25 with eight people and seven bots
the column ends 2 units short of the room on the 667 page and 5 on the 844 page (the column's top is 333 against the
objective's 325 and a gap of 6). So the bots' tag of #1300 cannot move into the column at 1.25 with a full room: a tag
a fingertip high needs 104 units. Without the chips 59 more are free, with fewer people more. The next saving is the
round card on one row (about 70 units), which is a follow-up issue.

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
