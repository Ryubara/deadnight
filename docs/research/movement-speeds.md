# Movement speeds: the dead against the player

How fast zombies move in Call of Duty Zombies, against the player's own speed, and what that says about our numbers.
We study it for design only: nothing here is copied, only numbers and rules are read. The decision it feeds is on
[rounds](../design/rounds.md) (the speed cap, the runner); the player's numbers are on
[the player controller](player-controller.md).

![Zombie speed against the round, Call of Duty above and Deadnight below, with the player's run and sprint as lines](movement-speeds.png)

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

## 5. Deadnight today

Player (`player_tuning_default.tres`, defaults from `player_tuning.gd`): run 4.8 m/s (a CoD 190 u/s is 4.83: the
numbers agree), sprint 7.0 (1.46 times run, CoD 1.5), aim 2.6 (0.54 times run). **There is no sprint limit.**

Dead (`default_tuning.tres`, `RoundTuning`): walking speed `0.9 + 0.1 (round - 1)`, each zombie times its type's
multiplier and a jitter of 12% either way, held at the **cap of 4.5**; light slows it to 60%.

| Round | Walker | Runner (x1.7) | Runner / run | Runner / sprint | Brute (x0.6) | Headliner (x0.8) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.90 | not yet | | | | |
| 4 | 1.20 | 2.04 | 0.43 | 0.29 | | |
| 8 | 1.60 | 2.72 | 0.57 | 0.39 | 0.96 | |
| 10 | 1.80 | 3.06 | 0.64 | 0.44 | 1.08 | |
| 12 | 2.00 | 3.40 | 0.71 | 0.49 | 1.20 | |
| 15 | 2.30 | 3.91 | 0.81 | 0.56 | 1.38 | 1.84 |
| 18 | 2.60 | 4.42 | 0.92 | 0.63 | 1.56 | 2.08 |
| 20 and on | 2.80 up | **4.50** | 0.94 | 0.64 | | |

(Speeds in m/s.) The crawler is half a walker's speed.

**Can a player outrun each type, and from which round does it stop?**

- **Sprinting (7.0): always.** The fastest thing in the game is 4.5, so a sprinting player gains at least 2.5 m/s.
  There is no round where this stops being true, and Call of Duty's does not either (sprint tier 0.67 of the
  player's sprint). Only a super sprinter would test it, and we have none.
- **Running (4.8): always, and that is the odd part.** The cap is below run speed, so from round 18 a runner at the
  cap only loses 0.3 m/s a second to a player who is merely running; no zombie ever catches a moving player. In
  Call of Duty the first sprinters, who match the player's base speed (E), arrive in round 6 to 11 and make up the
  whole round by round 10 to 19, so a player who is not sprinting stops gaining ground; the limited sprint does the rest.
- **Aiming (2.6): until round 8 for a runner and round 18 for a walker.** An aiming player is caught by a runner from
  round 8 (2.72) and by a walker from round 18 (2.6): the same kind of deadline as Call of Duty's, only later.
- **Lit ground** takes a capped runner to 2.7 m/s, the aim speed: that is the point of the light.

**Is that the feel we want?** Partly. Our own design says "late rounds pressure positioning instead of simple
running" ([rounds](../design/rounds.md#why-these-numbers)), and the cap below a sprint keeps "a sprinting player can
always get away". But with no stamina and a cap below the plain run, positioning pressure comes only from crowds,
boards and the alive cap, never from a zombie that can catch you. The balance simulator cannot tell: its players do
not move, so tuning speed barely changes a night (below). And the median night (round 10 to 14) never sees a runner
past 3.7 m/s, while a Call of Duty night at that round is all run or sprint tier.

## 6. Recommendation

1. **Keep the player's numbers** (4.8, 7.0, 2.6). They agree with the 190 and 285 u/s of the games.
2. **Raise the cap to 5.0 and the runner to x2.0** (the tuning change in this pair of pull requests). The runner is our
   sprint tier: at the cap it should match the player's run speed, so that running alone stops being a guaranteed
   escape (5.0 is 1.04 times run) while a sprint still wins by 2.0 m/s (0.71 of sprint, CoD's 0.67). The runner
   arrives at round 4 at 2.4 m/s (0.50 of run, a run tier), reaches the player's run speed in round 16 and passes it
   for the fastest rolls from round 14. Walkers and the rest do not change.
3. **Do not add a super sprinter.** Cold War needs one at round 51; our nights end at round 10 to 18.
4. **Decide on a sprint limit** (a follow-up issue). It is what makes a sprint-tier zombie dangerous in Call of Duty
   and we have none. It touches the controller, the HUD and the bots, so it is not a tuning edit.

### Balance gate

The five cells of the gate (60 nights, seed 4000), medians against their ranges:

| Cell | Range | Now | Cap 5.0 | Cap 5.0, runner x2.0 | Hard (cap 6, runner x2.5, step 0.2) |
| --- | ---: | ---: | ---: | ---: | ---: |
| weak, 1 | 4 to 9 | 5 | 5 | 5 | 5 |
| average, 1 | 10 to 14 | 11 | 11 | 11 | 10 |
| average, 2 | 11 to 16 | 13 | 13 | 14 | 13 |
| average, 4 | 12 to 17 | 15 | 15 | 15 | 14 |
| strong, 1 | 12 to 18 | 15 | 15 | 15 | 14 |

All inside. Even the hard row, with zombies about twice as fast, moves a median by one round: the simulator's bots
shoot from where they stand, so speed only changes how long a zombie takes to arrive. **The gate guards difficulty;
it cannot judge this feel**, which needs a person or the movement bots of #226 chasing a moving player.

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
