# Words over a card, read from the pixels (#1189)

The design check agreed the words on a plated player box were fine (ink against the seat's colour, 5.6 to 14.9 to one).
On a phone in a night they were not: #1161's measuring found the level and the name a smear of dark ink and a ring of
the seat's colour, and #1189 fixed it. This page is what was measured, what the fix is and what it does not reach. The
test is `game/tests/ui/test_plate_words.gd` (windowed only: it reads pixels, a headless run skips its six tests).

## What is measured

Every place that puts words over a calling card is built once for each of the 34 cards the game has, at the factor it
really runs at (a night: the interface size alone; the lobby: the menu's phone factor; the readings are [below](#the-
readings-which-phone)): the player box of a party of four, the compact box of a party of eight, the box of three
downed players, the scoreboard, the end board and the lobby's seats (a card, an emblem and a gold frame on each). The
words are the labels whose text lies over a card. Each place is drawn three times: as it is, with the words made
clear, and with the words in one flat colour nothing else is (`MARKER`, no outline, no shadow: a dark outline on a
dark card is not seen by a difference of two pictures).

- **Strongest pixel** (the issue's reading): the darkest or the lightest pixel the words changed against the average of
  the unchanged pixels in the word's own rows and columns, one pixel round it, as a WCAG ratio. 4.5 is AA for text.
- **Letters on what touches them**: the median, over the pixels the letters mostly cover (at least half flat colour), of
  the ratio between the pixel as drawn and the average of the pixels beside it that the letters do not cover. 0 for a
  word with no such pixel. It is the reading that shows a smear: a stroke under a pixel wide has no pixel that is mostly
  ink, and one strong pixel somewhere in an outline can hide that.

The strongest-pixel reading of #1161 took the whole label's box as the ground, which let the card above and below the
words move the number (the same word on the same strip read 4.8 on one card and 6.5 on another); this one takes the
rows the word covers. The numbers of that page's table are therefore a little different (1080p red 3.25 median there,
4.43 here); the same cards and seats fail. There are 34 cards, not 23.

## The readings (which phone)

- **1080p**: a desktop, one pixel to the unit.
- **night on a phone x2**: 1688 by 780, a phone page of 844 by 390 CSS pixels at a pixel ratio of 2 (the cap): the
  canvas a real phone has, 0.72 pixels to the unit in a night. **x3**: 2532 by 1170, 1.08 to the unit (#1197).
- **night on a phone**: a window of 844 by 390, 0.36 pixels to the unit: a page at a pixel ratio of 1 (an old or a
  low-end phone, a desktop browser's phone mode). #1161 read the fault here first, which is its worst case, and its
  numbers are too pessimistic for a phone at a ratio of 2: the fault is smaller on the real canvas (the red seat's
  strongest pixel is 1.81 at its worst there, 1.31 at 844 by 390; 105 words of 408 are under 4.5 against 254) but it
  is the same fault, and it is real: red, violet, pink and orange read 1.8 to 3.6 and a downed seat's DOWN 2.8 to 3.0.
  The fix is judged at 1688 by 780 first and at 844 by 390 as the worst case.
- **phone in the menu**: the lobby, at the menu's phone factor (2), at 844 by 390 and at 1688 by 780.

## The cause

The words were dark with a 3-unit outline in the seat's colour over the card. At 1080p the outline is a ring a quarter
of the word's pixels wide and reads, though on a dark card the ring is what is seen and the dark ink inside it is a
hole. In a night on a phone a unit is 0.36 of a pixel: the outline is a pixel, the letters' strokes are less than a
pixel, and no pixel of the words is wholly the seat's colour or wholly ink. The ink-to-outline ratio (the design check)
is a property of two colours; what reaches the eye is the colours blended by coverage. A letter six pixels tall cannot
be made to have the design ratio on every pixel; what a ground can do is give the best pixel the most headroom.

## The fix

1. **A strip behind the words** (`HudNameTab`): the seat's colour, from before the level to after the name's text, as
   high as the line and a little, centred in the box, its right end leaning like the points tab's left end. The card
   shows above and below it and round it, through the box's corners and under the emblem; the points have their own tab
   as before. The outline is gone (it is what blurred), so the words have one ground whatever the card is.
   It is not a node: the night's canvas-item budget (`tools/perf/budget.json`, 230; main peaks at 229) has no room for
   one more item a box, so `HudNameTab` is a `RefCounted` (rect, colour, visible) that `HudPointsTab` draws in its own
   `_draw`, right after the tab. Its opacity is one constant, `HudNameTab.ALPHA` (1.0); a translucent strip is that
   number.
2. **Heavier type where a unit is under 0.6 of a pixel** (`HudPlayerBox.THIN_BELOW`, `THIN_BOLD` 0.9 of the face's own
   embolden on top of the HUD's; name, level and points). It is for a phone at a pixel ratio of 1 (0.36 to the unit):
   at 1688 by 780 and 2532 by 1170 it is not on, and the strip and the DOWN colour alone read 4.5 on every word in
   every seat. At 844 by 390 the strip alone left the red, violet and pink seats
   under 4.5 (3.1 to 4.3: those colours' best ink reaches only 5.6 to 7 to one, and a thin stroke loses a share of it
   to blending); a heavier stroke gives some pixel that is almost wholly ink. It is chosen from the scale the screen
   really runs at (`get_viewport().get_final_transform()`), so a desktop at 1080p is unchanged. A headless test window
   is a few pixels wide and gets the heavier type; `test_plate_boxes` sets it either way.
3. **The word DOWN** was the danger red on the dark a downed seat's box is (2.1 to one before the fix, with a card or
   without, since the outline was the same dark). It is pulled toward white until it reads 7.5 to one
   (`HudPlayerBox.legible`, `DOWN_CONTRAST`).

Ablation at 844 by 390 (strongest pixel, worst over the cards): the strip alone leaves red 3.97 (player box) and 3.06
(compact), violet 4.25 and pink 4.07; with the heavier type 5.30, 4.74, 6.03 and 6.03. A dark strip with a light ink
(the red, violet and pink pulled toward the HUD's dark until their light ink read 10 to one) was tried and kept out:
its strongest pixel was higher (9.4 against 5.4 for the red) but the letters reading was about the same (2.9 against
2.5), and four bright strips with four dark ones would not read as one family.

## What it is, and what it is not

Before and after for each place, worst over the 34 cards and the seats of the place (every seat is in the table below):

| Place | Reading | Seats | Words read | Strongest pixel, worst | Words under 4.5 | Letters on what touches them, worst |
| --- | --- | --- | --- | --- | --- | --- |
| player box | 1080p | 4 | 408 | 2.75 -> 5.58 | 93 -> 0 | 2.94 -> 3.76 |
| player box | night on a phone x3 | 4 | 408 | 2.15 -> 5.58 | 102 -> 0 | 2.32 -> 2.85 |
| player box | night on a phone x2 | 4 | 408 | 1.81 -> 5.46 | 105 -> 0 | 1.60 -> 2.67 |
| player box | night on a phone | 4 | 408 | 1.31 -> 5.30 | 254 -> 0 | 1.08 -> 2.43 |
| compact box | 1080p | 8 | 816 | 2.75 -> 5.58 | 189 -> 0 | 2.94 -> 3.76 |
| compact box | night on a phone x3 | 8 | 816 | 1.88 -> 5.58 | 239 -> 0 | 2.10 -> 2.83 |
| compact box | night on a phone x2 | 8 | 816 | 1.80 -> 5.44 | 352 -> 0 | 1.62 -> 2.59 |
| compact box | night on a phone | 8 | 816 | 1.26 -> 4.74 | 474 -> 0 | 1.06 -> 2.29 |
| downed box | 1080p | 4 | 408 | 2.75 -> 5.58 | 161 -> 0 | 1.98 -> 3.76 |
| downed box | night on a phone x3 | 4 | 408 | 2.15 -> 5.58 | 167 -> 0 | 1.74 -> 2.85 |
| downed box | night on a phone x2 | 4 | 408 | 1.81 -> 5.46 | 170 -> 0 | 1.60 -> 2.60 |
| downed box | night on a phone | 4 | 408 | 1.31 -> 5.30 | 170 -> 0 | 1.08 -> 2.15 |
| scoreboard | 1080p | 4 | 272 | 5.47 (not changed) | 0 | 6.18 |
| scoreboard | night on a phone x3 | 4 | 272 | 5.44 (not changed) | 0 | 4.27 |
| scoreboard | night on a phone x2 | 4 | 272 | 5.90 (not changed) | 0 | 3.46 |
| scoreboard | night on a phone | 4 | 272 | 5.78 (not changed) | 0 | 2.33 |
| end board | 1080p | 4 | 272 | 5.47 (not changed) | 0 | 6.18 |
| end board | night on a phone x3 | 4 | 272 | 5.47 (not changed) | 0 | 4.30 |
| end board | night on a phone x2 | 4 | 272 | 6.05 (not changed) | 0 | 4.16 |
| end board | night on a phone | 4 | 272 | 6.24 (not changed) | 0 | 2.39 |
| lobby seat | 1080p | 4 | 408 | 5.74 (not changed) | 0 | 4.14 |
| lobby seat | phone in the menu x2 | 4 | 408 | 5.46 (not changed) | 0 | 3.09 |
| lobby seat | phone in the menu | 4 | 408 | 5.31 (not changed) | 0 | 3.29 |

- The bar of the test is 4.5 on the strongest pixel and 2.0 on the letters reading (main: 1.06 on a phone, a smear; 2.0
  is a letter with at least a pixel that reads, and is not a design ratio). The strongest pixel reaches 4.5 on every
  word on every card in every seat, at every reading. The letters reading does not reach 4.5 on a phone (at 1688 by 780
  the median letter reads 2.7 to 5.8 by seat, red 2.7, violet 2.8 and pink 3.0 the lowest; at 844 by 390 2.3 to 5.3),
  and cannot: a six-pixel letter's median stroke pixel is a blend, and those colours' best ink reaches only 5.6 to 7 to
  one. The ceiling is the phone's pixels, not the plate: the points number on its tab with no card at all reads the same
  (compact box, seat 8, 3.9 in the strongest-pixel reading at 844 by 390 before this change). What is left is the HUD's
  scale on a phone, which this change does not touch.
- The scoreboard, the end board and the lobby seats read at 4.5 on every card at every size, so they are not changed
  (their words are light with a dark outline on a card under a dark veil).
- The red seat's strongest pixel at 1080p is 5.58 at best because that is the ratio of its ink and its colour (light on
  red). The other seats reach 7 to 16.

## Every seat

Median and worst over the 34 cards, before and after (three words a seat in a box, two on a board, for each card).

| Place | Reading | Seat | Strongest pixel, median / worst: before | after | Words under 4.5: before | after | Letters, median / worst: before | after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| player box | 1080p | 1 | 4.43 / 2.75 | 5.58 / 5.58 | 59 | 0 | 3.16 / 2.94 | 3.92 / 3.76 |
| player box | 1080p | 2 | 5.28 / 3.47 | 10.78 / 10.78 | 31 | 0 | 5.83 / 4.81 | 7.11 / 7.07 |
| player box | 1080p | 3 | 7.54 / 5.39 | 14.21 / 14.21 | 0 | 0 | 6.75 / 4.92 | 9.60 / 7.52 |
| player box | 1080p | 4 | 8.03 / 4.07 | 14.86 / 14.86 | 3 | 0 | 8.09 / 7.28 | 9.97 / 9.41 |
| player box | night on a phone x3 | 1 | 4.01 / 2.15 | 5.58 / 5.58 | 65 | 0 | 2.51 / 2.32 | 3.17 / 2.85 |
| player box | night on a phone x3 | 2 | 5.65 / 3.96 | 10.78 / 10.78 | 34 | 0 | 3.27 / 2.78 | 4.17 / 4.01 |
| player box | night on a phone x3 | 3 | 7.80 / 4.82 | 14.21 / 14.21 | 0 | 0 | 4.98 / 3.97 | 5.76 / 5.63 |
| player box | night on a phone x3 | 4 | 7.87 / 4.18 | 14.86 / 14.86 | 3 | 0 | 4.02 / 3.31 | 5.18 / 5.16 |
| player box | night on a phone x2 | 1 | 2.37 / 1.81 | 5.55 / 5.46 | 68 | 0 | 1.85 / 1.60 | 2.73 / 2.67 |
| player box | night on a phone x2 | 2 | 5.80 / 4.05 | 10.78 / 10.42 | 15 | 0 | 2.74 / 2.11 | 4.85 / 4.53 |
| player box | night on a phone x2 | 3 | 7.10 / 4.24 | 14.18 / 13.04 | 6 | 0 | 2.74 / 2.23 | 5.25 / 4.20 |
| player box | night on a phone x2 | 4 | 6.65 / 4.13 | 14.42 / 14.19 | 16 | 0 | 3.08 / 2.11 | 5.75 / 4.18 |
| player box | night on a phone | 1 | 1.83 / 1.31 | 5.44 / 5.30 | 68 | 0 | 1.26 / 1.08 | 2.54 / 2.43 |
| player box | night on a phone | 2 | 3.43 / 1.90 | 9.62 / 7.90 | 68 | 0 | 1.34 / 1.18 | 4.12 / 3.41 |
| player box | night on a phone | 3 | 4.01 / 3.38 | 11.29 / 6.80 | 68 | 0 | 1.58 / 1.32 | 5.30 / 4.44 |
| player box | night on a phone | 4 | 4.65 / 2.42 | 13.81 / 9.72 | 50 | 0 | 1.60 / 1.21 | 5.12 / 3.84 |
| compact box | 1080p | 1 | 4.43 / 2.75 | 5.58 / 5.58 | 59 | 0 | 3.16 / 2.94 | 3.92 / 3.76 |
| compact box | 1080p | 2 | 5.67 / 3.91 | 10.78 / 10.78 | 28 | 0 | 5.78 / 4.97 | 7.07 / 6.78 |
| compact box | 1080p | 3 | 8.00 / 5.81 | 14.21 / 14.21 | 0 | 0 | 6.75 / 4.90 | 8.49 / 7.52 |
| compact box | 1080p | 4 | 8.35 / 4.02 | 14.86 / 14.86 | 3 | 0 | 7.95 / 7.19 | 9.41 / 8.84 |
| compact box | 1080p | 5 | 5.70 / 3.24 | 8.74 / 8.74 | 31 | 0 | 4.64 / 3.42 | 5.59 / 5.13 |
| compact box | 1080p | 6 | 4.34 / 3.61 | 6.38 / 6.38 | 56 | 0 | 3.54 / 3.03 | 4.27 / 4.10 |
| compact box | 1080p | 7 | 7.03 / 3.42 | 7.37 / 7.37 | 9 | 0 | 4.06 / 3.51 | 4.85 / 4.68 |
| compact box | 1080p | 8 | 7.29 / 4.13 | 16.54 / 16.54 | 3 | 0 | 8.78 / 8.32 | 10.64 / 9.73 |
| compact box | night on a phone x3 | 1 | 3.21 / 1.88 | 5.58 / 5.58 | 68 | 0 | 2.37 / 2.10 | 3.13 / 2.83 |
| compact box | night on a phone x3 | 2 | 5.13 / 3.53 | 10.78 / 10.78 | 31 | 0 | 3.82 / 2.93 | 4.81 / 4.08 |
| compact box | night on a phone x3 | 3 | 8.10 / 6.06 | 14.21 / 14.21 | 0 | 0 | 5.29 / 3.54 | 5.58 / 5.22 |
| compact box | night on a phone x3 | 4 | 8.23 / 4.18 | 14.86 / 14.86 | 6 | 0 | 4.89 / 4.61 | 6.58 / 4.75 |
| compact box | night on a phone x3 | 5 | 5.51 / 3.63 | 8.74 / 8.74 | 25 | 0 | 2.89 / 2.62 | 3.83 / 3.67 |
| compact box | night on a phone x3 | 6 | 4.40 / 3.26 | 6.38 / 6.38 | 56 | 0 | 2.42 / 2.32 | 3.24 / 2.88 |
| compact box | night on a phone x3 | 7 | 7.10 / 3.49 | 7.37 / 7.37 | 31 | 0 | 2.63 / 2.23 | 3.21 / 3.14 |
| compact box | night on a phone x3 | 8 | 5.47 / 4.02 | 16.54 / 16.54 | 22 | 0 | 4.84 / 4.04 | 6.51 / 6.12 |
| compact box | night on a phone x2 | 1 | 2.31 / 1.80 | 5.54 / 5.44 | 68 | 0 | 1.84 / 1.62 | 2.68 / 2.59 |
| compact box | night on a phone x2 | 2 | 5.24 / 2.83 | 9.34 / 8.10 | 34 | 0 | 2.34 / 1.86 | 3.71 / 3.39 |
| compact box | night on a phone x2 | 3 | 4.75 / 3.55 | 13.98 / 10.60 | 40 | 0 | 3.03 / 2.26 | 4.62 / 4.18 |
| compact box | night on a phone x2 | 4 | 7.57 / 4.00 | 14.29 / 12.93 | 6 | 0 | 2.65 / 2.08 | 4.53 / 3.97 |
| compact box | night on a phone x2 | 5 | 3.38 / 2.14 | 8.48 / 6.69 | 65 | 0 | 2.15 / 1.89 | 3.31 / 3.29 |
| compact box | night on a phone x2 | 6 | 4.18 / 3.62 | 6.38 / 6.33 | 56 | 0 | 1.92 / 1.73 | 2.82 / 2.73 |
| compact box | night on a phone x2 | 7 | 4.01 / 2.73 | 6.79 / 5.71 | 62 | 0 | 2.13 / 1.96 | 2.97 / 2.88 |
| compact box | night on a phone x2 | 8 | 6.43 / 3.85 | 16.54 / 15.65 | 21 | 0 | 2.70 / 2.33 | 4.30 / 3.99 |
| compact box | night on a phone | 1 | 1.81 / 1.26 | 5.40 / 4.74 | 65 | 0 | 1.19 / 1.06 | 2.45 / 2.29 |
| compact box | night on a phone | 2 | 5.70 / 2.59 | 9.91 / 9.53 | 34 | 0 | 1.82 / 1.15 | 3.55 / 3.18 |
| compact box | night on a phone | 3 | 3.75 / 2.56 | 9.38 / 9.08 | 68 | 0 | 1.27 / 1.13 | 3.82 / 3.15 |
| compact box | night on a phone | 4 | 4.67 / 2.61 | 13.31 / 6.35 | 41 | 0 | 1.47 / 1.17 | 4.67 / 3.43 |
| compact box | night on a phone | 5 | 3.77 / 2.89 | 8.72 / 8.37 | 68 | 0 | 1.58 / 1.36 | 3.76 / 3.66 |
| compact box | night on a phone | 6 | 2.76 / 1.95 | 6.17 / 6.03 | 68 | 0 | 1.26 / 1.07 | 2.67 / 2.31 |
| compact box | night on a phone | 7 | 3.63 / 1.96 | 6.79 / 6.03 | 62 | 0 | 1.46 / 1.11 | 2.87 / 2.56 |
| compact box | night on a phone | 8 | 3.79 / 2.97 | 14.20 / 7.80 | 68 | 0 | 1.46 / 1.20 | 5.14 / 4.32 |
| downed box | 1080p | 1 | 4.43 / 2.75 | 5.58 / 5.58 | 59 | 0 | 3.16 / 2.94 | 3.92 / 3.76 |
| downed box | 1080p | 2 | 8.64 / 2.76 | 8.64 / 7.99 | 34 | 0 | 5.21 / 2.26 | 4.98 / 4.43 |
| downed box | 1080p | 3 | 7.49 / 2.76 | 7.49 / 7.49 | 34 | 0 | 4.93 / 1.98 | 4.56 / 4.39 |
| downed box | 1080p | 4 | 7.35 / 2.77 | 7.35 / 7.35 | 34 | 0 | 4.87 / 2.00 | 4.69 / 4.36 |
| downed box | night on a phone x3 | 1 | 4.01 / 2.15 | 5.58 / 5.58 | 65 | 0 | 2.51 / 2.32 | 3.17 / 2.85 |
| downed box | night on a phone x3 | 2 | 8.64 / 2.77 | 8.64 / 7.99 | 34 | 0 | 3.29 / 1.94 | 3.08 / 2.97 |
| downed box | night on a phone x3 | 3 | 7.49 / 2.82 | 7.49 / 7.49 | 34 | 0 | 3.16 / 1.74 | 3.16 / 3.14 |
| downed box | night on a phone x3 | 4 | 7.35 / 2.80 | 7.35 / 7.35 | 34 | 0 | 3.02 / 1.78 | 3.02 / 2.86 |
| downed box | night on a phone x2 | 1 | 2.37 / 1.81 | 5.55 / 5.46 | 68 | 0 | 1.85 / 1.60 | 2.73 / 2.67 |
| downed box | night on a phone x2 | 2 | 8.64 / 2.96 | 8.30 / 7.99 | 34 | 0 | 3.57 / 1.87 | 3.57 / 2.67 |
| downed box | night on a phone x2 | 3 | 7.49 / 2.99 | 7.49 / 7.48 | 34 | 0 | 3.24 / 1.71 | 2.98 / 2.63 |
| downed box | night on a phone x2 | 4 | 7.35 / 3.00 | 7.35 / 7.15 | 34 | 0 | 3.23 / 1.75 | 3.08 / 2.60 |
| downed box | night on a phone | 1 | 1.83 / 1.31 | 5.44 / 5.30 | 68 | 0 | 1.26 / 1.08 | 2.54 / 2.43 |
| downed box | night on a phone | 2 | 8.08 / 2.43 | 7.91 / 7.84 | 34 | 0 | 3.00 / 1.41 | 3.01 / 2.19 |
| downed box | night on a phone | 3 | 8.63 / 3.12 | 7.88 / 7.21 | 34 | 0 | 3.16 / 1.31 | 2.80 / 2.50 |
| downed box | night on a phone | 4 | 7.35 / 2.59 | 7.67 / 7.27 | 34 | 0 | 2.87 / 1.38 | 2.75 / 2.15 |
| scoreboard | 1080p | 1 | 10.75 / 5.65 | 10.75 / 5.65 | 0 | 0 | 12.39 / 6.74 | 12.39 / 6.74 |
| scoreboard | 1080p | 2 | 9.22 / 5.53 | 9.22 / 5.53 | 0 | 0 | 11.76 / 6.18 | 11.76 / 6.18 |
| scoreboard | 1080p | 3 | 12.19 / 5.72 | 12.19 / 5.72 | 0 | 0 | 11.25 / 7.27 | 11.25 / 7.27 |
| scoreboard | 1080p | 4 | 10.62 / 5.47 | 10.62 / 5.47 | 0 | 0 | 13.09 / 6.62 | 13.09 / 6.62 |
| scoreboard | night on a phone x3 | 1 | 10.28 / 5.55 | 10.28 / 5.55 | 0 | 0 | 5.92 / 4.90 | 5.92 / 4.90 |
| scoreboard | night on a phone x3 | 2 | 8.70 / 6.21 | 8.70 / 6.21 | 0 | 0 | 5.53 / 4.27 | 5.53 / 4.27 |
| scoreboard | night on a phone x3 | 3 | 11.84 / 5.90 | 11.84 / 5.90 | 0 | 0 | 4.93 / 4.63 | 4.93 / 4.63 |
| scoreboard | night on a phone x3 | 4 | 10.55 / 5.44 | 10.55 / 5.44 | 0 | 0 | 4.78 / 4.42 | 4.78 / 4.42 |
| scoreboard | night on a phone x2 | 1 | 11.57 / 6.94 | 11.57 / 6.94 | 0 | 0 | 10.01 / 4.05 | 10.01 / 4.05 |
| scoreboard | night on a phone x2 | 2 | 10.37 / 7.23 | 10.37 / 7.23 | 0 | 0 | 5.30 / 4.47 | 5.30 / 4.47 |
| scoreboard | night on a phone x2 | 3 | 12.58 / 5.97 | 12.58 / 5.97 | 0 | 0 | 6.02 / 3.46 | 6.02 / 3.46 |
| scoreboard | night on a phone x2 | 4 | 12.18 / 5.90 | 12.18 / 5.90 | 0 | 0 | 5.24 / 4.05 | 5.24 / 4.05 |
| scoreboard | night on a phone | 1 | 11.01 / 7.90 | 11.01 / 7.90 | 0 | 0 | 4.87 / 3.09 | 4.87 / 3.09 |
| scoreboard | night on a phone | 2 | 9.76 / 6.80 | 9.76 / 6.80 | 0 | 0 | 6.56 / 2.76 | 6.56 / 2.76 |
| scoreboard | night on a phone | 3 | 12.30 / 7.53 | 12.30 / 7.53 | 0 | 0 | 4.66 / 3.85 | 4.66 / 3.85 |
| scoreboard | night on a phone | 4 | 9.73 / 5.78 | 9.73 / 5.78 | 0 | 0 | 4.59 / 2.33 | 4.59 / 2.33 |
| end board | 1080p | 1 | 10.75 / 5.65 | 10.75 / 5.65 | 0 | 0 | 12.39 / 6.74 | 12.39 / 6.74 |
| end board | 1080p | 2 | 9.22 / 5.53 | 9.22 / 5.53 | 0 | 0 | 11.76 / 6.18 | 11.76 / 6.18 |
| end board | 1080p | 3 | 12.19 / 5.72 | 12.19 / 5.72 | 0 | 0 | 11.25 / 7.27 | 11.25 / 7.27 |
| end board | 1080p | 4 | 10.62 / 5.47 | 10.62 / 5.47 | 0 | 0 | 13.09 / 6.62 | 13.09 / 6.62 |
| end board | night on a phone x3 | 1 | 10.24 / 5.62 | 10.24 / 5.62 | 0 | 0 | 6.78 / 5.09 | 6.78 / 5.09 |
| end board | night on a phone x3 | 2 | 8.54 / 6.14 | 8.54 / 6.14 | 0 | 0 | 6.14 / 4.30 | 6.14 / 4.30 |
| end board | night on a phone x3 | 3 | 11.76 / 5.92 | 11.76 / 5.92 | 0 | 0 | 5.32 / 4.99 | 5.32 / 4.99 |
| end board | night on a phone x3 | 4 | 10.29 / 5.47 | 10.29 / 5.47 | 0 | 0 | 4.89 / 4.69 | 4.89 / 4.69 |
| end board | night on a phone x2 | 1 | 11.49 / 7.15 | 11.49 / 7.15 | 0 | 0 | 6.73 / 5.00 | 6.73 / 5.00 |
| end board | night on a phone x2 | 2 | 10.38 / 7.24 | 10.38 / 7.24 | 0 | 0 | 5.19 / 4.16 | 5.19 / 4.16 |
| end board | night on a phone x2 | 3 | 13.05 / 6.44 | 13.05 / 6.44 | 0 | 0 | 5.33 / 4.89 | 5.33 / 4.89 |
| end board | night on a phone x2 | 4 | 10.96 / 6.05 | 10.96 / 6.05 | 0 | 0 | 6.11 / 4.47 | 6.11 / 4.47 |
| end board | night on a phone | 1 | 11.34 / 8.03 | 11.34 / 8.03 | 0 | 0 | 5.73 / 2.88 | 5.73 / 2.88 |
| end board | night on a phone | 2 | 9.61 / 7.10 | 9.61 / 7.10 | 0 | 0 | 5.22 / 2.39 | 5.22 / 2.39 |
| end board | night on a phone | 3 | 12.39 / 7.25 | 12.39 / 7.25 | 0 | 0 | 4.68 / 4.26 | 4.68 / 4.26 |
| end board | night on a phone | 4 | 11.92 / 6.24 | 11.92 / 6.24 | 0 | 0 | 4.95 / 2.54 | 4.95 / 2.54 |
| lobby seat | 1080p | 1 | 10.90 / 6.85 | 10.90 / 6.85 | 0 | 0 | 5.94 / 4.20 | 5.94 / 4.20 |
| lobby seat | 1080p | 2 | 11.51 / 7.80 | 11.51 / 7.80 | 0 | 0 | 5.76 / 4.74 | 5.76 / 4.74 |
| lobby seat | 1080p | 3 | 11.74 / 7.13 | 11.74 / 7.13 | 0 | 0 | 5.63 / 4.23 | 5.63 / 4.23 |
| lobby seat | 1080p | 4 | 10.91 / 5.74 | 10.91 / 5.74 | 0 | 0 | 6.54 / 4.14 | 6.54 / 4.14 |
| lobby seat | phone in the menu x2 | 1 | 11.79 / 6.82 | 11.79 / 6.82 | 0 | 0 | 4.34 / 3.09 | 4.34 / 3.09 |
| lobby seat | phone in the menu x2 | 2 | 11.63 / 7.78 | 11.63 / 7.78 | 0 | 0 | 3.96 / 3.09 | 3.96 / 3.09 |
| lobby seat | phone in the menu x2 | 3 | 12.23 / 7.34 | 12.23 / 7.34 | 0 | 0 | 4.62 / 3.09 | 4.62 / 3.09 |
| lobby seat | phone in the menu x2 | 4 | 11.79 / 5.46 | 11.79 / 5.46 | 0 | 0 | 4.88 / 3.09 | 4.88 / 3.09 |
| lobby seat | phone in the menu | 1 | 11.93 / 8.46 | 11.93 / 8.46 | 0 | 0 | 4.16 / 3.72 | 4.16 / 3.72 |
| lobby seat | phone in the menu | 2 | 11.52 / 7.61 | 11.52 / 7.61 | 0 | 0 | 4.33 / 3.60 | 4.33 / 3.60 |
| lobby seat | phone in the menu | 3 | 12.19 / 7.07 | 12.19 / 7.07 | 0 | 0 | 4.15 / 3.29 | 4.15 / 3.29 |
| lobby seat | phone in the menu | 4 | 11.46 / 5.31 | 11.46 / 5.31 | 0 | 0 | 4.41 / 3.38 | 4.41 / 3.38 |
