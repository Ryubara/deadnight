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
| `hit` | `player_id`, `zombie_id`, `zone` (`head`, `body`, `limb`, `weak`), `damage` (float, `> 0`), optional `melee` | the weapon code, from a player's shot or swing |
| `repair`, `buy` (`item_id`), `set_circuit` (`circuit_id`, `on`) | `player_id`, ... | a player's request |
| `tick` | `delta` (`0..1` s) | the server's fixed step only |
| `start`, `skip_break`, `add_player`, `remove_player`, `set_downed`, `zombie_gone`, `grant_points` | ... | the server only; never forward these from a client |

**Who owns a zombie's health: the rules.** `zombie_spawn_requested` gives the id and the health the
rules just assigned; from then on the rules track it. A `hit` takes `damage` off (`damage` is what the
weapon dealt, zone multiplier already applied; `zone` only decides the pay), so a kill is never a
claim: it is the hit that empties the health, decided by the server. There is no `kill` action.

| Event | Fields | The world should |
| --- | --- | --- |
| `zombie_spawn_requested` | `zombie_id`, `zombie_type`, `look`, `boss`, `health`, `speed`, `point_roll`, `damage`, `knockback`, `telegraph_seconds`, `barrier_speed`, `hit_chance` | build the zombie in its `look`; pick the spawn point with `point_roll % count`; its attack, knockback and barrier work come from the same event |
| `zombie_damaged` | `zombie_id`, `zombie_type`, `player_id`, `zone`, `damage` (taken off), `health` (left), `max_health` | play the hit reaction; drive the health bar (a boss's bar is `health / max_health`) |
| `zombie_changed` | `zombie_id`, `zombie_type`, `look`, `speed`, `health` | a limb hit brought a walker to the ground: swap to the crawler look and slow it |
| `zombie_removed` | `zombie_id`, `zombie_type`, `boss`, `cause` (`killed` or `gone`), `killer_id`, `zone`, `melee` | play the death for `killed` (by `zone`, `melee`), vanish quietly for `gone` |
| `special_round_announced` | `round`, `special_id`, `title`, `kind` (`boss` or `only`), `boss_type`, `boss_count`, `seconds` | in the break before a special round: the HUD marquee, the sting, the lights flicker. `seconds` is the whole break, 10 s longer than usual |
| `round_started` | `round`, `zombie_count`, `special_id` (`""` in a normal round), `boss_count` | show the round; a non-empty `special_id` keeps the marquee lit |
| `special_round_cleared` | `round`, `special_id`, `reward` | the reward line; `reward` was paid to each player on their feet as `points_changed` with reason `special_reward` |
| `round_ended` | `round`, `special_id` | |
| `fuel_changed` | `fuel` (exact), `delta` (whole units since the last one) | move the gauge. Sent only when the whole-unit value changes: about once per unit burnt or bought, never per tick |
| `action_rejected` | `reason`, `action`, optional `field` | tell only the sender; never broadcast |

The event's own key is `type`, so a zombie's type is `zombie_type` everywhere; no field is ever called `type`.

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

Every 5th round from round 5 is a special round (below): announced in a longer break, a boss night or a
round of one type, paying a reward when cleared. The night starts with a 12 s wait, then rounds run back to
back: **active** (zombies spawn until the round's count is out, the round ends when the last one falls),
then a 20 s **break** (spend, switch lights, reposition), then the next round. The night ends (`game_over`)
when everyone still in it is down (`all_down`) or when the last player leaves during the wait or a round
(`no_players`), so a server can free the match; `start` with nobody in the lot is rejected. Leaving before
the start is not an end. A player still down when a round ends gets up, minus a tenth of their points, so
being downed hurts but never locks you out.

## The tuning table

Defaults as shipped. Zombie counts show one, two and four players. "Light" is the ambient level the
world reads (1 is day). Counts follow `5 + 2.2(r-1) + 0.12(r-1)²`, times `1 + 0.6` for each extra
player. Health climbs 14 a round to round 8, then compounds by 5% a round. The runner, crawler and
brute columns are each type's share of the round (the first round of a type brings an exact number
instead: see the types below); special rounds replace the mix.

| Round | Zombies 1p / 2p / 4p | Health | Walk m/s | Runners | Crawlers | Brutes | Spawn every | Alive cap 1p | Light |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 5 / 8 / 14 | 60 | 0.90 | 0% | 0% | 0% | 2.40 s | 10 | 0.60 |
| 2 | 7 / 12 / 20 | 74 | 1.00 | 0% | 0% | 0% | 2.28 s | 12 | 0.56 |
| 3 | 10 / 16 / 28 | 88 | 1.10 | 0% | 0% | 0% | 2.17 s | 13 | 0.53 |
| 4 | 13 / 20 / 36 | 102 | 1.20 | 6% | 0% | 0% | 2.06 s | 14 | 0.49 |
| 5 | 16 / 25 / 44 | 116 | 1.30 | 10% | 0% | 0% | 1.95 s | 16 | 0.46 |
| 6 | 19 / 30 / 53 | 130 | 1.40 | 14% | 5% | 0% | 1.86 s | 18 | 0.42 |
| 8 | 26 / 42 / 74 | 158 | 1.60 | 22% | 9% | 3% | 1.68 s | 20 | 0.35 |
| 10 | 35 / 55 / 97 | 174 | 1.80 | 30% | 10% | 5% | 1.51 s | 24 | 0.28 |
| 15 | 59 / 95 / 166 | 222 | 2.30 | 30% | 10% | 6% | 1.17 s | 28 | 0.15 |
| 20 | 90 / 144 / 252 | 284 | 2.80 | 30% | 10% | 6% | 0.91 s | 28 | 0.15 |
| 30 | 170 / 272 / 475 | 462 | 3.80 | 30% | 10% | 6% | 0.54 s | 28 | 0.15 |

Points (everything is per player):

| Source | Points |
| --- | ---: |
| Starting points | 200 |
| Hit that does not kill / headshot hit (first 4 per zombie) | 4 / 8 |
| Kill / headshot kill / melee kill | 60 / 100 / 130 |
| Repair one board (at most 120 a round) | 12 |
| Round survived, standing | 20 + 10 per round |
| Special round cleared, standing | 150 or 200 + 40 per round (by kind, see below) |

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

## Zombie types

A type is data (`ZombieType`, listed in the tuning's `roster`); no code names one. Multipliers are on the
round's own value, so every type grows with the night. The look is a variant from
[zombies](zombies.md), picked by the rules from the spawn roll, so every client shows the same one.

| Type | Looks | Health | Speed | Blow / knockback | Pays | From round | Share of a round | Notes |
| --- | --- | ---: | ---: | --- | ---: | ---: | --- | --- |
| walker | walker, greaser, usher, farmhand | x1 | x1 | 15 / none | x1 | 1 | the rest | a limb hit that leaves it half its health or less brings it down to a crawler |
| runner | runner | x0.55 | x1.7 | 12 / none | x1.2 | 4 (one) | 6%, +4% a round, at most 30% | fast and fragile; replaces the old "sprinter" roll; never above 4.5 m/s |
| crawler | crawler | x0.7 | x0.5 | 12 / none | x1 | 6 (two) | 5%, +2% a round, at most 10% | low (`hit_chance` 0.6 of a walker's), goes under barriers (`barrier_speed` 0) |
| brute | brute | x2.5 | x0.6 | 35 / knocks back 2.5 m | x2.5 | 8 (one) | 3%, +1% a round, at most 6% | tears barriers 2.5 times as fast; up to 8 hits pay |
| headliner (boss) | its own, from the artist | x16, +100% per extra player | x0.8 | 40 / knocks back 4 m, 1.2 s telegraph | x6 | boss nights | boss nights only | weak spot: `weak` hits do x2.2; barriers 4 times as fast; up to 20 hits pay |

**One at a time.** A type's first round brings an exact number (`intro_count`), so every player meets
each one on the same round and never "maybe": the runner on round 4, the crawler on 6, the brute on 8.
After that the share grows. The specials together never take more than 70% of a round. The shuffle,
the counts' remainders, the speed jitter and the look all come from the seeded spawn stream.

**What the zombie behaviour reads.** `zombie_spawn_requested` carries `zombie_type`, `look`, `boss`,
`health`, `speed`, `damage` (a landed blow), `knockback` (metres), `telegraph_seconds` (the wind-up the
player may read and dodge; 0 is the ordinary swing), `barrier_speed` (1 is a walker; 0 skips barriers)
and `hit_chance` (the shot-landing factor for hitboxes). The rules never move a zombie; they say what it
is. A `weak` hit (the boss's lit bulb) is a zone like `head`: the weapon sends it when the ray hits that
box, and the rules multiply the damage by the type's `weak_multiplier` and pay it like a headshot.
Everything is plain numbers and names in the event, so the zombie code and the HUD never look a type up.

## Special rounds and boss nights

Every 5th round from round 5 (`SpecialTuning.every`, `first_round`) is special. The kinds come in turn
and start again:

| Round | Kind | What it is |
| ---: | --- | --- |
| 5 | **Double Feature** (boss) | 40% of a normal round's zombies as escorts, and the headliner walks in after the first 30% of them; one more headliner for every 3 players beyond the first (four players meet two) |
| 10 | **Midnight Stampede** | nothing but runners, 120% of the normal count, spawning twice as often |
| 15 | Double Feature | the same kind again, with the round's health |
| 20 | **Crawl Space** | nothing but crawlers, 110% of the count, spawning 1.5 times as often |

**Announced.** The break before a special round is 10 s longer (`break_bonus_seconds`), and starts with
`special_round_announced` (round, kind, title, `boss_type`, `boss_count`, `seconds`), the cue for the HUD
marquee, the sting and the flickering lights. `round_started` repeats the `special_id` and `boss_count`,
so a client that joined late shows it too.

**Paid.** Clearing it pays every player on their feet a reward on top of the round bonus
(`special_reward`: 200 + 40 per round for a boss night, 150 + 40 per round for the others) and sends
`special_round_cleared`. A boss kill pays x6 the usual kill, and up to 20 hits pay on the way down, so a
boss night is also where the points glut of the late rounds is partly spent.

**A telegraphed attack, a weak spot.** The headliner's blow takes 1.2 s to arrive (`telegraph_seconds`):
the behaviour shows it and the player can step out; the model of a player reads it with
`exp(-telegraph x read)`. The weak spot (`weak` zone) takes x2.2 damage, so aiming pays.

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
  (the controller's sprint is assumed near 6 m/s; revisit with the controller). The runner (the old
  sprinter, now a type) arrives on round 4 and settles at three in ten, fragile enough that a
  good shot ends it, so late rounds pressure positioning instead of simple running.
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
