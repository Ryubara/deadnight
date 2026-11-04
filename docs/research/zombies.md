# Zombies

How the dead are simulated, drawn and kept cheap (issue #17). Built on the kit's crowds spike (`docs/godot/crowds.md`)
and rig-sharing recipe (`docs/godot/rig-sharing.md`). Code: `game/gameplay/zombies/`; tests: `game/tests/zombies/`.

## Shape

```text
 GameRules (events)         server, no nodes                              client
 zombie_spawn_requested --> ZombieDirector --> ZombieSim --> ZombieCodec --bytes--> ZombieHorde
 zombie_removed ----------> (cap, spawn points)  ZombieBrain                         ZombieView x N
 take_hit(zone, damage) --> ZombieRulesPort --> GameRules                            AnimationThrottle
```

| Part | Does | Knows nothing of |
| --- | --- | --- |
| `ZombieBody` | one zombie as data: position, yaw, mode, target, timers, its profile (no health) | rules, nodes |
| `ZombieProfile` | what the rules made of its type: blow, knockback, windup (the telegraph), look, hit chance; from `zombie_spawn_requested`, or from the crawler type when a blast takes its legs | the sim, drawing |
| `ZombieBrain` | the state machine for one tick (static functions) | paths, nodes |
| `ZombieSim` | all zombies at a fixed 30 Hz step (whatever deltas `tick` is given): targets, repaths, separation, clearing the dead | the rules, drawing |
| `ZombiePathing`, `NavmeshPathing` | a path from A to B: straight, or `NavigationServer3D.map_get_path` | zombies |
| `ZombieDirector` | rules events in (spawn, removal), the crowd cap, the `take_hit` seam | animation |
| `ZombieRulesPort` | the one place a hit reaches `GameRules` (the rules own `ZombieState`, the health) | everything else |
| `ZombieCodec` | the zombies as 13 bytes each | the sim's internals |
| `ZombieHorde`, `ZombieView`, `ZombieRig`, `AnimationThrottle` | the client: views from decoded entries, animation | the sim |

Modes: `EMERGING` (rises 0.7 s) then `CHASE`, `ATTACK` when within 1.4 m (the blow lands 0.45 s into a 1.2 s swing,
or at the type's telegraph with the same 0.75 s of recovery after it, and only if the player is still within 1.8 m),
`STAGGER` (0.4 s, from any hit that does not kill; it loses the swing),
`DYING` (2.5 s on the ground, then cleared). A zombie keeps its target unless another player is 2 m nearer.

## What was decided

- **Health is the rules' business.** The sim has no health. A zombie is created by `zombie_spawn_requested`, falls on
  `zombie_removed` with cause `killed`, and vanishes on cause `gone`. `ZombieDirector.take_hit(zombie_id, zone, damage,
  shooter_id, melee)` is the seam for weapons: it sends `RulesAction.hit` through `ZombieRulesPort`, the rules take the
  damage off the zombie's health, pay and decide the kill (#60, merged), and the zombie only reacts to the answer
  (`zombie_damaged` staggers it, `zombie_removed` drops it).
- **No physics bodies, no `NavigationAgent3D` nodes.** The server sim is node-free, so it asks `NavigationServer3D`
  for paths directly (every 0.25 s, each zombie at its own phase) and walks them. A zombie's body for shooting is the
  analytic `Hitbox` shapes, not a collider. Avoidance is a spatial-hash push (0.8 m radius), not RVO: it is
  deterministic, runs on the server, and kept 40 zombies from stacking in the capture.
- **The dead stop a player's body, in the player simulation (#914).** Being data, they were nothing a `CharacterBody3D`
  could meet, and players ran through them. `DeadBlock` makes each living zombie a 0.4 m circle in `PlayerSimulation`
  (one-way, so a prediction a few centimetres off never fights the reconciler); the server stops each body by the dead as
  that player's client drew them; a push held 0.6 s rolls a zombie out of the way (`DeadShove`, `ZombieSim.nudge`).
  Numbers, variants and the choice: [The player and the dead](dead-contact.md).
- **The crowd cap is 40 whatever the rules ask.** The rules' alive cap grows with players (up to 46 with four); spawn
  requests beyond 40 wait in the director in order and enter as zombies fall.
- **Clients draw from bytes.** `ZombieCodec` is 2 + 13 bytes a zombie (id, position in cm, yaw, mode with a tearing
  bit, episode, speed in 0.05 m/s steps, look): 522 B for 40 zombies. The demo scene runs every tick through encode
  and decode, so what is drawn is what a remote client would draw. The message type and rate belong to the net
  protocol (`spikes/net`) and are not chosen here. What the fields cannot hold is under [Snapshot
  limits](#snapshot-limits).
- **The client never reads the server's objects.** `ZombieHorde.apply_snapshot(bytes, delta)` draws from bytes alone; the
  one number the views need from the tuning (the emerge time) is passed to `setup`. `publish` is the server half
  (encode) joined to that, for single-player.
- **A fixed step the caller cannot change.** `ZombieSim.tick(delta)` adds `delta` to a pending time and runs whole
  1/30 s steps; time that is not a positive number is ignored and a stall catches up by at most 8 steps. So a 60 Hz or
  uneven caller gives the same zombies as a 30 Hz one (before this, a 1/60 step put zombies inside solid boxes: the
  push and the path-following are tuned for 1/30). Determinism is tested on a real navigation mesh with a wall
  (`test_zombie_determinism.gd`): the same seed gives the same state hash on every one of 600 ticks, another seed does
  not, and slicing the time finer does not change it.
- **Coincident zombies part along a direction taken from their two ids** (not a random draw, not the clock) and the
  pushes on one zombie add up to at most `separation_max_speed` (4 m/s). Before, an exact overlap divided a unit
  vector by 0.001 and threw the pair 66 m in one tick; the old test offset the zombies by 0.01 m and never reached it.
- **The separation grid makes nothing (#933).** `SeparationGrid` sorts the standing zombies once a step: each is one
  `int` (its cell key times 65536, plus its place in the crowd) in a `PackedInt64Array` the engine sorts, so the three
  columns of cells a zombie reads are three runs of the list that `bsearch` finds. No `Array` per cell, no hash node,
  no `zombies.values()` copy in the step; the arrays grow to the biggest crowd and are reused. It pushes exactly as the
  grid of `Array`s did (the same sums in the same order, positions bit for bit; `SeparationReference` in the tests is the
  old pass, kept as the oracle) because a zombie reads the places the ones before it in the crowd already moved to.
  120 dead: the pass held 6 KB at its peak, now 0; `sim.separate` 385 to 334 us a step spread over 30 m and 1365 to
  1170 us piled in 3 m (`tools/bench/separation_cost.gd`, the same file runs on both commits).
- **A hit needs a zombie the sim holds.** `take_hit` rejects an id that is still waiting for room (the rules know it,
  the sim does not): no damage, no kill, no points.
- **Animation:** one `AnimationLibrary` (`zombie`: Idle, Walk, Run, Punch, HitReact, Death, and `Tear_Boards`,
  `Sprint` and `Crawl_Attack` from the extra clips' file) built once from the model and added to every model's
  player (the rig-sharing recipe); one `AnimationTree` per zombie with a state machine (move = Idle/Walk/Run/Sprint
  blended by speed, attack, crawl attack (a crawler's own: it never plays the standing punch, #971), stagger, die,
  tear).
  Every tree is advanced by hand by `AnimationThrottle` (every frame within 14 m, every 3rd to 24 m, every 6th beyond,
  every 12th off screen). A view starts its walk at a
  phase taken from its id, so a crowd does not step together.
- **Warm-up:** the library is built when the horde is set up (`ZombieRig.warm_up`, at the night's start), not when
  the first zombie appears: it loads the walker's model and the extra clips' file and holds them until the horde
  leaves. Headless, the first zombie's view took 22.3 ms cold and 0.7 ms after the warm-up (10 ms at the start)
  (`test_zombie_warm_up`); the barricades capture had a 31 ms frame at the first spawns (#245).
- **Crowd budget:** no zombie shadows, one mesh per zombie (the eyelid mesh is freed: the kit zombie has no eyelids
  here until a crowd variant merges them), sim at 30 Hz independent of the physics rate.
- **Light:** the sim asks a `lit_probe` callable at each repath and applies the rules' `speed_on_ground` (a zombie off lit
  ground is faster).

## Types in the night

The rules say what a zombie is (`ZombieType`, carried by `zombie_spawn_requested`); the night makes it so.

- **The director hands the request to the sim as a `ZombieProfile`.** The brain strikes with the profile's damage
  after its windup (the telegraph when the type has one, else the walker's 0.45 s) and the strike carries the
  knockback. `NightServer` puts the damage, the zombie's id and type, and the knockback into `player_damaged`; the
  player's own motion does not apply the knockback yet, it is recorded for that work.
- **The look travels in the frame.** One byte a zombie, so a client that joins late draws every zombie in its body from
  its first frame and a change shows: a walker crippled by a blast (`zombie_crippled`) becomes a crawler in the sim
  (its type's numbers, `speed_scale` of its speed, once) and the horde swaps the view's body. A crawler plays the kit's
  `Crawl` clip (the legless mesh is made for it); every look has one body in `zombie_<look>.glb`.
- **Game scale.** Every body is drawn at `ZombieModels.GAME_SCALE` (1.3, the style bible's), on top of its variant's
  height: the walker stands 1.77 m, the brute 2.09 m, the headliner 2.56 m, which is what the hit zones are sized for.
  Until the headliner's pull request the night drew them at the file's size (about 1.36 m for a walker), so the zones
  stood a third above the bodies; the captures had always applied the scale and hid it.
- **Hit zones take the zombie's size and pose.** `Hitbox.shapes(position, yaw, scale, weak, set)` sizes the set about
  the feet; the scale is the look's height (brute 1.18, runner 1.07) times the type's `hit_chance` when it stands (a
  crawler's zones are its body on the ground, so its 0.6 does not shrink them again), and the set is the look's, in
  the pose its mode and speed put it in (`ZombiePose`: moving, running, sprinting, striking, staggering, tearing,
  roaring), fitted to the skinned mesh ([hit zones](hit-zones.md)). The server sends both with each target
  (`"scale"`, `"pose"`, from `ZombieBody.hit_target`), the lag compensator keeps them, and the bots aim at the height
  the look stands at (a crawler's is low). Grenade blasts still use the six standing shapes.
- `barrier_speed` is carried on the profile and read at the fence's boards ([below](#the-fences-boards)).

## The fence's boards

How a zombie is held at a breach, and what we learned making it (#155):

- **The gate is the simulation's, not physics'.** Zombies are not bodies, so nothing "blocks" them: a zombie spawned
  at a field marker outside a breach carries the breach's id (`ZombieBody.gate_id`), and `ZombieSim` clamps its walk
  to 0.9 m short of the boards while the rules' count (`ZombieSim.barricades`) is above 0. It tears while it stands
  there, by entering the `ATTACK` mode again at the end of each swing, sets `tearing` (the mode byte's top bit on the
  wire, so a client plays `Tear_Boards` and not the punch: [Tearing boards](../design/zombies.md#tearing-boards)), and
  adds `delta * barrier_speed` to its progress; every `seconds_per_board` it reports `zombie_tore`, and the director
  turns that into the `tear_board` action. Two zombies at one breach both work on it, so a crowd is quicker.
- **The sim reads the rules' `BarricadeState`**, the plain data of how many boards stand at each breach, and never
  changes it: only the `tear_board` action does. It holds the object, not a `Callable` into the rules, so it needs no
  engine and a test hands it a state with the boards set.
- **Quitting while a door's navigation bake runs kills the engine.** `autopilot_night.tscn --rounds=1` (the CI step
  that plays a night headless) printed its report and then died with `corrupted size vs. prev_size in fastbins` (exit
  134, a segmentation fault locally) whenever the bot had just bought a door: the bake is on a worker thread and the
  quit does not wait for it. It is older than the boards (on `main`, `--rounds=3` does it too); the boards only moved
  the bot's purchase into round 1. The capture now waits for `DoorNavigation.is_busy()` to clear before it quits. A
  GdUnit4 suite does the same when its night buys a door and is freed at once (a segmentation fault after "PASSED"):
  `NightFixture.settle_bake` waits for the bake first.
- **Separation can push a zombie across the line**, so the clamp also runs after the crowd push. A test packs twelve
  zombies against the boards and none gets through.
- **A zombie in reach of a player strikes them** through the boards: standing at them is a risk, which is the point.
- **Boards are not CSG.** `NavmeshBaker` bakes every CSG box with collision, so a `CSGBox3D` board would shut the gap
  in the navigation mesh and the dead outside would have no path. They are `StaticBody3D`s on layer 2 (players' bodies
  get that bit in their mask in `NightWorld.add_body`); shots and grenades only look at layer 1, so they pass through
  the boards and a zombie at them can be shot.
- **The apron is ground the mesh needs.** The field's ground ends at the fence line; the dead's spawns outside it
  needed floor of their own, walled in on three sides.
- **`Transform3D` in a `.tscn` is written row by row**, so the third axis of a yawed node is the third *column*:
  `Transform3D(c, 0, s, 0, 1, 0, -s, 0, c, ...)` turns the node by `atan2(s, c)` and its +Z points at `(s, 0, c)`. The
  greybox builder got a breach's facing wrong the first time (depth read inside-out), and only a test of
  "spawn markers stand outside their breach" caught it.
- **A ray through boards needs the board's height.** The boards are 0.45 m with 0.15 m between, so a test ray at 1.2 m
  went through a gap and the test passed for the wrong reason before a negative control (the shot layer must see no
  boards, the board layer must) was written at a board's middle.

## The headliner in the night

The Projectionist (`zombie_boss.glb`, `docs/design/zombies.md#boss-the-projectionist`) is the look `headliner`, the last
of `ZombieModels.VARIANTS`. What the night does with it:

- **Clips.** `ZombieRig.attach_boss` gives it its own library (`Boss_*` and its own `Idle`) and machine: `Idle` and
  `Boss_Walk` blended by speed, `Boss_Roar` for the entrance, `Boss_Attack`, `Boss_Stagger`, `Boss_Death`. It does not
  sink into the ground: it appears roaring for `ZombieTuning.boss_entrance_seconds` (2.75 s, the clip's length) and
  chases after.
- **The blow lands on the telegraph.** The sim strikes `telegraph_seconds` (1.2 s) into the swing; the clip's `hit`
  event is at frame 32 (1.33 s), so the view plays `Boss_Attack` at 1.33 / 1.2 the speed through an
  `AnimationNodeTimeScale`. The client is told the telegraph per look (`NightView.setup`, from the roster), like the
  emerge time.
- **The lamp.** The model's emission map lights the lens. It is one material shared by every instance of the file, so
  each boss view gives itself a copy (near and far mesh) and puts it out at `Boss_Death`. No light node: the lot has
  lamps enough for the Compatibility renderer's budget.
- **The weak spot is a hit zone.** `Hitbox.WEAK_ZONE`: a 0.22 m ball (0.15 in a walker's units) 1.68 m up and 0.42 m
  ahead of its feet at the boss's size, where the lens is in the walk (measured with the model at game scale: the lens
  is 1.56 to 1.80 m up and 0.44 to 0.56 m ahead through `Boss_Walk`, higher with the arms raised, lower in the
  stagger). It is added only for a target with `"weak": true` (the director sets it from the roster's
  `weak_multiplier`), last in the shape list so the blast model's indices do not move. It sits ahead of the body
  capsule, so a shot from the front finds it first and one from behind never does. The weapons send `weak`, the
  rules take x2.2 and pay it as a headshot.
- **Stagger.** A weak hit that does not kill staggers the boss (`Boss_Stagger`, 1.42 s) and costs it its swing, once
  every `boss_stagger_cooldown` (6 s): a rifle that hits the lamp every shot must not hold it still for ever. No other
  hit staggers it (nor, in the night, any other zombie: the night never called the sim's `react_to_hit`).
- **The boss bar** (`HudBossBar`) follows `zombie_spawn_requested` (boss), `zombie_damaged` and `zombie_removed` in
  `HudState.bosses`, one bar a boss, under the banner.

## Snapshot limits

`ZombieCodec` fits 40 zombies in 522 bytes by spending few bits on each field. What a field cannot hold is pinned by
a test (`test_zombie_director.gd`); the encoder clamps only the speed.

| Field | Range | Past it |
| --- | --- | --- |
| id (u16) | 0 to 65535 | aliases: 65536 reads back as 0, 70000 as 4464. The rules never reuse an id, so a match would need 65 536 zombies; widen the field before a mode that gets near |
| position per axis (s16, cm) | -327.68 to 327.67 m from the world origin | wraps: 328 m reads back as -327.36 m. The lot's areas are about 120 m across ([the map](../design/map.md)); a bigger map moves its origin or widens the field |
| yaw (u8) | 256 steps of 1.4 degrees | rounds |
| speed (u8) | 0 to 12.75 m/s in 0.05 steps | capped |
| episode (u8) | 0 to 255 | wraps on purpose: only a change matters |
| look (u8) | the index in `ZombieModels.LOOKS` (append only) | an unknown index draws a walker |
| count (u16) | 65535 | a packet that says more than it holds is dropped |

## Numbers

Machine: Windows 11, RTX 5080, Godot 4.7.2, Compatibility; the greybox lot with 2 players, 40 zombies chasing and
being shot, `--fixed-fps 60`, 400 frames after 120 of warm-up, wall-clock frame time. The windowed run is capped by
the monitor's 240 Hz (4.17 ms is the floor), as in the crowds spike.

| Measure | Result | Crowds spike (40 zombies, same kind of machine) |
| --- | --- | --- |
| Sim step alone, 40 zombies, straight-line pathing (test) | 0.40 ms per 30 Hz tick | not measured |
| Sim step alone, 40 zombies, `NavmeshPathing` on the lot (headless, a loaded machine) | 0.65 to 0.75 ms per tick | not measured |
| Headless frame, whole zombie code and views | 20: 0.52, 30: 0.77, 40: 0.95 ms (empty lot: 0.02 ms) | 40: baseline 3.87, all techniques 1.47 ms |
| Windowed frame, 40 zombies | 4.19 ms mean (on the 240 Hz display floor, so it says nothing; read the percentile), 7.1 ms 95th percentile | 40: baseline 6.48, all techniques 2.69 ms |
| Windowed frame, empty lot | 4.17 ms mean (the floor), 5.1 ms 95th percentile | empty scene 0.72 ms |
| Draw calls, 40 zombies / empty lot | 126 / 92 | 84 at 40 zombies (no lot) |
| Animation trees advanced per frame | 11 to 13 of 41 | |
| Snapshot | 482 to 530 B | |

Script cost per zombie is about 0.024 ms against the spike's roughly 0.1 ms, which is the throttle, the 30 Hz step and
no physics body. The full-frame cost sits under the display floor here, so the 95th percentile (the lot alone 5.1 ms,
with zombies 7.1 ms) is the number to watch; the browser was **not** measured: the spike's factor of about 3 applies
until it is.

## The glide between snapshots (#105)

A client of a server is sent the zombies every second physics tick (`NightHost.SEND_EVERY`, 30 Hz), and a view that
was set to each entry stood still every other tick: a zombie at 3 m/s moved 0 and 10 cm in turn (`physics_interpolation`
smooths only between ticks that set a position). `ZombieView` now walks to an entry over the physics ticks since the last
one (`GLIDE_MAX_TICKS`, up to 6; a longer stall, a jump over 4 m or a first entry sets it down at once), so it moves
5 cm a tick, one entry (33 ms) behind the server. A view fed every tick, as on the loopback of single-player, is set at
once as before. A parked body forgets where it was, so its next life starts where its first entry says. Pinned by
`tests/zombies/test_zombie_glide.gd` (the steps of a 30 Hz run are within 0.045 to 0.055 m; before they were 0 and 0.1).

## Doors

The lot's purchase doors are CSG slabs, and the navigation mesh is baked from the CSG boxes, so a closed slab is a
wall to the dead. It stops being one the moment the rules emit `door_opened`, and two things follow, both on the
server:

- `LotDoors` (on the greybox's `Doors` node, `bind(rules)`) frees the door's slabs and label. The player walks
  through, shots pass.
- `DoorNavigation` puts the mesh of the lot as it now stands into the region (below: a saved one).
  Only for a lot nothing was saved for it falls back to `NavmeshBaker.bake_async`, which reads the CSG boxes at once
  and bakes on the navigation server's worker threads (about a second for the lot); the finished mesh replaces the
  region's, and zombies walk the old mesh until it lands. Doors bought while a bake runs mark it stale and one more
  bake follows, so the mesh always ends up matching the last door. The first mesh is set in `setup(lot, doors)`,
  with the doors as they stand, so a restored night starts with the right mesh.

### The meshes are baked ahead of time (#335)

Baking the lot (0.25 m cells over 140 x 125 m) takes about half a second, on a desktop and in the browser alike
(measured in Chrome: 470 to 630 ms). The web export has no worker threads (`thread_support=false`), so an "async" bake
runs on the main thread: one half-second frame at the start of the night and another at every door bought. Issue #335
blamed an 11 to 13 s freeze on it; it was not the bake (see [what the long frame was](#what-the-long-frame-was)). So
nothing is baked while the game runs:

- `tools/world/bake_lot_navmeshes.gd` (`godot --headless --path game -s res://tools/world/bake_lot_navmeshes.gd`)
  builds the lot the way the night does, opens each set of doors the shop can sell (nine: the concession first, then
  the booth, back lot and road in a chain, and the yard beside them) and bakes each. The nine meshes (about 2,500
  polygons each, 210 KB together, compressed) are `world/drive_in/lot_navmeshes.res`, a `LotNavmeshes` resource.
- A mesh is found by the **key of the geometry** it was baked from, not by door names: `NavmeshBaker.key` is a SHA-256
  of the baker's input (the boxes' faces to the millimetre) and the cell and agent sizes. `DoorNavigation` hashes the
  lot as it stands, at `setup` and at each `door_opened`, and swaps the saved mesh in at once (`baked` is emitted, no
  worker, `is_busy` stays false). A lot that changed finds nothing and is baked at run time as before, with a warning.
- Doors need no obstacles or links: the saved meshes are the very meshes a rebake makes, so the path the dead walk
  after a purchase is the one they walked (`test_lot_navmeshes.gd` compares every vertex and polygon).
- **After any change to the lot's collision boxes (a prop, a wall, a door) run the tool and commit the .res.**
  `tests/zombies/test_lot_navmeshes.gd` fails until you do (it names the tool). Changing the baker's sizes
  (`CELL_SIZE`, `AGENT_*`) does the same.

The cost in the browser, measured by `tools/web_smoke/door_swap.py` (it exports a copy of the project that starts on
`tests/captures/door_swap_bench.tscn`, builds the lot, joins the navigation and buys every door in turn; Chrome 156 with
a real GPU, RTX 5080, three runs, medians):

| In the browser | Saved meshes (the game) | Baked at run time (before) |
| --- | --- | --- |
| `DoorNavigation.setup`, the night's first mesh | 15 ms (7 ms to load the file) | 594 ms |
| A door bought: the call that opens it | 10 ms | 365 ms |
| A door bought: longest frame after it | 15 ms (worst 16 ms of 15 doors) | 370 ms (worst 474 ms) |

The map answers one physics frame after the mesh is set, so the night no longer waits for it. `first_use.py`'s marks
put "lot: settled" to "lot: navigation ready" at 40 ms in a whole Play. What is left of the frames over a second
between Play and a running night is the lot's first draw, not navigation
([First-use hitches](first-use-hitches.md#the-first-draw-of-the-lot-347)).

### What the long frame was

- **The wait for the map.** `NightWorld.build` waited for the navigation map's iteration id to move two steps. In
  the browser it stays at 1 while the map already answers, so the wait ran out its 600 frames: 10 s of the loading
  screen before every night. It now waits until the map finds a way across the field (`_map_answers`). Play to a
  running night went from 23.6 to 24.0 s to 10.8 to 11.3 s (Chrome, GPU, three fresh profiles each).
- **The first draw of the lot.** The 9 to 12 s frame that remains (10.9 to 11.2 s before, 9.0 to 9.4 s after, 11 to
  12 s with the warm-up of #339 on top) is the first frame in which the night's 3D scene is drawn: the browser
  compiles every shader of the lot at its first draw call, in that one frame. Found by timing the `await
  process_frame` in the warm-up's sound loop (11.7 s for one frame) and the bake (0.5 s). The warm-up's own lot pass
  afterwards costs about a second, so the programs are built by the time it starts. The loading bar cannot move in
  that frame; drawing the lot in pieces over several frames is the way to shorten it.

What was tried first: a disabled `NavigationLink3D` across each slab, switched on when the door opens. It joins the
two sides, but the baked mesh leaves a band without mesh round a closed slab (the slab and the agent radius on each
side, 1.3 m), and a zombie standing in the band is snapped back to the nearer edge at its next repath, 0.25 s later.
At 3 m/s it covers 0.75 m, short of the band's far half, so it walked back and forth on the link for ever (measured:
it stood at the door of the concession for 30 s). Links work only for an agent that keeps its path across them. A
rebake has no band and needs no change in the sim.

The night uses exactly this path: `NightWorld.build` bakes the first mesh through `DoorNavigation.setup`,
`NightServer` binds the lot to its rules (`NightWorld.bind` is `LotDoors.bind`) and takes the open areas for the
spawns from the doors that are open. The night's own rebake (a synchronous bake per door, which stalled the tick)
was removed. A night that ends while a bake runs is harmless: `NavmeshBaker.bake_async` skips a callback whose object
is gone. The autopilot's own path follows the mesh, so for the second after a purchase it walks the old one.

A finished bake is in the region at once but reaches the map over the next physics ticks (the server iterates the map
on a thread): 3 to 12 ticks after the `baked` signal on a loaded machine, so a test that waits a fixed few frames after
a bake races the machine. #192: with 8 suites at once next to 40 busy loops, 16 of 16 runs failed the each-bought-door
test, 13 the quick-succession one and 12 the on-its-way one. `map_force_update` does not shorten it, and the iteration
id counts changes, not readiness (a bake moved it by one here). The suite waits for the answer it is about:
`_map_current` polls the physics frames until the points the new mesh opens are reachable.

Proof: `game/tests/zombies/test_door_navigation.gd` (for each of the nine sets of doors a zombie reaches every sample
point of every open area and no path enters the footprint of a closed one; the doors bought one after the other
through `GameRules`; a walking zombie gets in once the booth is bought; doors bought in quick succession end with the
last in the mesh; and the control: a slab freed without a rebake leaves the dead outside) and
`game/tests/world/test_lot_doors.gd` (a purchase through the rules removes the slabs, the collision and the label).

### Walking to a door: the stands (#590)

A door's slab is no place to walk to. The mesh is cut back 0.5 m from a wall on both sides alike, so the slab's middle
lies between two cut edges, and `map_get_closest_point` (which every goal is snapped by, a bot's too) picks the nearer in
3 D by a few centimetres of rounding. The booth's door (0, 1.3, 22.2) snapped to the shut booth's floor (0, 0.35, 22.75)
instead of the midway at z 21.3: with only the concession open, the path from the field ended at (6.75, 0.35, 22.2),
6.75 m short, and bots never bought it. The mesh itself is right: (0, 21) is reachable. Every other door's middle was
only 1.2 m off, which is why only the booth stalled. A person is not affected: a hand reaches 3.2 m from the slab's
middle (`NightTuning.use_reach`) and the body stands at z 21.3.

Each slab has a `Stand*` marker on the open side, 1.5 m out (`slab()` in `tools/world/build_greybox.py`, with the side
the door is bought from), and `NightWorld.door_stands(door_id)` returns them. Anything that walks to a door (bots)
walks to a stand; `door_points` stays the place the hand reaches from, the HUD marker and the sound.
`tests/night/test_door_stands.gd` buys every door in the shop's order from its stands, each with the doors before it
open: the path ends within 2.5 m, a body on the stand is offered the door, a use press buys it. The slab's middle
fails it for the booth (6.75 m short). Picture: `tests/captures/door_stand_mesh.tscn` (`--target=slab|stand`).

### Dead standing at the concession door (#591)

Found by the shopping soak of the bots plan (`tests/captures/bots_shop_soak.tscn`): from round 2 on, three to six dead
stood still at (-2, -3) and (9, -3), beside the concession door, in chase mode with no gate, for minutes, and the round
never ended. The trace and a dump of the same night (seed 1, four bots, health x4, 3000 points each, 8 game minutes)
say why:

- **The map was the one baked before the door was bought.** The soak steps the night in a loop of `tick()` calls and
  never gives the engine a physics frame. The navigation server takes a new mesh in only on a physics frame, so the
  concession was bought (the lot's slab freed, `DoorNavigation` swapped the saved mesh into the region) and the map
  stayed as it was for the whole night: a query on the live map still found no mesh across the door gap (z -3.5 and -3.25
  at x -1 to 1), the concession's floor an island of its own. A night stepped by hand stands in no physics frame, and
  the server, which steps one tick a physics frame, has the mesh a few ticks after the purchase
  (`NavigationServer3D.map_force_update` does not shorten it, measured here).
- **The dead rose on that island.** `NightWorld.open_areas` put the midway's spawn points in at the purchase. A dead
  one risen there asks for a path to a bot on the field, gets the island's nearest point to it (`map_get_path` ends at
  the closest point of the part it can walk), walks there and stays: the inner face of the front wall, at z -3.25 (the
  slab's z -3.6 and 0.15 half thickness, 0.5 m of cut-back), at the x of the bot they were after: Z45 (3.89, -3.25) with
  the target at (3.93, -21.8); a path of two points, the second at (3.93, 0.35, -3.25); the same path on a fresh query.
  Others at (12.25, -3.25), after a 35-point walk from the west alley, and against the yard's north wall (54, -3)
  once the yard was bought. Never a breach (`gate_id` empty), and none of them could reach the bots, who stood on the field.
- **Not a fault of the mesh or of the dead's walking.** The same night with a physics frame every 30 ticks (the map
  takes each door in): no dead left standing, none swept, rounds ending after 63, 135, 200 and 267 s.

The fix on the zombie side: the dead rise only where the map walks to. `NightWorld.spawn_points` holds an open
area's spawn markers back until a path from the field reaches every one of them (`NAV_REACHED`), and the night asks
again every 15 ticks (`NightServer.SPAWN_RETRY_TICKS`, which replaced the server's own handler of `door_opened`), so
the area joins a few ticks after the purchase on a server, and never in a night with no frames (nobody can walk out
of it there either). The same guard holds in a bake (a lot nothing was saved for) that takes a second or more. The
soak must give the engine its frames too (it does not yet, #228): a night stepped by hand cannot test a door, and a
bot's errand to a bought door is judged on the map the purchase left.

Proof: `game/tests/night/test_spawns_wait_for_the_map.gd` (no spawns in the new room straight after the purchase or in
600 ticks without frames; they join with frames; every door of the shop in order gives its area's markers to the dead).

### A dead tearing the boards of a window it was not at (#810)

A night stopped closing a round: one dead left, `mode ATTACK g=start_4 tear=0.1..0.9`, a metre and a half outside the
east wall of the second map between windows 4 and 5, out of sight, and the bot's note `boards start_4` for eight
minutes (mend, tear, mend). A `ZombieGate` was a line across the gap with no width, so on a wall of windows it was the
whole wall: a dead that came for window 4 and whose path led along the wall to window 5 met the clamp 0.9 m short of
the line, 5 m from window 4's gap, and stood there tearing window 4's boards at the rate the bot mended them. (The
lot's breaches were the same kind of line.) A night is not repeatable by seed, so the stall is found by sets of nights.

A gate now has the width of its gap (`ZombieGate.half_width`, the barricade's `board_half`): a zombie is held and
tears only while it is within that width and `ZombieGate.SPAN_SLACK` (0.5 m) of it. When it leaves that width its
`gate_id` is not kept: it takes the gate whose gap it has come up to (outside the line, within `ZombieGate.REACH`,
1.5 m, and in front of the gap), or none while it walks beside the wall. `_keep_outside_the_boards` and the strand
watch use the same width. Proof: `game/tests/zombies/test_zombie_gates.gd`, two windows on one wall and a path along
it (the dead beside the wall tears nothing, takes the far window's gate when it comes to it, walks through once that
is open).

### Dead stranded in a pocket of the mesh (#770)

The nightly soak's Follow nights ended three times by its "a round of eight minutes" stop with one dead walker alive:
`mode CHASE`, no gate, `y -0.5`, standing for minutes 15 m from the person it chased, at (4.0, -52.8), (-66.2, 14.8)
and (27.5, -60.5). The same query as in the section above says why: `map_get_path` from there is **two points**, the
second at the pocket's edge (4.0, -53), and a grid of the lot's mesh finds stretches (the strip behind the screen, z
below -53, and the strips beside the fence) that the walking mesh does not join to the field. The spawn points are
joined to it, so how a dead one gets in is not proved (the sim moves the dead without colliding with walls: a crowd's
push or a cut corner near a spawn point can take one across a wall's line); once in, it walks to the end of a path
that goes nowhere and stays, and nothing a bot does reaches it: the pocket is a pocket for a bot too. A night is not
repeatable by seed (the bake finishes on a physics frame), so it was read from the trace of the nights that broke
(`bots_soak.tscn --tail=180`: one line every few seconds of a long round with every zombie's place, mode, target and
path).

The fix is on the zombie side. `ZombieSim` counts, for a chasing zombie with no gate and no lure, the seconds in which
the path it was given ends `STRAND_GAP` (3 m) or more short of its target and the target is `STRAND_FAR` (12 m) or
more away; at `STRAND_SECONDS` (12 s) it says `zombie_stranded` and `ZombieDirector` puts it back on a spawn point
(`ZombieSim.relocate`: it rises as a new one does, with no path). A zombie near its target (a car roof, a prop), at
its boards or with a way to the target is never counted. `director.relocated` counts them (the soak's nights report
it).

Proof: `game/tests/zombies/test_zombie_strand.gd` (the counting, on a pathing that stops short) and
`game/tests/night/test_zombie_stranded.gd` (in the real lot: a zombie put in the pocket at (4.0, -0.5, -52.8) reaches the
person; without the fix it stands there).

### A round that waits on its last dead (#950)

The performance sweep's two 30-minute solo nights (the autopilot and three bots, 1x) had rounds with one to three dead
standing for a minute or more, once seven minutes (round 16, minute 23 to the end). The soak says why in a day of
nights: `bots_soak.tscn --person --bots=3 --tail=30 --detail` prints, every few seconds of a long round, each dead's
place, mode, target, path (`--detail`: its points, its gate, whether it tears, whether each player has a line to it,
the boards of its gate), and `SoakWatch` counts the seconds a round stands down to its last three (`tail_longest`, a
gate at 150 s) and the longest round (`round_longest`). Two causes, neither a bot's fault, and a net under them:

| Found | What it was | Fix | Proof |
| --- | --- | --- | --- |
| Small map, `small_indoor` seed 16 round 3: one dead for 147 s (the nights then went on to 188 s and 198 s); the window was `upper_b2`, which #964 has since taken away | A walker at the left jamb of window `upper_b2`, 1.0 m from the gap's middle, ATTACK, tearing a board in 1.2 s; the person stood at the same jamb on the inside and put one back every 1.0 s (the autopilot mends when it has nothing to shoot, and the jamb is between them: `sight` 0.4 m). `board_torn` and `board_repaired` rose together, 11 apart, boards at 5 | `ZombieSim` counts the seconds a zombie tears at one gate without getting through (`siege_seconds`); at `SIEGE_SECONDS` (30) it says `zombie_burst`, `ZombieDirector` tears every board that stands (`ZombieRulesPort.tear_all`) and the zombie has no gate any more, so a board put back at once does not shut it out again. A hit on it starts the count over | `test_zombie_siege.gd`; `test_round_tail.gd` (seated night on the second map: a person holding the use button behind the jamb of `side_2`, a dead in front of it; on `main` the boards stand at 5 for the 75 s it runs, with the fix the round ends inside that limit) |
| Lot, seed 4 round 4: six dead for seven minutes (the rounds ran on to the 3-minute stop) | The person hugged two parked cars (`Row1/Car03`, `Car04`), 7 m from the six. The target is off the mesh, `map_get_path` snaps it to the nearest mesh point, and that flips from one side of the car to the other as the person moves a metre: west route 10 m, east route 29 m, `path` of 6 to 11 points one second and 20 to 23 the next. Every repath (0.25 s) turned them round; they walked up and down at full speed, never stranded (the gap was under 1.2 m) | `ZombieSim._keeps_its_route`: a new route 6 m longer than what is left of the old one is not taken while the old one still ends within 3.5 m of the target and there is more than 1 m of it left to walk | `test_zombie_route.gd` |
| The net | Anything else that stops the last dead being fought: a pocket, a jamb, a roost | With the marked few left (`mark_last`) and no blow struck, no damage done and no kill for 30 s (`ZombieDirector.RESCUE_AFTER`), a dead whose path stops 3 m or more short of its target rises at the spawn point nearest the people that is 25 m or more from them (the farthest when none is) and not at the breach it stood at (`ZombieDirector._watch_the_tail`; `director.rescued` counts them). One with a way is left alone (the first version did not look: a headliner slowly following a person is coming, and moving it would only lengthen the round) | `test_zombie_rescue.gd` (the wait, a hit putting it off, a dead with a way, a map with no far point, more than the marked few left, a break) |

The first version of the seated test put the autopilot at the window's repair spot: it shot the dead at once and the test
passed on `main` too. At the soak's own coordinates, (8.2, 3.5, -7.4), it stood pressed against the jamb for the whole
stall, so the test now holds the use button itself, in front of the jamb, and does not depend on the autopilot. After
the second map's windows were reworked (#964) `upper_b2` no longer exists, so the test takes its window from the map
(`side_2`: the gate's middle, 1.0 m along the wall for the dead and the person) and was run on `main` again to see it
stall. A test of a stall takes its coordinates from the log and is run on `main` after every merge of the map.

Soak, before and after (regular bots and a person stand-in, three bots, `--stall-minutes=6`, seeds 11 to 18 and 21 to
28 on each map, the commit before the change against this one with only the soak's own instruments on both; a night
is not repeatable by seed, so these are sets, not pairs). The round is the active stretch, the tail the stretch with
three dead or fewer left:

| | Nights | Longest round, max / median | Longest tail, max / median | Tails over 150 s | Stopped as stalled |
| --- | ---: | ---: | ---: | ---: | ---: |
| Small map, before | 16 | 242 s / 84 s | 198 s / 56 s | 2 | 0 |
| Small map, after | 16 | 91 s / 70 s | 63 s / 41 s | 0 | 0 |
| Lot, before | 16 | 360 s / 143 s | 120 s / 57 s | 0 | 1 |
| Lot, after | 16 | 208 s / 137 s | 126 s / 63 s | 0 | 0 |
| Veteran bots, small map, before (seeds 31, 32) | 2 | 360 s / 210 s | 320 s / 178 s | 1 | 1 |
| Veteran bots, small map, after (seeds 31, 32) | 2 | 63 s / 61 s | 36 s / 26 s | 0 | 0 |
| Veteran bots, lot, before (seeds 31, 32, and a third night of 31) | 3 | 348 s / 117 s | 55 s / 44 s | 0 | 1 |
| Veteran bots, lot, after (seeds 31, 32) | 2 | 360 s / 270 s | 96 s / 76 s | 0 | 1 |

These sets ran with the first version of the burst, in which the boards came off and the zombie kept its gate; the seated
test showed a hand that puts one board back at once could hold it again, so the zombie now leaves its gate when it
bursts.

After merging main (the second map's windows reworked, #964) four more nights on each map (seeds 41 to 44) ran on the
final code but for the rescue's first version: the lot's longest round was 141 s and longest tail 68 s; the small map's
tails were 22, 33 and 23 s and one of **201 s** (seed 41, round 5, and it repeats by seed): a walker standing at (1.5,
-6.5) for three minutes with a path of one or two points that ended 3 to 13 m short of whoever it chased (a pocket), while
two headliners were fought. The strand watch did not catch it, because a map this small has someone within 12 m of
every dead (`STRAND_FAR`), and the rescue did not either: it wanted a spawn point 25 m or more from every person and the
small map has none. The rescue now leaves a dead with a way alone (a headliner after a person is coming), takes the
farthest point when none is 25 m away, and waits 30 s; the same night then stood **95 s** on its
last three (30 s of waiting, the walk in, the fight). The strand watch's blindness near people is left open.

The veteran small-map night before the change stood 320 s on its last three dead in round 6 (its tail lines were not
printed, so its cause is not read; it is the kind the siege and the rescue are for). The one stopped veteran night after
the change (the lot, round 19, 360 s) is a late round of 18 dead against bots that are down or dry (`end` of the report:
every gun at 0), a long fight, not a last dead stood on. The third lot night before the change (round 9, 348 s, 44 s of
tail; a debug run with the tail printed) shows the cars' flips: paths of 4 to 12 points one second and 34 to 37 the next.
The lot's longest tails (120 to 126 s) are boss rounds (round 5) in which the stand-in person has an empty pistol and
the two headliners follow it at a walk while the bots are elsewhere: a fight that is long, not stuck (the dead are
closing on a person every second); the gate is set above it. The rescue never fired in the nights that report it (the
16 of seeds 21 to 28 and the 4 veteran ones: `rescued` is 0 in each): the siege and the route fix took the two causes
found, and the net is proved by its test only.

## Left open

- Browser and weak-machine measurement of the full scene: done in the browser (Chrome with a GPU, and the processor
  slowed 4 times as a weak laptop's stand-in): [the crowd by system](crowd-budget.md#the-browser-by-system-and-on-a-weak-processor-105)
  and [the autopilot night](web-export.md#big-crowds-in-the-browser-from-the-autopilot-171). A real weak laptop and
  Firefox are still not measured.
- Client interpolation between 30 Hz snapshots: done as a glide (below). The views are still one snapshot behind.
- The model: done in #90. The views wear the committed variants (`ZombieModels`, walker by default; `ZombieHorde.variant`
  or `ZombieModels.scene(name)` picks another). Each variant has a near and a far mesh; `ZombieView` swaps them with
  visibility ranges at 18 m, so one mesh is drawn per zombie. Choosing a variant per zombie (by round or role) is
  the director's, still open. A body with other bone names needs the rig-sharing retarget player.
- Hit reactions by zone, crawlers, window break-ins: the animation set is #40's.
- The navmesh is baked ahead of time from the greybox's CSG boxes, one for each set of doors ([Doors](#doors)); only a
  lot nothing was saved for is baked at run time (half a second in the browser). Heights follow the path ([Climbing](#climbing)).
- Spawn point choice ignores whether an area is open (the rules' design): `spawn_points` is whatever the caller gives.

## Climbing

Players said the dead had trouble going upstairs (#681). On the booth's ramp (25 degrees, 2 m wide, the roost's one way
up) a pack sent at a person on the roost climbed nothing: **0 of 6 at the top in 40 s**, from the ramp's foot and from the
booth door, and 0 of 16 for a bigger pack; the small map's two stairs the same (0 of 6 each).

- **Cause:** the sim kept every zombie at the height it spawned at ("the lot is flat"), but the lot is not. A zombie
  walked the path's x and z at y = 0 while the ramp rose over it. Each repath (4 a second) snapped that ground-level
  position to the *nearest* point of the mesh, and a little way up the ramp (z 25) the nearest point was the floor beside
  and under it (1.1 m off) rather than the ramp surface (1.8 m over its head). The path from the floor led back to the
  ramp's foot, so every zombie of the pack shuffled between z 23 and 25 for as long as the run lasted. The earlier tests
  never saw it: the bots' ramp test walks a physics body, the walk soaks use players, and the sim's own tests ran on a
  flat field.
- **Fix:** `ZombieSim._settle_on_ground` reads the floor off the path (the segment ending at the zombie's waypoint, by
  where it stands along it), takes off the baker's offset (`NavmeshPathing.GROUND_OFFSET`, 0.4 m: flat ground measures
  0.35, the roost 0.45, the ramp 0.4 to 0.5) and moves the zombie there at `climb_speed` (6 m/s, so a 45 degree stair is
  fine). A straight-line path (`ZombiePathing` base, the tests') has no offset (`NAN`) and keeps the height as before.
  With a true height the repath snaps to the right layer.
- **What a height changes elsewhere:** zombies more than `separation_height` (1 m) apart in height do not push each
  other (the ramp over the floor beside it shared one x/z); and a swing needs the person within `reach_height` (2 m) of
  the zombie's height, or the dead under the roost's floor would hit the person standing over their heads.
- **Measured** (`tests/zombies/test_zombie_climb.gd`, six at 2.4 m/s, two abreast, the person on the roost; time until the
  last zombie stands on the roost): ramp from its foot 5.6 s (first 2.5 s), from the booth door 6.3 s, sixteen from the
  door 8.0 s; small map stair A 11.7 s, stair B 8.8 s. The longest any of them went without rising: 0.32 s. Before: never
  (the test's control walks the same mesh with the heights left out, and the same file failed on `main`).
- **Left open:** the views draw the zombie at its snapshot height, so a zombie on a ramp walks the ramp, but its feet
  are placed within about 0.1 m of the surface (the baker rounds heights to a quarter of a cell).

## The navigation map is not synchronised on a thread (#733, #736)

The server's dead path over the world's navigation map, so `NightWorld.build` turns
`NavigationServer3D.map_set_use_async_iterations` off for it. With the default on, a run that sold every link in one
loop (three saved meshes swapped into the region in one go) sometimes ended on a map lacking the last doors: the
dead's paths stopped 3 m short of the players, the upper floor and the side room cut off, and they stood still. It
failed a CI shard of `test_smallmap_windows` (7 of 12 windows torn) and about one run in two of
`test_smallmap_bot_night`'s four bots. Six runs of `tests/world/smallmap` passed after it. The suite
`test_smallmap_windows` asserts the setting and that a path from every window ends at the hall.

## Reproduce

```text
godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/zombies -c --ignoreHeadlessMode
godot --path game res://tests/captures/zombie_chase.tscn --fixed-fps 10 --write-movie out/chase.png --quit-after 250 -- --warmup=30
godot [--headless] --path game res://tests/captures/zombie_chase.tscn --fixed-fps 60 -- --warmup=30 --bench --zombies=40
```
