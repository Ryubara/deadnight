# Movement speeds: the dead against the player

How fast zombies move in Call of Duty Zombies, against the player's own speed, and what that says about our numbers.
We study it for design only: nothing here is copied, only numbers and rules are read. The decision it feeds is on
[rounds](../design/rounds.md) (the speed cap, the runner); the player's numbers are on
[the player controller](player-controller.md).

![Zombie speed against the round: Call of Duty above; Deadnight below, before and after the rework, lit and dark, with the player's run and sprint as lines](movement-speeds.png)

## How to read the numbers

Every number carries a mark. **D** is datamined: read from the game's own scripts or engine source, quoted in the
sources below. **M** is a stock value stated by a mod's changelog ("from 70% to 100%"). **W** is a wiki or forum
claim we could not check against files. **E** is our estimate, with its basis.

**Units.** A Call of Duty unit is taken as 1 inch, so 1 u = 0.0254 m (E: the community convention; no engine source
states it). 190 u/s is 4.83 m/s; 285 u/s is 7.24 m/s.

## 1. How a zombie's speed tier is chosen (D)

The scripts never give a zombie a number of units a second. They give it a **tier** (walk, run, sprint, and in two
games super sprint), and the animation of that tier moves it: the real speed is the animation's root motion, which no
script contains. What the scripts do fix is which tier a zombie gets, in every game from World at War to Cold War:

```text
roll = randomintrange(L, L + 35)         # a whole number from L to L + 34
roll <= 35  -> walk
roll <= 70  -> run
else        -> sprint                    # BO4 and Cold War: sprint up to 236, above it super sprint
```

`L` is the round number times a multiplier, and 1 in round 1. The multiplier is 8 in WaW, BO1 and BO2 (normal
difficulty), 4 in BO3, BO4 and Cold War (normal; 2 on easy, 5 on Cold War's and BO4's hardest). On easy, a roll above
70 stays a run: no sprinters. Three details that matter:

- **One round late (WaW, BO1, BO2, BO3).** The value is set at the end of a round from the round just finished, so
  round 2 rolls with `L = 8` (BO3: 4), not 16. BO4 and Cold War read the zombie's own starting round instead, with no
  lag. A fan project that copied the formula put the sprinters one round too early for this reason.
- **The last zombie sprints.** BO1 and BO2 turn the one zombie left in a round (from round 4) into a sprinter, so
  nobody can hide it (BO2 only while the round is below 10). BO3 has the same function, but its decompiled test reads
  so that we cannot say it fires.
- **Map overrides.** BO3 and BO4 have a `speed_change_round` (15) that would turn part of a round into
  walkers, but its count (`speed_change_max`) is 0 in the base game, so it is off. Revelations uses a multiplier of 5.

### Share of each tier by round (D, computed from the rule)

Walk / run / sprint, in percent:

| Round | WaW, BO1, BO2 | BO3 | BO4, Cold War |
| ---: | --- | --- | --- |
| 1 | 100 / 0 / 0 | 100 / 0 / 0 | 100 / 0 / 0 |
| 2 | 80 / 20 / 0 | 91 / 9 / 0 | 80 / 20 / 0 |
| 4 | 34 / 66 / 0 | 69 / 31 / 0 | 57 / 43 / 0 |
| 5 | 11 / 89 / 0 | 57 / 43 / 0 | 46 / 54 / 0 |
| 6 | 0 / 89 / 11 | 46 / 54 / 0 | 34 / 66 / 0 |
| 8 | 0 / 43 / 57 | 23 / 77 / 0 | 11 / 89 / 0 |
| 10 | 0 / 0 / 100 | 0 / 100 / 0 | 0 / 89 / 11 |
| 12 | 0 / 0 / 100 | 0 / 77 / 23 | 0 / 66 / 34 |
| 14 | 0 / 0 / 100 | 0 / 54 / 46 | 0 / 43 / 57 |
| 16 | 0 / 0 / 100 | 0 / 31 / 69 | 0 / 20 / 80 |
| 18 | 0 / 0 / 100 | 0 / 9 / 91 | 0 / 0 / 100 |

| Milestone | WaW, BO1, BO2 | BO3 | BO4, Cold War |
| --- | ---: | ---: | ---: |
| First runners | round 2 | round 2 | round 2 |
| Walkers gone | round 6 | round 10 | round 9 |
| First sprinters (11%) | **round 6** | **round 11** | **round 10** |
| Every zombie sprints | round 10 | round 19 | round 18 |
| First super sprinters | none | none | round 51 (6%) |
| Every zombie super sprints | none | none | round 60 |

## 2. Speed of each tier (E)

Not in any script we found, and the animation files are not public, so these are estimates, expressed against the
player's base speed (the next section). The basis is thin and the confidence is low, which is why the conclusions
below hold if each is out by a fifth.

| Tier | Estimate, u/s | m/s | Of player base | Of player sprint | Basis |
| --- | ---: | ---: | ---: | ---: | --- |
| Walk | 50 | 1.3 | 0.26 | 0.18 | a walker is visibly far slower than a walking player |
| Run | 110 | 2.8 | 0.58 | 0.39 | between the two |
| Sprint | 190 | 4.8 | 1.0 | 0.67 | a wiki states that sprinters move about as fast as a player with a light weapon who is not sprinting (W, read in a search summary); a fan project for the same mode set its sprinters at 3.9 to 4.5 m/s against a player at 4.1 (E) |
| Super sprint | 260 | 6.6 | 1.4 | 0.91 | mods that add it claim 2 to 10 times a sprinting player ([ModMe 2366](https://forum.modme.co/wiki/threads/2366.html)); the stock tier is only said to be "considerably faster" (W). Weakest number here |

## 3. The player

| Item | Value | Game | Mark |
| --- | --- | --- | --- |
| Base move speed | 190 u/s (4.83 m/s): `g_speed` default | CoD4 engine, which World at War inherits; BO1 and BO2 are assumed unchanged | D for CoD4, E for the others |
| Sprint | base times 1.5: 285 u/s (7.24 m/s): `player_sprintSpeedScale` | same | D for CoD4, E for the others |
| Backwards, strafe | 70%, 80% of base (a mod raises both to 100%) | BO2 | M |
| Weapon weight | each weapon file carries a move-speed scale: pistols 100%, light machine guns 87.5%, snipers 95%, submachine guns 110% | BO1 (BO2 the same for LMG and snipers) | M |
| Aiming | a separate scale in the weapon file; a mod lists pistols at 200%, which is a different base from hip speed, so the ratio is not readable | BO1, BO2 | M. Typically about half of hip speed (E) |
| Stamin-Up | sprint 10% faster with any weapon (dvar `player_enduranceSpeedScale` 1.1) and sprint time doubled, about 4 s to 8 s | BO1 | M (the mod's own change from 1.1 to 1.07 states the stock) and W |
| | "normally only sprint 10% faster" | BO2 | M |
| | 7% movement speed and doubled sprint | BO3 | W (a wiki, read in a search summary) |
| | not found | BO4, Cold War | |
| Sprint limit | about 4 s, then 1 s before it returns; Stamin-Up doubles it; a mod removes the limit | BO1, BO2 | W, M |
| Burning zombie | animation rate 0.8 | WaW, BO1 | D |

The engine dvars `player_sprintTime`, `player_backSpeedScale` and `player_sprintSpeedScale` exist in the BO2 hash
table too, so the 190 and 1.5 are a good bet for BO1 and BO2, but we have not read their defaults there. BO3 on moved
to a new movement system whose numbers are not in the scripts: we have no number for it and make no claim.

## 4. Across the games, in one table

| | WaW | BO1 | BO2 | BO3 | BO4 | Cold War |
| --- | --- | --- | --- | --- | --- | --- |
| Speed multiplier (normal) | 8 | 8 | 8 | 4 | 4 | 4 |
| Applied | late by a round | late | late | late | at spawn | at spawn |
| First sprinters | round 6 | round 6 | round 6 | round 11 | round 10 | round 10 |
| All sprint | round 10 | round 10 | round 10 | round 19 | round 18 | round 18 |
| Super sprint | none | none | none | none | round 51 | round 51 |
| Stamin-Up | none | sprint x1.1, time x2 | sprint x1.1 | 7% (W) | not found | not found |

Reading it: BO3 halved the multiplier, so the same mix arrives about twice as late (every zombie sprints in round 19,
not 10), and BO4 and Cold War added a tier above the sprint for the very late rounds. Across all of them the
**sprint tier is about the player's base speed** (E) and the player's sprint about 1.5 times that, with a sprint that
runs out in the games that have a limit (section 3). So you can outrun a sprinter, but only for the length of a
sprint.

## 5. Deadnight before the rework

Player (`player_tuning_default.tres`, defaults from `player_tuning.gd`): run 4.8 m/s (CoD's 190 u/s is 4.83: the
numbers agree), sprint 7.0 (1.46 times run, CoD 1.5), aim 2.6 (0.54 times run). **There is no sprint limit.**

The dead were `0.9 + 0.1 (round - 1)` m/s, times the type's multiplier and a jitter of 12% either way, held at a
cap of 4.5, and **lit ground slowed them to 60%**. That put the pace under the lights far below the games':

| Round | Walker lit (before) | Walker dark (before) | BO3 mean (E) | BO1 mean (E) |
| ---: | ---: | ---: | ---: | ---: |
| 5 | 0.78 | 1.30 | 1.9 | 2.6 |
| 10 | 1.08 | 1.80 | 2.8 | 4.8 |
| 15 | 1.38 | 2.30 | 3.9 | 4.8 |

A lit walker moved at about 40% of what BO3's zombies do at the same round (and a fifth of BO1's), and a lit zombie of
any type never exceeded 2.7 m/s. The light made the night safe instead of holding it off. Against the player, nothing could
catch a moving one: the fastest zombie (4.5) was below even the run (4.8), and the player's sprint has no limit.

## 6. The rework (the maintainer's decision)

**The dead are at Call of Duty's pace under the lights, and faster in the dark.** The 60% slow is gone; ground that
is not lit (a circuit off, the generator dry) makes the dead 25% faster.

| | Before | Now |
| --- | --- | --- |
| Walker pace under the lights | `0.9 + 0.1 (r - 1)`, then x0.6 | `1.2 + 0.16 (r - 1)` |
| Runner (our sprint tier) | x1.7, lit x0.6 | x1.4 |
| Cap under the lights | 4.5 | 5.0 (1.04 of run, 0.71 of sprint) |
| Dark | x1.0 | x1.25 (`dark_speed_multiplier`), at most 6.25 |
| Crawler, brute, headliner | x0.5, x0.6, x0.8 of the walker | x0.4, x0.4, x0.45: about the pace they had in the dark before; they are slow by design |
| Jitter | 12% | 12% |

Speeds in m/s, lit and dark (before: lit is the old x0.6 and dark the old plain speed):

| Round | Walker before | Walker now | Runner before | Runner now | Brute now | Headliner now |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | 0.54 / 0.90 | 1.20 / 1.50 | | | | |
| 4 | 0.72 / 1.20 | 1.68 / 2.10 | 1.22 / 2.04 | 2.35 / 2.94 | | |
| 5 | 0.78 / 1.30 | 1.84 / 2.30 | 1.33 / 2.21 | 2.58 / 3.22 | | 0.83 / 1.03 |
| 8 | 0.96 / 1.60 | 2.32 / 2.90 | 1.63 / 2.72 | 3.25 / 4.06 | 0.93 / 1.16 | |
| 10 | 1.08 / 1.80 | 2.64 / 3.30 | 1.84 / 3.06 | 3.70 / 4.62 | | 1.19 / 1.48 |
| 12 | 1.20 / 2.00 | 2.96 / 3.70 | 2.04 / 3.40 | 4.14 / 5.18 | 1.18 / 1.48 | |
| 15 | 1.38 / 2.30 | 3.44 / 4.30 | 2.35 / 3.91 | 4.82 / 6.02 | | 1.55 / 1.94 |
| 20 | 1.68 / 2.80 | 4.24 / 5.30 | 2.70 / 4.50 | 5.00 / 6.25 | 1.70 / 2.12 | 1.91 / 2.39 |

The walker now tracks the BO3 and BO4 pace (1.9, 2.8 and 3.9 at rounds 5, 10 and 15 against our 1.84, 2.64 and 3.44;
the runner is the faster mix that makes up the rest, and the dark adds a quarter); it is slower than WaW, BO1 and
BO2, which have every zombie at the sprint tier by round 10.

**Can a player outrun each type, and from which round does that stop?**

- **Sprinting (7.0): always, in the light and in the dark.** The fastest zombie is 5.0 lit and 6.25 dark. In the
  dark the margin is down to 0.75 m/s: a sprinting player still gets away, but only just, and for as long as the
  sprint lasts, which is for ever (the issue linked below).
- **Running (4.8): until round 15 in the light and round 11 in the dark** for a runner (4.82 lit, 4.82 dark); until
  round 24 lit and round 18 dark for a walker. After that a runner who is not stopped by a bullet catches a player who
  is only running. This is Call of Duty's rule: from round 6 to 11 the sprint tier moves at the player's base speed.
- **Aiming (2.6): from round 6 for a runner and from round 10 for a walker** (lit). An aiming player is caught,
  which matches the point of aiming being a commitment.
- **Walker and runner ratios to the player's run, lit:** round 10, 0.55 and 0.77; round 15, 0.72 and 1.00.

**Is that the feel we want?** It is what the maintainer asked for: a night that stays a challenge with the
generator on, and gets worse when the lights fail. Two things to keep an eye on. A dark runner at the cap
(6.25) is 0.89 of the sprint, so the dark leaves the player almost no room; and with no sprint limit there is still no
stamina cost to running away (the follow-up issue #236).

### Balance gate

The shipped numbers pass the five-cell gate (60 nights, seed 4000, `BalanceTargets.check`: medians, the first
special rounds, time to kill, spending). Medians against their ranges:

| Cell | Range | Before (`main` now) | After | First try (base 1.2, step 0.18) | After the other work landed, step 0.18 |
| --- | ---: | ---: | ---: | ---: | ---: |
| weak, 1 | 4 to 9 | 5 | 4 | 5 | 4 |
| average, 1 | 10 to 14 | 11 | 10 | 8 (out) | 9 (out) |
| average, 2 | 11 to 16 | 12 | 12 | 12 | 12 |
| average, 4 | 12 to 17 | 14 | 13 | 13 | 13 |
| strong, 1 | 12 to 18 | 13 | 13 | 13 | 13 |

The first try kept the old type multipliers (brute x0.6, headliner x0.8, crawler x0.5, runner x1.5) on the faster
base: the average solo median fell to 8 and the round 5 boss night killed 45% of average and 100% of weak solo nights
(at most 40% and 85%). Keeping the special types at about their old pace in metres per second and the runner at x1.4
fixed it. Then the health and count retune landed on `main` and the same speeds put the average solo median at 9 (and
a dark of x1.2 left the boss night at 89% of weak solo nights): the step went from 0.18 to 0.16, which passes every
target with the dark at x1.25 (a dark of x1.15, or x1.2 with the headliner at x0.4, also passed).

## 7. What is left

1. **A sprint limit** (#236): in Call of Duty it is what makes the sprint tier a threat; here it would make the
   dark's 6.25 m/s runner one.
2. **A playtest of the dark.** The 1.25 is a number a person should feel; the movement bots of #226 can then chase a
   moving player.
3. **Do not add a super sprinter.** Cold War needs one at round 51; our nights end at round 10 to 18.

## Where each number comes from

Datamined (read from the files, not from a description of them):

- WaW: `raw/maps/_zombiemode.gsc` (round end sets `zombie_move_speed = round * 8`, then the round counter rises),
  `_zombiemode_spawner.gsc` (`set_run_speed`) in [the mod tools](https://github.com/CallOfDutyModding/call_of_duty_world_at_war_mod_tools).
- BO1: `maps/_zombiemode.gsc` (`zombie_move_speed_multiplier` 8, `zombie_speed_up`) and `_zombiemode_spawner.gsc` in
  [a raw file dump](https://github.com/JTAG7371/T5-RawFile-Dump).
- BO2: `ZM/Core/maps/mp/zombies/_zm.gsc` (multiplier 8, easy 2) and `_zm_utility.gsc` (`set_run_speed`,
  `set_run_speed_easy`) in [the Plutonium script dump](https://github.com/plutoniummod/t6-scripts).
- BO3: `scripts/zm/_zm.gsc` (multiplier 4, easy 2; `speed_change_round` 15) and `scripts/shared/ai/zombie_utility.gsc`
  in [t7-source](https://github.com/shiversoftdev/t7-source).
- BO4: `scripts/core_common/ai/zombie_utility.gsc` (the 236 and super sprint) in
  [t8-src](https://github.com/shiversoftdev/t8-src); multipliers in `scriptbundle/zmdifficultysettings/` of
  [bo4-source](https://github.com/ate47/bo4-source).
- Cold War: the same two files in [bocw-source](https://github.com/ate47/bocw-source): the same rule, the same
  multipliers (easy 2, normal 4, hard 4, hardest 5).
- Engine: `g_speed` 190 in [KisakCOD](https://github.com/SwagSoftware/KisakCOD) (`src/game/g_main.cpp`), sprint scale
  1.5 and back scale 0.7 in [CoD4x](https://github.com/callofduty4x/CoD4x_Server) (`src/g_sv_main.c`).

Stated by others (M, W):

- Stock player values from the changelogs of [BO1 Reimagined](https://github.com/Jbleezy/BO1-Reimagined) and
  [BO2 Reimagined](https://github.com/Jbleezy/BO2-Reimagined), and its
  [Stamin-Up commit](https://github.com/Jbleezy/BO1-Reimagined/commit/aed1a496bba8c0471bfa4267699abfefb5661a22).
- The modding threads that explain the multiplier: [ModMe 586](https://forum.modme.co/wiki/threads/586.html),
  [ModMe 1161](https://forum.modme.co/wiki/threads/1161.html), [UGX-Mods](https://www.ugx-mods.com/forum/scripting/87/how-to-change-the-max-amount-of-zombies-that-spawn-per-round/13967/).
  The UGX thread on [base speeds](https://www.ugx-mods.com/forum/help-desk/10/trying-to-change-base-player-and-zombie-speed/7151/)
  says the base speed is a number in the weapon file that script can scale, and states the four-second sprint.
- A fan project's [speed pull request](https://github.com/michaeljjdougherty/stew-zombies/pull/21) (3.9 to 4.5 m/s
  sprinters).
- Not opened (the pages refused us): the Call of Duty wiki's Zombie page and the Nazi Zombies wiki's Stamin-Up page,
  whose claims we saw only in search summaries; the CoD Zombies forum thread on Stamin-Up.

## Not found

The animation root speeds (the real units a second of each tier), the BO1 to Cold War engine defaults for `g_speed`
and the sprint scale, the weapon files' aim scales as numbers against hip, and Stamin-Up for BO4 and Cold War. A
spike that measures a clip's root motion would settle the first, and only for animations we make ourselves.
