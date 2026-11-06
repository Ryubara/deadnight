# The challenge card on a phone (#1299)

The challenge prompt stood at 0.36 of the screen's height on the left edge, under the round and objective cards and over
the players' column. On a phone the weapon strip is a fingertip high and lifts that column, and a room of eight grows it
up: the card was drawn over the points.

## What was measured

`HudFixture`, `hud.touch_layout = true`, 8 people, notch insets, the card up with three lines, the card's bottom against
the column's top (a negative room is an overlap), on the two phone pages (844 x 390 and 667 x 375 CSS px, ratio 2):

| Interface size | Canvas (667 page) | Room, 8 people | Room, with 7 bots (chips) |
| --- | --- | --- | --- |
| 0.8 | 2400 x 1350 | +88 | +23 |
| 1.0 | 1921 x 1080 | -53 | -118 |
| 1.25 | 1537 x 864 | -194 | -259 |

(The 844 page is the same within 6 units.) The issue's table was for one interface size; the card is over the column at
1.0 and 1.25 on every page, with or without the bots, and a taller column (a tag in it, #1286 first stood there) would
have crossed it at 0.8 too. There is no room in a column of the left edge: at 1.25 on the 667 page the column's top
(219 to 284) is above the objective's bottom (325), so the card cannot stand under the objective at any height.

## What stands now

`ChallengeFit.place` (pure geometry, `ui/hud/challenge_fit.gd`) and `Hud._fit_challenge`: the card stands where it always
did when nothing is in the way, and otherwise in the nearest free place beside the column (x from the column's right
edge), as wide as the ground allows (316 units, 253, or 190 at the least, the words wrapping onto another line, the
count typed at the words' size under 260 so the caption is not cut: `HudChallengeCard.set_width`). What it keeps off
is read from the boxes on the screen, so no number says how tall the column may get:

- **hard** boxes, which it never stands over: the round, objective, points, health, perks, weapon strip and ammo cards,
  the three corner columns whole (so a tag put in one later is in its box), the box round the middle of the screen
  (`CENTRE_CLEAR`) and every touch button and place (`Hud.markers.held`, which `NightScreen` sets from the touch layer);
- **soft** boxes, which it keeps off while there is room and meets when none misses them: the feeds, the banner, the
  marquee, the boss bar, the prompt, the lane's cards and the ground the point gains take (their whole stretch, from
  the offset beside the crosshair to the bottom, centred as `HudGains.room` is: a hidden part's own rectangle is not
  where it will draw).

It looks again each frame the card shows (the columns, the buttons and the cards settle over a few frames, and a perk or
a lane card comes and goes), and only searches when the boxes, the words or the HUD's size changed. When nothing misses
the hard boxes it keeps the usual place, as before.

Because the card goes beside the column and not above it, how tall the column gets does not matter: a block a fingertip
high added to the column leaves the card clear on every page and size, and so does one 480 units high (a sweep). What
limits the card is the ground to its right: on the smallest page at 1.25 the free band between the column's edge and the
gains is 190 to 253 units, and with a card of the lane, a feed and the prompt all up as well the card may meet a row of
the feed (a left hand's feed stands on the card's side) rather than a button or a card that stays: the test names that
one case.

## Found on the way

At 1.25 on both pages the players' column of 8 people stands over the objective card (38 to 106 units): #1301.

## The measure of a card (the mistake)

The search first took the card's height from `get_combined_minimum_size()` straight after setting its width, which
answers for the width the card had until the layout runs, and the card was 12 units taller than it measured: it stood
over a button. `HudChallengeCard.size_at` now measures from the parts (the lines the words break into at the width times
`get_line_height()`); the search takes the height the layout gave (`HudChallenge.laid_size`) for the width the card has
and `size_at` for the others, looks again each frame, and the card keeps its size at its least. On the real page the
same words took a third line at 0.8 (the first web run found the card 175 high where the headless run said 147), so
the busiest case is run in Chrome as well
([lesson](https://github.com/Ryubara/gdstudio/blob/main/docs/lessons/2026-11-05-a-card-measured-its-height-before-the-layout-gave-it-its-width.md)).

## Tests

`test_hud_challenge.gd`: the overlap check runs on the desktop canvases with the touch layout on and off, both hands;
`test_on_a_phones_page_it_stays_clear_of_eight_players_and_the_buttons` (both pages, three interface sizes, both hands,
with and without the bots, every perk, a feed, a prompt, a card of the lane, the real touch buttons' boxes);
`test_a_column_a_fingertip_taller_still_leaves_the_card_clear`; and the narrow card's words and height.
`test_challenge_fit.gd` is the geometry. `tools/web_smoke/challenge_card_phone.py` runs the busiest case on the real
page in Chrome as a phone, reads the boxes the scene publishes and takes the pictures.
