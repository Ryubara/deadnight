# The balance simulator

What was learnt building a headless balance simulator for the rules engine, so the next change to it starts
from facts. The game-facing description (targets, results) is in [rounds](../design/rounds.md#the-balance-simulator).

## What it is

`game/tools/balance/` plays whole nights through the real `GameRules` with modelled players, in plain
GDScript and no scene tree: `NightSim` (one night), `BalanceBatch` (many nights of one cell, plus the reading
functions), `BalanceTargets` (the ranges), `balance_cli.gd` (one cell to JSON from the command line) and
`tools/balance/run_report.py` (nine cells in parallel Godot processes, then the charts).

## Measured

- **Speed.** One solo night costs 0.05 to 0.15 s (a step of 0.25 s of game time, a few thousand `apply`
  calls); four players about 4 times that. 500 nights of all nine cells (3 skills by 1, 2, 4 players) take
  about 3 minutes on 16 cores with nine processes; the CI gate (five cells, 60 nights, seed 4000) about 30 s.
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
- **Where the model is thin.** Players are bots on a stand-in weapon table (`SimWeapons`), shoot only at
  what they can see (view range falls with the light), turn to one of four sides at a time, and ignore
  barricades, repairs, circuits, grenades, melee and doors (which only cost points). The report is a
  tool for comparing tunings, not a prediction of a person's night; rerun it when the weapons, the player's
  health (#151) or the shop (#152) land.

## Using it

```text
uv run --with matplotlib python tools/balance/run_report.py --out <folder> --nights 500
... --set rounds.health_growth=1.06 --set roster.types:brute.share_max=0.04   (try a number, no file edit)
... --brief                                                                   (tables only, no charts)
```

A Godot `--import` must have run since the last new `class_name` script.
