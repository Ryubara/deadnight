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
- **Snapshots.** `to_dict()` returns everything (the tuning table is left out because both sides
  load the same one; its fingerprint, `tuning_id`, and the snapshot `version` are in) and restoring
  brings back the random streams and each living zombie's health without emitting events. A restored
  copy continues exactly like the original (tested), so a late joiner or a restarted server can pick
  up mid-night. **Which form to use:** the dictionary is exact only as Variant data; through plain JSON
  the integer player keys become strings, the 64-bit random states lose bits and some floats change.
  So a save file or a binary message uses `to_bytes()` / `from_bytes()` (`var_to_bytes`), and anything
  inside JSON uses `to_wire()` / `from_wire()` (the same bytes as a base64 string); both restore
  exactly (tested through `JSON.stringify`). A restore returns `""` on success, else `bad_version`,
  `wrong_tuning` (another table: a server deploy that retunes mid-night must not resume old saves) or
  `malformed`, and leaves the night as it was.
- **Reads change nothing.** `points_of`, `price_of`, `is_door_open` and `zombies_remaining` are
  queries; clients may call them on their mirror.

## Actions and events (the seam)

Both are plain dictionaries (numbers, strings, booleans), safe for any transport. `apply` checks
every action first (`RulesAction.validate`, the one schema the server and the tests share): a
missing field, a wrong type, a negative, NaN or oversize tick, a damage outside `0..100000`, an unknown
zone or an unknown id is answered with one `action_rejected` event and **changes nothing**; it
never raises. Names may arrive as Strings (JSON has no `StringName`); whole numbers must be ints.

| Action | Fields | Who sends it |
| --- | --- | --- |
| `hit` | `player_id`, `zombie_id`, `zone` (`head`, `body`, `limb`), `damage` (float, `> 0`), optional `melee` | the weapon code, from a player's shot or swing |
| `repair`, `buy` (`item_id`), `set_circuit` (`circuit_id`, `on`) | `player_id`, ... | a player's request |
| `tick` | `delta` (`0..1` s) | the server's fixed step only |
| `start`, `skip_break`, `add_player`, `remove_player`, `set_downed`, `zombie_gone`, `grant_points` | ... | the server only; never forward these from a client |

**Who owns a zombie's health: the rules.** `zombie_spawn_requested` gives the id and the health the
rules just assigned; from then on the rules track it. A `hit` takes `damage` off (`damage` is what the
weapon dealt, zone multiplier already applied; `zone` only decides the pay), so a kill is never a
claim: it is the hit that empties the health, decided by the server. There is no `kill` action.

| Event | Fields | The world should |
| --- | --- | --- |
| `zombie_spawn_requested` | `zombie_id`, `health`, `speed`, `point_roll` | build the zombie; pick the spawn point with `point_roll % count` |
| `zombie_damaged` | `zombie_id`, `player_id`, `zone`, `damage` (taken off), `health` (left) | play the hit reaction; drive the health bar |
| `zombie_removed` | `zombie_id`, `cause` (`killed` or `gone`), `killer_id`, `zone`, `melee` | play the death for `killed` (by `zone`, `melee`), vanish quietly for `gone` |
| `fuel_changed` | `fuel` (exact), `delta` (whole units since the last one) | move the gauge. Sent only when the whole-unit value changes: about once per unit burnt or bought, never per tick |
| `action_rejected` | `reason`, `action`, optional `field` | tell only the sender; never broadcast |

A `hit` is rejected (`reason`) as `wrong_phase` (not in an active round), `unknown_player`,
`player_downed` or `unknown_zombie`. The last one is routine, not an error: two shots land on the same
dying zombie, and the second is rejected and pays nothing. The world sends `zombie_gone` for a death
that is not a player's (a trap, a fall) and `set_downed` as players go down and get up.

**What a zombie is worth.** The first 4 hits that do not kill pay 4 (8 to the head); the hit that
kills pays the kill (60, head 100, melee 130) instead of a hit. Any hits after the fourth, and hits
on a dead zombie, pay nothing, so a zombie is worth at most 4 hits and a kill (132 with the head)
however many shots it takes; tiny hits cannot farm it. The tables below still hold.

Not the rules' job: whether a client could really have fired that shot (aim, range, rate of fire,
ammo). The server checks that when it builds the `hit`, and the network layer rate-limits.

## How rounds work

The night starts with a 12 s wait, then rounds run back to back: **active** (zombies spawn until the
round's count is out, the round ends when the last one falls), then a 20 s **break** (spend, switch
lights, reposition), then the next round. The night ends (`game_over`) when everyone still in it is
down (`all_down`) or when the last player leaves during the wait or a round (`no_players`), so a
server can free the match; `start` with nobody in the lot is rejected. Leaving before the start is
not an end. A player still down when a round ends gets up, minus a tenth of their points, so being
downed hurts but never locks you out.

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
| Hit that does not kill / headshot hit (first 4 per zombie) | 4 / 8 |
| Kill / headshot kill / melee kill | 60 / 100 / 130 |
| Repair one board (at most 120 a round) | 12 |
| Round survived, standing | 20 + 10 per round |

Shop (prices at round 1):

| Item | Points | Notes |
| --- | ---: | --- |
| Door: concession stand / generator yard / booth / back lot / road | 350 / 500 / 750 / 1250 / 2000 | opens for everyone; the yard and booth need the concession, the back lot the booth, the road the back lot ([the lot](map.md)) |
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

When the doors open, per player (200 starting points, a player's share of the round's zombies at about 85 points
each, the round bonus), the first round whose end covers the running total of the doors so far. "All in" spends
everything on doors; "half" is the plan's pace, the other half going to weapons, fuel and tonics:

| Door | Price | Running total | All in, 1 / 2 / 4 players | Half, 1 / 2 / 4 players |
| --- | ---: | ---: | --- | --- |
| Concession stand | 350 | 350 | 1 / 1 / 1 | 1 / 2 / 2 |
| Generator yard | 500 | 850 | 2 / 2 / 2 | 3 / 3 / 3 |
| Projection booth | 750 | 1,600 | 3 / 3 / 3 | 4 / 5 / 5 |
| Back lot | 1,250 | 2,850 | 4 / 4 / 5 | 6 / 6 / 7 |
| The road | 2,000 | 4,850 | 5 / 6 / 6 | 8 / 9 / 9 |

More players come out a round or so later (less per head), as intended. The map reads these prices from
`default_tuning.tres`, so changing one is one edit there and a rerun of `tools/world/build_greybox.py`.

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
