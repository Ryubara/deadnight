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

Since #1179 a room can hold 15 bodies, and the bots are not in this decision's numbers: [Rooms of fifteen bodies](#rooms-of-fifteen-bodies-1193)
measures them and gives the bots a `BOT_BUDGET` of their own.

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

### Rooms of fifteen bodies (#1193)

Since #1179 took the bots out of the eight-person cap, a night holds **8 people and 7 bots, 15 bodies**
(`NightHost.MAX_SEATS`). The two decisions above were measured with people only (`ROOM_CAPACITY` 3 on three rooms of
eight), and #1191 measured only the bandwidth of the new room. This section measures the tick, the memory and the
bandwidth of the worst room the same way, and changes what the numbers do not allow.

**How.** `crowd_server_bench.tscn` as in #712 (`--stagger=1`, 1200 ticks a run, the crowd filled and settled first, the
snapshot of every person made as `NightHost` makes it), with the bots seated and run as `NightHost._physics_process`
runs them (`--bots=N`: `NightBots`, the host's own class; a frame is built on every step and every bot hears it, as in
a room that has a bot) and the events between two sends kept for the next one, as the host keeps them. The people
stand; the bots roam and fight. A service `rooms-bench-1193` of the test project, the server's own Dockerfile with the
bench as its command: AMD EPYC 9655P, 48 vCPUs shown and a limit of 8 (`cpu.max` 800000 100000), 8 GB, `us-west2`;
deleted after. Four deployments, three runs of every setting each, **interleaved in one container**, and the old
accepted setting (three rooms of eight people at 120 alive, **A**) in every deployment as the control.

**The host is not the host of #712.** The control read mean 11.1 to 12.5 ms and p95 15.2 to 17.5 ms in three
deployments, against 8.4 to 9.3 and 11.5 to 13.3 on the page above, and 18.0 to 19.1 and 28.2 to 31.1 in a fourth (the
processor was the same model; the host's load average, the `LOAD` line before each run, was 12 to 30 in the
first three and 46 to 61 in the fourth). That is 1.3 to 2.1 times, between two deployments an hour apart.
**Read each setting against the control of its own deployment** (the last column); the milliseconds are for this host on
these hours. Even the setting #712 accepted ran over the 16.7 ms tick on 2 to 10 percent of ticks (53 to 59 percent in
the slow deployment) when it was run again.

| Setting (rooms x people + bots, alive in all) | Mean tick | p95 | p99 | Ticks over 16.7 ms of 1200 (3 runs) | p95 against its control | RSS MB | A person down, KB/s |
| --- | --- | --- | --- | --- | --- | ---: | ---: |
| **A, control: 3 x 8 + 0, 120** (deployment 1) | 11.6 to 12.2 | 15.5 to 16.7 | 17.9 to 19.4 | 60, 27, 23 | 1 | 343 to 346 | 9.1 |
| **3 x 8 + 7, 120 (the worst room `ROOM_CAPACITY` 3 allowed)** | **26.6 to 28.8** | **33.5 to 37.1** | 38.8 to 42.7 | **1200, 1200, 1200** | **2.21** | 386 to 388 | 16.0 |
| the same, the server's bodies (`--drawn=0`, no model) | 26.4 to 27.8 | 33.6 to 34.6 | 39.1 to 40.2 | 1200, 1200, 1200 | 2.15 | 340 to 341 | 16.0 |
| 3 x 8 + 3, 120 | 19.0 to 19.1 | 24.7 to 25.5 | 29.2 to 30.9 | 909, 867, 891 | 1.58 | 363 to 364 | 12.8 |
| 2 x 8 + 7, 80 | 17.3 to 18.1 | 21.7 to 23.3 | 24.4 to 27.1 | 824, 629, 729 | 1.40 | 338 to 339 | 15.8 to 16.0 |
| 2 x 8 + 7, 120 | 19.5 to 21.0 | 24.5 to 27.1 | 28.6 to 30.8 | 1163, 1133, 1058 | 1.61 | 340 to 341 | 18.0 to 18.3 |
| 1 x 8 + 7, 40 | 9.0 to 9.5 | 13.3 to 14.3 | 16.2 to 17.3 | 18, 9, 10 | 0.87 | 318 | 15.9 to 16.3 |
| **1 x 8 + 7, 120 (the lone room at the desktop ceiling)** | 12.1 to 13.1 | **19.4 to 21.3** | 22.8 to 24.2 | **241, 265, 413** | **1.26** | 320 | **24.7 to 25.5** |
| 1 x 8 + 0, 120 | 7.3 to 8.0 | 14.6 to 16.4 | 17.5 to 19.2 | 20, 22, 51 | 0.96 | 318 to 319 | 17.4 |
| 1 x 8 + 7, 60 (deployment 2) | 9.4 to 9.7 | 14.2 to 15.2 | 16.8 to 17.6 | 12, 25, 15 | 0.95 | 319 | 17.8 |
| 1 x 8 + 7, 80 | 10.3 to 10.6 | 16.0 to 17.2 | 18.9 to 20.4 | 75, 47, 65 | 1.07 | 319 | 19.9 to 20.4 |
| 2 x 8 + 3, 80 | 12.0 to 12.6 | 15.1 to 15.9 | 16.7 to 17.3 | 31, 15, 12 | 0.98 | 322 | 12.8 |
| 2 x 8 + 2, 80 | 11.0 to 11.4 | 13.5 to 14.7 | 15.5 to 16.0 | 3, 6, 1 | 0.90 | 322 to 323 | 12.4 |
| 2 x 8 + 2, 120 | 12.6 to 13.3 | 16.0 to 17.0 | 17.7 to 19.7 | 76, 35, 46 | 1.06 | 322 to 323 | 14.5 |
| 2 x 8 + 1, 80 | 9.6 to 10.2 | 11.9 to 13.1 | 13.7 to 15.3 | 2, 2, 2 | 0.81 | 322 | 10.7 |
| 3 x 8 + 1, 120 | 14.8 to 15.2 | 19.6 to 20.4 | 22.6 to 23.3 | 257, 339, 288 | 1.28 | 353 | 10.6 to 10.9 |
| 1 x 8 + 4, 120 (deployment 3) | 10.4 to 11.7 | 18.1 to 20.4 | 21.4 to 23.3 | 109, 156, 282 | 1.12 | 320 to 321 | 21.4 |
| 1 x 8 + 3, 120 | 10.2 to 11.5 | 18.3 to 21.2 | 21.9 to 24.2 | 209, 129, 272 | 1.16 | 318 to 320 | 21.6 |
| 2 x 8 + 3, 120 | 14.7 to 16.1 | 18.9 to 21.2 | 21.9 to 24.3 | 179, 386, 208 | 1.16 | 326 | 15.3 |
| 1 x 8 + 2, 120 (deployment 4, control p95 28.2 to 31.1) | 13.3 to 15.1 | 26.0 to 30.6 | 33.6 to 40.1 | 523, 424, 505 | 0.97 | 319 to 320 | 21.5 |
| 2 x 8 + 1, 120 (the same) | 16.3 to 20.2 | 24.1 to 30.2 | 29.4 to 38.8 | 863, 603, 452 | 0.90 | 322 to 323 | 12.9 to 13.0 |
| 1 x 8 + 1, 120 (the same) | 12.0 to 12.7 | 23.6 to 26.4 | 29.1 to 32.2 | 426, 391, 370 | 0.85 | 319 to 320 | 19.3 |

Three rooms of four people (the earlier decision's load) are not in this table; the page above has them. The runs
are in the scratch of the pull request, not committed.

What it says:

- **It misses, and by a wide margin.** Three rooms of eight people and seven bots took 2.2 times the control's p95 and
  every tick of the 1200 was over the 16.7 ms. The old `ROOM_CAPACITY` 3 does not hold the room #1179 allows. One
  room of 15 at the desktop's 120 dead is also over (p95 1.26 times the control, 20 to 34 percent of ticks over),
  and one room of 15 at 40 or 60 dead is under it.
- **The first bot costs most.** A room with any bot builds its frame on every step, not on every second one
  (`NightHost._physics_process`: `framed = sending or bots.count() > 0`), so one bot in each of three rooms
  (3 x 8 + 1) is already 1.28 times the control; the bots' own thinking is about 0.3 ms each (`bots_ms`: 2.1 to 2.3 ms
  for seven in one room) and the rest is the frame, its bigger snapshots (533 bytes against 303 a person) and the
  zombies' targets over more bodies. Eight people at 120 dead alone are at the control's level and every bot added to
  that room takes it over (3 to 4 bots: 1.12 to 1.16, 7: 1.26).
- **The bodies the server draws change nothing.** `--drawn=0` (the shipped server: no soldier model) and the bench's
  default (the page's: drawn) read the same tick with bots and without; the memory is 45 MB lower.
- **Memory is not the limit:** 318 to 320 MB for one room of 15, 386 to 388 MB for three, of 8 GB (the bots add
  about 2 MB each: 43 MB for the 21 of three rooms, against three rooms of eight people).
- **Bandwidth** is the bench's byte count of the snapshots a person is sent (30 a second), not the wire's framing:
  **16 KB/s down for a person in a room of 15 at 40 dead, 25 KB/s alone in the room at 120 dead** (8 people alone:
  9 and 17 KB/s). #1191 measured 21.3 KB/s at 37 dead on the wire with real sockets. A phone on a poor link holds
  200 KB/s (Lighthouse's baseline for a mobile page, 1.6 Mbit/s: [throttling](https://github.com/GoogleChrome/lighthouse/blob/v7.4.0/docs/throttling.md),
  "the bottom 25 percent of 4G and the top 25 percent of 3G") and about 50 KB/s on Chrome's "Slow 3G" preset (400
  kbit/s, from a secondary source, not read off DevTools). 25 KB/s is 12 percent of the first and half of the second
  before the transport's overhead, and about 90 MB an hour of mobile data. It fits, with little room on the slow
  preset; the Discord proxy and a lossy link were not measured.
- **Local, for what it is:** the same bench on this PC (Windows, Ryzen 7 9800X3D, other agents' runs on it, three runs
  interleaved) read 3 x 8 + 0 at mean 12.4 to 13.8 and p95 16.5 to 19.7 ms, 3 x 8 + 7 at 24.3 to 29.1 and 30.8 to
  34.9, 1 x 8 + 7 at 120 at 11.3 to 12.3 and 18.7 to 19.9, 2 x 8 + 7 at 120 at 17.8 to 19.8 and 20.7 to 23.7, four
  rooms of 8 + 7 at 36.7 to 41.0 and 42.0 to 49.6: the same shape as Railway's with a ratio of 2.0 for the worst room
  against 2.2. It is not Railway's number and not CI's (CI runs no server bench; its numbers are in
  [Performance](performance.md#the-worst-rooms-own-case-1193)).

### Decision: the bots share two places a process, `ROOM_CAPACITY` stays 3

The rule is the one of the decisions above, in the container's own terms: the worst load the settings allow has to
cost no more than the setting #712 accepted, measured beside it in the same deployment. The levers that exist are
`ROOM_CAPACITY`, `MAX_BOTS` (a room), `BOT_BUDGET` (the process; each open room takes its share) and `ALIVE_BUDGET`;
the crowd of 120 is the desktop decision of #453 and is not touched here.

| Setting | Value now | Was | Why |
| --- | --- | --- | --- |
| `ROOM_CAPACITY` | 3 | 3 | three rooms of people are what the tick holds (the control), and the bots now give way to them |
| `BOT_BUDGET` | **2** (`GameServer.DEFAULT_BOT_BUDGET`, read when the variable is not a number; 0 is no budget) | none | a lone room seats 2, two rooms 1 each, three rooms none: the worst loads are 1 x 8 + 2 (0.97 of the control), 2 x 8 + 1 (0.90) and 3 x 8 + 0 (the control) |
| `MAX_BOTS` | 7 | 7 | the host's Bots setting still asks for up to 7; the server seats what the budget gives the room |
| `ALIVE_BUDGET` | 120 | 120 | unchanged |

The three loads this allows are at or under the control in all of their runs (the last three rows of the table, in the
deployment whose host was twice as slow, and the same shape in the others). What a bigger number costs is in the table:
a lone room with 3 or 4 bots is 1.12 to 1.16 times the control, with 7 it is 1.26 and over the tick on a fifth of the
ticks; with two rooms at 80 dead, 3 bots each (2 x 8 + 3) is at the control (0.98) and at 120 dead it is not (1.16).
An operator on a faster host, or with fewer people a room, sets `BOT_BUDGET` higher; one on a slower host sets it to 0
(or `BOTS_OFF`).

**This takes the bots out of most rooms on the deployed server, and that is a decision for the maintainer to keep or
change**: the feature of #1179 (7 bots beside 8 people) holds only where the process has one room and 60 dead or fewer
(1 x 8 + 7 at 60 dead is 0.95 of the control), which `ALIVE_BUDGET` does not give a lone desktop room. The ways to
get it back, each with its cost: a cheaper room with bots (the frame built on every step is about 1.2 ms a room of the
tick; filed as an issue, not done here: it is net-code work, not capacity), `ROOM_CAPACITY` 2 with
`BOT_BUDGET` 4 (a lone room with 4 bots measured 1.12 of the control, two rooms with 2 each 1.06), a second service for
more rooms (above), or `ALIVE_BUDGET` 60 for a lone room of 15, which the desktop decision (120) argues against.

What this does not say: the people stood still (a moving, shooting room costs more: the bots' and the zombies' paths);
Railway's host changed speed 2.1 times between two deployments an hour apart, so every millisecond here is for that
hour, and the ratios are the result; a lone 15-body room was not run on a processor slower than this one; the live
`deadnight-server` was not touched (its `ROOM_CAPACITY` and `BOT_BUDGET` variables, when set, override these defaults);
a room being built while others run is not timed; the Discord proxy and a lossy link were not measured.

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
