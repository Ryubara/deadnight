# The balance simulator

What was learnt building a headless balance simulator for the rules engine, so the next change to it starts
from facts. The game-facing description (targets, results) is in [rounds](../design/rounds.md#the-balance-simulator).

## What it is

`game/tools/balance/` plays whole nights through the real `GameRules` with modelled players, in plain
GDScript and no scene tree: `NightSim` (one night), `SimWeapons` (the real weapon definitions as timing and damage),
`BalanceBatch` (many nights of one cell, plus the reading functions), `BalanceTargets` (the ranges),
`balance_cli.gd` (one cell to JSON from the command line; it quits with an error when `--out` cannot be written, and
`run_report.py` makes `--out` absolute) and `tools/balance/run_report.py` (nine cells in parallel Godot processes,
then the charts; `--compare <folder>` draws a before and after).

## Measured

- **Speed.** One solo night costs 0.05 to 0.15 s (a step of 0.25 s of game time, a few thousand `apply` calls); four
  players about 4 times that and eight about 7 times (a night of eight is 0.9 s, 120 nights a cell in 110 s on one
  process, #690). 500 nights of all nine cells (3 skills by 1, 2, 4 players) take about 3 minutes on 16 cores with nine
  processes. The CI gate (five cells, 60 nights, seed 4000; a sixth, average by 8, since #690, takes about 47 s on its
  thread and so sets the time) took 40 s as a whole suite in CI; it took 1 min 53 s when it ran the batch twice, one
  cell after another ("about 30 s" was never true there). The cells now run on worker threads (`WorkerThreadPool`),
  each with its own copy of the tuning, and the shipped batch is run once in `before()`. Nights are node-free
  `RefCounted` objects, so the only shared state is the weapon cache, filled first by `SimWeapons.warm()`; a test pins
  that threaded cells equal serial ones.
- **Determinism.** Same seed, same night, on every run (tested). A batch is therefore reproducible, and a
  CI range that passes once passes always; only a change to the rules, the tuning or the model moves it.
- **A fixed player is a cliff.** With one fixed skill per level, every night of a cell ended in the same
  round or the next: survival read 100, 100, 100, 17, 0 and said nothing about balance. Each night now draws
  its own skill within 20% either way, which gives the S-shaped curves a person's nights have.
- **Damage taken is the wrong difficulty measure.** It is 0 in most rounds and then everything. How close the
  round came to downing someone (the lowest health a player reached, 0 to 1) rises smoothly and is what the
  spike is computed from. Add a small floor to both sides of a ratio (`SPIKE_FLOOR`) or a round next to
  untouched neighbours reads as a spike of 50.
- **Compounding meets a fixed weapon at a threshold.** Health that compounds against weapons that do not
  grow makes a queue: when the zombies' health arriving per second passes what the players deal, the
  alive cap fills and the night ends within one or two rounds. The shape of the end of the night is set by
  how fast arrival rate (spawn interval times health) grows, not by health alone; slowing the spawn decay
  from 0.92 to 0.95 moved the wall from round 11 to the thirteenth or fourteenth round for a good player.
- **A type can be the wall.** Before the brute and the crawler were capped, the first round that held all
  of them at once killed every night at once. The cap (`share_max`) per type and an exact first-round
  number are what make a type something to learn.
- **A stand-in weapon table hides the balance.** The first simulator shot a made-up table (a rifle at 210 damage a
  second) and said an average solo player reaches round 11. With the real definitions (`WeaponCatalog`, `DamageModel`)
  and reloads the same nights ended at round 4: the rifle is 85 a second sustained, the best gun (the SMG) 101, the
  pistol 59. Read every number a model uses from the game's own data, and say in the report where each comes
  from. Reloads are time, not a share of "uptime": with a weapon cycle explicit, `SimSkill.uptime` is only the
  time spent moving and looking.
- **Free things hide decisions.** The model gave tonics effects the game does not have and slowed the dead on lit
  ground without ever lighting a circuit, so the light never cost fuel ("fuel was never short enough to buy").
  With circuits switched through `RulesAction.set_circuit` and lit ground applied only while the tank has fuel
  (`GeneratorState.is_lit`, `power_level`), the average solo player buys about 260 points of cans a night.
- **A weak player's boss night is a cliff.** Boss health 15, 16 and 22 times a walker's killed about 75%, 90% and 95 to
  100% of weak solo nights at it: they never land the weak spot, so their kill rate stops covering the boss's
  arrival all at once. A number that makes strong players feel the boss walls the weak ones.
- **No weapon is a big step.** Sustained damage a second: flare gun 32 (plus a 3 m blast), pistol 59, shotgun 68,
  rifle 85, SMG 101. Health that compounds against weapons that barely grow set the whole curve; the retune of #188
  had to lower health, counts and the alive cap, not raise anything.
- **Where the model is thin.** Players are bots, shoot only at what they can see (view range falls with the
  light), turn to one of four sides at a time, and ignore barricades, repairs, grenades, melee, the geometry of
  doors and shop spots (which only cost points), penetration and where a player stands when they shoot. Only the
  hearty tonic has an effect, and the model has it (the rules give the player the health). The report is a tool
  for comparing tunings, not a
  prediction of a person's night; rerun it when the weapons, the player's health (#151) or the shop change.
- **Finite ammunition changes who is hard pressed, not how the ranges look.** Free reloads hid that a weapon holds
  few rounds against a horde: with reserves the game gives (a revolver 90 at most, a shotgun 54) the average solo
  player lost a round and the weak one's boss night went from three deaths in four to five in six (the headliner went
  from 15 to 13 times a walker's health to bring it back to seven in ten). What decides it is
  the player's policy more than the price: ammunition at half price moved the median by nothing, filling up before
  the announced special round moved the weak boss night by eight points. Write the policy down (`SimSkill`
  `ammo_floor_mags`, `ammo_topoff`, `swaps`) and test it against the game's own reload (`SimArm.reload` is compared
  with `WeaponState` in a test), or the model quietly plays a different game.
- **A weapon is worth what its player does with it.** The first finite-ammunition run picked the weapon by sustained
  damage at point blank, so the shotgun went into every hand and a night with it ended three rounds earlier than
  without. A player takes the weapon that suits the target in front of them (40% more damage a second to switch) and
  the same shotgun became a small gain. Ask what a weapon is worth with the shopping list, not with the default
  one: `balance_cli.gd --shopping=weapon_rifle` with `--set economy.start_points=20000` takes price out of it.

## The crane's price

The crane is now a play, a spin and a grab ([the Mystery Box research](mystery-box.md)); the simulator plays it as a
shopper at the glass in a break: it pays, waits out the spin in ticks of a quarter second, takes the weapon the moment
it is held out, and after a breakdown (refunded, not counted as spent) tries again at the next break. It was run at
three prices with 150 seeded nights a cell (seed 77, the crane's own random stream, the shopping lists of
`sim_skill.gd`):

| Crane price | Median round weak / average / average, 4 players / strong | Points into the crane a night, average solo |
| ---: | --- | ---: |
| 500 | 5 / 11 / 14 / 14 | 1,567 (three plays) |
| 750 | 5 / 11 / 14 / 14 | 1,160 (one and a half) |
| 950 | 4 / 11 / 14 / not run | 1,438 (one and a half) |

The balance gate's own cell (average, solo, 60 nights, seed 4000) is closer to the edge of its range of 10 to 14: the
median round is 11 at a price of 500 and 550, 10 at 600 and 650, and 9 at 750, which fails the gate. So 750 is out
whatever the wider run says, and at 950, the Mystery Box's own price, a weak player falls a round sooner: the crane eats
the points their first wall weapon needs. At 500 it was a cheap shortcut (three plays in an average night, a tenth of
the points). The price is **550**: under the cheaper wall weapon (900), a round clear of the gate's floor. The strong
950 cell was lost when a file was moved mid-run; the other cells are as above. The numbers are medians of a model of a
player, not a promise: rerun with `--set=economy.items:crane_play.price=<n>`.

- **Pick the weapon by what it kills, not by damage a second.** Shots land whole: a 95 damage rifle against 117 health
  needs two, and does no better than a 60 damage gun. Choosing by sustained damage sent the average solo median from 11
  to 9 when the shop weapons were stepped up (#254), because the model held a slow rifle and a pump shotgun in a
  stampede
  instead of the submachine gun. `SimWeapons.sustained_dps(id, health)` and `kill_rate_at` count the shots against the
  walker the round sends; with them the same weapons raise the share of average solo nights that reach round 10 from 59%
  to 83%. Rerun the step-up of any weapon through the model before believing its median.

- **The gate went red after #260 and #271, and the retune was weapons.** The faster dead (#260) and the dearer crane
  (#271) took the average solo median to 9 (wanted 10 to 14) and the weak boss night to 94% deaths (limit 85%). Nothing
  in the ranges was loosened: the shop weapons were stepped up (#254, #265) and the simulator's weapon choice fixed,
  which brought the medians to 5, 10, 11, 13 and 12 (weak solo, average 1, 2 and 4 players, strong solo). Health growth,
  steps and counts were tried and left alone (see [round
  scaling](round-scaling.md#7-what-the-simulator-showed-and-what-is-applied)).

## The re-cut and the tonic (#281)

The modelled players buy the weapon re-cut (`upgrade_weapon`) and the hearty tonic through the same `buy` the night
does; `SimArm.upgrade` re-cuts with the same `WeaponDef.upgraded` the combat server uses, and the player's health is
what the rules say (`PlayerState.max_health`). What it needed of the model, and what the sweep showed, is in
[Weapon upgrades](weapon-upgrade.md): `SimSkill.saves_for` (nothing after the items a player saves for is bought),
`re_cuts` (a list is read again at every break, so a repeatable item needs a stopping point), and weapon functions
that take a `WeaponDef` (`SimWeapons.damage_of`, `sustained_dps_of`, `kill_rate_of`) because a re-cut weapon is not in
the catalogue. A try of a multiplier: `--set upgrade.damage_multiplier=1.6 --set rounds.health_growth=1.07`.

## The two-weapon carry (#410)

Three choices made here are open for the maintainer, not decided: the 1.5 replace margin below, the stampede cut to
110% of the count, and the revolver and the crowbar in the crane pool at weight 1. The fourth, the starting crowbar,
was settled by the quick melee (#411, [below](#the-quick-melee-replaces-the-starting-crowbar-411)).

A player carries two weapons, and the modelled players follow it (`NightSim`, `REPLACE_GAIN`): a wall weapon or a
crane prize replaces the weakest weapon they carry (by sustained damage for a firearm, by blows for a melee weapon),
and only when it is worth 1.5 times more; they play the crane only when some prize they lack would be. At 1.0 they
bought in circles (the same shotgun 79 times in 60 nights, 3 to 4 plays of the crane a night) and the average solo median
round was 8; at 1.3 it was 9; at 1.5 it was 10 to 12. The policy matters as much as the rule, so the number is the
average player's taste, written down. Without a carried melee weapon the simulator falls back on the quick melee's blow
(#411). With it the gate held only after the stampede was cut from 140% to 110% of the count
(at 140% a solo average player died in 54% of the stampedes, wanted 40% at most).

## The quick melee replaces the starting crowbar (#411)

A player starts with the revolver alone and a free hand, and the always-available blow is the quick melee (40, 0.6 s,
one target; the knife of the genre) instead of the crowbar's (45, 0.55 s, two targets). `SimWeapons.START_ARMS` is the
revolver and `SimPlayer.knife` the quick melee. Two numbers moved the gate and one did not:

- **The blow's numbers did not matter.** The quick melee at the crowbar's own numbers gave the same median round as at
  its own (the average solo player's median was 8 either way): the simulated players are not dry for more than a moment
  (`dry_rounds` 0), so the always-available blow is not what carries a night.
- **The free hand did.** With the free hand taking any weapon, the average solo median fell from 10 to 8 (the players
  played the crane and bought the weakest wall weapons for the empty slot, and the points went there instead of into
  doors, rounds and the re-cut). A free hand is worth what the blow every player has is worth: a weapon must beat the
  quick melee by the same 1.5 margin a weapon beats the one it replaces (`NightSim._worth_taking`). Then the gate holds:
  the median round is 4 (weak, solo), 13 (average, solo), 14, 15 (average, two and four) and 15 (strong), inside every
  range, and 97% of average solo nights clear round 4. The 1.5 margin and the stampede's 110% stay as they were.

## The quick melee was one hit past round 1 in the night and two in the model (#897)

The maintainer: V "should not be one tapping zombies after round 1". The tables said 40 (two blows on round 1's 50
health); the real night did 60 on every blow, one blow on rounds 1 and 2 and then two. The cause was in the sweep and
not the table: it leaves the eye (1.55 m) with a 0.4 m thickness and a walker's head sphere is at 1.62 m, so the zone
was the head on every blow at every reach and aim, and the head's x1.5 turned 40 into 60. The simulator rolls the zone
from the skill's head rate and `WeaponWorth` reads the body, so both under-valued the blow by half a hit.

The blow is now 50 in every zone (`quick_melee.tres`): one blow on round 1 (50 health), two on rounds 2 to 7, three on
rounds 8 to 10 ([the table](../design/weapons.md#hits-to-kill-by-round)), the same on the head, the chest and the
legs, so the model and the night agree. The gate (60 nights, seed 4000, the six cells) is **unchanged**: medians 5 /
13 / 15 / 16 / 18 / 18 before and after, no misses, means within 0.2 (the simulated players are never dry,
`dry_rounds` 0). What moved is the free hand's yardstick: the blow is worth 83 health a second against round 1's
walker (it was 42), 48 to 82 on rounds 2 to 7, 59 to 79 on rounds 8 to 10, so on round 1 a free hand takes no weapon
(it needs 1.5 times 83); a weapon beats it on round 2 (the smg, rifle, bat, mp5, ppsh, m4a1, m249) and again on round
8; from round 5 only the rifle does, and on round 10 only the axe. The bat, the axe and the
crowbar had the same fault and are fixed in #924 (next section).

## The bat, the axe and the crowbar landed every blow on the head too (#924)

The same sweep, the same cause: from the eye (1.55 m) with a 0.4 m thickness it met the head sphere (1.62 m) at every
reach (0.7, 1.1, 1.5 m), every crosshair height (head, chest, legs), walking up or striking, so the real blow was the
table's number times the head's multiplier: crowbar 45 x 1.5 = 68, bat 60 x 1.5 = 90, axe 150 x 2.5 = 375 (a probe
through the combat server with the walker's fitted hit set, `tests/captures/melee_zone_probe.gd`: 126 blows each, all
head). `WeaponWorth` and the simulator read the body, so they valued the real weapons low: the axe killed a walker in
one blow to round 16 in the night and to round 10 in the model. The three are flat now, as V is (zone multipliers
x1.0): the bat 60 and the axe 150 as the tables always said; the crowbar 55 (it was 45), so that a weapon carried in a
slot is never a weaker blow than the free V (50): on round 1 a crowbar blow kills a walker, as V's does.

The gate (60 nights, seed 4000, six cells) stays as it was: medians 5 / 13 / 15 / 16 / 18 / 18, `dry_rounds` 0 in
every cell, and `test_balance_targets` passes. The model's valuations changed only for the crowbar (82 to 100 a
second), and the gate did not move. One test in `test_sim_weapons` did: with only the crowbar, a round-1 walker (50)
is now the crowbar's (one blow, 0.55 s) and not V's (one blow, 0.6 s). The hits-to-kill table of
[the weapons design page](../design/weapons.md#hits-to-kill-by-round) covers every melee weapon, held by
`test_melee_hits_to_kill.gd` (the combat server) and `test_night_melee.gd` (the real attack button).
A finding left open: a melee hit is a head-zone hit for the rules (8 points for a non-killing hit, not 4).

## The weak boss night against the bots (#568)

The simulator says 40% of weak four-player nights that reach round 5 pass it; four Rookie bots passed 16 of 16 in the
real server. `SimSkill` was **not** changed: the Rookie was, to 40% over 90 nights (the fit and the table of what was
tried are in [the bots page](bots.md#rookie-and-the-weak-boss-night)). The bots started high for reasons the model
leaves out, and the model is a tool for comparing tunings, not a measurement of the real boss:

- **No movement.** Simulated players stand where they are hit; a bot that makes out the headliner's telegraph steps out
  of a 1.2 s swing at a sprint and the boss, at 0.45 of a walker's speed, does not catch up. The Rookie now never makes
  the telegraph out, so its blows land (the simulator's weak `read` 0.25 lets 26% miss).
- **No stagger.** The real boss is held off its swing by hits (`boss_stagger_seconds`, with a cooldown for the weak
  spot); the model's zombies are never held.
- **One approach.** Every simulated zombie arrives, queues for a barrier and hits; in the lot they arrive in a stream,
  by their routes.

If the real boss is later found too easy for weak players (a person's playtest, phase 7), these three are where to
look, and moving `SimSkill`'s `read` alone would not fix them: a change to the boss's health or blow is a change to
`rounds.md` and this gate, not to the bots. The gate's own limit (at most 85% of weak solo nights die in the first boss
night) is untouched.

## The bosses at 1.25 times the health (#688)

The headliner's `health_multiplier` went from 13 to 16.25 and nothing else moved. 300 nights a cell, seed 1: the
headliner's time to kill (average solo) 19.55 s to 24.74 s, the weak boss night 65% to 80% deaths, the second boss night
(round 15) 82% to 99% deaths for an average solo player, and the gate's average solo median round from 10 to 8 (the gate
floor moved to 8, flagged for the maintainer). All the numbers are in
[the rounds page](../design/rounds.md#the-bosses-25-tougher-688). A boss's health is the one number this page's
simulator and the real server read from the same file, so the rise needs no separate model change.

## The bots against the model (#231)

The nightly bot soak ([the bots page](bots.md#phase-7-validation-at-scale-and-tuning)) plays whole nights of bots in the
real server and sets each profile beside the cell of the same skill and team size (`balance_cli.gd`, 300 nights, read
with the same cap as the bots). `SimSkill` was **not** changed: what the bots measured is what they are held to, not what
the model is fitted to, because the gate of `BalanceTargets` reads the model. Measured on the code after #766, eight
nights a cell: the Veteran's curve is the strong cell's (Kolmogorov 0.00 to 0.05, median round 16 at a cap of 16), the
Regular's median is within a round of the average cell's and its curve is not (0.34 to 0.89: seven or eight of eight
nights reach the cap), and the Rookie is two rounds better than the weak cell alone and four or five in a team. Landing
percentages and head shares against the model's `accuracy` and `head_rate` (0.45 and 0.68, 0.65 and 0.81, 0.82 and 0.85):
Rookie 49 to 60% and 62 to 68%, Regular 74 to 76% and 72 to 76%, Veteran 81 to 84% and 73 to 83%.

What the comparison showed about the model: its weak boss night is a cliff (68% of two-player and 81% of four-player nights
ended in round 5 before #766) that a bot, which steps and reloads, passes more smoothly, which is why one number of the
Rookie (`careful_below` and `safe_below` 0, so it does not back away when hurt) moves its first boss night between
97% and 53% of passes. The curve gate of 0.2 is hard to meet for a cliff and a slope however close their medians are;
read it with the medians.

## The headshot retune (#745)

The hit zones that follow the bodies ([hit zones](hit-zones.md), #694) made the chibi head half the figure, so a bot
that aims at the chest lands 64 to 88% of its hits on the head and avoids more blows. `SimSkill` still carried the
numbers of the old 0.22 m head ball. This task set `SimSkill` to what the bots read and retuned the game around it,
with the zones, the shape of the multipliers and the boss left as they were.

**What the bots read** (`test_bot_bands.gd`: eight seeds, 110 s each; three runs, two on this machine and one on the
CI runner):

| Level | Head share of hits | Dodge | `SimSkill` head rate before / after | `SimSkill` dodge before / after |
| --- | --- | --- | --- | --- |
| weak (Rookie) | 0.64 to 0.72 (CI 0.66) | 0.15 to 0.21 (CI 0.16) | 0.06 / **0.68** | 0.12 / **0.17** |
| average (Regular) | 0.78 to 0.84 (CI 0.82) | 0.47 to 0.68 (CI 0.47) | 0.15 / **0.81** | 0.30 / **0.55** |
| strong (Veteran) | 0.81 to 0.88 (CI 0.81) | 0.73 to 0.91 (CI 0.79) | 0.30 / **0.85** | 0.50 / **0.80** |

The bands test follows `SimSkill` again (head share within 0.1, dodge within 0.2: the width of the spread above, since
two runs of the same commands are not bit-identical and a Veteran's dodge is read from about 30 blows a run). The
dodge is the share of the blows that came due on the bot and did not hurt it: the bots step out of reach, as the early
retreat of [phase 3](bots.md) was meant to make them, and they kill faster on the new zones.

**Per-weapon re-cuts and the strong-solo ceiling (#794).** The re-cut is a profile for each weapon
(`RecutProfile`); on the roster of `main` (five weapons that can be re-cut, the revolver now fires every 0.40 s once
re-cut, the flare gun carries 3 shots, 6 re-cut) the gate's six cells read 5 / 10 / 15 / 16 / 18 / 18, as before. The
simulator does not model the elements (a blast, an arc, a fire): they are held by their own tests. The maintainer allowed
a strong-solo ceiling of 19 for the roster of seventeen (`BalanceTargets.MEDIAN_ROUND`, 12 to 19); the cell on the full
roster is run when its weapons land (see the pull request of #794).

**What it did to the gate.** Medians of the gate's six cells (60 nights, seed 4000; weak solo, average 1, 2, 4 and 8,
strong solo), ranges 4 to 9, 8 to 14, 11 to 16, 12 to 17, 14 to 20, 12 to 19 (widened, #789):

| Step | Medians | Gate |
| --- | --- | --- |
| `main` with #694 (the old `SimSkill`) | 4 / 9 / 14 / 16 / 18 / 18 | passes |
| `SimSkill` set to the bots, nothing else | 5 / 15 / 17 / 20 / 20 / 20 | four cells too easy |
| the head share alone (dodge as before) | 5 / 15 / - / - / - / 20 | |
| the dodge alone (head rate as before) | 4 / 12 / - / - / - / 20 | |
| every head multiplier cut to a third (x1.5, x1.35, x1.15) | 5 / 15 / 15 / 19 / 20 / 20 | still too easy |
| the headshot kill 100 to 70 and the headshot hit 8 to 5 | 5 / 10 / 15 / 20 / 20 / 20 | average solo back, the rest too easy |
| and health growth 1.09 / 1.11 / 1.13 / 1.16 after round 8 | strong 20 / 20 / 20 / 17 (average 4: 19 / 18 / 17 / 16) | 1.16 passes with the headliner at 14.5 |
| **shipped**: kill 70, growth 1.15, brute x3, the simulator's crawler hit chance 1.0 | **5 / 10 / 15 / 16 / 18 / 18** | **passes, no misses** |

What each lever is worth:

- **The multipliers are not the lever.** On top of the retuned numbers, x1.75 instead of x2.5 costs one to two rounds
  in the larger cells and every head bonus at x1.0 two to three (the gate still passes). They stay: the pistol and
  rifle x2.5, SMG x2, shotgun x1.5 (the table in [weapons](../design/weapons.md)), so a round-1 zombie still falls to
  one headshot.
- **Points were.** A headshot kill paid 100 against 60 and most kills are headshots now (the simulator's kills went
  from 13 / 26 / 41% headshots to 81 / 90 / 93% for weak, average and strong), so a kill paid about a third more (70
  on average, 96 now) and the re-cut and the wall weapons came sooner: an average solo night earned 13,700 points,
  then 20,100. The headshot kill pays **70** (the old mix of a quarter at 100 and the rest at 60); the hit pay (8 and
  4) stayed.
- **Late health was the other.** Strong players and companies are not stopped by the first rounds, so the climb after
  round 8 went from 7% to **15%** a round; the knee and the first rounds are as they were (round 1 still takes 50).
- **The brute** (health x2.5 to **x3**): its time to kill had fallen under the gate's 3 s. The headliner's x16.25
  (#688) stays, which caps the growth: at 1.16 its time to kill reads 30.3 s against a limit of 30.
- **The crawler** is shot through zones that are its body on the ground, so it is no harder to hit than a walker
  (`ZombieProfile.hit_scale`). The simulator used the type's `hit_chance` 0.6 for it and now uses 1.0 for a crawling
  look (the type's data and its tests are untouched). Its time to kill, average solo, went from 0.96 s to 0.41 s.
  **Recommendation: leave it.** At x0.7 health and a body on the ground it is the easiest type to kill, but it is at
  most a tenth of a round: with its health at x1.0 its time to kill is 0.67 s and no median of the four cells run
  moves (weak 1, average 1 and 4, strong 1; 300 nights, seed 1000), so a harder crawler is a design wish (its health,
  not a smaller zone), not a balance need.

**Before and after, kills.** 300 nights a cell, seed 1000, three skills by one, two and four players (`NightSim` now
counts `kills` and `head_kills` by round: `BalanceBatch.kills_in`). A round's kills are its zombie count, which the
retune did not touch, so the kills a night makes are the rounds it reaches:

| Cell | Median round before / after | Mean round | Kills a night | Headshots of the kills | Points earned |
| --- | --- | --- | --- | --- | --- |
| weak, 1 | 4 / 5 | 4.3 / 5.6 | 25 / 38 | 13% / 81% | 2,194 / 3,698 |
| weak, 2 | 5 / 5 | 5.1 / 6.3 | 51 / 82 | 12% / 80% | 2,405 / 4,059 |
| weak, 4 | 5 / 5 | 5.9 / 7.2 | 118 / 191 | 12% / 81% | 2,927 / 4,816 |
| average, 1 | 10 / 15 | 9.9 / 12.6 | 127 / 182 | 26% / 90% | 13,724 / 20,107 |
| average, 2 | 15 / 15 | 12.9 / 14.4 | 309 / 367 | 23% / 90% | 16,002 / 19,690 |
| average, 4 | 16 / 17 | 15.7 / 16.6 | 782 / 843 | 22% / 90% | 20,224 / 22,534 |
| strong, 1 | 18 / 19 | 16.7 / 18.0 | 324 / 377 | 41% / 93% | 36,078 / 38,868 |
| strong, 2 | 20 / 20 | 19.0 / 19.8 | 653 / 739 | 38% / 92% | 35,069 / 37,398 |
| strong, 4 | 20 / 22 | 19.8 / 21.5 | 1,244 / 1,547 | 36% / 93% | 33,120 / 39,321 |

Average solo, by round:

| Round | 1 to 4 | 5 (boss) | 6 | 8 | 10 (stampede) | 12 | 14 | 15 (boss) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Kills in the round, before / after | 4, 5, 7, 8.9 / 4, 5, 7, 9.0 | 4.6 / 4.9 | 12.0 / 12.0 | 16.3 / 16.6 | 20.8 / 21.1 | 27.0 / 26.7 | 31.9 / 32.2 | 11.5 / 10.3 |
| Nights of 300 that reach it | 300 / 300 | 294 / 300 | 204 / 271 | 182 / 270 | 151 / 238 | 111 / 191 | 104 / 184 | 92 / 164 |
| Die in it | 0% / 0% | 31% / 10% | 1% / 0% | 12% / 7% | 25% / 19% | 1% / 2% | 12% / 11% | 59% / 79% |

**The honest summary: a night is inside the gate and a little easier than before.** The gate (60 nights, seed 4000)
reads 5 / 10 / 15 / 16 / 18 / 18, inside every range and shaped as before. The bigger report reads the average solo
median at 15 (mean 12.6), a round over its range on that sample, and strong players at 19: the first boss night kills
10% of average solo nights (31% before) and the second 79% (59%). Making the middle harder runs into the stampede,
which the gate holds to 40% of the nights that reach it: a health step of 9.5 or 10 (from 8) brought the 300-night
average solo median to 10 and the gate's stampede deaths to 59 and 62% (a step of 9: median 12, deaths 45%), and no
runner health or pay change fixed both. The stampede and the second boss night are where this model says the
head-heavy night is decided, so a next retune (or a smaller head zone) starts there.

**Recommendation to the maintainer: keep the zones, or shrink the head zone.** Kept, the game is balanced and
playable, but a headshot is no longer a choice: 90% of kills are headshots at every level, the multiplier is a flat
damage bonus, the pay premium had to go, and the bots' head share hardly separates the levels (0.68, 0.81, 0.85, where
it was 0.06, 0.15, 0.30). A smaller head zone (the skull and face, not the whole chibi head) would make aim worth
something again; the headshot kill could then go back toward 100, the climb toward 7%, and `SimSkill`'s head rates
would be read again from `test_bot_bands.gd`; the fit tool `tools/hit_fit/` already makes the zones.

**Tooling added.** `balance_cli.gd --skill-set=head_rate=0.7` replaces a number of the level for a try (the sweeps
above ran on it), and the cell has `kills` and `head_kills` by round.

## The weapons now reach their nominal rate (#708)

The simulator always shot a weapon at its nominal interval (`SimWeapons.interval`, with the leftover of a step
carried in `NightSim`), but the real `WeaponState` clamped its cooldown at zero and so rounded every interval up to
whole 60 Hz ticks: the SMG (0.075 s, 4.5 ticks) fired every fifth, 360 shots in 30 s against 400 nominal, the revolver
106 against 107. `WeaponState` now carries the leftover of the tick in which the wait ran out into the next shot (never
more than one shot a tick, nothing banked while idle). Because the model already assumed the nominal rate, the
simulator's table is **unchanged** (60 nights a cell, seed 4000, six cells, identical to the last digit before and
after); the change moves the real game, and the SMG most (up to 11%). The bot-band tests (`test_bot_bands.gd`) read the
real server and are the check on it. Test: `tests/weapons/test_weapon_fire_rate.gd`.

## Using it

```text
uv run --with matplotlib python tools/balance/run_report.py --out <folder> --nights 500
... --set rounds.health_growth=1.06 --set roster.types:brute.share_max=0.04   (try a number, no file edit)
... --brief                                                                   (tables only, no charts)
... --jobs 3                                                                   (cells at once; the default 9 is a lot
on a shared machine)
balance_cli.gd --shopping=weapon_rifle --set=economy.start_points=20000       (what a weapon is worth, price out of it)
```

A Godot `--import` must have run since the last new `class_name` script.

## The perks (#687)

The six perks are played by the same `buy` the night uses and the effects are read from `PerkEffects`: the wait between
shots and the reload per player, a revive held for the helper's own time, the shock as a blast on every dead thing in
reach when a reload starts (with its cooldown and a hold), the carry limit, and what a down takes. What it showed, the
prices, the limit and the loss are in [Perks: what the simulator said](perks.md). Two things for the next change to the
model: **a solo night's median round is not a stable number on a hundred nights** (the same seed gave 13 and 10 on 100
and 150 nights), so compare the mean round and the share of nights that reach round 10 and 14; and **a perk's value
shows in a team**, not a solo night (the loss on a down is the same 11.8 solo with all three settings and 18.6 to 20.2
for four).

## The double-barrel (#684)

The pump shotgun (6 shells, 19 a pellet, 0.8 s, 2.4 s reload) became a double-barrel (2 shells, 22 a pellet, 0.3 s
between barrels, 1.8 s reload, reserve 16 of 32 at most). A first try at 21 a pellet and a 2.0 s reload fell under
the submachine gun in the weapon pick against round 10's health (`test_sim_weapons`), and the average
four-player round-15 reach fell from 91% to 64%; 22 and 1.8 s give the pump's kills a second against that health.
150 nights a cell, seed 1, `tools/balance/run_report.py --brief`, before (the pump) and after:

| Skill, players | Median round before / after | Mean round before / after | Reach r15 before / after |
| --- | --- | --- | --- |
| weak, 1 | 4 / 4 | 4.3 / 4.3 | 0% / 0% |
| weak, 2 | 5 / 5 | 5.3 / 5.4 | 0% / 0% |
| weak, 4 | 5 / 5 | 6.0 / 6.3 | 0% / 1% |
| average, 1 | 10 / 10 | 10.6 / 10.4 | 25% / 20% |
| average, 2 | 13 / 13 | 12.5 / 12.6 | 41% / 36% |
| average, 4 | 15 / 15 | 15.5 / 14.8 | 91% / 77% |
| strong, 1 | 16 / 16 | 15.8 / 15.4 | 72% / 66% |
| strong, 2 | 17 / 19 | 17.2 / 17.8 | 94% / 86% |
| strong, 4 | 19 / 20 | 18.7 / 19.9 | 100% / 100% |

Every median is the same or a round better; the means of the average and strong one-to-two player cells are a few
tenths lower (a magazine of two leaves a player waiting under two seconds in a crowd more often), inside what 150
nights a cell moves. A weapon's magazine and reload time reach the model through `WeaponDef` alone (`SimWeapons`,
`SimArm.reload` is compared with `WeaponState` in a test), so no model code changed.

## The six firearms (#793)

The MP5, PPSh, M4A1, M249, .50 calibre rifle and 870 pump go into the box's pool at #785's weights (10.5 on top of the
old 13) with their rounds on sale at #785's prices, and the re-cut on all six (`UpgradeTuning.weapons`). The gate's six
cells (60 nights, seed 4000; weak solo, average 1, 2, 4 and 8, strong solo; the medians in that order), the baseline
taken from a separate checkout of `main` (`6eb77065`) before any change, every row the same seeds:

| Step | Medians | Average solo mean, headliner time to kill | The gate |
| --- | --- | --- | --- |
| `main` (the control: the six defined and left out of the pool gives these exactly) | 5 / 10 / 15 / 16 / 18 / 18 | 11.57, 29.1 s | passes |
| the six in the pool, their rounds on sale | 5 / **15** / 15 / 17 / 18 / 18 | 12.20, **31.5 s** | average solo 15 (to 14), the boss night kills 85% of weak players (at most 85%), the headliner takes 31.5 s (at most 30) |
| the same without their rounds on sale | 5 / 12 / 14 / 16 / 18 / 18 | 11.13, 31.5 s | only the headliner's time |
| the rounds at x1.5 / x2 the price | 5 / 14 / 15 / 17 / 18 / 18 and 5 / 15 / 15 / 17 / 18 / 18 | 12.08 / 12.13 | the headliner's time (31.2, 31.0 s) and the weak boss night |
| the new weights x0.75 | 5 / 14 / 15 / 17 / 18 / 18 | 11.78, 31.0 s | the headliner's time |
| health growth 1.16 alone | 5 / 14 / 15 / 16 / 18 / 18 | 11.93, 32.2 s | the headliner's time, the weak boss night |
| the headliner at x15 alone | 5 / 15 / 15 / 17 / 18 / 18 | 12.37, 29.4 s | average solo 15 |
| **health growth 1.16 and the headliner at x15** (shipped) | 5 / 14 / 15 / 15 / 18 / 18 | 11.88, 29.8 s | passes (the weak boss night 82%) |

What it says:

- **#785's gate run left the rounds out of the box's pool.** It gave the new guns no ammunition to buy (its players bought
  through the crane and the walls and re-cut), so a weapon ran dry at its reserve; with the rounds on sale the average solo
  night is half a round longer on average and the median jumps from 10 to 15 (the distribution is two humps, so a half
  round is five in the median). The ammunition's own share of the spending stays in its range.
- **Each gun alone moves the headliner's time by a second either way** (the PPSh 30.0, the MP5 31.5, the M4A1 28.9 s,
  pairs 29.9 to 30.7): about 60 headliners are killed in a cell, so the number is good to a second and a half and the
  baseline sits 0.9 under its limit. No single gun is the cause, which is why no number of the guns was moved: they are
  #785's.
- **The lever is the rounds' table, as #785 said it might be** (`health_growth` 1.15 to 1.16 puts the median back to
  14) and the headliner's health (x16.25 to x15, the boss at 92%: its time 29.8 s). Both are in `default_tuning.tres`;
  the bots' risk table (`bot_revive_risk.gd`) follows the boss. The maintainer's decision of the strong solo ceiling
  (19) is in `BalanceTargets`; the cell read 18, so it is headroom.
- **Box only** (the maintainer's rule, #858: a wall sells only the weaker guns): the pump, MP5 and M4A1 have no wall on
  either map. The simulator's players never bought the walls (they reach the guns through the box), so every number above
  is the shipped shop's; the gate was read again after the walls were taken out and is the same.
- **Not modelled**: the .50's and the M249's piercing, the M249's wider shot on the move, the pump's interrupted reload
  (the simulator reloads a pump when it is empty, the 2.8 s of its definition).

Run it: `godot --headless --path game -s <script> -- --set=rounds.health_growth=1.16 --set=roster.types:headliner.health_multiplier=15`
with the six cells of `test_balance_targets.gd` run on worker threads; the sample behind every number above is
60 nights a cell, seed 4000, except where a row says otherwise.
