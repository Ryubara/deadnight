# Weapon upgrades and the health perk

Issue #281, from [round scaling](round-scaling.md): zombie health that compounds at the genre's 10% a round needs a
player whose damage is bought in steps. The genre's answer is an upgrade station for the weapon in hand and perks that
raise the player's health. We studied them for design only; the machine, names, numbers, look and sounds are our own.
What was built is on [the re-cut and the hearty tonic](../design/upgrades.md).

## What the genre does (design only)

Figures are the community's (W in the sense of [round scaling](round-scaling.md#how-to-read-the-numbers)), not read
from files.

- **The upgrade station** costs 5,000 points once per weapon, multiplies the weapon's damage (about 2 to 2.5 in the
  older games, 25% steps up to four times in a later one), grows the magazine and refills the reserve. It is the
  step that keeps a wall weapon alive past round 15.
- **Perks** are bought at machines, about 2,000 to 3,000 points each, at most four carried. The health perk raises the
  most health by a large share of the base (from 100 to 250 in the older games).
- Both are **bought with a hold or a press at a place in the map**, with a sound and a short animation, and cost
  points the economy has already paid out, so there is a point in the night where a player stops buying doors and
  walls and saves.

## What we took

| | Genre | Deadnight |
| --- | --- | --- |
| Station | 5,000 points, x2 to x2.5 damage | **1,500** (+1,500 per weapon already re-cut), **x1.75** damage, x1.5 magazine and reserve limit, filled |
| Health perk | 2,000 to 3,000, +150 health | **hearty tonic**: 1,000, **+50** (100 to 150), one per player |
| Names and look | the genre's | the re-cut at the projector, the soda fountain's tonics: from [the lot's design](../design/index.md) |

The prices are lower because our night pays less (an average solo player earns about 10,800 points reaching round 10
and spent 6,700 of them before this change) and has fewer things to buy; a player with a 1,500 point goal reaches it at
round 7 or 8. The multiplier is lower because our health curve is not the genre's: it is what the gate allows (below).

## How the numbers were chosen

Every run is the real rules and the real weapon definitions ([the simulator](balance-simulator.md)); the gate is the
shipped one (60 nights a cell, seed 4000, health growth 1.07 unless said). Medians are weak solo / average solo / average
2 players / average 4 players / strong solo; the gate wants 4 to 9 / 10 to 14 / 11 to 16 / 12 to 17 / 12 to 18.

| Re-cut damage | Medians | Gate |
| --- | --- | --- |
| nothing (the re-cut and the tonic change nothing, bought for 1 point) | 5 / 9 / 10 / 10 / 10 | **fails 8 ways**: four medians, the stampede kills 86%, the boss night is x1.03 |
| x1.25 | 5 / 10 / 11 / 14 / 15 | passes |
| x1.5 | 5 / 10 / 13 / 15 / 15 | fails: the stampede kills 50% (limit 40%) |
| x1.6 | 5 / 14 / 15 / 15 / 17 | passes |
| **x1.75 (shipped)** | **5 / 14 / 15 / 16 / 17** | **passes** |
| x2.0 | 5 / 15 / 15 / 18 / 16 | fails: average solo 15 (limit 14), 4 players 18 (limit 17) |

- **The first row is the finding.** The same shopping and the same 7% a round without a working re-cut is a wall: the
  medians fall by two to seven rounds and the stampede on round 10 becomes the end of the night. At 5% a round (health
  as it was) the gate was already green with no re-cut at all.
- **The upper edge is the boss night.** Above x1.75 average players reach round 15, the second boss night (86% of those
  who reach it die), and the median lands there, one over the gate's 14. The medians are steps because a boss night
  sits on 15: x1.5 and x1.25 pass or fail on the stampede, not on the median, and the 60-night cells are noisy
  (x1.25 passing while x1.5 fails is that noise, not a trend).
- **Health growth the weapon can carry.** At x2.0, 1.09 does not help (average solo still reaches 15); at x1.6, 1.09
  passes (13 / 14 / 15 / 15). So the re-cut at x1.6 to x1.75 can carry 1.07 and perhaps more; the issue asked for
  1.06 or 1.07 and it ships at **1.07**.
- **The price barely matters.** At x2.0 and 1,500, 2,500 or 3,500 points the medians stay 15 / 15 / 17 to 18: an average
  player who saves still pays for it by round 8 and the points glut ([rounds](../design/rounds.md#open-questions)) means
  a dearer re-cut costs them things they never needed (doors). It is set at 1,500 so it is a decision at round 7 to 9,
  not a luxury past round 12.
- **The step keeps the bench honest.** In the first runs, with one flat price and no stopping point, a strong solo
  player re-cut about four weapons a night (9,700 points) and reached round 16. The third now costs 4,500, and the
  model stops at two.
- **The hearty tonic is small in the model** (strong solo 16 against 17 without it, average solo unchanged): a blow is
  12 to 40 and the modelled player is down when it lands too often, not at 100 against 150. It is worth more to a person
  who plays near zero health than to the model, and nothing here depends on it.

### The 300 night report, before and after (seed 1)

`tools/balance/run_report.py --nights 300 --seed 1`, current `main` against this change. Medians by round, then
the average solo player's night:

| Cell | Median round before / after | Reach round 15 before / after |
| --- | --- | --- |
| weak, 1 player | 5 / 5 | 0% / 0% |
| average, 1 | 10 / **14** | 0% / 48% |
| average, 2 | 11 / **15** | 1% / 89% |
| average, 4 | 13 / **16** | 10% / 96% |
| strong, 1 | 12 / **17** | 2% / 75% |

| Average solo | Before | After |
| --- | ---: | ---: |
| Points earned a night | 10,800 | 21,500 |
| Points spent (share of earned) | 6,700 (62%) | 10,200 (47%) |
| Spent on the re-cut / the tonic | 0 / 0 | 1,170 / 780 |
| Spent on ammunition | 1,930 | 3,040 (14%) |
| Time to kill a walker / runner / brute (s) | 0.94 / 0.67 / 5.15 | 0.92 / 0.43 / 3.76 |
| Stampede (round 10): reached, killed | 57%, 25% | 78%, 0% |
| Boss night (round 15): reached, died in it | 0%, - | 48%, 86% |

The nights are longer, so they earn twice the points; every share is inside the gate (spend 20 to 90%, ammunition
8 to 35%, time to kill brute 3 to 12 s). The end of an average night moved from the stampede and the rounds after it
(round 10 to 13, a mix of walls) to the second boss night at 15, as in the original, where a player of this skill dies
between 8 and 15.

## 5,000 flat, once a weapon (#909)

The maintainer, playing round 12 with three bots, saw the bench ask 3,000 for his second weapon and said it should
cost 5,000 every time, and that a weapon can be re-cut once "for now". **Where the price grew:** the section "The step
keeps the bench honest" above. #435 chose 1,500 plus a step of 1,500 for each weapon already re-cut
(`UpgradeTuning.price_step`) because the first runs, with one flat price and no stopping point, let a strong solo
player re-cut four weapons a night; then the carry (#566) added `PlayerState.recuts_lost` so that giving a weapon up
did not make the next re-cut cheaper. Both came from the model's behaviour, and the genre's own station (5,000 once
per weapon, the first row of this page) was set aside on the note that "the price barely matters". The price was the
maintainer's to set. Now it is the item's alone (`upgrade_weapon`, 5,000), `price_step` and `recuts_lost` are gone
(the rules snapshot is version 15), and the refusal for a re-cut weapon was already there (`ALREADY_OWNED`, the
bench's `recut_done`); its card now says why.

The simulator and the bots read the price from the item, so they follow with no change of their own: a modelled player
saves for 5,000 (`saves_for`), re-cuts one weapon (two when strong), and the bots' `re_cuts` still counts weapons.
Gate cells (60 nights, seed 4000; weak solo, average 1, 2, 4 and 8, strong solo), the baseline taken from `main`
(`0fe9a1ff`) before any edit:

| | Medians | Gate |
| --- | --- | --- |
| `main`, 1,500 and the step | 5 / 13 / 15 / 16 / 18 / 18 | passes |
| 5,000 flat | 5 / 11 / 14 / 16 / 17 / 17 | passes (every median inside its range; no retune) |

The average player's re-cut comes later (it needs 5,000 saved), which costs a round or two in the middle cells, as
this page said it would ("a dearer re-cut costs them things they never needed").

## Traps the model fell into (and the policy that fixed them)

- **A shopping list is read again at every break.** The re-cut can be bought for another weapon, so the modelled player
  bought one every break and was always saving for the next at 3,000, never reaching the tonic. `SimSkill.re_cuts` is
  how many weapons a player re-cuts in a night (1, 2 for strong).
- **Saving has to stop other buying.** Players who bought doors and the crane first never had 1,500 at a break; the
  gate saw no effect. `SimSkill.saves_for` names the items a player saves for: nothing after them in the list is
  bought until they are.
- **The order matters more than the item.** With the re-cut before the crane the average player had no Tommy gun in the
  stampede (the crane is where it comes from), re-cut the rifle (0.5 s a kill) and the stampede killed 83% of them.
  The list is the wall weapons, the doors, the crane, then the re-cut and the tonic: a human buys the crowd weapon
  first and re-cuts it.
- **Which weapon.** The player re-cuts the firearm with the best sustained kill rate against the walker of that round
  after the re-cut (`SimWeapons.sustained_dps_of`), usually the Tommy gun.
- **A long wait in the break ran into the next round.** The crane's spin (4.5 s) in a 5 s break lets the break expire
  inside the sim's wait; a night could play a round past its cell. The cell now stops at its last round.

## Open

- Only the hearty tonic has an effect; second wind, quick hands and fleet are entries with no effect and no machine.
- One re-cut a weapon, the maintainer's rule "for now" (#909). A second step (the later games' repack) is a follow-up
  if weapons need to keep up past round 20.
- Hearty may want more (+75 or +100) once the model has blows that scale with health; the gate does not ask for it.

## Sources

- Upgrade station and perk figures: the same community sources as [round scaling](round-scaling.md#sources) (the
  Call of Duty Zombies wiki on Pack-a-Punch and perks; patch notes for the later games).
