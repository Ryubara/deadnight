# The dead's script cost at the late rounds

What the dead's own script costs a tick at round 12, 3x, four players and about 99 dead, what was cut for it
(issue #947, from the #906 performance sweep), and what was left alone and why. The rest of the night's script at that
crowd belongs to other issues: the client's decode (#930), the server's crowd lists (#931), the separation pass (#933),
and the engine's own cost of the crowd (#949).

## What runs, how often, and what it scales with

`ZombieSim._step` runs at 30 Hz (the server ticks at 60, so every second tick) and calls `_think` for every dead that is
not dying and not held. It scales with the **dead standing**; the players multiply only the retarget (a distance each,
every `retarget_interval`). Each bot runs `BotPerception.observe` on every tick; it scales with the dead in the frame
(once, to find its contacts) and the contacts it holds.

Counts of a real night (headless, 3 bots, round 12, 3x, desktop ceiling, 60 samples): 97 dead standing, of which 42 to
60 % swinging at a player, the rest walking; **19 % are farther than 20 m from every player, 10 % farther than 30 m and
5 % farther than 40 m**.

## Where the time went

The labelled medians of the sweep (`sim.think` 1.2 to 1.3 ms a tick at 99 dead, `sim.path` 0.5 ms of it) are the
repaths' nav queries plus about 8 to 9 us of script a dead a step. Per call, in a quiet loop (ns, noisy): the brain's
step 2,300 to 2,900, the ground settle 1,600 to 2,200, the waypoint 700 to 800, the retarget 500 to 600, the swing test
250, the ground speed 300. The rest was calls and made values that a dead did not need that step.

## What was cut (the dead are the same, step by step)

| Where | Was, for every dead every step | Now |
| --- | --- | --- |
| `_think` | `_lure_for` called with no lure burning | a test of the list first |
| `_think`, `_retarget` | `targets.has` asked twice | `_retarget` answers whether it has a target |
| `_think`, `_repath` | a call that subtracted a timer and mostly returned | the timer in `_think`, the call when it ran out |
| `_think`, `_watch_strand` | `gates.get` and a distance before the cheap `path_gap` test | `path_gap` first; the call only when it can be stranded |
| `_think` | `_can_swing` (and on the second map a sight ray) for a dead rising, staggered or with no target | asked for a dead that walks or swings |
| `_think` | `_ground_speed` for a dead that does not walk | asked for a dead that walks |
| `_waypoint` | four property reads a loop | read once |
| `_settle_on_ground` | the pathing's `ground_offset()` asked each time; a write of the height that did not change; the segment's geometry on a flat segment | asked once for a pathing; written only on a change; a flat segment is its own height |
| `ZombieBrain` | a new `{}` for the answer of each step | one shared `NO_STRIKE` |
| `BotPerception.observe` | a by-id dictionary of the whole frame (99 inserts) for a handful of contacts | only the zombies the bot holds a contact on (99 lookups, a few inserts); no `filter` of an empty blow list |

None changes a number the dead compute: the arithmetic on vectors stays the same (a float32 `Vector2` length is not
swapped for a double `sqrt`, which would move a position by a bit), the order of the checks only moves pure ones first.

## Not cut: thinking less often for the dead far away

The issue named it: a dead 30 m from every player could think every third step, as the animation throttle does. It was
not done. It moves where the dead are and when (a step of three times the length walks past a waypoint, tears a board a
step late, separates from its neighbours on another schedule), so the dead would no longer be the dead of the golden and
parity tests; and the counts above show how little it would take: 10 % of the dead are past 30 m, so a third of the
rate saves a fifth of a tenth of `sim.think`, about 0.05 ms. A decision for the maintainer if the crowd or the ceiling
grows: the counts to look at are `far30` and `far40` of the probe.

## Numbers

All with the same scripted night fed to both versions, 99 dead, 600 steps, four repeats; headless; the machine had 21
Godot processes up.

**The sim, old code beside the new in one process** (the old `ZombieSim` and `ZombieBrain` copied under other names,
which of the two goes first alternating every step, median of the per-step `sim.think`; the state of every dead
compared after every step: identical in all repeats):

| Map | `sim.think` old (us) | new (us) | new / old |
| --- | ---: | ---: | ---: |
| the lot (flat), a bent path over a floor | 1,075 to 1,144 | 922 to 966 | 0.85 |
| two storeys, with the sight | 1,122 to 1,207 | 953 to 1,004 | 0.85 |
| straight path, no floor | 936 to 955 | 770 to 792 | 0.82 |

**The real night** (round 12, 3x, 3 bots, desktop ceiling, `zz` probe of the review, seed 1, 100 s; base and branch
started together; the second pair played the same crowd in both arms, 77.6 standing, 3,600 ticks): `sim.think` 1,269 /
1,233 us a tick (`sim.path` 498 / 504 of it, so the dead's own script 771 / 728, -6 %), `tick.bot` 365 / 337, the rest
unchanged. The first pair played different crowds in the two arms (the nights are not reproducible between runs) and read
-8 % on the same label.

**The bots' filter**: dictionary entries made by one `observe` with a contact held, 99 before, as many as there are
contacts in the frame now (a handful to 23); the beliefs are identical on every tick of 4,000 (`bot_ab`), and
`tick.bot` fell 8 %, within the noise of the machine.

The dead's script is still the larger part of the server's tick. The budget of 6 ms for the night's script at 99 dead
(the sweep's table) is **not met by this change alone**: it takes `sim.think` from about 1.25 to 1.17 ms of the 5 to 7
ms of the server's tick; the other shares are #930, #931 and #933.

## How to measure it again

`game/tools/bench/think_cost.gd` (`gds godot -- --headless --path game -s res://tools/bench/think_cost.gd`): the median
of `sim.think`, the step and the counts of the dead thinking and swinging. Copy it to another checkout to compare two
commits, and run both together. For a change under 20 %, copy the old script under another class name and time both in
one process ([Performance budgets](https://github.com/Ryubara/gdstudio/blob/main/docs/godot/performance-budgets.md)
in the kit docs); two processes on this machine moved by more than the cut.

`test_zombie_think_cost.gd` keeps the proof: a digest of a scripted night of 60 dead (a gate with boards, a lure, a
freeze and a chill, a blast, deaths, a cripple; on the lot and on two storeys) taken on the code before the cuts. It
changes only if the dead change.
