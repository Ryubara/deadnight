# Weapon firing

What building the server-side shooting (`game/gameplay/weapons/`) taught us. The design and the numbers are in
[Weapons](../design/weapons.md).

## Shape that worked

- **Same pattern as the rules: a `RefCounted`, actions in, events out.** `CombatServer.apply(action)` takes a
  dictionary from `CombatAction` and returns the events it caused. Every suite runs without a scene, and the same
  object serves a dedicated server and single-player. `var_to_bytes` round trips every action and event (tested), and
  the `LoopbackLink` does exactly that on each message, so a non-plain value fails in a test, not on the wire.
- **The world is a `Callable`.** `world_ray(from, to) -> float` (distance to the first solid thing, or -1) is the only
  contact with the physics server (`WorldProbe`, about ten lines). Tests pass a box, so wall, corner and penetration
  cases need no physics step.
- **Hit zones are analytic shapes, not colliders.** A ray against a few spheres and capsules is cheap (a broad sphere
  rejects most zombies) and, being plain maths on plain positions, can be run against any past frame. A physics body
  cannot be put back where it was a quarter second ago.
- **Rewind is a ring of frames, not a rollback.** `LagCompensator` stores `{id: {pos, yaw}}` per step, interpolates
  between the two frames around the view time and clamps the view time to `[now - cap, now]`. Targets that did not
  exist at that time are simply absent, and the server drops ones that are dead now, so a rewound shot cannot kill a
  corpse twice.
- **The camera ray picks the point, the muzzle ray does the shot.** Start the camera ray at the muzzle's depth along
  it (the camera is behind the shooter, so anything between would otherwise eat the shot), then aim the muzzle at what
  it found. Corner and penetration cases fall out for free because the muzzle ray is an ordinary ray.
- **Spread is a function of a seed, not of an RNG stream.** `shot_seed(match, shooter, shot number)` makes the pattern
  identical on the client and the server for the same shot, so the predicted tracer lands where the authoritative one
  does, and a replay of a night scatters the same way.
- **Per-target damage, not per-pellet.** A shot's pellets add up per zombie before the rules hear about it: one `hit`
  or `kill` per target per shot. The rules pay by event, so this keeps points honest.
- **One seam to the rules** (`RulesDamage`): the rest of the code never builds a rules action. Today it keeps the
  zombie's remaining health and sends `hit` or `kill`; when the rules own health (#60) it sends one damage action
  carrying the target, zone and amount, and the file is the only thing that changes.
- **Client prediction is the same code.** The test range's client runs `AimResolver` on its own view for the tracer
  and keeps a `WeaponState` to gate the flash; the server's `weapon_equipped` and `shot_fired` events overwrite its
  ammo. The client's state must be ticked each step or its cooldown never ends (the first capture showed one shot per
  weapon).

## Godot behaviour worth knowing

- **A static function named `reload` on a script class is unreachable.** `CombatAction.reload(1)` called the script's
  own `GDScript.reload()` and returned an int, so `apply` failed with "cannot convert argument 1 from int to
  Dictionary". The function is `reload_weapon`; avoid `reload`, `new`, `free`, `get_script`-style Object and Script
  method names on static builders.
- **New `class_name` scripts need an import pass before a GdUnit4 run.** The global class cache
  (`.godot/global_script_class_cache.cfg`) is written by `godot --headless --import`; without it every suite fails
  with "Identifier not declared in the current scope" and the `-d` run loops on the parser error until the timeout.
- **`:=` on a value read from an untyped `Dictionary` is a parse error** ("cannot infer the type"); write
  `var weight: float = ...`.
- **A `RefCounted` that connects a lambda to itself is a reference cycle.** `GameRules` does this with its generator;
  at exit Godot prints "resources still in use" (an `ERROR` line, though the game is fine). `CombatServer.detach()`
  breaks the server's side, and the range disconnects the generator's lambdas on `_exit_tree`; the proper fix is a
  `dispose()` on the rules.
- **A projectile's events come from the tick, not from a request.** Only answers to requests flow back on a request
  path; what the server causes alone (a burst, a finished reload, the rules' round events) must be broadcast
  (`LoopbackLink.broadcast`), or the client never learns of the kill.
- **`AABB.intersects_segment` returns `Variant`** (a point or `null`), and tests built on it need the `null` check.
- **Movie Maker advances the world 1/fps per frame**; a tracer that lives 0.1 s is gone between two frames at 10 fps,
  so effects in a capture live 0.2 to 0.3 s.

## What the numbers say

Measured in the test range's tour (seed 20260101): the rifle kills the first zombie and hurts the second behind it in
one shot (70 and 42), the SMG kills in five hits (every 0.1 s), the crowbar kills in two swings (+130 melee kill), the
shot at the corner is stopped by the wall and the same shot from 1.6 m to the right hits, and the flare kills with a
direct hit (90) and ends the round (+60 kill, +30 round bonus). The tests check each of those against the rules' point
table.
