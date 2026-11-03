# The second map, played: what the dead, the presses and the bots did on it

What building the links, windows, buys and box of the small indoor map (#632) turned up, and the bot nights that prove
it. The design is [Playing it](../../design/smallmap.md#playing-it-links-windows-buys-and-the-box); the targets are rows
20 to 26 of [the formula](small-map-formula.md#economy-and-placement-targets).

## Four things written for one floor

The drive-in lot has one floor, so three rules measured flat and were right there. The map has two, 3.4 m apart; each
broke the first night, and each was found by tracing a bot's death, not by a test (the tests had no floors).

| Rule | What it did on two floors | Now |
| --- | --- | --- |
| A zombie keeps the height it spawned at | the dead of an upper window walked the ground floor's height, and everyone on a stair was a floor off | on a map with a storey the height is the path's: from the last point passed to the next, less the baker's lift (the walking mesh's points run 0.35 m over the floor, measured on this map), so a stair is a ramp |
| A swing lands within the flat reach | a zombie on the stair struck a player standing beside it, through the stair's wall: seven blows in four seconds, a solo bot down in round 5 | a swing needs the target within half a storey in height and a clear ray at 1.3 m (over the counter and racks) when it is near |
| A press reaches within the flat reach | a player upstairs was in reach of the door, wall weapons and boards on the floor below | doors, spots and boards must be on the player's floor (`NightWorld.on_level`) |
| A zombie picks the flat-nearest player | the dead under a player upstairs stood under him for want of a stair | a floor of height weighs three metres of walk, so the dead go for the player they can reach |

The lot is untouched: a map with no storey keeps the old path, and the old suites passed unchanged. Each fix has a
test that fails without it (the dead's height and the press's floor: `test_smallmap_windows.gd`,
`test_smallmap_links.gd`; the swing and the weight: `test_zombie_storeys.gd`).

## The bots had the lot's numbers

The bots' errands (shop, boards) begin only when the nearest dead one is 12 m away, and a lull to shop in comes when a
quarter of the round is left; a hurt teammate (under half health) holds every door back; and every profile's list names
the lot's doors. On 600 m² with up to 24 dead the dead are never 12 m away, so a night of four bought one link and sat on
10,000 points. The map's overlay now carries its own numbers (5 m, 0.6, 0 and its own list, weapons first, then the
stairs, the box last), and the lot's stay as they were. With them one bot alone buys all three links by round 6 to 8
and four buy the door and the first stair by round 2, but never the second stair: the door's "turn" rotates every 40 s
among the bots and the break is short. Playing with every link sold before the night (`--open=all`) shows the whole
map.

## The nights

`godot --headless --path game res://tests/captures/smallmap_bot_night.tscn -- --bots=4 --rounds=10 --seed=1 [--open=all]`
(`Regular`, `Veteran` and `Rookie` bots, the second map, the shared round table, 24 dead at the most):

| Night | Round reached | How it ended | Links bought by the bots | Windows torn | Most dead at once | Box plays |
| --- | ---: | --- | --- | ---: | ---: | ---: |
| One bot, seed 1 | 8 | alive in round 8 when the 40 minutes ran out (the round never closed) | side (round 1), stair start (round 3), stair side (round 6) | 12 of 12 | 9 | 2 |
| One bot, seed 2 | 10 | round 10 cleared at 9:15, stopped | side (round 1), stair start (round 2), stair side (round 8) | 12 of 12 | 10 | 3 |
| One bot, seed 3 | 10 | round 10 cleared at 26:00, stopped | side (round 1), stair start (round 2), stair side (round 6) | 12 of 12 | 10 | 0 |
| Four bots, seed 1 | 8 | all down in round 8 at 9:51 | side (round 1), stair start (round 2) | 12 of 12 | 20 | 5 |
| Four bots, seed 2 | 10 | round 10 cleared at 11:06, stopped | side (round 1), stair start (round 2) | 12 of 12 | 22 | 7 |
| Four bots, every link sold first, seed 1 | 10 | round 10 cleared at 9:55, stopped | all three, before the night | 12 of 12 | 20 | 6 |
| Four bots, every link sold first, seed 2 | 10 | round 10 cleared at 10:43, stopped | all three, before the night | 12 of 12 | 20 | 7 |

All twelve windows were torn in every night that opened the upstairs (every one of these), and the first link was bought
in round 1. The most dead at once never passed 24 (20 to 22 with four). The long runs take 15 s (one bot) to two minutes
(four) of wall time for 8 to 10 game minutes; they are not deterministic to the last bit (the bodies are physics), so
the table is a spread, not a number. Round 10 was reached in all seven nights and cleared in five.

The balance simulator's numbers for the map (`tools/balance/run_report.py --map small_indoor --nights 200 --brief`, the
shared round table with the map's overlay, its bots' shopping list; the simulator knows prices and counts, not
geometry):

| Skill | 1 player: median round (reach round 10) | 2 players | 4 players |
| --- | --- | --- | --- |
| weak | 3 (0%) | 5 (0%) | 7 (5%) |
| average | 10 (57%) | 11 (97%) | 13 (100%) |
| strong | 12 (100%) | 14 (100%) | 15 (100%) |

A strong party of four reaches round 15 in 73% of nights and a pair in 22%; a strong player alone in none: the formula's
ceiling (Nacht: "hard to push 20"), where the wall weapons stop improving and health grows 7% a round.

## What is open

- **A round that never ended.** In some nights (one in seven of these, and one of the first run) a bot stood alive for the
  rest of the 40 minutes with the round never closing. The trace shows a **train**: eight dead walking behind one bot round
  the side room's rack loop (31 m), no kill for minutes, and the bot's shotgun with 0 rounds in the magazine and 57 in
  reserve, its Tommy gun empty, 4,300 points unspent. It runs from the train and never stops long enough to reload,
  and the dead are slower than it, so nothing ends: the formula's train, held by a bot that does not reload on the
  move. A follow-up issue.
- **Four bots bought two links (fixed, #696).** The door's turn (the nearest able bot, rotating every 40 s) sat inside
  the team's one-errand turn (30 s slices, spent on ammo and weapons first), and the holder was rarely free with the dead
  within 5 m. The map's overlay now sets `bot_team_links`: the nearest free bot buys an affordable link, the others cover.
  The second stair also needed its stand chosen by height: the flat-nearest stand was the one up the flight, a walk round
  the map for a bot below. Four bots, rounds to 8, seeds 1 to 5: all three links bought by round 2 (round 3 in one), no
  bot over twice a link's price for more than 30 s (before, seeds 1 to 3: the second stair never, one bot 400 s over).
- **The offer card says "the next part of the lot".** The prompt's copy is the lot's; the map's own words are the HUD's.
- **The kit's solid sills.** The greybox's sills are bodies the walking mesh never reads, so the dead pass them; when the
  kit's window fixtures (CSG sills) replace the boxes, the dead need a way over, as the art page asks.
