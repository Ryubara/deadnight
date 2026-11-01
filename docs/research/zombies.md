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
- **A hit needs a zombie the sim holds.** `take_hit` rejects an id that is still waiting for room (the rules know it,
  the sim does not): no damage, no kill, no points.
- **Animation:** one `AnimationLibrary` (`zombie`: Idle, Walk, Run, Punch, HitReact, Death, and `Tear_Boards` from the
  extra clips' file) built once from the model and added to every model's player (the rig-sharing recipe); one
  `AnimationTree` per zombie with a state machine (move = Idle/Walk/Run blended by speed, attack, stagger, die, tear).
  Every tree is advanced by hand by `AnimationThrottle` (every frame within 14 m, every 3rd to 24 m, every 6th beyond,
  every 12th off screen). A view starts its walk at a
  phase taken from its id, so a crowd does not step together.
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
- **Hit zones take the zombie's size.** `Hitbox.shapes(position, yaw, scale)` sizes the whole set about the feet; the
  scale is the look's height (brute 1.18, runner 1.07) times the type's `hit_chance` (the crawler's 0.6 makes it low
  and small). The server sends it with each target (`"scale"`), the lag compensator keeps it, and the bot aims at the
  height the look stands at. Grenade blasts still use the walker's zones.
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

## Left open

- Browser and weak-machine measurement of the full scene (the spike's follow-up still stands).
- Client interpolation between 30 Hz snapshots: views jump to each decoded position. It belongs with the net client.
- The model: done in #90. The views wear the committed variants (`ZombieModels`, walker by default; `ZombieHorde.variant`
  or `ZombieModels.scene(name)` picks another). Each variant has a near and a far mesh; `ZombieView` swaps them with
  visibility ranges at 18 m, so one mesh is drawn per zombie. Choosing a variant per zombie (by round or role) is
  the director's, still open. A body with other bone names needs the rig-sharing retarget player.
- Hit reactions by zone, crawlers, window break-ins: the animation set is #40's.
- The navmesh is baked ahead of time from the greybox's CSG boxes, one for each set of doors ([Doors](#doors)); only a
  lot nothing was saved for is baked at run time (half a second in the browser). Heights are flat: a zombie
  keeps the height it spawned at.
- Spawn point choice ignores whether an area is open (the rules' design): `spawn_points` is whatever the caller gives.

## Reproduce

```text
godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/zombies -c --ignoreHeadlessMode
godot --path game res://tests/captures/zombie_chase.tscn --fixed-fps 10 --write-movie out/chase.png --quit-after 250 -- --warmup=30
godot [--headless] --path game res://tests/captures/zombie_chase.tscn --fixed-fps 60 -- --warmup=30 --bench --zombies=40
```
