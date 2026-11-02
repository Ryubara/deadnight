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
  `RulesAction` (`tick`, `hit`, `kill`, `repair`, `tear_board`, `buy`, `set_circuit`, `set_downed`, `add_player`,
  `revive` and so on) and returns the **events** it caused, also plain dictionaries
  (`{"type": &"points_changed", "player_id": 1, "total": 260, ...}`). The same events go out through
  `event_emitted` after the state has settled. A server applies what clients ask for, broadcasts the
  events, and clients mirror them. The full event list is in the header of `game_rules.gd`.
- **Time is an action.** Time passes only through `RulesAction.tick(delta)`, a fixed step the caller
  owns. Replays and tests do not need a clock.
- **Seeded randomness only.** The seed picks every speed, spawn point roll and crane prize. Same seed
  and same actions give the same night. The seed is a required argument of `GameRules.new(tuning, seed)`
  (no default, so a night never starts on a forgotten 0): whoever builds the night, the server, chooses it,
  and `to_dict()` records it as `seed`.
- **One action at a time.** An action sent from inside an `event_emitted` listener, while the events of the
  action before it are still being handed out, is answered with a `reentrant` rejection (returned to that
  caller, never emitted) and changes nothing. Queuing it instead would hide its events from the caller
  that sent it and let the order clients see depend on who listened first; a listener that wants a follow-up
  tells its owner, which sends it once `apply` has returned.
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
  `malformed`, and leaves the night as it was. The version is checked first, so a snapshot of any older
  layout answers `bad_version`; the insides are checked before anything changes (a plan naming no type,
  a zombie without a `type`, a player or the generator missing a field answer `malformed`). The
  version is 10 (5 added the plan and the zombies' type, 6 the players' health, 7 the fence's boards, 8 the
  crane, 9 the re-cut weapons, 10 the match settings); 4 named two
  different layouts and is never used again.
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
| `explosion` | `player_id`, `victims`: a list of `{zombie_id, damage, leg_damage}` (`leg_damage <= damage`) | the grenade code, for one blast ([Grenades](weapons.md#grenades)) |
| `use_grenade` | `player_id` | the grenade code, when the pin is pulled; refused as `no_grenades` when the player has none |
| `blow` | `player_id`, `damage` (float, `> 0`), optional `bearing` (radians clockwise from -z, seen from above; 0 when unknown), optional `source_id` (the zombie) | the night server, for a zombie's landed swing; refused as `wrong_phase`, `unknown_player` or `player_downed` |
| `repair` (`barricade_id`), `buy` (`item_id`, and for ammunition `rounds`), `set_circuit` (`circuit_id`, `on`) | `player_id`, ... | a downed player cannot buy: `purchase_denied` with `PLAYER_DOWNED`, nothing spent (doors, weapons, fuel, all of it); a player's request; the server fills in `rounds` ([ammunition](#ammunition)); a player uses a [breaker post](map.md#the-breaker-posts) to send `set_circuit` |
| `revive` | `player_id` (the one raising), `target_id` (the downed one) | the night server, when a teammate has held use beside the downed player for the whole channel ([Revives](#revives)); refused as `wrong_phase`, `unknown_player`, `self_revive`, `player_downed` (the reviver) or `not_downed` |
| `tear_board` | `barricade_id`, `zombie_id` | the zombie simulation: a zombie finished pulling a board off; server only |
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
| `zombie_removed` | `zombie_id`, `zombie_type`, `boss`, `cause` (`killed` or `gone`), `killer_id`, `zone`, `melee` | play the death for `killed` (by `zone`, `melee`), vanish quietly for `gone` |
| `special_round_announced` | `round`, `special_id`, `title`, `kind` (`boss` or `only`), `boss_type`, `boss_count`, `seconds` | in the break before a special round: the HUD marquee, the sting, the lights flicker. `seconds` is the whole break, 10 s longer than usual |
| `round_started` | `round`, `zombie_count`, `special_id` (`""` in a normal round), `boss_count` | show the round; a non-empty `special_id` keeps the marquee lit |
| `special_round_cleared` | `round`, `special_id`, `reward` | the reward line; `reward` was paid to each player on their feet as `points_changed` with reason `special_reward` |
| `round_ended` | `round`, `special_id` | |
| `zombie_crippled` | `zombie_id`, `zombie_type` (the crawler it became), `look`, `player_id`, `cause` (`legs` or `wounded`), `health` (left), `speed_scale` | switch the zombie to a crawler (lower, slower by `speed_scale`); sent once per zombie, after its `zombie_damaged` |
| `player_hurt` | `player_id`, `damage` (taken off), `health` (left), `max_health`, `bearing`, `source_id` | the HUD's damage arc toward `bearing` (turned by where the player faces), the health bar; the camera shake |
| `player_healed` | `player_id`, `health`, `max_health`, `reason` (`regen` or `revive`) | the health bar. `regen` is sent when the whole-unit health changes (about 25 a second while mending), `revive` once with `player_revived` |
| `player_downed` | `player_id`, `cause` (`blow` or `forced`), `bearing`, `bleed_seconds` (the time they have before they are dead) | the DOWN tag and the held red frame and the clock; the night ends when every player is down or dead |
| `player_revived` | `player_id`, `reviver_id` (the teammate; 0 when the round ended and got everyone up) | the DOWN tag goes; "IS BACK UP" in the feed, or `RUBY REVIVED PAUL` when a teammate did it. Account progression pays the rescue to `reviver_id` (never to a bot). Counts for the reviver on the scoreboard |
| `player_died` | `player_id`, `cause` (`bleed_out`) | the DEAD tag; down until the round ends |
| `grenade_count_changed` | `player_id`, `count`, `reason` (`thrown`, `refill`, `purchase`) | update the grenade count |
| `fuel_changed` | `fuel` (exact), `delta` (whole units since the last one) | move the gauge. Sent only when the whole-unit value changes: about once per unit burnt or bought, never per tick |
| `board_torn` | `barricade_id`, `boards` (left), `zombie_id` | take the top board off that breach; a splinter burst and a sound there |
| `board_repaired` | `barricade_id`, `boards` (now up), `player_id` | put a board back on that breach |
| `action_rejected` | `reason`, `action`, optional `field` | tell only the sender; never broadcast |

The event's own key is `type`, so a zombie's type is `zombie_type` everywhere; no field is ever called `type`.

A `hit` is rejected (`reason`) as `wrong_phase` (not in an active round), `unknown_player`,
`player_downed` or `unknown_zombie`. The last one is routine, not an error: two shots land on the same
dying zombie, and the second is rejected and pays nothing. The world sends `zombie_gone` for a death
that is not a player's (a trap, a fall) and `set_downed` as players go down and get up.

**Who owns a player's health: the rules too.** A player starts with `HealthTuning.max_health` (it is the player's
own `max_health`, so a tonic can raise it), a `blow` takes it off and restarts the wait, and a player at zero is
down. After `regen_delay` seconds without a blow health mends at `regen_per_second` (in a break as well as a
round), announced as `player_healed` whenever the whole-unit value changes. Getting up by the end of the round or a
`set_downed` false restores all of it; getting up by a teammate's hold gives `ReviveTuning.health_fraction` of it
([Revive](revive.md)). Health, its maximum, the wait since the last blow, the bleed-out clock, a hold in progress and
whether a player bled out are in the snapshot.

**What a zombie is worth.** The first 4 hits that do not kill pay 4 (8 to the head); the hit that
kills pays the kill (60, head 100, melee 130) instead of a hit. Any hits after the fourth, and hits
on a dead zombie, pay nothing, so a zombie is worth at most 4 hits and a kill (132 with the head)
however many shots it takes; tiny hits cannot farm it. The tables below still hold.

Not the rules' job: whether a client could really have fired that shot (aim, range, rate of fire,
ammo). The server checks that when it builds the `hit`, and the network layer rate-limits.

## Revives

A downed player stays down until a teammate raises them, they bleed out, or the round ends (then every downed
player gets up with all their health for a tenth of their points; see `down_penalty_fraction`). A teammate holds the use
button within 2.0 m (`NightTuning.revive_reach`) of them for **3.5 seconds** (`HealthTuning.revive_seconds`) and they
get up with **half their health** (`HealthTuning.revive_fraction`), mending again after the usual 5 s without a blow.
Letting go, stepping out of reach or going down starts the time over; being struck does not, so a revive under attack
is the reviver's call. Only in a round. The prompt (`{kind: revive, id, progress, bleed}`) comes before any door's, and
the frame carries `reviving` (whom a player is raising) and `revive` (0 to 1, on the downed one). Two helpers at once do
not speed it up. The rules take only the finished `revive` action; the channel lives in `NightServer`.

**Bleed-out** ([Revive](revive.md)): a downed player has `ReviveTuning.bleed_out_seconds` (45 s) to live. The clock
stands still while a teammate holds the revive on them. At zero they are dead (`player_died`), past reviving, until the
round ends and gets them up like everyone else. The night ends when every player is down or dead. A revive counts for
the reviver (`revives`, the scoreboard's REVIVES column) and pays `ReviveTuning.reviver_points` (0).

## The fence's boards

Six breaches in the field's fence (`barricades` in the tuning: `nw`, `ne`, `w`, `e`, `n`, `n2`) are each closed by
5 boards. The rules keep the count (`GameRules.barricades`, `boards_of(id)`; it rides the snapshot) and change it
only through two actions:

- **`tear_board`** (server only, from the zombie simulation, for a living zombie): one board off, answered by
  `board_torn`; `no_boards` when none are left.
- **`repair`** (a player): one board back, in a break or a round, answered by `board_repaired` and the points
  (`points_changed`, reason `repair`). Refused as `barricade_full` (nothing to put back, so nothing to farm),
  `unknown_barricade`, `player_downed` or `wrong_phase`. The pay stops at the cap (120 from one round's end to the
  next, so a break's repairs count against the next round's), but the board goes up either way.

**Hold to repair** (#297). The player does not press once a board: a press of `interact` at a breach puts the first
board up at once, and the button held down keeps putting boards up, one every `repair_interval` (night tuning, 1.0 s),
at the rules' pay per board (12; nothing else changes). The rules know nothing of it: each `repair` is the same action
a press sends, and the server paces them. The client sends the press (`use`, an edge) and whether the button is still
down (`use_held`, a level) in every command, so it works the same from the keyboard, any gamepad and the touch button,
which all press the `interact` action. The server lets go of the hold, and the next board needs a new press, when:

| Ends with | Because |
| --- | --- |
| the button comes up | that is what holding means |
| the breach is whole | nothing to put back (no `barricade_full` refusal is sent, the hold simply ends) |
| the player is out of reach of the breach, or behind its boards | `use_target` no longer names it; walking back in while still holding does not resume |
| the player is hit (`player_hurt`) | a blow knocks the hammer out of their hand |
| the player fires, reloads or swaps | the hands are busy: a hold is not a thing to do while shooting |
| the player goes down | downed players do nothing |

While the boards go up the player's weapon is put away and a claw hammer is in their hand, nailing each board home
on the rules' beat; the weapon comes back when the hold ends ([Animation](animation.md#repair)).

A board torn off while the player holds is put back too (the hold names the breach, not a count). Nothing else repeats
on a held `interact`: a door, a gun, the crane, a breaker and a fuel can stay one press each. `NightTuning.repair_hold`
(off: one board a press, as before) and `repair_interval` are exported on the night tuning resource. A command that
never arrives is not expired by the server (#163): a stalled client keeps its last level, as it does for `fire`.

Whether a zombie is held at the boards is the simulation's, not the rules': every zombie spawned outside a breach
stops short of its boards while any stand and works on them at its `barrier_speed` (a walker takes 1.2 s a board, the
tuning's `seconds_per_board`: one swing); with none up it walks in; a type with `barrier_speed` 0 (a crawler) goes
under without a stop. How the world draws and holds it is in [the map](map.md#the-fences-breaches).

## How rounds work

Every 5th round from round 5 is a special round (below): announced in a longer break, a boss night or a
round of one type, paying a reward when cleared. The night starts with a 12 s wait, then rounds run back to
back: **active** (zombies spawn until the round's count is out, the round ends when the last one falls),
then a 5 s **break** (spend, switch lights, reposition), then the next round. The night ends (`game_over`)
when everyone still in it is down (`all_down`) or when the last player leaves during the wait or a round
(`no_players`), so a server can free the match; `start` with nobody in the lot is rejected. Leaving before
the start is not an end. A player still down when a round ends gets up, minus a tenth of their points, so
being downed hurts but never locks you out. A player who bled out gets up then as well; their death lasts for the rest
of the round ([Revive](revive.md#the-states)).

## Match settings

What whoever starts a match chooses before the night: how intense it is, how many may stand at once and how long
the breaks are. There is no round time limit: a round ends when its last zombie falls, whatever the settings.
`MatchSettings` (`game/gameplay/rules/match_settings.gd`).
The server owns them (`GameRules.settings`), they ride the rules' snapshot (`match_settings`, so the WELCOME of the
first player, a late joiner and a player coming back all carry them) and they are set only while the night has not
started. The defaults are today's game exactly, and every shipped test runs on them unchanged.

| Setting | Values | Default | What it does |
| --- | --- | --- | --- |
| `count_multiplier` (the night's intensity) | 1x, 2x, 3x offered on the Play screen; any 0.25 to 5 | 1x | round N brings `RoundTuning`'s count for N and the players times this, rounded, at least one, and the dead come this many times as fast (below) |
| `max_alive` | 0 (auto) or 1 to 40 | auto | a number replaces the round's alive cap and never goes above `alive_cap_ceiling` (40, the crowd the lot stands); auto is the tuned cap times the multiplier |
| `break_seconds` | 0 (the tuned 5 s) or 1 to 120 | 0 | the break after each round; the wait before round 1 (12 s) and the 10 s extra before a special round are unchanged |

- **Where the multiplier applies.** To the tuned count of a normal round, which is also what a special round starts
  from (a stampede is 110% of the scaled count, an escort party its share of it). A new type's first round still
  brings its exact `intro_count`, and a boss round its own bosses (by players, not by the multiplier): the lesson of
  meeting each type once stays whatever the crowd.
- **The multiplier is intensity, not a longer round.** The spawn interval divides by the multiplier
  (`MatchSettings.spawn_interval`) and the auto alive cap multiplies by it (`MatchSettings.alive_cap`, at most
  `alive_cap_ceiling`), so 3x the dead arrive in about the time of 1x and 3 times as many stand at once. Without the
  cap scaling the round still stretched: at round 10 the tuned cap (13) is the limit on 3x the spawn rate, and the
  rounds ran 15 to 26% longer at 3x. The interval never goes below `RoundTuning.spawn_interval_floor`, **0.2 s** (5 a
  second): it is what four players already reach at 1x (the tuned minimum 0.5 s over 2.5), so no crowd or multiplier
  asks the spawner for more. The floor only holds a multiplier above 1x back, and never slows an interval already
  under it, so the defaults (and a lot of 4 or more at 1x) change nothing. A cap the host chose is not scaled.
  Proof (`test_a_round_lasts_about_as_long_at_2x_and_3x_as_at_1x`): a player who kills each zombie 7 s after it
  stands, rounds 1 to 10, seed 7. Seconds per round at 1x / 2x / 3x: round 1 18.1 / 19.7 / 20.2, round 3 26.2 /
  27.7 / 28.2, round 6 37.2 / 38.5 / 39.0, round 8 47.0 / 48.2 / 48.6, round 10 (the stampede) 43.0 / 44.2 / 44.2.
  Every round from 2 is within 10% of 1x (round 2 at 3x is the edge, 10%; the rest are 1 to 8%) and
  round 1, with 4 zombies at 1x, within 15% (12%): the wait before the first zombie and the last one's
  life are fixed, and N zombies have N-1 gaps.
- **Setting them.** `RulesAction.configure(settings)` (the one action, refused as `wrong_phase` once the night began,
  as `out_of_range` with field `settings` for a value out of bounds; it answers `settings_changed`), or the
  constructor `GameRules.new(tuning, seed, settings)`, which pulls values into bounds with `clamped()`.
  `NightServer.new(..., settings)` and `Night.match_settings` (before `start`) carry them for a night on this machine,
  and `NightScreen.match_settings` is the Play screen's hand-over, taken once.
- **For a room host.** `NightHost.configure_match(settings)` is the hook: it applies at once to a night nobody has
  started (returning true), otherwise keeps them for the next night the host builds (false). A `GameServer` room is
  a `NightHost`, so it is `room.configure_match(settings)` after `room.built`, or `room.match_settings = settings`
  before it is added to the tree. The panel for the host's lobby is `MatchSettingsPanel`
  (`game/ui/components/match_settings_panel.gd`, built from `UIRow`, `UIOptionSelector` and `UISlider`): `settings()`
  reads it, `set_settings()` shows a value without a signal, `set_editable(false)` is the guest's read-only view of
  what the WELCOME carried (`MatchSettings.from_snapshot(welcome["snapshot"])`; `Night.match_settings` after
  `start_remote`), and `changed` fires when a control moves. A dedicated server takes `--count`, `--max-alive`
  and `--break`.

## The tuning table

Defaults as shipped. Zombie counts show one, two and four players. "Light" is the ambient level the
world reads (1 is day): round 1 is the lot's night as built and round 14 the darkest it gets, with the ambient light,
moon, sky and fog dimmed in step and eased over the break (`NightLight`). Counts follow
`4 + 1.3(r-1) + 0.07(r-1)²`, times `1 + 0.6` for each extra player. Health climbs 8 a round to round 8, then
compounds by 7% a round (it was 5% until weapons could be re-cut, [the re-cut](upgrades.md)). The runner,
crawler and brute columns are each type's share of the round (the first
round of a type brings an exact number instead: see the types below); special rounds replace the mix.

| Round | Zombies 1p / 2p / 4p | Health | Walk m/s, lit | Runners | Crawlers | Brutes | Spawn every | Alive cap 1p | Light |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 4 / 6 / 11 | 50 | 1.20 | 0% | 0% | 0% | 3.20 s | 6 | 0.60 |
| 2 | 5 / 9 / 15 | 58 | 1.36 | 0% | 0% | 0% | 3.07 s | 7 | 0.56 |
| 3 | 7 / 11 / 19 | 66 | 1.52 | 0% | 0% | 0% | 2.95 s | 8 | 0.53 |
| 4 | 9 / 14 / 24 | 74 | 1.68 | 6% | 0% | 0% | 2.83 s | 8 | 0.49 |
| 5 | 10 / 17 / 29 | 82 | 1.84 | 10% | 0% | 0% | 2.72 s | 9 | 0.46 |
| 6 | 12 / 20 / 34 | 90 | 2.00 | 14% | 5% | 0% | 2.61 s | 10 | 0.42 |
| 8 | 17 / 26 / 46 | 106 | 2.32 | 22% | 9% | 3% | 2.40 s | 12 | 0.35 |
| 10 | 21 / 34 / 60 | 121 | 2.64 | 30% | 10% | 5% | 2.22 s | 13 | 0.28 |
| 15 | 36 / 57 / 101 | 170 | 3.44 | 30% | 10% | 6% | 1.81 s | 17 | 0.15 |
| 20 | 54 / 86 / 151 | 239 | 4.24 | 30% | 10% | 6% | 1.47 s | 21 | 0.15 |
| 30 | 101 / 161 / 282 | 470 | 5.00 | 30% | 10% | 6% | 0.98 s | 28 | 0.15 |

Points (everything is per player):

| Source | Points |
| --- | ---: |
| Starting points | 200 |
| Hit that does not kill / headshot hit (first 4 per zombie) | 4 / 8 |
| Kill / headshot kill / melee kill | 60 / 100 / 130 |
| Kill by a grenade blast | 40 (times the type's pay, like a bullet's) |
| Repair one board (at most 120 from one round's end to the next) | 12 |
| Round survived, standing | 20 + 10 per round |
| Special round cleared, standing | 150 or 200 + 40 per round (by kind, see below) |

Shop (prices at round 1):

| Item | Points | Notes |
| --- | ---: | --- |
| Door: concession stand / generator yard / booth / back lot / road | 350 / 500 / 750 / 1250 / 2000 | opens for everyone; the yard and booth need the concession, the back lot the booth, the road the back lot ([the lot](map.md)) |
| Wall weapons: shotgun / rifle | 900 / 1200 | per player |
| Crane play | 550 | a spin, then a random weapon the player lacks to take (shotgun 4, rifle 3, SMG 2, flare gun 1); may break down and refund ([the crane](#the-prize-crane)) |
| Re-cut of the weapon in hand | 1500, +1500 for each weapon already re-cut | x1.75 damage, x1.5 magazine and reserve limit, filled; once a weapon ([the re-cut](upgrades.md)) |
| Tonics: second wind / hearty / quick hands / fleet | 750 / 1000 / 1500 / 1500 | one of each, four at most; only hearty does anything yet: +50 most health ([the hearty tonic](upgrades.md#the-hearty-tonic)) |
| Fuel can (+25 units) | 100 + 20 per round | a partial fill pays only for the room |
| Grenades (+2) | 150 + 5 per round | up to 5 carried; a part purchase pays a part price |
| Ammunition: revolver / tommy gun / shotgun / rifle / flare gun | 50 / 90 / 80 / 80 / 90 | rounds added: 20 / 60 / 8 / 8 / 2 (see [ammunition](#ammunition)) |

Generator: 100 units; it burns 0.03 a second idle plus each lit circuit (screen lot 0.06,
concession 0.05, booth 0.08, back lot 0.07), grows 3% a round, and burns at half rate in breaks.
Screen lot only: 0.09 a second, about 18 minutes of tank. Everything lit: 0.29 a second, under 6
minutes, and the draw rises every round.

## The prize crane

Modelled on the Call of Duty Zombies Mystery Box ([research](../research/mystery-box.md)): a play costs 550, the claw
digs for 4.5 seconds, then the chosen weapon floats for 12 seconds and only the buyer can take it. A weapon the player
carries is never drawn; the draw is seeded (its own stream, `crane_rng_state` in the snapshot). The first 3 plays at a
place never break down; after that the chance is 15% for four plays, 30% for four more, then 50%. A breakdown refunds
the whole price (not counted as earned), shows a dud prize for 4 seconds and moves the crane to one of the other
places whose door is open ([the places](map.md#the-cranes-places)); with no other place open it cannot break down.
The numbers are `CraneTuning` and the item `crane_play` in `default_tuning.tres`.

**Why 550.** The balance simulator ([the crane's price](../research/balance-simulator.md#the-cranes-price)) was run
with the crane from 500 to 950 (the Mystery Box's own price). The dearer the play, the later an average solo player
has a second weapon: the balance gate's median round (the average solo cell) is 11 at 500 and 550, 10 at 600 and 650,
9 at 750, under its floor of 10. 550 keeps the range with a round to spare and still costs under the cheaper wall
weapon (900); a prize is worth about what the walls charge for it, and the SMG and flare gun are sold nowhere else.

## Ammunition

The reserve of every weapon is finite: the night gives a weapon its starting reserve when the player gets it
([Weapons](weapons.md#the-arsenal)) and nothing refills it by itself. The shop sells rounds, one item per weapon
(`ammo_pistol`, `ammo_smg`, `ammo_shotgun`, `ammo_rifle`, `ammo_flare_gun`; the crowbar needs none).

- **The rules price, the combat server counts.** The reserve is the combat server's (it already owns the magazine and
  the reload), so a purchase is `RulesAction.buy(player, item, rounds)` with `rounds` the room the weapon's reserve
  has, filled in by the server (`NightServer.buy`). The rules charge the price for exactly the rounds that fit
  (rounded up to a whole point, like fuel and grenades), cap them at what one purchase holds (`ShopItem.amount`), and
  answer `purchase_denied` with `AMMO_FULL` when nothing fits, taking no points. The purchase's `detail` is
  `{ammo: weapon, rounds: n}`, and the server turns it into a `CombatAction.add_ammo`, which never passes the
  weapon's `reserve_max`.
- **The magazine is not filled by a purchase**: rounds go to the reserve and a reload moves them across.
- **Ammunition goes to the weapon the item names**, not the one in hand, so a player can top up the rifle while holding
  the revolver. A weapon not carried takes none (the server offers `0` rounds room).

## Zombie types

A type is data (`ZombieType`, listed in the tuning's `roster`); no code names one. Multipliers are on the
round's own value, so every type grows with the night. The look is a variant from
[zombies](zombies.md), picked by the rules from the spawn roll, so every client shows the same one.

| Type | Looks | Health | Speed | Blow / knockback | Pays | From round | Share of a round | Notes |
| --- | --- | ---: | ---: | --- | ---: | ---: | --- | --- |
| walker | walker, greaser, usher, farmhand | x1 | x1 | 15 / none | x1 | 1 | the rest | a blast that takes its legs ([grenades](weapons.md#grenades)) turns it into a crawler, `zombie_crippled` |
| runner | runner | x0.55 | x1.4 | 12 / none | x1.2 | 4 (one) | 6%, +4% a round, at most 30% | fast and fragile; replaces the old "sprinter" roll; never above 5.0 m/s under the lights |
| crawler | crawler | x0.7 | x0.4 | 12 / none | x1 | 6 (two) | 5%, +2% a round, at most 10% | low (`hit_chance` 0.6 of a walker's), goes under barriers (`barrier_speed` 0); also what a crippled walker becomes |
| brute | brute | x2.5 | x0.4 | 35 / knocks back 2.5 m | x2.5 | 8 (one) | 3%, +1% a round, at most 6% | tears barriers 2.5 times as fast; up to 8 hits pay |
| headliner (boss) | its own, from the artist | x13, +100% per extra player | x0.45 | 40 / knocks back 4 m, 1.2 s telegraph | x6 | boss nights | boss nights only | weak spot: `weak` hits do x2.2; barriers 4 times as fast; up to 20 hits pay |

**One at a time.** A type's first round brings an exact number (`intro_count`), so every player meets
each one on the same round and never "maybe": the runner on round 4, the crawler on 6, the brute on 8.
After that the share grows. The specials together never take more than 70% of a round. The shuffle,
the counts' remainders, the speed jitter and the look all come from the seeded spawn stream.

**What the zombie behaviour reads.** `zombie_spawn_requested` carries `zombie_type`, `look`, `boss`,
`health`, `speed`, `damage` (a landed blow), `knockback` (metres), `telegraph_seconds` (the wind-up the
player may read and dodge; 0 is the ordinary swing), `barrier_speed` (1 is a walker; 0 skips barriers)
and `hit_chance` (the shot-landing factor for hitboxes). The rules never move a zombie; they say what it
is. The night reads all of them: damage, knockback, the telegraph, the look, `barrier_speed` (how fast it
tears the fence's boards, below) and `hit_chance` (which sizes the zones;
[zombies research](../research/zombies.md#types-in-the-night)). A `weak` hit (the boss's lit bulb) is a zone like
`head`: the weapon sends it when the ray hits that box (`Hitbox.WEAK`, only on a zombie that has a weak spot: the
headliner), and the rules multiply the damage by the type's
`weak_multiplier` and pay it like a headshot.
Everything is plain numbers and names in the event, so the zombie code and the HUD never look a type up.

## Special rounds and boss nights

Every 5th round from round 5 (`SpecialTuning.every`, `first_round`) is special. The kinds come in turn
and start again:

| Round | Kind | What it is |
| ---: | --- | --- |
| 5 | **Double Feature** (boss) | 40% of a normal round's zombies as escorts, and the headliner walks in after the first 30% of them; one more headliner for every 3 players beyond the first (four players meet two) |
| 10 | **Midnight Stampede** | nothing but runners, 110% of the normal count, spawning 1.8 times as often (140% before a player carried only two weapons, #410; an open question for the maintainer) |
| 15 | Double Feature | the same kind again, with the round's health |
| 20 | **Crawl Space** | nothing but crawlers, 110% of the count, spawning 1.5 times as often |

**Announced.** The break before a special round is 10 s longer (`break_bonus_seconds`), and starts with
`special_round_announced` (round, kind, title, `boss_type`, `boss_count`, `seconds`), the cue for the HUD
marquee, the sting and the flickering lights. `round_started` repeats the `special_id` and `boss_count`
for a client that is there at the time. A client that joins late gets a snapshot, not these events: its HUD reads
`special_id` and the bosses' health from the snapshot and the schedule from the shared tuning, so it shows the
banner, the boss bar and, in a break, the marquee too ([HUD](hud.md)).

**Paid.** Clearing it pays every player on their feet a reward on top of the round bonus
(`special_reward`: 200 + 40 per round for a boss night, 150 + 40 per round for the others) and sends
`special_round_cleared`. A boss kill pays x6 the usual kill and up to 20 hits pay on the way down, so a
boss night adds to the points glut of the late rounds; nothing is spent there.

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
- **The dead are fast under the lights, faster in the dark.** The walker's pace follows the original games'
  speed tiers ([movement speeds](../research/movement-speeds.md)): `1.2 + 0.16 (round - 1)` m/s, about 1.8 on round 5,
  2.6 on round 10 and 3.4 on round 15, a little under the pace the games' run tier has there (BO3: 1.9, 2.8, 3.9);
  the runner (the games' sprint tier, now a type, x1.4) arrives on round 4 at 2.4 and passes the player's run speed
  (4.8) from round 15. Under the lights
  nothing exceeds 5.0 m/s, a hair above the player's run, so running alone no longer shakes the fastest while a
  sprint (7.0) still gains 2 m/s. Ground that is not lit (a circuit off, the generator dry) makes every zombie 25%
  faster (`dark_speed_multiplier`), at most 6.25 m/s, still under the sprint. The brute, crawler and headliner keep
  their old pace in metres per second (x0.4, x0.4, x0.45): they are slow by design, not by round.
- **The lot cap protects the web build and the player.** At most 6 alive in round 1, rising 0.8 a round to 28;
  each extra player adds 6, and no count of players takes it past 40, the most the lot stands
  ([crowd budget](zombies.md#crowd-budget)). Zombies wait their turn, so a big round is a long fight, not a
  wall of bodies.
- **More players, more zombies, less per head.** Each extra player adds 60% of the solo count, and
  spawns come faster, so two people face about 1.6 times the zombies, four face 2.8 times. Points are
  earned from kills, so per-player income stays comparable while the load per head falls: company
  is safer and a little poorer.
- **Points are sized against what a round earns.** A zombie pays about 80 to 100 points all in
  (kill, some headshots, a few hits). Round 1 earns about 350, round 5 about 1,700, round 10 about
  3,500 solo (the stampede pays well). The first door (350) is within reach after round 1, the booth (750)
  after round 2 or 3, the back lot (1250) in the middle rounds, a tonic (1000 to 1500) is a round's work. Kills pay
  by far the most, hits little, so spraying is not worth more than aiming; melee pays double the
  risk. Repair pays a fixed trickle, capped, so board-sitting cannot become the economy. The crane
  at 500 is a gamble: the average weapon is worth more than the play, with a spread.
- **Fuel is the light pillar's price.** The light does not slow the dead: it keeps them at their round's pace,
  and ground that is not lit makes them 25% faster, so every lit circuit holds the line and costs fuel. Each
  circuit has its own draw, so *which* parts of the lot stay lit is the decision, not whether the lights are on.
  The table is the simulator's average solo player, who keeps two circuits lit (screen lot and concession, 0.14 a
  second with the idle draw), measured in [the report](#the-balance-simulator): round length is what it took, the burn
  counts the break after it at half rate, the cost is the can's price for that many units:

  | Round | Round earns (solo) | Round length | Fuel burnt | Fuel cost | Fuel / earnings |
  | ---: | ---: | ---: | ---: | ---: | ---: |
  | 1 | 347 | 19 s | 4.1 | 20 | 6% |
  | 5 | 1,726 | 36 s | 7.2 | 57 | 3% |
  | 10 | 3,533 | 48 s | 10.3 | 124 | 4% |
  | 12 | 2,570 | 68 s | 14.6 | 198 | 8% |

  Early it is a footnote (a tank of 100 lasts many rounds while the doors are the big spend); in the
  middle rounds a refill is needed about every five rounds, and the average solo player spends about 260
  points a night on cans. The draw grows 3% a round, the rounds run longer and the can's price rises
  20 a round, so fuel takes a growing share of income as the night goes on (round 12 is already
  8%): the generator is always one decision away from running dry. When it does, the lights fade (the
  last tenth of the tank), every circuit goes dark, and the dead speed up by a quarter everywhere.
- **An empty tank is not the end.** The circuits keep their switches (a circuit can be thrown dry and lights when fuel
  comes), nothing burns, and the only way back is a fuel can: a player walks to a can stand (one in the concession
  stand, one by the generator's cage in the yard; [the lot](map.md#the-fuel-cans)), presses `use` and pays the can's
  price. The card shows the price and the units it adds (only the room that is left, for a part price); a full tank
  refuses. The tank rises at once, `fuel_restored` fires, the lamps and the lit pace come back, and the generator's card
  shows. The yard's stand needs the yard's door and the stand's the concession's, so before the first door there is no
  fuel to buy: the starter tank has to last until the concession is bought.

When the doors open, per player (200 starting points, a player's share of the round's zombies at about 85 points
each, the round bonus), the first round whose end covers the running total of the doors so far. "All in" spends
everything on doors; "half" is the plan's pace, the other half going to weapons, fuel and tonics:

| Door | Price | Running total | All in, 1 / 2 / 4 players | Half, 1 / 2 / 4 players |
| --- | ---: | ---: | --- | --- |
| Concession stand | 350 | 350 | 1 / 1 / 1 | 2 / 2 / 2 |
| Generator yard | 500 | 850 | 2 / 2 / 3 | 4 / 4 / 4 |
| Projection booth | 750 | 1,600 | 3 / 4 / 4 | 5 / 6 / 6 |
| Back lot | 1,250 | 2,850 | 5 / 5 / 6 | 7 / 8 / 9 |
| The road | 2,000 | 4,850 | 7 / 7 / 8 | 10 / 11 / 12 |

More players come out a round or so later (less per head), as intended. The retune of the zombie counts
(#188) pushed every door about a round later than before. The map reads these prices from
`default_tuning.tres`, so changing one is one edit there and a rerun of `tools/world/build_greybox.py`.

The door table is an estimate from the tuning (the counts and prices alone, no weapons); the simulator
below is the measured version, and the fuel table above is read from it. Retune doors, tonics and fuel
together.

## The balance simulator

Balance is measured, not guessed. `game/tools/balance/` plays thousands of seeded nights through the real
`GameRules` (the rules are node-free, so it runs headless and fast) with modelled players, and
`tools/balance/run_report.py` turns nine cells (weak, average and strong players, by 1, 2 and 4 players) into
tables and charts. The research page [balance simulator](../research/balance-simulator.md) has the speeds,
the traps and how to run it; the numbers below are its report for 300 nights per cell (seed 1000).

**Where each number comes from.** The simulator models only what the rules do not own, and reads the rest
from the game:

| What | Source |
| --- | --- |
| Damage, pellets, falloff, zone multipliers, fire interval, magazine, reload | the weapon definitions (`WeaponCatalog`, priced with `DamageModel`, the functions the combat server uses) |
| A flare's pull on the dead | the definition's `lure_radius` and `lure_seconds`; it hurts no one ([zombies](zombies.md#the-flare-lure)) |
| Health, regeneration delay and rate | `HealthTuning` in the rules' table (100, 5 s, 25 a second) |
| A zombie's blow and swing | the type's `damage` (the night reads the same since #191), `ZombieTuning.swing_seconds` |
| Lit ground | `GeneratorState`: a circuit keeps the dead at their round's pace (off it they are faster) only while it is on and the tank has fuel, and every circuit burns fuel |
| Everything else (where zombies are, whether a shot lands, who buys what) | the model: `SimSkill` and `NightSim` |

**The players.** Three levels of `SimSkill`: how many shots land and where (head, limb, a boss's weak spot),
how much of the time they shoot (reloads are in the weapon, so this is the time not spent moving or looking),
how often a blow misses them, how well they read a telegraphed blow, how much of the walk to them is on lit
ground and which circuits they keep on for it (weak: the screen lot; average: plus the concession; strong: plus
the booth), and what they buy, in order. Each night draws its own skill within 20% of the level's, so a level is
a spread of nights. A touch player with the aim assist (`--assist=`, `SimSkill.with_touch_assist`) has the misses
the assist wins back added to the accuracy, by what a thumb bot measured
([Touch aim assist](../research/aim-assist.md#how-much-it-is-worth)); the gate's cells never use it. They shoot
only what they can see (view range falls with the light), face one of four sides
at a time, revive each other in `ReviveTuning.revive_seconds` (a player nobody reaches within
`bleed_out_seconds` is dead until the round ends) and mend between rounds, and pick the weapon with the best sustained
damage a second. **Not modelled:** the other three tonics (they do nothing yet). Grenades, repair, the fence's boards (the
simulator keeps its own six-second barrier) and the doors' and spots' geometry (they only cost points) are not
modelled either.

**Ammunition and the shop** (#152). The players carry the revolver and the crowbar from the start and every weapon
they buy or win with the reserve the weapon gives; rounds only come from the shop, at the shop's price for the
rounds that fit (`NightSim` asks the rules the same `buy` the night does). Between rounds a player, in order: buys
fuel, buys rounds up to a reserve of `ammo_floor_mags` magazines for each weapon worth shooting (at least half the
best one's sustained damage), buys the things they are saving for, and with what is left over (keeping the price of
the next goal) tops the reserves up (weak players to half, the others to full). Before a special round, which the
marquee announces, everyone fills up first. In a round a player takes another loaded weapon in hand when it does 40%
more damage a second to the target in front of them (a shotgun for what is at the door, the rifle for what is far;
weak players do not); a weapon that runs dry is put away for the next; when what is left is worth less than three
quarters of the best weapon carried and the player has points, they run to a locker (8 s without shooting) and buy
rounds; with nothing to shoot and nothing to pay with they swing the crowbar (130 points a kill, at arm's length
only). Reserves, reloads and prices are the game's own numbers.

**The change that made this honest** (#188). The first simulator shot a stand-in table (a rifle at 210 damage a
second). With the real definitions and reloads the best weapon is the SMG at about 100 and the rifle comes
after it at about 85; the pistol is 59, so **no weapon the shop sells is a big step up from the pistol**, which
sits badly with the "a starting weapon stops being enough" pillar above (see the open questions). Same seeds,
medians of the gate's cells (1 player unless noted):

| Model and tuning | weak | average | average, 2 / 4 players | strong |
| --- | ---: | ---: | ---: | ---: |
| Stand-in table, old tuning (as merged in #166) | 5 | 11 | 13 / 15 | 14 |
| Real weapons, lit circuits that cost fuel, old tuning | 3 | 4 | 8 / 9 | 10 |
| Real weapons, retuned, ammunition free (as merged in #197) | 5 | 12 | 14 / 15 | 15 |
| Finite ammunition bought at the shop's prices, the boss retuned (#152, the tables on this page) | 5 | 11 | 12 / 14 | 14 |

Finite ammunition cost the average solo player one round and the others up to one: the gate's ranges hold for
every median. It did fail one target, the first boss night's toll on weak players (84% die at 300 nights, 90% on the
gate's 60 at seed 4000, limit 85%), and the one retune is the headliner's health, **15 to 13 times a walker's**: a
weak player has the revolver and what they could pay for, so the boss costs them more than it did when every reserve
was full. At 14 it kills 80%, at 13 72% (74% before), at 12 63%; the average solo player's boss night is 8% either
way. What it changes is who is hard pressed: reserves are small (a revolver holds 90 rounds at most,
a shotgun 54) against a round-10 horde of 21 that takes some 150 revolver rounds, so the late rounds are fought
from the lockers.

The retune made the dead fewer, softer, slower to arrive and fewer at once: counts `4 + 1.3(r-1) + 0.07(r-1)²`
(were 5, 2.2, 0.12), health 50 plus 8 a round (were 60 and 14), spawns every 3.2 s decaying 4% a round (2.4 s,
5%), 6 alive at once rising 0.8 a round (10 and 1.5). The headliner has 13 times a walker's health (was 16; 15
until finite ammunition, see below)
and the stampede is 140% of a round (was 120%). No type's blow changed.

**Survival by round** (share of nights that reach the round; 50% is the median):

| Players | Skill | Median round | Reach round 10 | Reach round 15 |
| ---: | --- | ---: | ---: | ---: |
| 1 | weak / average / strong | 5 / 11 / 14 | 0% / 80% / 100% | 0% / 0% / 19% |
| 2 | weak / average / strong | 5 / 12 / 15 | 6% / 97% / 100% | 0% / 2% / 78% |
| 4 | weak / average / strong | 5 / 14 / 16 | 9% / 96% / 100% | 0% / 19% / 99% |

An average solo player reaches round 11 (the target is 10 to 14: inside its range, a round from the low edge),
company adds two or three rounds, skill adds three. Rounds 1 to 4 are safe for nearly everyone; the first deaths are the
first boss night, and a weak player's median of 5 is that night: they reach it and about seven in ten do not
leave it (it was three in four before ammunition was sold; with finite ammunition and the boss at 15 times a
walker's health it was five in six, over the gate's limit, which is why the boss is at 13).

**Economy.** An average solo night earns about 14,400 points and spends about 7,300 of them (51%), 2,700 of that on
ammunition (19% of what it earns); a strong one earns 26,600, spends 9,200 and 3,300 on ammunition. Before
ammunition was sold the same player spent 4,700 of 16,800 (28%). The shop still runs out (doors, two wall weapons,
the crane, rounds and fuel were all there was to buy; the re-cut and the hearty tonic came later, see below), so
the points glut in "Open questions" remains, smaller. Earnings per round climb from 350 in round 1 to 1,700 in
round 5 and 3,500 in the stampede round.
Light costs fuel: the average player buys cans for about 260 points a night.

**Time to kill** (seconds under fire from the first hit, solo average): walker 1.5, runner 0.8, crawler 2.1,
brute 5.4, headliner 16.

**How hard each special round is.** The measure is how close a round came to downing a player (the lowest
health reached, 0 to 1), and the spike is that over the mean of the rounds either side (each plus 0.05):

| Round | Kind | Solo average | 2 players average | 4 players average | Weak solo | Strong solo |
| ---: | --- | --- | --- | --- | --- | --- |
| 5 | Double Feature | x3.0, 8% die | x2.8, 3% die | x6.6, 4% die | x2.2, 72% die | x1.2, 0% die |
| 10 | Midnight Stampede | x0.9, 16% die | x0.5, 0% die | x1.0, 0% die | not reached | x0.8, 0% die |
| 15 | Double Feature | not reached | the wall by then | x1.1, 90% die | not reached | x0.8, 54% die |

The first boss night is a spike for the players it was tuned for: three to seven times the pressure of
the rounds around it, about one night in twelve lost solo, one in thirty in company. The first report's
two findings, and what was decided:

- **A strong player barely feels the first boss night** (x1.1). It stays that way, on purpose. Raising the
  headliner's health from 16 to 22 times a walker's made it x2.1 for strong players but killed nearly every weak
  player at it (about 75% die at 15, 90% at 16, 95 to 100% at 22): weak players never land the weak spot, so their kill
  rate falls off a cliff. The boss is tuned to leave weak players a chance; making strong players feel it
  needs a boss that answers the player (its telegraph and weak spot, which need the headliner's own behaviour,
  #181), not another number.
- **The stampede is a mild spike** (x0.9 solo average now: the rounds around it are harder with finite
  ammunition): it was brought up from 120% of a round to 140% at 1.8
  times the spawn rate, which kills 14% of average solo nights, under the gate's 40%; at 170% and 2.2
  times it killed 81% of them. Strong players pass it untouched: runners are fragile and they see them coming at
  range.

## Balance targets

`BalanceTargets` holds these ranges and the GdUnit4 suite `test_balance_targets.gd` runs 60 nights of five
cells (seed 4000, the same on every machine) and fails, naming the number, if a tuning change leaves one:

| Target | Range |
| --- | --- |
| Median round, average solo (the design target) | 10 to 14 |
| Median round, average 2 / 4 players | 11 to 16 / 12 to 17 |
| Median round, weak solo / strong solo | 4 to 9 / 12 to 18 |
| Average solo nights that clear round 4 | at least 85% |
| A special round up to round 10 kills (average players) | at most 40% of the nights that reach it |
| The first boss night against its neighbours (average solo) | at least x1.5 |
| The first boss night kills weak solo players | at most 85% |
| Time to kill, average solo, seconds: walker / runner / brute / headliner | 0.5 to 3 / 0.2 to 2 / 3 to 12 / 8 to 30 |
| Points spent over points earned, average solo | 20% to 90% |
| Points spent on ammunition over points earned, average solo | 8% to 35% |
| Rounds in which an average solo player runs out of every firearm | at most 10% |

The suite also checks that better and more players always go further, that a night repeats exactly for its
seed, and that the gate itself fails on a tuning that is far too hard or far too easy, or whose ammunition nobody can
pay for. A change to a range
is a change to this table in the same pull request. To try a number: `tools/balance/run_report.py --set
rounds.health_growth=1.06` (see the research page).

## A 5 s break (#382)

The maintainer shortened the break from 20 s to 5 s (`RoundTuning.break_seconds`; the intro stays 12 s and a special
round's break is 10 s longer, so 15 s). The balance report was run again with the same seed and 300 nights per cell,
with the old break and the new one (`--set rounds.break_seconds=20` is the old):

| Cell (skill, players) | Median round, 20 s break | Median round, 5 s break | Mean round |
| --- | ---: | ---: | ---: |
| weak, 1 | 5 | 5 | 4.9 / 4.9 |
| average, 1 | 10 | 10 | 9.7 / 9.7 |
| average, 2 | 11 | 11 | 11.6 / 11.4 |
| average, 4 | 13 | 13 | 13.0 / 12.7 |
| strong, 1 | 12 | 12 | 12.0 / 12.0 |
| weak, 2 / 4 | 7 / 7 | 7 / 5 | 6.6 / 7.2 and 6.3 / 6.5 |

The gate's five cells hold their medians and every range of the table above; the group play of weak players loses a
little (a break is the time to spend points and mend), the most in the four-player weak cell (a median of 5 where it
was 7, mean 7.2 to 6.5), which no target covers. Points earned barely move for solo players and fall about 7% in a
four-player average night (15,038 to 14,098). Nothing was retuned.

## The re-cut and the faster health climb (#281)

Zombie health now compounds at 7% a round after round 8 (it was 5%), because a player can pay to re-cut a weapon for
x1.75 damage and hearty adds 50 health. The modelled players save for the re-cut after the wall weapons, the doors
and the crane, re-cut the weapon that kills most, and buy the tonic ([upgrades](upgrades.md); the sweep is in
[Weapon upgrades](../research/weapon-upgrade.md)). The report for 300 nights a cell (seed 1) moved the medians
from 5 / 10 / 11 / 13 / 12 (weak solo, average 1, 2 and 4 players, strong solo) to 5 / 14 / 15 / 16 / 17: inside the
gate's ranges, which are unchanged, with the end of an average night moving from the stampede and the rounds after
it to the second boss night at round 15. The gate itself, with the same shopping and a re-cut that changes nothing,
fails at 7% (a test).

## Retune after the speed rework and the crane (#265)

The speed rework (#260, faster dead in the dark) and #271 (the crane at 550 points) turned the gate red: an average
solo median of 9 and
the weak boss night at 94% deaths. The retune is the shop weapons of #254 (rifle 95 damage, 0.5 s; shotgun 19 a pellet,
0.8 s) with the simulator choosing weapons by what they kill, not by damage a second ([round
scaling](../research/round-scaling.md)).
The ranges and the health, count and spawn curves are unchanged.

## Open questions

- **Points glut after round 12 or so.** Once the doors, weapons and tonics are bought, fuel and rounds absorb
  points (a fifth of an average night's earnings goes on rounds); the re-cut and the hearty tonic
  ([upgrades](upgrades.md)) are the first sinks that also make the player stronger, and the modelled average player
  now spends 47% of what it earns (it was 62%) because the nights are longer.
- **The weapon limit** (two or three weapons) is still open: the weapons and their numbers are in
  [Weapons](weapons.md) (shots to kill per round are tabled there).
- **The shop's weapons are barely better than the pistol.** Sustained, reloads included, the pistol does about 59
  damage a second, the shotgun 68, the rifle 85, the SMG 101 (the flare gun hurts no one since #439). With health
  that compounds against weapons that do not grow, this is why the health curve had to come down (#188). The
  shop now sells them (#152) and the simulator can say what each is worth, so the question has numbers.
  Average solo players with 20,000 points (so price is no object and only the weapon counts), buying nothing but
  the weapon and its rounds, 300 nights each:

  | Weapon bought | Median round | Reach round 10 | Strong solo: median, reach round 12 |
  | --- | ---: | ---: | --- |
  | none (the revolver) | 8 | 2% | 10, 6% |
  | shotgun, as shipped | 8 | 6% | 10, 7% |
  | rifle, as shipped | 9 | 29% | 10, 37% |
  | shotgun and rifle, as shipped | 9 | 29% | 10, 37% |
  | **proposed** shotgun | 9 | 26% | 10, 1% |
  | **proposed** rifle | 10 | 62% | 13, 63% |
  | both proposed | 10 | 58% | 10, 17% |

  The shotgun at 900 points is no step up at all (it is 14% better than the revolver at point blank, 98 a second
  against 86 before reloads, and worse beyond 5 m), the rifle at 1,200 is worth a round. The finite ammunition does
  not change that, it only adds a price to every shot. Applied in #265 (see
  [round scaling](../research/round-scaling.md)), after the simulator's weapon choice learnt about overkill: **the
  rifle** to 95 damage
  (a round-5 zombie falls to one body shot, a round-10 one to two), a shot every 0.5 s, and a reserve of 40 to 80
  (was 70, 0.55 s, 32 to 64); **the shotgun** to 19 a pellet, a shot every 0.8 s, full damage out to 8 m and sliding
  to 35% at 22 m, a reserve of 30 to 60 (was 11, 0.9 s, 5 m, 18 m and 25%, 24 to 48). With both, the average solo
  player buying one reaches round 10 in about six nights in ten against two in a hundred with the revolver, and a
  strong one gains three rounds from the rifle. Ammunition prices follow the weapon's damage per round (about 0.1
  point of ammunition per point of damage) and would not change. Applying it moves the weapon table, the shots to
  kill and the gate's cells, so it is a decision for the maintainer with the weapon work, and the health curve could
  climb again behind it. `tools/balance/run_report.py` and `balance_cli.gd --shopping=...` reproduce the table (see
  the research page).
- **Downed players and revives**: the revive is built ([Revives](#revives)); a downed player now bleeds out after
  `ReviveTuning.bleed_out_seconds` and is dead until the round ends ([Revive](revive.md)). The exact penalty at a
  round's end (a tenth of the points) is still for the player work to settle; the maintainer's decisions on solo
  self-revive, a revive perk and points for a revive are made ([the list](revive.md#decided-2026-11-02-505)).
