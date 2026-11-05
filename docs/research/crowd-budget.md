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

- **One number per match, from the weakest client in it** (`RoundTuning.ceiling_for`, `CrowdCeiling.set_platform`): a
  client tells the server what it is with a `PLATFORM` packet after its welcome (protocol version 10; a client
  that says nothing counts as a browser, so the safe number holds). A browser that joins a night of
  desktop players takes the crowd down to 40 for what spawns next; one that leaves puts it back. The rules' cap
  (`GameRules.crowd_ceiling`) and the sim's hard cap are set together.
- **A bot is not a client** (#946): it has no screen, so the ceiling follows the **people's** platforms, not the seats'.
  `NightServer` registers no platform for a bot's seat (before, a hosted bot was registered as a browser and any night
  with a bot stood 40 on a desktop). (A person who took a bot's seat counted as a browser until its client said what it
  was, and a bot that inherited a seat dropped the leaver's platform; since #1179 a bot holds no seat of a person's, so
  neither happens.) A night with nobody but bots follows this process's own
  platform. The cost at the higher ceiling is in [the bots section](#bots-and-the-desktop-ceiling-946).
- The match settings' slider offers the host's platform's ceiling (a browser host 40, a desktop host 120).
- **A server operator's cap**: `MAX_ALIVE` (`ServerConfig`) caps every night of the process. The rooms of one process
  share one thread's tick, so what the deployed server takes is sized in [the last section](#rooms-in-one-process-561)
  (`ROOM_CAPACITY`, `ALIVE_BUDGET`); a room of browsers is 40 whatever any of them says.
- The default curve of the rules (28 alive for one player, 46 for four) is unchanged: the 120 is reached by the host's
  "Most alive at once" setting or by the intensity multiplier (a count of 3x asks for three times the curve).

What this does not say: one machine of each kind and four standing players; a crowd chasing four moving players spreads
the neighbours and costs less in separation and more in paths; four rooms in one process were not run together; the
Discord proxy and a lossy link were not measured.

### Bots and the desktop ceiling (#946)

A hosted bot joined the crowd's table as a browser, so on a desktop any night with a bot stood the web's 40. A bot has
no screen and no platform: **the ceiling follows the people's platforms** and a bot's seat is not in the table
(`NightServer._join`; a person taking a bot's seat registers as a browser until its client says what it is; a bot
inheriting a seat drops the leaver's flag; `test_bot_crowd_ceiling.gd`). Nobody but bots follows the process's
platform (a Linux game server: 120). A person on the web build still holds the room at 40, with bots or not.

What the lift costs, measured as the performance review did ([#907](https://github.com/Ryubara/deadnight/issues/907)):
the real night (HUD, the autopilot as the person, 3 bots, 3x, from round 12, seed 1), the person told it is a desktop,
150 s a headless run and 110 s a windowed one, two runs of each arm one after the other, counted over the ticks with
at least 85 alive (99 is the rules' cap there; 34 or more for the old arm, whose cap is 40). "Old" is the build before
the fix, bots registered as browsers (ceiling 40); "new" is the fix (ceiling 120, 99 stood). Debug build, the machine
at 95 to 100 % CPU the whole time, so read the ratio and the order, not the milliseconds.

| | Ceiling / alive | Labelled tick, headless (ms of 16.7) | Windowed 1280 x 720, frame mean / p95 / p99 | Frames over 25 ms |
| --- | --- | --- | --- | --- |
| Old (bots as browsers) | 40 / 38 | 5.9 and 5.9 | 6.6 / 13.3 / 16.5 and 6.4 / 13.4 / 21.1 | 0 % and 1 % |
| New (bots do not count) | 120 / 99 | 12.1 and 8.1 | 16.4 / 29.6 / 38.1 and 12.5 / 21.8 / 31.8 | 11 % and 3 % |

The tick is `pump + server + client + bots + the autopilot` of `Night.tick`, the labels of the review. The nodes at the
end were 5446 (old) and 5955 (new, the extra dead and their views), with no orphans in either. The tick at 99 alive is
8 to 12 ms of the 16.7 ms budget: it fits, with the margin the machine's load takes away. Frame time doubles (as the
issue read), and on this loaded machine 3 to 11 % of the frames go over 25 ms. The review put about 4.8 ms a tick of
crowd work in #930 (the client's crowd decode once a step) and #931 (the server's crowd lists once a step); this
measurement is without them. The ceiling number itself (120, #453) is unchanged: it comes from the Railway server step
(p95 14.8 ms at 120) and the 2.4 ms client draw above, which this run does not contradict.

### The client's script in the tick, with bots: the crowd is decoded once (#907, #930)

The decision above counted the client's draw and the server's step, not the client's GDScript in the tick. The review
of #907 (a night at round 12, 3 bots, `count_multiplier` 3, the desktop ceiling, about 98 alive, headless so no draw
cost, a busy machine) found the client side of a 60 Hz tick (`tick.pump`) as large as the server's step. Part of it
was the same bytes read again and again: the frame event carries one `PackedByteArray` of zombies to every reader, and
the readers (the person's `ClientState`, one more for **each bot**, the horde for the views) each decoded all of it,
five decodes a tick with three bots, though the simulation steps at 30 Hz and every second frame holds the bytes of the
one before.

What changed:

- `ZombieCodec.decode_shared` keeps the last bytes and entries and hands the same list out again; `ClientState` and the
  horde use it. A reader never changes the list or an entry (`ZombieCodec.decode_count` is what a test counts).
- `ZombieHorde.apply_snapshot` returns without touching a view when its bytes are the ones it applied last, and keeps
  the time for the next one. The views walk to the new place over the ticks since the last (`ZombieView._move_to`), as
  a client of a server always did, so the dead still move evenly (`test_zombie_shared_decode.gd`).
- `NightView` updates the dead's voices (`ZombieVoices.update`) only when the horde moved, with the time since the last
  (and at least every 0.25 s, for a crowd that stands quite still). A hit, a cripple or a death changes the bytes
  (the mode, the look), so it is never late; a swing's sound can start up to one step (33 ms) after the tick it was
  due on.

Measured with the review's probe (`PerfProbe` labels, mean microseconds a tick over the ticks with 85 or more standing,
3,300 ticks; headless, 3 bots, round 12, `count_multiplier` 3, the desktop ceiling): the base commit and the branch run
**at the same time** on the same night (the rounds and counts are the same in both). Two pairs on a quiet machine, and
one on a very busy one (about twice the time):

| Label | Quiet before | Quiet after | Busy before | Busy after |
| --- | ---: | ---: | ---: | ---: |
| `tick.pump` (the client side) | 2,937 / 2,734 | 1,732 / 1,594 | 11,087 | 5,855 |
| `event.frame` (a frame applied to every `ClientState` and the view) | 2,406 / 2,230 | 1,202 / 1,128 | 8,962 | 4,056 |
| `view.horde` | 674 / 635 | 280 / 278 | 2,506 | 847 |
| `view.voices` | 665 / 593 | 417 / 389 | 3,096 | 1,747 |
| `horde.decode` | 173 / 154 | 1 / 1 | 536 | 1 |

Decodes of the crowd: about 4.5 a tick before (541 in 120 ticks of a night with 3 bots, `test_zombie_shared_decode.gd`),
3,118 in 6,000 ticks after (one for each simulation step). About 1.1 to 1.2 ms of a quiet tick, and 5 ms of a busy one.

What is left: `view.voices` is still the largest of these (the loop runs for each step and sorts the due idle voices),
and `event.frame` still carries the 19 listeners of the frame and the HUD. The server's lists are #931.

### The browser by system, and on a weak processor (#105)

`tools/web_smoke/crowd_cost.py` exports the crowd bench (`crowd_cost_bench.tscn`: the real lot and views, the director
in the page) and reads each stage of a frame from the page: Chrome 156, RTX 5080, unpaced, 30 s of crowd before the
first frame, 400 frames, two runs a cell (the processor slowed 4 times: one run):

| Zombies | Frame mean / p95 | Animation | The director and paths | Views | The rest (drawing, engine) | With the processor slowed 4 times |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 0 | 1.06 / 1.25 ms | 0.00 ms | 0.00 ms | 0.00 ms | 1.06 ms | 4.6 / 5.0 ms |
| 20 | 1.79 / 2.10 ms | 0.10 ms | 0.03 ms | 0.00 ms | 1.65 ms | 6.4 / 10.6 ms |
| 40 | 2.33 / 2.90 ms | 0.16 ms | 0.06 ms | 0.01 ms | 2.09 ms | 7.8 / 13.6 ms |
| 80 | 2.95 / 4.50 ms | 0.28 ms | 0.14 ms | 0.02 ms | 2.49 ms | not run |

A zombie costs about 0.015 ms of frame in the browser with a GPU past the first 40 (0.03 ms each up to 40, the first
ones carry the fixed costs of drawing a skinned model; 0.01 on the desktop), and about 0.08 ms with the processor slowed
4 times. The crowd bench is lighter than the night: the same slowed processor takes
89 ms a frame with 40 zombies in the shipped night ([above](web-export.md#big-crowds-in-the-browser-from-the-autopilot-171)),
so read the bench for the share a crowd takes and the night for what a player gets. Not run: Firefox (not installed on
the machine) and a real weak laptop; the slowed processor is the stand-in.

### The server's crowd lists, once a step (#931)

The review of #907 found the server building lists for the dead at 60 Hz that change at 30 Hz: the target list twice a
tick (the combat server's, then the grenades'), the combat and grenade servers' own copies of it and the lag history's
frame, a host with bots building the whole frame (and the zombies' bytes in it) on every tick, which gave back half of
what the build every second tick above saved, and `NightWorld.shop_spots()` making 19 dictionaries for every player's
prompt on every tick. The fix keys them on `ZombieSim.revision`, a number that moves with every step and every change
to a zombie (a spawn, a hit that staggers, a blast, a status, a cripple, a death, a relocation):

- `NightServer._target_list()` and the frame's zombie bytes are built once for a revision. A kill between two steps
  moves it, so the grenades' second ask rebuilds only when a shot killed something in the tick.
- `CombatAction.targets(list, revision)` and `GrenadeAction.targets(list, revision)`: the same number as the last
  action keeps the server's table. The combat server still records a frame in the lag history on every tick, as the
  same table (`LagCompensator.record_again`), so a rewind between two ticks blends exactly as before.
- `shop_spots()` reads the markers once and hands out the same read-only list.

A test rig that writes a `ZombieBody` field by hand (`SeatedNight.drop_zombie`, the staging) calls `sim.touch()`; the
sim's own methods already do. Without it the new place shows at the next step, up to one tick late.

Measured with the review's probe (`measure.gd` of #907: a real `Night` with the HUD, three bots, 3x, round 12, the
desktop ceiling, 100 s, the ticks with 85 or more alive), headless. The two builds ran **at the same time** on the same
loaded machine, two pairs, the same seed (the runs are bit-for-bit the same night: the same 3,300 ticks and the same
alive count in both arms). Mean microseconds a tick:

| Label | Before (A / B) | After (A / B) | Change |
| --- | ---: | ---: | ---: |
| `tick.server` (all the server's work) | 4,256 / 4,318 | 3,094 / 3,150 | **-1.1 ms (-27 %)** |
| `server.target_list` (the first ask of a tick) | 544 / 566 | 299 / 304 | -0.25 ms |
| `server.frame` (the frame, the grenades and their second ask) | 1,474 / 1,498 | 630 / 626 | **-0.85 ms (-58 %)** |
| `server.encode` | 135 / 144 | 72 / 71 | -0.07 ms |
| `server.combat` | 310 / 305 | 215 / 213 | -0.1 ms |
| `server.zombies`, `server.move`, `server.act` | | | no change (not touched) |

The counts, which a loaded machine does not move: 6,600 target lists built in the 3,300 ticks before (two a tick), 1,806
after (one for each step, 1,650, and 156 more for the ticks a kill or a spawn came between); 3,300 encodes of the
zombies before, 1,735 after. An earlier run on a busier machine read `tick.server` at 11.4 ms for the same night (the
review's 5.8 ms was a quieter hour): read the ratio of two runs made together, not the milliseconds. No
ceiling moves on this; the saving is about a quarter of the server's work at this crowd and grows with the crowd.

## Rooms in one process (#561)

The numbers above are one night in one process. A game server runs its rooms (`GameServer`, each a `NightHost` in a
`SubViewport`) one after the other in one thread, so what has to fit the 16.7 ms tick is the **sum of the rooms**: four
rooms at 120 alive would need about 28 ms. Measured on Railway, as the real server runs them.

### How the rooms were measured

`game/tests/captures/crowd_server_bench.tscn` now takes `--rooms=K`: K nights, each in a `SubViewport` of its own as
`GameServer` builds a room, four players standing in each, the crowd filled to `--zombies=N` in every room, all stepped
in the same physics frame; the snapshots each player would get are made as `NightHost` makes them. `tick_ms_*` is the
whole process's work in a physics frame (every room's step and snapshots), which is the number that has to fit; 1200
frames a run. `--web=1` makes the players browsers, `--stagger=1` is the change below. The image is the game server's
own Dockerfile with the bench as its command, a service `deadnight-rooms-bench` in the test project (deleted after),
`us-west2` like the real server. The container: 48 vCPUs shown, **a limit of 8 vCPUs** (`cpu.max` 800000 100000) and 8 GB
memory, so the process has one busy core and seven idle.

The processor was not the one of the earlier runs: **AMD EPYC 9655 and 9655P** (three containers, two of them at the
same time, which made them noisier), against the Xeon Icelake the single-room numbers above came from. The same step
costs **1.7 times** as much on that Icelake (p95 7.5 / 14.8 ms at 40 / 120 alive against 4.3 / 8.8 here). Size for the
slower one.

### Alternate heavy ticks

A room's heavy tick is the zombies' 30 Hz step plus the frame built after it, every second 60 Hz tick, and every room
began on the same parity, so with several rooms they all fell on one tick. `GameServer` now gives each room the half of
the physics frames (`NightHost.heavy_parity`) that fewer rooms use, and a room begun on the wrong one lets its zombie sim
count one tick early (`NightHost.phase`). The worst tick becomes about half the rooms' heavy work plus the other half's
light work. A test (`test_rooms_put_their_crowds_steps_on_alternate_ticks`) opens four rooms and checks that two step
their zombies in every frame.

![The process tick against the rooms, with the rooms stepping together and alternating](crowd-budget-rooms.png)

### Numbers

p95 of the process tick in ms: the first container (the two settings interleaved, so like for like), then the range over
the later runs of the alternating one (six runs, from two containers running together). The last column is the ticks over
16.7 ms of 1200, over all alternating runs (5 percent, 60 ticks, is the p95 line).

| Rooms x alive | Together, first container | Alternating, first container | Alternating, later runs | Over 16.7 ms, alternating |
| --- | --- | --- | --- | --- |
| 1 x 40 | 5.3 | 5.0 | 6.0 to 7.6 | 0 to 1 |
| 2 x 40 | 8.1 | 5.7 | 7.2 to 9.0 | 0 to 2 |
| 3 x 40 | 11.6 | 8.7 | 10.2 to 13.2 | 0 to 13 |
| 4 x 40 | 13.7 | 9.7 | 12.1 to 15.8 | 2 to 43 |
| 6 x 40 | 19.3 | 14.2 | 18.0 to 23.7 | 10 to 488 |
| 8 x 40 | 27.2 | 17.4 | | 113 |
| 1 x 120 | 10.4 | 9.2 | 10.9 to 15.3 | 0 to 36 |
| 2 x 80 | 13.3 | 8.8 | 9.7 to 12.3 | 0 to 6 |
| 2 x 120 | 16.0 | 10.5 | 11.6 to 17.2 | 1 to 70 |
| 3 x 120 | 24.0 | 16.8 | 21.2 to 24.5 | 64 to 467 |

- The tick follows the **total alive in the process** more than the room count: about 5 ms at 40 alive, 9 ms at 120, 10
  at 160, 14 to 17 at 240 to 320 (alternating, quiet container). The players stand still in this bench, so a moving crowd
  costs somewhat more in paths and less in separation.
- A room costs about 26 MB of memory (261 MB for one, 299 MB for three, 366 MB for six): memory is not the limit.
- The p99 is 2 to 5 ms above the p95, and the worst tick of a run is 15 to 30 ms (a room being built, the first zombie
  spawns): a room opening can stall the others for a tick or two.
- On the 1.7 times slower Icelake the 3 x 40 and 1 x 120 cases (8.7 and 9.2 ms in the quiet container) would be 15 to 16
  ms: under the tick with almost nothing to spare. 4 x 40 (9.7 quiet, 12 to 16 loud) would be over it there.

### Decision: three rooms, an alive budget of 120 for the process

| Setting | Value | Why |
| --- | --- | --- |
| `ROOM_CAPACITY` | 3 (the new default; set on `deadnight-server`) | three browser rooms of 40 are the most the Discord Activity can ask for, and they fit |
| `ALIVE_BUDGET` | 120 (the new default; set on `deadnight-server`) | the most alive in all the rooms of the process together: each room is cut to its share (`GameServer`, at least 20), so a lone desktop room stands 120, two stand 60 each, three 40 each |
| `MAX_ALIVE` | unset | a cap on one room, still there for a small container |

The worst load this allows is 3 x 40 (or 1 x 120, or 2 x 60), which measured 8.7 to 13.2 ms at p95 on AMD (under 16.7 in
every run) and is about 15 to 16 ms scaled to the older processor. The budget is a share, so a night in progress loses
spawns, never zombies, when a room opens: the cap falls and nothing new comes until fewer stand. `ROOM_CAPACITY` above
3 without a larger `ALIVE_BUDGET` cuts the rooms below 40 (down to 20) instead of going over the tick.

Checked on the deployed service: with this branch deployed to `deadnight-server` the log says `capacity=3`, and a Godot
client (`game/tests/captures/rooms_online_probe.tscn`) signed four guests in on the deployed backend, each starting a
night of its own: three were welcomed by the server and the fourth got `no_server` from the backend.

### Rooms of eight on Railway (#712)

The decision above was measured with four players a room. A room now seats eight ([multiplayer](multiplayer.md)), and
the local bench said three rooms of eight were tighter (a loaded machine). Measured on `deadnight-server` itself:
`crowd_server_bench.tscn --stagger=1` as the service's start command for one deployment (the image is the game
server's own, so the same Godot build and the same container), `--players=8` standing players a room, 1200 ticks a run,
**three runs of each setting one after the other in the same container**. The container: AMD EPYC 9655P, 48 vCPUs shown,
a limit of 8 (`cpu.max` 800000 100000), `us-west2`. p95 of the process tick in ms, the three runs, and the ticks over
16.7 ms of 1200:

| Rooms x alive, players a room | Mean tick | p95 | p99 | Over 16.7 ms | Memory | Out, all players |
| --- | --- | --- | --- | --- | --- | --- |
| 1 x 40, 8 | 3.4 to 3.9 | 6.7 to 8.0 | 8.6 to 9.5 | 0, 0, 1 | 284 MB | 72 KB/s |
| 1 x 120, 8 | 5.2 to 6.1 | 10.0 to 12.2 | 11.4 to 16.2 | 0, 8, 0 | 284 MB | 138 KB/s |
| 2 x 40, 8 | 5.8 to 6.6 | 7.6 to 8.8 | 8.7 to 10.4 | 0, 0, 0 | 287 MB | 145 KB/s |
| 2 x 60, 8 | 7.0 to 7.2 | 8.7 to 9.1 | 10.0 to 10.6 | 0, 1, 0 | 287 MB | 186 KB/s |
| **3 x 40, 8 (the worst `ROOM_CAPACITY` 3 allows)** | **8.4 to 9.3** | **11.5 to 13.3** | **13.7 to 15.3** | **5, 2, 2** | **312 MB** | **217 KB/s** |
| 3 x 40, 4 (the earlier decision's load) | 6.0 to 6.2 | 8.7 to 8.9 | 9.9 to 10.6 | 1, 1, 1 | 298 MB | 108 KB/s |
| 4 x 40, 8 | 11.1 to 11.8 | 13.6 to 15.6 | 15.4 to 19.4 | 12, 8, 40 | 345 MB | 289 KB/s |

- **Three rooms of eight fit.** The p95 is 11.5 to 13.3 ms against the 16.7 ms tick and at most 5 ticks of 1200 (0.4
  percent) go over, with 120 alive (`ALIVE_BUDGET`) shared by 24 people. Eight players a room cost about **1.4 times**
  the process tick of four (mean 8.4 to 9.3 ms against 6.0 to 6.2; p95 11.5 to 13.3 against 8.7 to 8.9): the
  snapshots to twice the people and the zombies' targets over more of them. The step alone is 8.7 to 9.9 ms at p95;
  building and sending the snapshots is the rest (2.0 to 2.2 ms a sending tick).
- **`ROOM_CAPACITY` 3 and `ALIVE_BUDGET` 120 stay.** Nothing to change in the settings.
- **Four rooms of eight are the edge:** p95 13.6 to 15.6 ms and 8 to 40 ticks over (up to 3.3 percent). That is the
  tick a player feels as a hitch now and then, so four stays out, as the open question below already said for four
  players. Memory is not the limit (about 28 MB a room, 345 MB at four).
- The local run (a loaded machine, three rooms of eight, mean 12.1 ms, 158 ticks over) was worse than Railway's: it is
  the machine's noise, and Railway's container is the number to size by.
- The bytes out grow with people times their share: 217 KB/s for 24 people at 120 alive, 9 KB/s a person.
- Not measured: the processor Railway gives the service can change (the earlier decision took 1.7 times from an older
  Xeon for one room: 3 rooms of eight would be about 20 ms there, over the tick), moving players, shots and a room being
  built while others run.

### Open question for the maintainer: more than three rooms costs money or work

Not changed, because each option costs something. The container has 8 vCPUs and the process uses one.

- **Keep three rooms** (3 rooms, 120 alive): nothing.
- **`ROOM_CAPACITY` 4 and `ALIVE_BUDGET` 160** (4 rooms of 40): nothing, but p95 12 to 16 ms on AMD and over the tick on
  an Icelake host, so it would drop ticks some of the time.
- **A second service `deadnight-server-2`** with its own `SERVER_ID`, public domain and `ACTIVITY_PATH` (`/server2`, and
  a second URL mapping in Discord's developer portal, which is the maintainer's): 6 rooms. Railway bills usage, $20 per
  vCPU-month and $10 per GB-month ([plans](https://docs.railway.com/reference/pricing/plans)). A process is about 0.3 GB
  ($3) and 0.1 to 0.2 vCPU idle ($2 to $4), up to about 0.7 vCPU with three busy rooms ($14): **about $5 to $17 a month
  more** (estimates, not read off a bill).
- **Replicas of `deadnight-server`**: not usable as is. Replicas share one `SERVER_ID` and one public domain, so a ticket
  for a room on one replica can reach another.
- **Several Godot processes in the one container** (a supervisor, one port each): about 7 x 3 rooms, no new money
  (billing is by use), but work: Railway gives a service one public port, so a small proxy in front, and a heartbeat
  per process.

What this does not say: three containers on one processor family and one region; players standing still (no moving
crowd, no shots); the Icelake figure is a ratio from one room, not a measured multi-room run (Railway does not let us
pick the processor); the Discord proxy and a lossy link were not measured; a room being built while others run is not
timed.

## Bots in a room: what the frame was not, and the budget (#1222)

A room with any bot builds its frame on every step (`NightHost._physics_process`: the bots decide every step), and
Issue #1193 measured one bot in each of three rooms at 1.28 times the control. The issue read that as the frame's cost.
Probes on the pieces (`PerfProbe`, the bench with 8 people, 7 bots and 120 alive, local, ms a tick) said otherwise:

| Piece | Before | After | What |
| --- | ---: | ---: | --- |
| `server.frame` (the frame, with 15 bodies) | 3.0 | 1.2 | the prompt of each body was 1.9 of it |
| `server.act` (each body's commands) | 2.4 | 0.7 | the same prompt, asked again for every body on every tick |
| The bots (hear, observe, think, walk, motor, crew) | 2.9 | 2.1 | code not changed (the gap is the machine's noise): about 0.3 each |
| `server.move` (15 bodies) | 1.8 | 1.4 | code not changed (noise) |
| Whole tick, mean | 14.6 to 15.3 | 9.7 to 10.6 | |

`NightServer.use_target` (the card a body shows, and what the use guard times a press by) is asked for every body on
every tick, and again for the frame; almost every answer is `{}` because the body stands in the open, but each ask
walked every door, breach, spot and post. `UseSites` is a flat bound first: the points an offer can come from, each
with its reach, and a body farther than all of them is offered nothing. It is exact, so the bots hear the same:
`test_use_sites.gd` compares both answers at every half metre of both maps (and fails if a reach is cut short), and the
bench prints a hash of every command every bot sent (`bot_commands`), the same with the bound on and off
(`--sites=1|0`, one build in one container): locally with 7 bots, and in all three reps on Railway with 1 and 7 bots in
one room and in three. The bots decide the same, step for step.

### On Railway

`crowd_server_bench.tscn --stagger=1 --players=8`, a service of the test project (deleted after) on the game server's
own image; the container is 48 vCPUs shown, a limit of 8. Three reps of each setting one after the other in one
container, so the processor is the same within a run, and Railway picked three different ones: Xeon 6975P-C (quiet),
Xeon Gold 5520+ (twice as slow, so its milliseconds are no use, only its ratios) and AMD EPYC 9655P (the earlier
decisions' processor, on a host at a load of 21 to 35 and so noisy: the same setting spread by 4 ms between reps).
Process tick in ms, mean and p95 over the three reps, and the ticks over 16.7 ms of 1200:

| Quiet Xeon 6975P-C | Mean | p95 (median) | Over 16.7 ms |
| --- | --- | --- | --- |
| 1 x 120, no bots, old (the control) | 6.8 to 7.4 | 14.1 to 15.6 (14.7) | 10 to 31 |
| 1 x 120, no bots, new | 5.8 to 6.4 | 12.0 to 14.3 (13.2) | 1 to 12 |
| 1 x 120, 1 bot, old / new | 7.9 to 8.5 / 6.8 to 7.2 | 14.8 / 14.1 median | 24 to 43 / 12 to 27 |
| 1 x 120, 7 bots, old | 11.6 to 13.7 | 18.7 to 22.9 (22.9) | 194 to 545 |
| 1 x 120, 7 bots, new | 9.8 to 11.8 | 16.7 to 21.8 (20.3) | 61 to 292 |
| 3 x 40, no bots, old (the control) | 11.2 to 12.2 | 15.7 to 17.7 (16.6) | 36 to 103 |
| 3 x 40, no bots, new | 8.9 to 9.7 | 13.0 to 14.7 (13.9) | 1 to 20 |
| 3 x 40, 1 bot each, old | 15.3 to 15.6 | 19.7 to 21.9 (19.8) | 292 to 393 |
| 3 x 40, 1 bot each, new | 11.4 to 13.0 | 15.9 to 18.6 (16.1) | 40 to 135 |
| 3 x 40, 7 bots each, old / new | 26.6 to 30.1 / 22.7 to 23.2 | 36.6 / 29.2 median | 1200 / 1184 to 1199 |

![The process tick before and after, by rooms and bots, on Railway](crowd-budget-bots.png)

- **The saving is about 1 to 3 ms of the mean** with bots (and about 1 without: the prompts of 8 standing people are
  asked every tick too), which is **the 1 bot in each of three rooms back at the control's p95** (16.1 against the
  control's 16.6, from 19.8: 1.19 times).
- **7 bots are not at the control**: 20.3 against 14.7 in a lone room (1.38 times; it was 1.55). The issue's target
  is **not met**. What is left is not the frame: the bots' own work (about 0.3 ms each) and the bodies they are
  (move, act, the dead's field and the shove, the zombies' targets, the bigger snapshots), about 0.6 to 0.9 ms a bot
  in all. Seven bots in each of three rooms are 29 ms: far over the tick.
- Spread: a setting's three reps differ by 1 to 2 ms (quiet container), up to 4 to 8 ms (the loud one), and p95 moves
  with them. The mean and the ticks over 16.7 ms are steadier.

### Decision: `BOT_BUDGET` 3 (it was 0, none; #1213 proposes 2)

The measure is the bots' p95 against the control's in the same run (the old build, no bots: the load the maintainer
accepted for the rooms), on the setting the budget allows:

| Rooms x bots | Control p95 (old, no bots) | New, with the bots p95 | Ratio, by container: quiet Xeon / AMD / slow Xeon |
| --- | --- | --- | --- |
| 1 x 1 | 14.7 | 14.1 | 0.96 |
| 3 x 1 each | 16.6 | 16.1 | 0.97 / 1.21 / 0.93 |
| 2 x 1 each (AMD) | 15.3 | 17.1 | 1.12 |
| 1 x 2 (AMD) | 19.7 | 20.5 | 1.04 |
| 1 x 3 (AMD) | 19.7 | 21.9 | 1.11 |
| 1 x 4 (AMD) | 19.7 | 22.5 | 1.14 |
| 2 x 2 each (AMD) | 15.3 | 18.6 | 1.21 |

A budget of 3 seats 3 bots in a lone room and 1 in each of two or three rooms: at or near the control's p95 in all of
them (0.93 to 1.12, inside the spread), and three rooms now have a bot where the budget of 2 gave none. 4 puts 2 bots
in each of two rooms (1.21) and 4 in a lone room (1.14), past the spread. `MAX_BOTS` stays 7 and `BOT_BUDGET=0`
turns the budget off. `GameServer.DEFAULT_BOT_BUDGET` is the number; the host's setting (0 to 7) is still a request.

### What this does not say

- The frame is still built on every step with a bot in the room (1.2 ms with 15 bodies against 0.5 on the
  control's half of the steps): a frame for the bots that holds only what they read, built on the steps between the
  people's, would save about 0.3 ms, and was not done: every field a bot reads off `players` would need an audit, and
  the exact-hash proof above would be needed for it too.
- The bots' own work (`BotClient`: `_track_crew` builds a dictionary for every body, for every bot, every tick: 0.6 ms
  for 7 bots; the events' filter and the frame's copy for each bot: 0.4 ms) is the next piece to measure.
- Players stand still in the bench; the bots walk and shoot in it. A moving room (paths, shots, doors) is in the
  soak, not here; the soak (`pair`, `churn`, ten game minutes each) passes.
- One container each of three processors, three reps each: the ratios carry about 10 percent of spread.
