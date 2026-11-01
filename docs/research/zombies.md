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
| `ZombieBody` | one zombie as data: position, yaw, mode, target, timers (no health) | rules, nodes |
| `ZombieBrain` | the state machine for one tick (static functions) | paths, nodes |
| `ZombieSim` | all zombies at a fixed 30 Hz step: targets, repaths, separation, clearing the dead | the rules, drawing |
| `ZombiePathing`, `NavmeshPathing` | a path from A to B: straight, or `NavigationServer3D.map_get_path` | zombies |
| `ZombieDirector` | rules events in (spawn, removal), the crowd cap, the `take_hit` seam | animation |
| `ZombieRulesPort` | the one place a hit reaches `GameRules` (the rules own `ZombieState`, the health) | everything else |
| `ZombieCodec` | the zombies as 12 bytes each | the sim's internals |
| `ZombieHorde`, `ZombieView`, `ZombieRig`, `AnimationThrottle` | the client: views from decoded entries, animation | the sim |

Modes: `EMERGING` (rises 0.7 s) then `CHASE`, `ATTACK` when within 1.4 m (the blow lands 0.45 s into a 1.2 s swing,
and only if the player is still within 1.8 m), `STAGGER` (0.4 s, from any hit that does not kill; it loses the swing),
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
- **Clients draw from bytes.** `ZombieCodec` is 2 + 12 bytes a zombie (id, position in cm, yaw, mode, episode, speed
  in 0.05 m/s steps): 482 B for 40 zombies. The demo scene runs every tick through encode and decode, so what is
  drawn is what a remote client would draw. The message type and rate belong to the net protocol (`spikes/net`) and
  are not chosen here.
- **Animation:** one `AnimationLibrary` (`zombie`: Idle, Walk, Run, Punch, HitReact, Death) built once from the model
  and added to every model's player (the rig-sharing recipe); one `AnimationTree` per zombie with a state machine
  (move = Idle/Walk/Run blended by speed, attack, stagger, die). Every tree is advanced by hand by `AnimationThrottle`
  (every frame within 14 m, every 3rd to 24 m, every 6th beyond, every 12th off screen). A view starts its walk at a
  phase taken from its id, so a crowd does not step together.
- **Crowd budget:** no zombie shadows, one mesh per zombie (the eyelid mesh is freed: the kit zombie has no eyelids
  here until a crowd variant merges them), sim at 30 Hz independent of the physics rate.
- **Light:** the sim asks a `lit_probe` callable at each repath and applies the rules' `speed_on_ground`.

## Numbers

Machine: Windows 11, RTX 5080, Godot 4.7.2, Compatibility; the greybox lot with 2 players, 40 zombies chasing and
being shot, `--fixed-fps 60`, 400 frames after 120 of warm-up, wall-clock frame time. The windowed run is capped by
the monitor's 240 Hz (4.17 ms is the floor), as in the crowds spike.

| Measure | Result | Crowds spike (40 zombies, same kind of machine) |
| --- | --- | --- |
| Sim step alone, 40 zombies (test) | 0.40 ms per 30 Hz tick | not measured |
| Headless frame, whole zombie code and views | 20: 0.52, 30: 0.77, 40: 0.95 ms (empty lot: 0.02 ms) | 40: baseline 3.87, all techniques 1.47 ms |
| Windowed frame, 40 zombies | 4.19 ms mean (at the 4.17 floor), 7.1 ms 95th percentile | 40: baseline 6.48, all techniques 2.69 ms |
| Windowed frame, empty lot | 4.17 ms mean, 5.1 ms 95th percentile | empty scene 0.72 ms |
| Draw calls, 40 zombies / empty lot | 126 / 92 | 84 at 40 zombies (no lot) |
| Animation trees advanced per frame | 11 to 13 of 41 | |
| Snapshot | 482 to 530 B | |

Script cost per zombie is about 0.024 ms against the spike's roughly 0.1 ms, which is the throttle, the 30 Hz step and
no physics body. The full-frame cost sits under the display floor here, so the 95th percentile (the lot alone 5.1 ms,
with zombies 7.1 ms) is the number to watch; the browser was **not** measured: the spike's factor of about 3 applies
until it is.

## Left open

- Browser and weak-machine measurement of the full scene (the spike's follow-up still stands).
- Client interpolation between 30 Hz snapshots: views jump to each decoded position. It belongs with the net client.
- The model: the kit zombie is third-party (CC0) and not committed here (a maintainer decides); `ZombieView` needs it
  at `game/assets/zombie_kit/zombie.glb` (git-ignored). Variants (#40) bring bodies with the same bones, which play
  the same library; a body with other bone names needs the rig-sharing retarget player.
- Hit reactions by zone, crawlers, window break-ins: the animation set is #40's.
- The navmesh is baked at load from the greybox's CSG boxes (`NavmeshBaker`); the world owner should bake once in the
  editor. Heights are flat: a zombie keeps the height it spawned at.
- Spawn point choice ignores whether an area is open (the rules' design): `spawn_points` is whatever the caller gives.

## Reproduce

```text
godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/zombies -c --ignoreHeadlessMode
godot --path game res://tests/captures/zombie_chase.tscn --fixed-fps 10 --write-movie out/chase.png --quit-after 250 -- --warmup=30
godot [--headless] --path game res://tests/captures/zombie_chase.tscn --fixed-fps 60 -- --warmup=30 --bench --zombies=40
```
