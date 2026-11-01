# Rounds, points and fuel

The core loop as rules: how a night is cut into rounds, how each round gets harder, how points flow
and what they buy, and how the generator's fuel drains. The code is `game/gameplay/rules/`; every
number is in one resource, `default_tuning.tres`, and the tests pin the behaviour
(`game/tests/rules/`). Nothing here draws anything.

## Built for a server

Deadnight is network-first: an authoritative server owns the night, and single-player runs the very
same code in-process behind a loopback transport. So the rules are shaped to be owned by a server:

- **One object, no engine.** `GameRules` is a `RefCounted`. It holds all the state (its fields, one
  `PlayerState` per player, one `GeneratorState`, two seeded random streams) and uses no scene-tree
  node, no Godot multiplayer, no clock and no global random.
- **Change only through actions.** `rules.apply(action)` takes a plain dictionary built by
  `RulesAction` (`tick`, `hit`, `kill`, `repair`, `buy`, `set_circuit`, `set_downed`, `add_player`
  and so on) and returns the **events** it caused, also plain dictionaries
  (`{"type": &"points_changed", "player_id": 1, "total": 260, ...}`). The same events go out through
  `event_emitted` after the state has settled. A server applies what clients ask for, broadcasts the
  events, and clients mirror them. The full event list is in the header of `game_rules.gd`.
- **Time is an action.** Time passes only through `RulesAction.tick(delta)`, a fixed step the caller
  owns. Replays and tests do not need a clock.
- **Seeded randomness only.** The seed picks every speed, spawn point roll and crane prize. Same seed
  and same actions give the same night.
- **Snapshots.** `to_dict()` returns everything (Variant data, safe for `var_to_bytes`; the tuning
  is left out because both sides load the same table) and `from_dict()` restores it, random streams
  included, without emitting events. A restored copy continues exactly like the original (tested), so
  a late joiner or a restarted server can pick up mid-night. Random states are 64-bit integers:
  convert them before sending as JSON.
- **Reads change nothing.** `points_of`, `price_of`, `is_door_open` and `zombies_remaining` are
  queries; clients may call them on their mirror.

The world's side: build a zombie when `zombie_spawn_requested` arrives (choose the spawn point with
`point_roll % count`); send `hit` for non-lethal hits and `kill` for the killing blow; send
`zombie_gone` for a death that is not a player's; send `repair` per board; send `set_downed` as
players go down and get up.

## How rounds work

The night starts with a 12 s wait, then rounds run back to back: **active** (zombies spawn until the
round's count is out, the round ends when the last one falls), then a 20 s **break** (spend, switch
lights, reposition), then the next round. Everyone down at once is game over. A player still down
when a round ends gets up, minus a tenth of their points, so being downed hurts but never locks you
out.

## The tuning table

Defaults as shipped. Zombie counts show one, two and four players. "Light" is the ambient level the
world reads (1 is day). Counts follow `6 + 2.4(r-1) + 0.12(r-1)²`, times `1 + 0.6` for each extra
player. Health climbs 18 a round to round 8, then compounds by 7% a round.

| Round | Zombies 1p / 2p / 4p | Health | Walk m/s | Sprinters | Spawn every | Alive cap 1p | Light |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 6 / 10 / 17 | 60 | 0.90 | 0% | 2.40 s | 10 | 0.60 |
| 2 | 9 / 14 / 24 | 78 | 1.00 | 0% | 2.21 s | 12 | 0.56 |
| 3 | 11 / 18 / 32 | 96 | 1.10 | 0% | 2.03 s | 13 | 0.53 |
| 5 | 18 / 28 / 49 | 132 | 1.30 | 14% | 1.72 s | 16 | 0.46 |
| 8 | 29 / 46 / 80 | 186 | 1.60 | 35% | 1.34 s | 21 | 0.35 |
| 10 | 37 / 60 / 104 | 213 | 1.80 | 49% | 1.13 s | 24 | 0.28 |
| 15 | 63 / 101 / 177 | 299 | 2.30 | 50% | 0.75 s | 28 | 0.15 |
| 20 | 95 / 152 / 266 | 419 | 2.80 | 50% | 0.50 s | 28 | 0.15 |
| 30 | 177 / 282 / 494 | 824 | 3.80 | 50% | 0.50 s | 28 | 0.15 |

Points (everything is per player):

| Source | Points |
| --- | ---: |
| Starting points | 200 |
| Hit that does not kill / headshot hit | 4 / 8 |
| Kill / headshot kill / melee kill | 60 / 100 / 130 |
| Repair one board (at most 120 a round) | 12 |
| Round survived, standing | 20 + 10 per round |

Shop (prices at round 1):

| Item | Points | Notes |
| --- | ---: | --- |
| Door: concession stand / booth / back lot | 350 / 750 / 1250 | opens for everyone; each needs the one before |
| Wall weapons: shotgun / rifle | 900 / 1200 | per player |
| Crane play | 500 | random weapon the player lacks (shotgun 4, rifle 3, SMG 2, flare gun 1) |
| Tonics: second wind / hearty / quick hands / fleet | 750 / 1000 / 1500 / 1500 | one of each, four at most |
| Fuel can (+25 units) | 100 + 20 per round | a partial fill pays only for the room |

Generator: 100 units; it burns 0.03 a second idle plus each lit circuit (screen lot 0.06,
concession 0.05, booth 0.08, back lot 0.07), grows 3% a round, and burns at half rate in breaks.
Screen lot only: 0.09 a second, about 18 minutes of tank. Everything lit: 0.29 a second, under 6
minutes, and the draw rises every round.

## Why these numbers

Round-based survival games share a shape that we studied for design only: a steady climb in
numbers, health that grows gently and then compounds, a minority of fast enemies appearing from
the middle rounds, a cap on how many are alive at once, and points that inflate until something
big absorbs them. We took the idea, not any figure; the values above are ours and are reasoned from
the pillars.

- **A night that closes in, three ways at once.** More zombies (the curve steepens, so rounds
  feel like they are slipping away), tougher zombies (straight early so the first rounds teach,
  compounding after round 8 so a starting weapon stops being enough and the shop matters), and
  darker (ambient falls from 0.60 to 0.15 by round 14).
- **Fast ones are rare and capped.** A zombie never exceeds 4.5 m/s, below a sprinting player
  (the controller's sprint is assumed near 6 m/s; revisit with the controller). Sprinters arrive at
  round 4 and settle at one in two, so late rounds pressure positioning instead of simple running.
- **The lot cap protects the web build and the player.** At most 10 alive in round 1, rising to 28;
  each extra player adds 6. Zombies wait their turn, so a big round is a long fight, not a
  wall of bodies.
- **More players, more zombies, less per head.** Each extra player adds 60% of the solo count, and
  spawns come faster, so two people face about 1.6 times the zombies, four face 2.8 times. Points are
  earned from kills, so per-player income stays comparable while the load per head falls: company
  is safer and a little poorer.
- **Points are sized against what a round earns.** A zombie pays about 80 to 100 points all in
  (kill, some headshots, a few hits). Round 1 earns about 500, round 5 about 1,800, round 10 about
  3,400 solo. The first door (350) is within reach after round 1, the booth (750) after round 2 or
  3, the back lot (1250) in the middle rounds, a tonic (1000 to 1500) is a round's work. Kills pay
  by far the most, hits little, so spraying is not worth more than aiming; melee pays double the
  risk. Repair pays a fixed trickle, capped, so board-sitting cannot become the economy. The crane
  at 500 is a gamble: the average weapon is worth more than the play, with a spread.
- **Fuel is the light pillar's price.** Lit ground slows the dead to 60% of their speed, so
  every lit circuit buys safety and costs fuel. Each circuit has its own draw, so *which* parts of
  the lot stay lit is the decision, not whether the lights are on. The estimate below assumes two
  circuits lit:

  | Round | Pts per zombie | Round earns (solo) | Round length | Fuel burnt | Fuel cost | Fuel / earnings |
  | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
  | 1 | 80 | 510 | 32 s | 5.9 | 24 | 5% |
  | 5 | 96 | 1798 | 80 s | 14.1 | 102 | 6% |
  | 10 | 88 | 3376 | 156 s | 29.5 | 331 | 10% |
  | 20 | 88 | 8580 | 388 s | 87.5 | 1680 | 20% |
  | 30 | 108 | 19436 | 716 s | 190.1 | 5170 | 27% |

  Early it is a footnote (a tank lasts many rounds while the doors are the big spend). Through the
  middle rounds a refill is needed every few rounds. In the late game the draw
  grows with the round, the rounds run long, and the can price rises, so fuel climbs toward a quarter of
  income: the generator is always one decision away from running dry. When it does, the lights fade
  (the last tenth of the tank), every circuit goes dark, and the dead move at full speed.

These tables are computed from the tuning by a script from assumed weapon damage (20, then 45 from
round 6, then 90 from round 12), 30% headshot kills and 4 seconds of fighting per zombie, so they
are estimates until the weapons and the controller exist. Retune doors, tonics and fuel together.

## Open questions

- **Points glut after round 12 or so.** Once the doors, weapons and tonics are bought, only fuel
  absorbs points. Ammo and weapon upgrades (the re-cut in the projection booth) are the intended
  sinks; they need their own issue.
- **Weapon damage, ammo and the weapon limit** belong to the weapon work; the health curve assumes
  the damage tiers above.
- **Downed players and revives** are only modelled as down and up; the revive action, bleed-out and
  the exact penalty are for the player work to settle.
