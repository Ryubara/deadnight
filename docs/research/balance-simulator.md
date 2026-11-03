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

- **Speed.** One solo night costs 0.05 to 0.15 s (a step of 0.25 s of game time, a few thousand `apply`
  calls); four players about 4 times that. 500 nights of all nine cells (3 skills by 1, 2, 4 players) take
  about 3 minutes on 16 cores with nine processes. The CI gate (five cells, 60 nights, seed 4000) takes 40 s as a
  whole suite in CI; it took 1 min 53 s when it ran the batch twice, one cell after another ("about 30 s" was never
  true there). The five cells now run on worker threads (`WorkerThreadPool`), each with its own copy of the tuning,
  and the shipped batch is run once in `before()`. Nights are node-free `RefCounted` objects, so the only shared state
  is the weapon cache, filled first by `SimWeapons.warm()`; a test pins that threaded cells equal serial ones.
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
