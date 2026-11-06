# Performance: the worst night, its costs, its leaks, its budgets and limits (#906)

A maintainer playing round 12 at 3x with three bots on a desktop, in the editor, said the game lags, that nobody knew
its limits, and that "we're just not cleaning up objects properly" might be why. This page is what was measured, what
was found and what is held in CI now. The method that applies to every game is the kit's
[Performance budgets](https://github.com/Ryubara/gdstudio/blob/main/docs/godot/performance-budgets.md); the web and
phone work before this is [phone-frames.md](phone-frames.md), [web-heap.md](web-heap.md) and
[crowd-budget.md](crowd-budget.md).

## The answer in short

- **What the game costs.** At round 12, 3x, four players, a crowd of 99 on the desktop's ceiling, a frame is **about
  12 to 23
  ms** on this machine (RTX 5080, 16 logical cores), of which **9 to 12 ms is the night's script** (the server's tick,
  the clients' apply, the bots, the views) and the rest the engine drawing and animating the crowd. A dead costs about
  **0.1 ms of script and 0.05 ms of engine**: the frame runs from 6 ms with none to 20 ms with 100.
- **The maintainer's own settings stand 40, not 99.** A hosted bot counts as a browser in the crowd's ceiling
  (`NightServer._join` passes `local` false for it), so any night with a bot in it stands the web's 40 dead on a
  desktop,
  at **10 to 13 ms a frame** here. The 99 (up to 120) that the design allows is reached only with no bot in the room.
  That is filed, not changed, because it moves the game's difficulty (issue below).
- **Background load is most of what a wall clock here measures, and probably a large part of the lag reported.** This
  machine ran at 88 to 100 % CPU with 20 to 46 Godot processes up during every measurement. The same code in the same
  arm took **8 ms and 115 ms a frame** at 45 dead in two runs an hour apart (14 times); headless runs took 16 to 237 ms
  a frame against 17 to 24 windowed. At the maintainer's settings (40 dead) the game costs about 7 to 9 ms of script
  and 10 to 13 ms a frame under that load. I cannot measure the maintainer's machine: on one like this one the game
  itself does not lag at his settings, and a weaker machine, or the editor, can. The editor runs a debug build
  (the pinned Godot here is one too, so these numbers are the editor's scripts) with a debugger link, and its Remote
  scene tree walks all 5 000 to 5 300 nodes of the running game each time it refreshes (the same walk in script cost
  8 to 10 ms here); closing that tab or playing an exported build is the first thing to try.
- **No leak of objects found.** Over 25 and 30-minute nights nodes, objects and resources grow with the round and the
  crowd and then follow it down and up; orphans stay at 0 or 1; the bodies of the dead are pooled (12 a look) and the
  pool is the whole of the growth in skeletons. Static memory still creeps 0.7 MB a minute in the 1x night after
  minute 12
  (0.15 of it the profile's own rows); it is not explained and the nightly soak watches it. What did grow without
  bound was the profile's own bookkeeping, first.
- **The two biggest cheap costs are already issues in flight** ([#930](https://github.com/Ryubara/deadnight/issues/930),
  [#931](https://github.com/Ryubara/deadnight/issues/931), from the review of #907): the zombie list is decoded five
  times
  a tick and the target list built twice. This sweep measured what they are worth with a throwaway version of each (not
  shipped here, so the two pull requests do not collide): decodes **5.0 a tick down to 0.55**, the clients' apply 2.9 ms
  down to 1.8 to 2.3, the grenades' second list **0.82 ms down to 0.30**: about 1 ms of a 10 ms tick.
- **A budget is held in CI** (counts tight, work counted, time as a ratio; below).

## How it was measured

The real night, not a bare crowd: `AutopilotRun` (`game/tools/bench/autopilot_run.gd`, started with
`-- --autopilot ...`) plays the shipped rules with a player who cannot die, the shipped lot, HUD, lights, sounds and
bots, and `PerfSampler` (`perf_sampler.gd`) writes a row a second: the engine's monitors (frame, process, physics and
navigation time, draw calls, primitives, objects, nodes, orphans, resources, static and texture memory, bodies), what
stands in the tree (lights, particles, decals, sounds playing, skeletons, mesh instances, canvas items), every
`PerfProbe` label's time in milliseconds a frame (mean and median) and its counts, and a calibration (a fixed loop of
GDScript timed in the same process, every 5 s). New arguments: `bots=N`, `startround=R` (every player given
`points`), `ceiling=desktop`, `sample=1`, `frames=0`, `labels=0`.

```text
gds godot -- --path game -- --autopilot --rounds=12 --startround=12 --hold=70 --seconds=110 --count=3 --bots=3 \
    --ceiling=desktop --sample=1 --out=<report.json>                       # windowed
godot --headless --path game --fixed-fps 60 -- --autopilot ... --sample=1  # headless, a frame is a tick
```

**Every timing here was taken on a loaded machine**, so each is a repeat of three, and what carries weight is what does
not move with the load: counts (nodes, objects, draw calls), counts of work (decodes a tick), the labelled medians of a
run (a frame the machine took the processor from does not move a median), and the process's CPU seconds a frame
(polled from outside). Machine CPU, GPU and Godot process counts were recorded beside each run and are in the notes of
the pull request. The wall times are real and are the numbers a player on a busy machine gets; they are not what the
game costs.

## The worst case, system by system

Round 12, 3x, four players (the autopilot and three bots with 20 000 points each), the desktop's ceiling (cap 99),
windowed on a GPU, steady state (90 % of the cap standing), three runs of 40 s:

| What | Frame median (ms) | Notes |
| --- | --- | --- |
| Everything, 99 dead | 19.5, 22.8, 20.1 | p95 29 to 36; 400 draw calls; 5 300 nodes; 18 700 objects |
| HUD hidden (`ui=0`) | 17.1, 18.6 | 125 fewer draw calls (400 to 270): the HUD is about **1.5 to 3 ms** |
| Every light hidden (`lights=0`) | 18.4, 20.0 | **no difference**: 57 lights cost nothing measurable on this GPU |
| The maintainer's settings (cap 40, bots count as browsers) | 12.7, 10.0 | 44 dead, 435 draw calls |

The script, from the labels (mean of the three windowed runs, ms a frame, nested labels are inside their parent):

| System | ms | Of it |
| --- | --- | --- |
| The server's tick (`tick.server`) | 6.3 | the dead's AI `sim.think` 1.4, paths 0.6, separation 0.4 (`server.zombies` 1.8 in all); the frame and its pings, boards 2.0 (0.9 of it the grenades' second target list); the combat's target list 0.8; the players 0.7; shots 0.4; the commands 0.4 |
| The clients' apply (`tick.pump`) | 3.6 | `event.frame` 3.0: the zombie list decoded five times, then the horde's views 0.8, voices 0.8, animation throttle 0.5 |
| The bots (`tick.bots` + `tick.bot`) | 1.9 | three bots thinking and walking in a crowd |
| The HUD (`hud.*`) | 0.2 | the labelled script; the rest of its 1.5 to 3 ms is drawing |
| Sound (`audio.*`, `snd.*`) | 0.1 | pooled voices, at most 2 starts a frame |
| Particles, decals | 0 | the effects are pooled shader quads (blood 16 drops, impacts 24); the only emitters are the machines' one-shot sparks and fizz, which run when someone uses the machine (the soak's person re-cuts in the late-round run, #1011) |
| The engine's own (skinning 135 skeletons, drawing, physics server, audio mix) | about 8 | what is left of a 20 ms frame |

Network: a snapshot of 120 dead is 561 bytes for each of four players at 60 Hz ([crowd-budget.md](crowd-budget.md)); the
loopback link here serializes every event; a room's cost is in that page, not repeated.

![Frame against the crowd, three runs](performance-crowd-cost.png)

A dead costs about 0.13 ms of frame: 0.1 of script (1.7 ms at under 10 dead, 11.8 at 99) and the rest in the engine, so
doubling the crowd roughly doubles the frame's variable part.

## Leaks

Two 30-minute-class nights of four players (the autopilot, who cannot die, and three bots), headless at a fixed step,
`PerfSampler` every second with per-frame rows and labelled times off: **1x** (round 1 to 19, 30 minutes, up to 42
dead) and **3x with the desktop's crowd** (round 1 to 12, 25 minutes, up to 106 dead). Values at the end of each window.

| Game minute | Round | Dead (mean, max) | Nodes | Objects | Resources | Orphans (max) | Static MB | Skeletons |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **1x** 3 | 4 | 7.0, 23 | 4 762 | 13 324 | 1 803 | 1 | 211 | 36 |
| 12 | 10 | 10.9, 29 | 5 152 | 15 316 | 2 197 | 0 | 234 | 62 |
| 21 | 15 | 13.1, 28 | 5 195 | 15 667 | 2 294 | 1 | 239 | 64 |
| 30 | 19 | 28.3, 42 | 5 311 | 16 320 | 2 324 | 0 | 247 | 76 |
| **3x** 5 | 4 | 24.5, 60 | 5 358 | 15 539 | 1 975 | 1 | 227 | 64 |
| 12.5 | 9 | 41.1, 96 | 5 963 | 18 366 | 2 223 | 0 | 253 | 113 |
| 20 | 10 | 30.9, 94 | 6 001 | 18 360 | 2 261 | 0 | 254 | 117 |
| 25 | 12 | 48.4, 106 | 5 979 | 18 287 | 2 279 | 0 | 257 | 112 |

![Counts and memory over the two nights](performance-leaks.png)

- **No leak of nodes, objects or resources.** All three rise in the first 10 to 12 minutes (the first use of each sound,
  material, effect and look; the pools of the dead's bodies filling, 12 a look) and then follow the crowd: in the 3x
  night they fall when the crowd thins (5 963 to 5 892 nodes, 18 366 to 17 896 objects) and are at 5 979 and 18 287
  at 106
  dead eight minutes later. Resources add about 2 a minute after minute 12 (2 223 to 2 279 in 13 minutes at 3x; 2 197 to
  2 324 in 18 at 1x). Orphans: 0 at almost every second, 1 for a moment (a node between `remove_child` and its free),
  never 2.
- **Skeletons grow 24 to 76 (1x) and 135 (3x)** because bodies are parked for reuse, not freed: the pool is the whole
  growth, and the 3x night at 100 dead holds 113 to 135.
- **Memory is not flat in the 1x night:** 181 MB at the start, 234 at minute 12, 247 at minute 30, 0.7 MB a minute from
  minute 12, of which the sampler's own rows are about 0.15. The rest rises with the crowd and the round (the 3x
  night, with
  more than twice the crowd, held 251 to 257 MB from minute 12.5 to 25) and is not explained; it is 40 MB an hour at
  most,
  and the nightly soak below reads it each night. The first measurement of this sweep read 1 MB a minute and was the
  soak's own
  per-frame rows (108 000 `[ms, round, dead]` arrays) and a sampler row of 150 entries a second: the harness is the
  first
  suspect of a leak that appears only in a long run
  (the kit's lesson `a-long-soaks-memory-growth-was-the-soaks-own-rows`).
- **Rounds that do not end:** one soak left the last dead of round 16 standing for 7 minutes
  ([#950](https://github.com/Ryubara/deadnight/issues/950));
  the other run did not.

### The two red leak nights of 2026-11-04 and 2026-11-05 (#1319)

`bots-nightly`'s `leak` job failed twice, for two different limits, and neither was a leak.

| Night (30 minutes, 1x, CI) | Code | Resources at start | Resources peak | Rise to the peak | Resources a minute | Memory a minute | Failed on |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| 2026-11-04 | `935e84fe` | 1 410 | 2 380 | 970 | 14.4 | **1.8** (limit 1.5) | memory growth |
| 2026-11-05 | `61a990df` | 1 582 | **2 576** (limit 2 500) | 994 | 10.0 | 0.9 | resources peak |
| 2026-11-06 (a dispatch on `main`) | `d15d770f` | 1 602 | **2 569** | 967 | 14.6 | 1.0 | resources peak |

- **The peak rose because the start rose, not the night.** The resources a headless run holds at its first second:
  1 414 at `935e84fe`, 1 586 at `61a990df` (the same two commits, run here), 1 601 on today's `main`. Between the two
  commits the cache holds 94 more files by path (85 of them GDScript: 37 in `gameplay`, 34 in `ui`, 12 in `net`, 2 in
  `core`, the XP, levels, profile, challenges, popups and wardrobe) and 86 more unnamed resources they make. The
  start moved in steps (sampled at fourteen commits, 1 to 37 a step: `bea7a89b` 1 411, `40365bce` 1 434,
  `b504d699` 1 464, `d75d1c2a` 1 502,
  `e2f2e8f2` 1 546, `9455fecd` 1 568, `eb4c9cd8` 1 580), none of them a leak and none a fault: each is a feature. The
  rise from the start to the peak did not move (970, 994, 967).
- **What the rise is: the sounds a night plays.** A dump of the resource cache by path (`ResourceLoader.has_cached` over
  every file, at 1 s, 30 s, 6, 12, 25 and 30 minutes) shows the Ogg streams going from 14 to 74, 265, 349, 396 and 401
  of the 840 in `assets/audio`; the other paths grow by only 10 in all (734 by path at 1 s, 1 131 at
  30 minutes). A new sound costs 2.0 to 2.8 resources (the stream and its packet sequence) and about 0.2 MB of static
  memory (resources against sounds: 1 779 / 74, 2 262 / 265, 2 496 / 349, 2 588 / 396). Of the 14 MB of memory the
  steady window rises by, about 11 are the 52 sounds first heard in it. A later round plays new sounds more slowly:
  60, 191, 84, 47 and then 5 new streams in the successive windows.
- **It is flat.** One 60-minute night on `main` (local, same command, 3 599 rows, round 24): resources a minute 15.6 in
  minutes 12 to 30, **3.3** in 30 to 45 and **0.0** in 45 to 60, peak 2 638, reached by minute 48 and held; memory
  1.75, 1.03 and 0.61 MB a minute, peak 287.5 MB; nodes 28, 3 and 1 a minute. The 60-minute night passes the new
  budget.
- **The limits.** Resources 2 500 became **2 750**: the most any night read is 2 593 in 30 minutes (2 638 at 60), so
  it is 6% over the 30-minute peak and 4% over the 60-minute plateau, where the old limit was 7.6% over its one
  measure; a feature that adds scripts spends that room and, as with the node limit above, frees some first or shows
  what its number is. Memory growth 1.5 became **2.5** MB a minute: the three CI nights read 1.8, 0.9 and 1.0 and the
  local ones 1.7 to 2.4, all of it the first hearing of sounds as above; the peak limit (300 MB, 266 on CI, 287.5
  after 60 minutes) is unchanged. Nodes (40 a minute) and objects (200) are unchanged and do not fail on CI (22, 11 and
  2 a minute; 48 to 138 for objects), though a local night read 37 to 64 nodes a minute when its last window was
  a large crowd: the window is the crowd's, so read nodes' growth against the round before calling it a leak.
- **The night itself changed.** The dispatch on `main` reached round 13 in the 30 minutes (169 kills) against round 17
  to 18 (268 to 270 kills) on 2026-11-04 and 2026-11-05, with a peak of 2 569 all the same. Whether #1023 (the
  weapon numbers) or #1292 (the automatic reload) slows the autopilot's night was not looked at; it is not a leak
  and it is where a reader of the next red `leak` job should look first.

## What the two biggest cheap costs are worth

[#930](https://github.com/Ryubara/deadnight/issues/930) (one decode of a tick's zombie list for every client) and
[#931](https://github.com/Ryubara/deadnight/issues/931) (one list of targets, not two) were found by the review of
issue 907
at the same time as this profile, and other agents own them. To put numbers on them, a throwaway version of each was
measured here and **not shipped in this pull request**: `ZombieCodec.decode` memoized for the newest bytes, and the
grenades given the combat's list less the dead that fell since. Arms ran interleaved (before, after, before, after)
three
times each at round 12, 3x, four players, 99 dead, so a busy hour falls on both.

| | Before | After (throwaway) | What it is |
| --- | --- | --- | --- |
| Zombie list decoded a tick | **5.0** | **0.55** | counted, identical on any machine (the sim steps at 30 Hz, so half the ticks repeat the bytes) |
| Target lists built a tick | **2.0** | **1.0** | counted |
| `event.frame`, the clients' apply (ms a tick, headless, fixed step) | 2.87, 2.84, 2.68 | 2.29, 2.32, 1.78 | labelled median of each run |
| `server.grenades` (ms a tick, headless) | 0.82, 0.82, 0.83 | 0.31, 0.31, 0.29 | labelled median |
| `tick.pump` (ms a tick, headless) | 3.34, 3.32, 3.06 | 2.77, 2.76, 2.12 | labelled median |
| The night's script (ms a tick, windowed) | 11.2, 7.5, 8.7 | 7.9, 5.2, 5.7 | labelled median; the three runs drifted with the load |
| Frame median (ms, windowed) | 22.6, 15.6, 16.1 | 17.5, 11.9, 14.6 | wall time on a loaded machine: direction, not size |
| CPU a frame (ms, the process's CPU seconds over its frames, windowed) | 19.9, 14.1, 15.4 | 14.6, 10.6, 13.2 | polled from outside; less affected by waiting for a core |

![Before and after](performance-before-after.png)

- The clients' apply and the grenades' list are the part that is certain: counts and labelled medians moved the same
  way in
  every run. Together they are 0.6 to 1.0 plus 0.5 ms a tick, about a tenth of the night's script.
- The wall-time rows drifted with the machine's load more than the fix is worth; do not read their size.
- Nothing else in the sweep was changed in the game: the rest of the costs are the issues listed at the end of the page,
  each with the numbers.
- The sampler and the labels this needed are in the pull request (`PerfSampler`, `view.animation`, the autopilot
  arguments); the counters for the work (`PerfProbe.count(&"codec.decoded")` in the decode, `&"server.target_lists"` in
  `_target_list`) belong to #930 and #931: add them with the fix, and `budget.json`'s `max_per_tick` holds them.

## Budgets and limits

Numbers are this dead's worst case on the dev machine (frames on a loaded machine; script and counts from the
labels and the monitors). **Limit** is what CI holds (`tools/perf/budget.json`); **Budget** is what the system should
cost,
and where the two differ the system is over its budget and the issue named is the work.

| System | Desktop budget | Now (99 dead) | Phone (browser, [phone-frames.md](phone-frames.md)) |
| --- | --- | --- | --- |
| Frame | 16.7 ms (60 fps) | 12 to 23 ms here; 10 to 13 ms at 44 dead | 33 ms on a phone; the x4 CPU stand-in took 21 ms with 0 to 9 dead and 88 ms with 40 |
| Dead alive | 120 (99 at round 12, 4 players, 3x) | 99; **40 with any bot** ([#946](https://github.com/Ryubara/deadnight/issues/946)) | 40 |
| The server's tick | 4 ms | 5.2 to 6.3 ms | not measured apart |
| The clients' apply (decode, views, voices, animation) | 2.5 ms | 3.6 | 47 ms of script at x4 |
| Bots (three) | 1.5 ms | 1.9 ms | the same code |
| HUD | 1 ms, 100 draw calls | 1.5 to 3 ms, 125 draw calls ([#948](https://github.com/Ryubara/deadnight/issues/948)) | the touch layer is redrawn only on change |
| Engine: skinning, drawing, physics server, audio mix | 6 ms | about 8 ms ([#949](https://github.com/Ryubara/deadnight/issues/949)) | fill-bound: pixel ratio capped at 2, no MSAA |
| Draw calls | 500 | 400 | 490 batched (770 before) |
| Nodes / objects / resources | 6 400 / 19 500 / 2 100 (limit) | 5 771 / 17 525 / 1 833 | 3 500 / 12 500 / 2 300 |
| Orphan nodes | 0 (limit 2) | 0 | 0 |
| Static memory | 290 MB (limit) | 240 MB | the page's heap: 3.9 MB a minute ([web-heap.md](web-heap.md)) |
| Lights shining | 64 (limit; 8 a mesh is the engine's) | 57 | 30 on the lot |
| Particles, decals | 3 particle systems emitting at once (the Re-Cut's sparks, the soda fountain's fizz, the crane's sparks, one-shot, under a second each), 0 decals | 0 to 1 | 0 |
| Sounds | 32 positional, 12 plain, 6 beds | 22 to 25 playing | the same, 2 starts a frame |
| Physics bodies | 6 | 4 (the players; the dead are not bodies) | 4 |
| Skeletons (bodies parked included) | 150 (limit) | 135 | 40 on screen at most |
| Zombie list work a tick | 1 decode, 1 target list | 5 decodes, 2 lists ([#930](https://github.com/Ryubara/deadnight/issues/930), [#931](https://github.com/Ryubara/deadnight/issues/931)) | the same |

A limit is a number a game can say "no" with, so each one has what it does past it in the section below. The phone
column is read from earlier pages; this sweep did not run a phone.

## The CI check

`tools/perf/check_budget.py` reads the report of the worst-case run and `tools/perf/budget.json`; the `godot` job's
first
shard runs it (about 1.5 minutes) and writes what it measured into the job summary. It fails on:

- **a count over its limit** while the crowd stands (nodes, objects, resources, orphans, static memory, bodies, lights,
  particles, decals, sounds playing, skeletons, mesh instances, canvas items, collision pairs);
- **the frame over a multiple of the calibration** (limit 15; 3.0 measured in a quiet minute here, 7 to 26 on a
  loaded machine): a catcher of a large regression
  that holds on a slow runner and a busy machine; it is deliberately loose until three runs of the real runner's
  summary say where it should sit;
- **a labelled section over its share of the frame** (`server.xp`, `server.challenges`): see the next section.

### What the label limits mean

`server.challenges` and `server.xp` are `PerfProbe` sections of a few microseconds a frame (the median of the steady
rows is 0.03 to 0.05 ms and 0.005 to 0.01 ms, against a frame of 8 to 16 ms). Their limit is a **share of the frame**:
the median over the steady rows of the section's mean milliseconds a frame, over the median of the rows' `frame_ms`
(the mean wall time of a frame). Read it as "this much of a tick goes to the section", and a limit of 0.0045 as "the
challenge tracker may cost 0.45 % of a frame on the runner it runs on". The limits sit above the highest share the
runners gave and below twice the lowest, so a section twice as slow fails on every runner measured and an unchanged one
passes on every one:

| | Share of the frame, 46 runs of `godot (1)` | Limit | A section twice as slow, lowest of the 46 |
| --- | --- | --- | --- |
| `server.challenges` | 0.00270 to 0.00368 (median 0.0030) | 0.0045 | 0.0054 |
| `server.xp` | 0.00047 to 0.00074 (median 0.0006) | 0.00085 | 0.00094 |

**Why not the calibration (the first rule, #1129 and #1114).** The limit was a multiple of the calibration (a fixed
loop of arithmetic of 3 ms, best of five), 0.012 for the challenges and 0.01 for the XP award. Over the 46 runs of
`godot (1)` that came after the tracker's last change (2026-11-05, 07:40 to 12:10 UTC, 46 different commits, no commit
ran twice) the ratio moved from 0.0057 to 0.0123 (a factor of 2.1), and failed two unrelated runs (0.0123 on a UI-only
pull request, 0.0120 on `main`):

- The runners come in three kinds, told apart by the calibration: about 3.1 ms (8 of the 46), 4.5 ms (16) and 6.0 ms
  (22). The section costs almost the same on all three (0.032, 0.039 and 0.041 ms), so a ratio of the calibration
  reads 0.0101, 0.0087 and 0.0068: the fastest kind of runner sat at 84 % of the limit with unchanged code. The
  calibration is a hot loop that a fast core runs twice as fast; a few microseconds of cold script do not speed up in
  step.
- Within a kind, a busy neighbour slows the frame and the section together (frames of 10.0 to 16.6 ms at about 4.5 ms of
    calibration) and the best-of-five calibration does not see it.
- Across the 46 runs the log of the section's time rose with the log of the frame with a slope of 0.98 (r 0.92) and
  with the log of the calibration with a slope of 0.35 (r 0.49): the calibration cancels a third of what the host does
  to this section, the frame cancels all of it. The spread of the ratio fell from 2.1 to 1.36 (challenges) and from
  2.3 to 1.57 (XP).
- The old limit could not both pass the fast kind and catch a slower section: the same 46 runs with the section made
  twice as slow failed the old rule 42 times (the four it missed were the slow-calibration runners), the new rule 46;
  at 1.5 times as slow 19 against 29. The XP award's old limit (0.01, seen at 0.0010 to 0.0026) failed none of the 46
  at twice the time: it needed about four times.

**Timer resolution and sample.** `Time.get_ticks_usec` counts microseconds, and a row used to round a mean to
0.001 ms: the challenges' median moves 0.3 % by that, the XP award's up to 7 % (0.0054 read as 0.0050), so rows now keep
0.0001 ms. A row is the mean of 60 frames; a single row can read five times the median (a preempted frame), so the
rule takes the median of the 78 to 81 steady rows, not their mean.
**Same commit, four local runs** (this machine, other work running): frames of 9.6 to 18.1 ms, the challenges' section
0.029 to 0.038 ms, its share 0.0021 to 0.0030, the old ratio 0.0083 to 0.0091. On a loaded desktop the frame slows more
than the section, so a local share reads low (a twice-as-slow section at 0.0042 would pass a 0.0045 limit); CI is
the gate and its runners read 0.0027 to 0.0037.

**Proof the limit still has teeth.** A throwaway change (not committed) made both sections wait for as long as they had
just taken, so each took twice as long, in the budget's own command: the challenges read 0.0057 of the frame (limit
0.0045) and the XP award 0.00098 (limit 0.00085), and `check_budget.py` exited 1 on both. The same command without
the change, on the same machine, read 0.0021 to 0.0030 and 0.00037 to 0.00056 and passed.
`tools/perf/test_check_budget.py` runs in CI before the budget and keeps the two facts for eight runners made from the
numbers above (the three kinds, a busy one, and the highest and lowest share of each section): unchanged passes, twice
as slow fails, for each section.

**What it does not do.** A section that takes a third of a runner's frame still passes if the frame slows with it, and a
frame that slows without the section lowers the share; the frame has its own limit (15 times the calibration), and
the counts (`challenge.advance` a tick) catch more work. The XP award's margin is the thinnest (the limit is 15 % above
the highest and 10 % below twice the lowest of the 46); if its rows at the finer resolution say it can be tighter, move
it with a run of the test.

Canvas items (limit 200) count every `CanvasItem` in the tree, so the HUD's nodes are counted as built, empty or not.
What only a bigger night needs is built when a night reaches it and freed on the way down: the bots' chip strip
(`HudBotChips`, two nodes) first sat in the points column at four bodies and took the peak from 215 to 217 here (229 to
232 on CI, main 229); `HudPoints` now makes it past eight bodies only. The HUD at four bodies is the same 164 canvas
items as on main (a probe over the fixture), and the budget's run peaks at 215 locally, as main does. A night of 15
bodies (8 people, 7 bots) holds 60 more HUD canvas items (224 against 164, boxes and chips only, before the scoreboard
or end board is up): 276 here and on CI, which the four-player case does not cover, so the worst room has a case of
its own (next section).

### The worst room's own case (#1193)

A night can now hold 8 people and 7 bots (15 bodies, `NightHost.MAX_SEATS`), with the desktop's crowd (the cap
reaches the ceiling of 120 with that many players). `tools/perf/budget_worst_room.json` holds that case, played by the
second step after the four-player one in the first shard: round 12, 3x, 85 s of night headless at a fixed step,
`--bots=7 --people=8` (`StandInPeople`: one process holds one client, so the other seven people sit as seats a client
would hold, with a bot's brain; they are people to the crowd's table, the looks and the HUD). It runs 137 s on the CI
runner (the four-player case 94 s: the crowd takes a minute to reach 90 percent of its cap, 33 steady rows on CI) and
its limits are the peaks of the first CI run and a local one with 5 to 35 percent over, not the four-player ones raised:

| Count | Four players (limit, CI peak) | 15 bodies (limit, CI peak) | Why it differs |
| --- | --- | --- | --- |
| `bodies` | 6, 4 | 15, 15 | one physics body a seat |
| `nodes` | 6,800, 5,812 | 7,500, 6,920 | the views of 11 more bodies and the HUD's 60 more canvas items |
| `skeletons` | 160, 136 | 200, 179 | 11 more soldiers (the dead's pool is the same) |
| `canvas_items` | 230, 230 | 300, 276 | the HUD's boxes and chips for 15 |
| `pairs` (collision pairs) | 50, 16 | 60, 45 (51 on a local run) | 15 bodies against the lot |
| `lights` | 68, 50 | 76, 70 | 20 more with the 11 more bodies (what they carry was not split further) |
| `xp.gained`, `challenge.advance` a tick | 0.12, 0.08 and 0.18, 0.12 | 0.35, 0.27 and 0.48, 0.38 | more players to award and follow |
| `mem_static_mb` | 300, 253 | 310, 280 | |
| frame / calibration | 15, 2.35 | 15, 4.87 | 15 bodies' scripts in the tick |
| `server.challenges` / calibration | 0.012, 0.0068 | 0.04, 0.0164 (0.027 on a local run) | the boards of 15 accounts |

The tick of the server, which is what the capacity decision rests on, is not in this case (CI has no Railway
container): it is in [the crowd budget](crowd-budget.md#rooms-of-fifteen-bodies-1193).

### Canvas items by part

`--canvasparts=1` on the budget's command (headless, `--xp=1`, as CI plays it) adds each part's item count to every row
(`canvas_parts`), and `python tools/perf/canvas_parts.py <report.json> [--markdown]` prints the steady rows' least and
most. Round 12, 3x, four players, the same 81 steady rows, local run (the CI runner reads 13 to 15 higher, 230 for
215 and 185 for 172: the CI peak is the number that counts):

| Part | Before | Now |
| --- | ---: | ---: |
| Hud/Points (four player boxes) | 46 | 46 |
| EndBoard | 21 | 1 |
| NightScreen touch layer | 12 | 12 |
| Hud/Ammo, Hud/Slots | 10, 10 | 10, 10 |
| Hud/Gains (a pool of rows) | 8 to 10 | 8 to 10 |
| Hud columns (nine containers) | 9 | 9 |
| Hud/Challenge | 9 | 1 |
| Hud/Fuel, Hud/Health, Hud/Prompt | 9, 9, 9 | 9, 9, 9 |
| Hud/Round | 8 | 8 |
| Hud/Scoreboard | 7 | 1 |
| Hud/Events (a pool of rows) | 3 to 6 | 3 to 6 |
| Hud/Marquee | 6 | 1 |
| Hud/Banner, Hud/Objective, Hud/BossBar | 5, 5, 5 | 5, 5, 1 |
| Hud/Notices, ControllerHint, MenuPopups | 3, 2, 2 | 3, 2, 2 |
| 14 parts of one item each | 14 | 14 |
| **Peak of the steady rows** | **215** | **172** |

What was freed is what the night builds and hides the whole of the budget's night: the end board, the challenge
prompt, the scoreboard, the marquee and the boss bar (43 items). Each makes its words the first time it is needed (the
end board's parts are properties whose getter builds; `HudTicket.body` makes its padding and box on first use), so a
test (`test_hud_idle_canvas_items.gd`) holds both ends. A popup card makes the next-unlock line, the thumbnail chip and
the poster and prizes only for the kind of card that shows them (4 to 5 items a card, not 16): a card is up for a few
seconds and each one in a steady second counts. Not touched, with the room each would give: the player boxes'
card, tab, frame, emblem, level icon and level (up to 4 of the 11 items of a box without a plate, #1199), the fuel
card (8, hidden until a fuel night), and the labels the gains and events pools hold.

**What the peak moves with.** On one commit the local run is the same every time (four runs, two of them at once on
a loaded machine, the same 81 rows). What moves is the transient part: the gains and event rows (a pool that grows to
its cap as a second has more events: 8 to 10 and 3 to 6 items) and the popup cards, whose number and kind follow the
night's events, so a runner whose float arithmetic or timing differs by a hair lands a different event in a steady
second (a guess: main read 229, 230, 230 and 229 on four commits that changed no UI, which no local run reproduces,
and this change read 185 on two commits). That is the spread, about 1 on the runner, and the limit is set above it
rather than on the peak.

**The limit.** 230 became **200**: the CI peak 185, the spread of 1 to 3, and about 12 kept for the planned night UI
that each took the old limit over by 1 to 4 (the plated boxes #1199, the phone keyboard #1200, the corner cards #1218
and the touch layer #1217). A pull request that adds items spends that room; one that needs more than is left frees
some first (`--canvasparts=1`, then the hidden parts above) and does not raise the number.

Teeth: the report of a run with the node limit set under the peak fails and names it (output in the pull request).
`max_per_tick` (a counted piece of work a tick, from `PerfProbe.count`) is built in for the fixes of #930 and #931 to
use.
The nightly job `leak` in `bots-nightly.yml` plays 30 minutes at 1x and holds `tools/perf/leak_budget.json`: after
the first
12 minutes nodes may grow 40 a minute, objects 200, resources 25 and static memory 2.5 MB (measured: 6, 34, 6 and
0.4; the memory limit was 1.5 until #1319), and
orphans stay at 2 or fewer. Peaks: nodes 6 500, objects 19 500, resources 2 750 (2 500 until #1319), memory 300 MB.

## What past a limit does

| Limit | What happens past it |
| --- | --- |
| Dead alive: 120 on a desktop with no browser in the match, 40 with one; the cap grows with round, players and the multiplier (99 at round 12, 4 players, 3x) | `ZombieDirector` admits a spawn only while fewer than the cap stand; the rest wait in its queue and still count for the round's end |
| Sounds: 32 positional voices, 12 plain, 6 beds; at most 2 starts a frame in a night | `VoiceBudget` steals the weakest voice of a group at its limit, drops a repeat inside its cooldown; `Audio.culled` counts the dropped |
| Impacts 24, blood 16 drops a hit (marks recycle), HUD gain rows 3 | the oldest slot is reused |
| Bodies of the dead: 12 parked a look | a view past 12 is freed |
| Animation: tiers 1, 3, 6, 12 frames by distance and view | the throttle advances a far or off-screen zombie less often with the time it missed |
| Lights: 8 a mesh (the Compatibility renderer's own), 57 on the lot | the lot is batched into cells that at most 6 lights reach (`LotBatcher`) |
| A web page: 40 dead, draw calls about 490 batched | the web ceiling; `PhoneRender` caps the pixel ratio at 2 and drops MSAA |

## Reproducing

```text
# The worst case, windowed (the profile's arms are in the notes of the pull request):
uv run --project ../gdstudio/python gds godot -- --path game -- --autopilot --rounds=12 --startround=12 \
    --hold=70 --seconds=110 --count=3 --bots=3 --ceiling=desktop --sample=1 --out=<abs>/report.json
# The same as CI plays it, and the check:
godot --headless --path game --fixed-fps 60 -- --autopilot --rounds=12 --startround=12 --hold=110 \
    --seconds=140 --count=3 --bots=3 --ceiling=desktop --sample=1 --out=<abs>/perf.json
python tools/perf/check_budget.py <abs>/perf.json tools/perf/budget.json
# A 30-minute leak soak (no per-frame rows, thin sampler rows):
godot --headless --path game --fixed-fps 60 -- --autopilot --rounds=999 --hold=9999 --seconds=1800 \
    --count=1 --bots=3 --frames=0 --labels=0 --sample=1 --out=<abs>/leak.json
# The HUD's draw calls part by part (add --hudprobe=1; prints HUDPROBE {json} once 60 dead stand)
```

Ablations (`BenchAblation`): `lights=0`, `ui=0`, `hide=Field`, `cull=D`, `fog=0`, `scale=N`, `msaa=0`. Record the
machine's load beside each run (processes, CPU %) and repeat; a headless run needs `--fixed-fps 60` to mean anything.

## Not done, and why

- A quiet machine was not available: every timing is of a loaded one. The CI summary is the first clean reading of the
  script cost; read it before tightening the time limit.
- The editor's own cost (debugger, Remote scene tree) was not measured, only the walk of the tree in script.
- The phone was not re-measured; its column is [phone-frames.md](phone-frames.md) and
  [crowd-budget.md](crowd-budget.md).
- The costs that need more than a few files are issues, each with these numbers:
  [#946](https://github.com/Ryubara/deadnight/issues/946) (bots as browsers),
  [#947](https://github.com/Ryubara/deadnight/issues/947) (the dead's script),
  [#948](https://github.com/Ryubara/deadnight/issues/948) (the HUD),
  [#949](https://github.com/Ryubara/deadnight/issues/949) (the crowd's engine cost),
  [#950](https://github.com/Ryubara/deadnight/issues/950) (a round that lasts minutes); the reviewer pass is
  [#907](https://github.com/Ryubara/deadnight/issues/907).
