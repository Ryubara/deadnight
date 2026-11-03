# Round scaling: Call of Duty Zombies against Deadnight

How Call of Duty Zombies makes each round harder, what that asks of the player's weapons and points, and what it says
about our curves (issue #265, and #254 for the shop weapons). We study the numbers for design only; nothing is copied.
The decisions it feeds are on [rounds](../design/rounds.md) and [weapons](../design/weapons.md); the speed side is on
[movement speeds](movement-speeds.md).

![Health, count, time to kill and points against the round: Call of Duty and Deadnight before and after](round-scaling.png)

## How to read the numbers

**D** is read from the game's scripts (quoted by the community), **W** a wiki or forum claim we could not check
against files, **E** our estimate with its basis. The games differ (World at War, Black Ops 1 to 3 share the rules
below; Cold War and later change them), and most of what a fan site prints is **W**.

**Our units.** Our walker has 50 health in round 1 and 8 more a round to round 8, then 5% a round. The original's
zombie has 150, so "in our units" divides by 3 and keeps every ratio: 150 is 50, 950 is 317.

## 1. Zombie health (W, widely quoted from the scripts)

150 in round 1, 100 more each round to round 9 (950), then 10% more each round: `950 * 1.1^(round - 9)`.

| Round | 1 | 5 | 9 | 10 | 15 | 20 | 30 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Original | 150 | 550 | 950 | 1,045 | 1,683 | 2,711 | 7,031 |
| In our units | 50 | 183 | 317 | 348 | 561 | 904 | 2,344 |
| Deadnight | 50 | 82 | 111 | 117 | 149 | 190 | 310 |

Five times the original's growth in the first nine rounds, then 1.1 against our 1.05 a round. By round 20 a zombie there
is 18 times a round-1 one and here 3.8 times. Boss and special zombies are other tables.

## 2. Zombies in a round (W: wiki tables, reproduced by community datamines; the formula for round 10 on is a fit)

Solo: 6, 8, 13, 18, 24, 27, 28, 28, 29 in rounds 1 to 9; from round 10, `24 + floor(0.5 * 0.18 * round^2)` solo and
`24 + floor((players - 1) * 0.18 * round^2)` with two to four players (round 10: 33 solo, 42 with two, 78 with four).
Two players are 7, 9, 15, 21, 27, 31, 32, 33, 34 in rounds 1 to 9; four 10, 12, 21, 29, 37, 45, 49, 52, 56. The count
grows with the square of the round, and each extra player adds about as much again from round 10 (our `count_per_extra_player`
of 0.6 per player sits close to it: four players are 2.8 times solo here and about 2.4 there).

## 3. Spawn cap and spawn delay (W, one forum chart; the cap is also in the mod sources)

- **Alive at once:** 24 zombies, at every round and player count (the rest of the round's count waits).
- **Delay between spawns:** 2.0 s in round 1, times 0.95 each round, down to a floor of 0.1 s (round 64) (W). Round 10:
  1.26 s, round 20: 0.76 s.
- Round time follows: a zombie only appears when there is room under 24, so from about round 8 the delay is not what
  paces the round; the cap and how fast the players kill are.

Ours: 3.2 s decaying 4% a round to 0.5 s (round 10: 2.2 s, round 20: 1.5 s), and 6 alive at once rising 0.8 a round to 28
(round 10: 13). The original fills its map from round 5; ours climbs more slowly and has the room to fill later.

## 4. Points (W: wikis for World at War and Black Ops 1)

10 for every bullet that hits and does not kill, 60 for a kill by a body shot, 100 for a headshot kill, 130 for a melee
kill. No round bonus. Doors cost 750 to 2,000, wall weapons 500 to 1,500 (their ammunition half the price), the Mystery
Box 950, Pack-a-Punch 5,000, perks 2,000 to 3,000. The kill values are ours already (60, 100, 130); we pay 4 or 8 for a
hit and at most four hits a zombie, which is the main difference and a decision (it stops a high-volume gun from
farming one zombie).

A round in the original pays about its zombies times 100 to 130: round 10 is about 3,300 to 4,300 (E: 33 zombies, one
or two paid hits each and the kill). Ours pays about 1,400 to 1,700 in round 10 (the balance report, average solo), which
is a smaller share of a bigger shop of cheaper things.

## 5. Damage, headshots, Pack-a-Punch and why the box matters (W and E)

- **Damage per bullet** is roughly 20 to 40 for the starting pistol and the wall rifles and submachine guns, so a round-1
  zombie (150) takes 2 to 8 hits and a round-20 one (2,711) 70 to 130. A weapon that does not grow cannot keep up with a
  10% a round compounding.
- **Headshot multipliers** differ by weapon: about 1.5 to 2 for pistols and submachine guns and up to 3 to 5 for sniper
  rifles (W). They help a skilled player but do not change the order of magnitude.
- **Pack-a-Punch** (5,000 points) is the scaling mechanism: it multiplies the weapon's damage (about 2 to 2.5 times in
  World at War and Black Ops 1 (E); in Black Ops 4 a repack adds 25% up to four times (W: a patch note); in Cold War
  the third level is a multiplier of 4, raised to 5 in a season 4 update (W: a patch note)), adds ammunition, and
  upgrades further in later games.
- **Wall weapons stop being viable at about round 15 to 20** (E: community consensus; the basis is that a 30 damage gun
  needs 56 hits for a round-15 zombie): the player stays alive on Pack-a-Punched weapons and the box's wonder weapons,
  which deal hundreds to thousands a hit or by area. That is why the box matters: it is the only source of the very
  strongest weapons, and the economy pays for it (950 a spin, and the points a round earns by round 10 buy about
  four spins).

The shape is therefore not "health outgrows weapons": it is **health compounds at 10% and the player's damage is bought
in steps** (wall weapon, then Pack-a-Punch, then the box's best), each step paid for by the points the round before it
earned. A game with health that compounds and weapons that do not has a wall by design.

## 6. Our curves against the original's

| Round | Original (our units) | Deadnight health | Original zombies, solo | Deadnight zombies |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 50 | 50 | 6 | 4 |
| 5 | 183 | 82 | 24 | 10 |
| 10 | 348 | 117 | 33 | 21 |
| 15 | 561 | 149 | 44 | 36 |
| 20 | 904 | 190 | 60 | 54 |

- **Count** is close from round 15 and about a third short in rounds 5 to 10. It is a cost of the alive cap and the
  spawn pace too (section 3), not of the count alone.
- **Health** is far flatter. The reason is weapons: our weapons did not grow at all, and the balance simulator showed
  that no shop weapon was a step up from the revolver (#254), so the curve had been lowered to the weapons that exist
  (#188, #197). The original answers the same problem with Pack-a-Punch and the box.

### Time to kill, with the shop weapons stepped up (body shots, reloads spread over the shots)

Seconds under fire to kill a walker, the table in the chart. Before and after the weapons of #254 (rifle 95 damage,
0.5 s
a shot, 40 to 80 reserve; shotgun 19 a pellet, 0.8 s, full damage to 8 m and 35% at 22 m, 30 to 60 reserve):

| Weapon | Round 1 | Round 5 | Round 10 | Round 15 | Round 20 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Revolver | 1.2 | 1.6 | 2.1 | 2.9 | 3.3 |
| Tommy gun | 0.6 | 0.8 | 1.2 | 1.5 | 1.9 |
| Pump shotgun | 1.3 -> 1.2 | 1.3 -> 1.2 | 2.6 -> 1.2 | 2.6 -> 1.2 | 3.9 -> 2.4 |
| Hunting rifle | 0.8 | 1.7 -> 0.8 | 1.7 -> 1.6 | 2.5 -> 1.6 | 2.5 -> 2.3 |

The rifle now kills with two body shots up to round 20 (190 health; it was two shots to round 13), the shotgun with one
blast at point blank up to round 15 (152 damage; it was one to round 5). Against the original, where the same zombie is
5 to 18 times the health of round 1, the revolver and the submachine gun stay in the same 1 to 3 seconds because our
health barely moves: that is the other half of the finding in section 7.

## 7. What the simulator showed, and what is applied

- **The model had a blind spot, now fixed.** The simulated player picked its weapon by sustained damage a second. A
  95 damage rifle against 117 health needs two shots, so it does no better than a 60 damage gun, and the picks went
  wrong: with the stepped-up shop weapons the average solo median fell from 11 to 9 and the stampede killed half of the
  strong players, because they held a slow rifle and a pump shotgun in a crowd instead of the submachine gun. The
  pick (and the swap to the weapon for the target in front of them) now counts the shots that land whole against the
  walker the round sends (`SimWeapons.sustained_dps(id, health)`, `kill_rate_at`). With that the same weapons are worth
  what they should be. A person sees the same thing: a weapon that overshoots the health does not make the kill faster.
- **The weapon step-up of #254 is applied as proposed.** With the corrected model each shop weapon is worth rounds:
  the rate at which average solo players reach round 10 rises from 59% to 83% with them (old model rerun with the same
  seeds), and the `--shopping` experiment of #254 (20,000 points, one weapon bought) gives the rifle +2 rounds
  (10 against 8).
- **The health and count curves are left alone, on evidence.** Every variant tried (growth 1.06 or 1.07, a steeper
  step, a later knee, more zombies from round 2) lowered the medians by a round or more and moved the deaths to the
  boss and stampede nights, and none moved the end of the night to later rounds. With weapons that are not
  upgraded the curve has to stay flat: the rifle stays a two-shot kill to round 20 and the shotgun a one-shot kill to
  round 15 at 1.05 a round; at 1.1 they would be three-shot and two-blast kills by round 14, as it is in the original,
  where the player has
  Pack-a-Punch. A faster curve waits for a weapon upgrade (see "Follow-ups"): it came with #281, and the curve was
  1.07 (1.15 since the headshot retune, #745, 1.16 since the six firearms, #793).
- **Economy:** no change. The spend share (62%), ammunition share (18%) and dry share (0%) sit inside the gate.

### Result: median round of 200 nights a cell (same seed)

| Cell | Before (main at the start, no speed rework) | After this change, on main with #260 and #271 |
| --- | ---: | ---: |
| weak, 1 player | 5 | 5 |
| average, 1 | 11 | 10 |
| average, 2 | 13 | 11 |
| average, 4 | 14 | 13 |
| strong, 1 | 14 | 12 |

The faster dead of #260 and the dearer crane of #271 cost about a round, and main's gate was red (an average median of 9
against 10 to 14, a weak boss night at 94% deaths against 85%) before this change; the weapon step-up brings it back
inside the ranges. The gate's ranges are unchanged: they match the original (a casual solo player dies between rounds
8 and 15 there (W)).

## Follow-ups

- ~~A weapon upgrade (the Pack-a-Punch role)~~: done in #281, see [weapon upgrades](weapon-upgrade.md): a re-cut for
  x1.75 damage lets the health growth rise from 1.05 to 1.07 with the medians inside the gate (5 / 14 / 15 / 16 / 17).
- The prize crane (Mystery Box) is being reworked and owns its pool; the best weapons should come from it.

## Sources

- Zombie counts per round and per players, and the formula from round 10:
  [The Math of COD Zombies](https://jackhanke.github.io/posts/zombies) (from the Zombies wiki).
- Spawn delay (2.0 s, times 0.95 a round, floor 0.1 s) and the 24 zombie limit:
  [callofdutyzombies.com, "Zombie charts"](https://callofdutyzombies.com/topic/137395-zombie-charts).
- Health (150, +100 to round 9, then x1.1) and Pack-a-Punch multipliers:
  [Call of Duty Wiki, Round](https://callofduty.fandom.com/wiki/Round_(Call_of_Duty:_Zombies)) (not fetched here:
  the site refused the request, the figures are the community's standard ones and agree with
  [the Randomonia guide](https://randomonialand.fandom.com/wiki/Spookystorm%27s_Guide_to_Black_Ops_Zombies)),
  [BO2 Reimagined](https://www.github.com/Jbleezy/BO2-Reimagined) and
  [Dexerto on Cold War Season 4 Reloaded](https://dexerto.com/call-of-duty/all-cod-zombies-weapon-buffs-nerfs-in-black-ops-cold-war-season-4-reloaded-update-1611701).
- Points per hit and kill (10, 60, 100, 130): the same wikis; the numbers are the ones we use for kills already.

The chart is drawn by `tools/balance/scaling_chart.py` from the two folders' own tuning and weapon files and two balance
reports.
