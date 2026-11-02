# Crowd budget: what each platform pays for its crowd

The measurement behind [the crowd-budget decision](../design/zombies.md#decision-the-rules-cap-stops-at-40-315)
(issue #315): four players could have 46 zombies alive, the web ceiling is 40. Method, numbers and what they do not
say. The kit's crowds spike (`docs/godot/crowds.md` there) measured a bare crowd; this page measures the real night.

![Frame time against the crowd, as played and at worst](crowd-budget.png)

## What the client does above 40

Nothing: it never stands more. `ZombieTuning.hard_cap` (40) lets the director admit a spawn request only while fewer
than 40 stand; the rest wait in its queue, still counted alive by the rules (which decide spawns and the end of the
round) and by the balance model, which has no director. So a cap of 46 meant 40 on the lot and 6 queued. In the web
build with the cap at 46 the highest `alive` the probe ever read was 40 in all four runs.

## How it was measured

A throwaway build of the game (not committed; the numbers are the product) with these changes, otherwise the shipped
code and the real menu, night, camera and view:

- `RoundTuning.alive_cap` read from the page's `?alive=N`; 600 zombies a round, one every 0.25 s, 30% runners, 10%
  crawlers and 6% brutes from round 1 (the round-30 mix), player health 1,000,000 so the night does not end.
- `?worst=1`: every zombie at gameplay detail whatever its distance (`FAR_FROM` 100 km), the animation throttle off
  (every zombie advances every frame), and no frustum culling. This is the most the crowd can cost; real play is
  between the two.
- `tools/web_smoke/first_use.py`'s page recorder (a `requestAnimationFrame` delta per frame, the probe's `alive`), the
  player walking a square and firing, 25 s of night after the menu. Frames counted are those with at least 90% of the
  cap alive (the empty lot: after 10 s). Two runs a cell.
- Chrome 156 (installed, GPU: RTX 5080 through ANGLE D3D11), headless, `--disable-gpu-vsync --disable-frame-rate-limit`
  so the page is not held to the display, 1280 x 720, a fresh profile each run.

## Numbers (ms per frame, mean and p95, two runs each)

| Alive | As played mean / p95 | Worst case mean / p95 |
| ---: | --- | --- |
| 0 | 2.5 / 4.2 | 3.2 / 5.5 |
| 28 | 2.4 to 4.0 / 5.0 to 11.3 | 8.1 to 11.0 / 12.7 to 16.7 |
| 40 | 3.4 to 5.1 / 7.9 to 14.3 | 8.1 to 10.3 / 12.5 to 14.8 |
| 46 asked | peaked at 40 (never settled at 46) | peaked at 40 |

- At worst a zombie costs about 0.15 ms here (3.2 ms empty, 8 to 10 ms at 40), so the six more would add about 1 ms
  on this machine. As played, the cost is a third of that: most of the crowd is off screen or beyond 18 m, on the cheap
  mesh and the slow animation tier.
- The spread between runs (8.1 and 11.0 at 28) is the machine, not the crowd: another agent's browser run shared the
  GPU for part of it. Read differences under 30% as noise, as the spike did.
- With Chrome's CPU throttled 4 times (`Emulation.setCPUThrottlingRate`, a rough stand-in for a weak laptop's
  processor, not its GPU) the empty lot already took 11 to 16 ms (to 39 in a noisy run) and 28 zombies 70 to 180 ms,
  40 zombies 150 to 200 ms. That is an upper bound of a poor model, but it says the web build has no headroom on a slow
  CPU at 28, let alone at 46: raising the ceiling is not supported.

## What it does not say

- It is one fast machine and one browser. A real weak laptop (integrated GPU, a thermally limited CPU) and Firefox are
  still not measured ([#105](https://github.com/Ryubara/deadnight/issues/105)); big rounds from the browser need the
  autopilot from the page ([#171](https://github.com/Ryubara/deadnight/issues/171)).
- Four players also draw three more soldiers; the build here has one.
- The crowd stood still around a walking player in the greybox's field: zombies at the breaches, queued at the boards.

## What changed

`RoundTuning.alive_cap_ceiling` (40, the same number as `ZombieTuning.hard_cap`, a test pins it) cuts the cap, so
four players ask for 40 from round 21 on instead of up to 46.

The balance report, rerun with the same seed and 300 nights a cell, once with the ceiling lifted
(`--set rounds.alive_cap_ceiling=1000`) and once with it in place, is **byte for byte the same**: every cell's median
and every round's pressure and death rate. The reason is in the cap's own arithmetic: four players pass 40 only from
round 22, and no simulated four-player night gets there (the strong cell, the best: 2 of 300 nights reach round 21, none
round 22; its median is 17). So the cells could not tell whether the cap or the count binds past 40 because nothing in
the model lives there; the ceiling is a rule about the web build, not a retune, and the gate's targets are untouched.

## Desktop and game server: 100 and more alive (#453, #156)

The web numbers above are the browser's. The ceiling of 40 held on every platform, so a desktop (and a game server)
never had a budget of its own: the maintainer, on an RTX 5080: "over 100 zombies at once on non-web, easily, without
lagging; I guess at that point it is stress on the server". Three budgets, measured at 40, 120 and 160 alive (80 on
the client):

![The server's tick on Railway and on this PC, and the desktop client's frame, by the crowd](crowd-budget-platforms.png)

**The desktop client** (`game/tests/captures/crowd_cost_bench.tscn` with `--unpaced`: the shipped code, the real lot
and views, a crowd chasing two players and being shot, no HUD, 1920 x 1080 with the window system's refresh and the
frame limit off, so a frame is its work; RTX 5080, two runs a cell, 900 frames after 30 s of crowd):

| Zombies | Frame mean / p95 | Draw calls | Animation | The director and the views | The rest (drawing, engine) |
| ---: | --- | ---: | ---: | ---: | ---: |
| 40 | 1.3 to 1.5 / 1.7 to 2.5 ms | 115 | 0.26 ms | 0.04 ms | 1.0 to 1.1 ms |
| 80 | 1.9 / 3.4 to 3.7 ms | 135 | 0.45 ms | 0.07 ms | 1.3 ms |
| 120 | 2.4 to 2.5 / 5.2 to 5.6 ms | 149 | 0.69 ms | 0.14 ms | 1.5 to 1.6 ms |
| 160 asked (127 stood on average: the bench shoots) | 2.5 to 2.7 / 5.3 to 6.1 ms | 150 | 0.64 to 0.72 ms | 0.17 ms | 1.6 to 1.7 ms |

A zombie costs about 0.01 ms of frame here (the far mesh and the animation throttle carry most of the crowd), so the
**client is not what limits a desktop**: 160 draw in under 3 ms. The server's step is in the same process in
single-player, so it adds to that frame, below.

**The server tick** (`game/tests/captures/crowd_server_bench.tscn`, headless: the real `NightServer` and lot, four
players standing in the lot, the rules bent so the crowd fills at once and the players cannot die, every step timed and
the snapshot of each player made as `NightHost` makes it; 1200 steps a run, the steps of a 60 Hz tick). The zombies
step at 30 Hz inside it (`ZombieSim.STEP`), so every other tick carries all of their work: read the p95 and the ticks
over budget, not only the median. Before is the build of `main` before this change, after this change, **in the same
Railway container**, interleaved, so the processor is the same (Xeon Icelake, 48 vCPU; a first pair of runs on two
deploys landed on two different processors, one twice as fast, which is why the pair is run together):

| Zombies | Median step before / after | p95 before / after | Ticks over 16.7 ms of 1200 before / after |
| ---: | --- | --- | --- |
| 40 | 4.2 / 3.1 ms | 8.1 / 7.5 ms | 3 / 0 to 2 |
| 120 | 9.0 / 7.0 ms | 17.8 / 14.8 ms | 75 to 117 / 10 to 32 |
| 160 | 11.1 / 8.9 ms | 22.2 / 17.3 ms | 180 to 319 / 42 to 130 |

On this PC (a machine shared with other agents' test runs, so the mean and p95 are noisy; four runs a cell, median of the
medians): 2.4 to 1.9 ms at 40, 5.6 to 4.2 ms at 120, 7.1 to 5.4 ms at 160. The deterministic part of the saving is the
work: **path queries a tick 2.5 to 1.4 at 40, 7.5 to 4.2 at 120, 10 to 5.7 at 160**, and a frame built every second tick
instead of every tick.

What the probes (`PerfProbe`, medians a tick at 160 alive) said, and what was done:

| Where | Before | After | What was done |
| --- | ---: | ---: | --- |
| The zombies' step (`server.zombies`) | 3.7 ms | 2.8 ms | a zombie asked for a path every 0.25 s whatever it was doing; it now asks only while it chases, half as often beyond 14 m (`ZombieTuning.repath_far_distance`), and separation skips the square root for neighbours beyond the radius |
| The target list and the combat server (`server.target_list`, `server.combat`) | 0.9 ms | 0.4 ms | three dictionaries were made for each zombie each tick (the list, the combat server's copy, the lag history's copy); the entries are shared (`LagCompensator.placed`) |
| The frame (`server.frame`, `server.encode`) | 1.1 ms | 1.0 ms a built frame | built only on the ticks a snapshot goes out after (every second: `NightServer.step(delta, with_frame)`), so about half the cost at every tick |
| Moving the bodies (`server.move`) | 0.31 ms | 0.31 ms | nothing: four bodies, not the crowd |

**The network** is what [#545](https://github.com/Ryubara/deadnight/pull/545) changed (zombie deltas and an interest
radius), measured by the same bench with its snapshots: a snapshot of 120 zombies is 561 bytes for each of four players
(67 KB/s in all) against 1291 (155 KB/s) with every zombie in every snapshot, and 553 to 1636 bytes at 40 to 160 without
deltas. Bandwidth is not the limit at this size.

### Decision: 120 for a desktop and a server, 40 with a browser in the match (#453)

| Platform | Ceiling | Why |
| --- | ---: | --- |
| Web | 40 | the browser's measurement above (8 to 10 ms a frame at the worst on a fast desktop in Chrome, no headroom on a slow CPU) |
| Desktop (single-player) and a game server with no browser in the room | 120 | the client draws 120 in 2.4 ms; the server's step is 7 ms at the median and 14.8 ms at p95 on Railway, under the 16.7 ms tick; 160 is 17.3 ms at p95 there, over it |

- **One number per match, from the weakest client in it** (`RoundTuning.ceiling_for`, `NightServer.set_platform`): a
  client tells the server what it is with a `PLATFORM` packet after its welcome (no protocol version change: a client
  that says nothing, or an old one, counts as a browser, so the safe number holds). A browser that joins a night of
  desktop players takes the crowd down to 40 for what spawns next; one that leaves puts it back. The rules' cap
  (`GameRules.crowd_ceiling`) and the sim's hard cap are set together.
- The match settings' slider offers the host's platform's ceiling (a browser host 40, a desktop host 120).
- **A server operator's cap**: `MAX_ALIVE` (`ServerConfig`) caps every night of the process, because the rooms of one
  process share one core's tick (`ROOM_CAPACITY`, 4): four rooms at 120 alive would need about 28 ms of a 16.7 ms tick on
  the Railway processor above. Until the deployed server is sized (a service with more rooms than cores' worth of
  ticks), set `MAX_ALIVE` or a small `ROOM_CAPACITY` for it; a room of browsers is 40 whatever it says.
- The default curve of the rules (28 alive for one player, 46 for four) is unchanged: the 120 is reached by the host's
  "Most alive at once" setting or by the intensity multiplier (a count of 3x asks for three times the curve).

What this does not say: one machine of each kind and four standing players; a crowd chasing four moving players spreads
the neighbours and costs less in separation and more in paths; four rooms in one process were not run together; the
Discord proxy and a lossy link were not measured.
