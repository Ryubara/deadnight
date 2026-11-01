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
  per target per shot. The rules pay by event, so this keeps points honest.
- **The rules own the health; shooting only reports damage.** Each damaged zombie is one `RulesAction.hit` carrying
  the target, the zone and the damage with the zone multiplier already applied (a head pellet makes the whole hit a
  headshot). The rules take it off the zombie, pay, decide the kill and answer with `zombie_damaged` and
  `zombie_removed`, which the server turns into `damage_dealt` and `target_killed`. The server keeps no health of its
  own, only a set of zombies still alive (from the rules' spawn and removal events) so a rewound shot cannot hit a
  corpse.
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
- **A lambda that uses `self` holds its `RefCounted` strongly; a method `Callable` does not.** `GameRules` used to
  connect lambdas to its generator, a cycle that Godot reported at exit as "resources still in use" (an `ERROR`
  line, though the game is fine). It connects methods and `_emit.bind(...)` now, so rules and servers free
  themselves with no `dispose()`; `test_rules_lifetime` holds a `weakref` to prove it.
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

## Selling rounds, giving the weapon (#152)

- **Shop ids are not weapon ids.** The shop sells `weapon_shotgun` and the crane's pool lists `weapon_smg`; the weapons
  are `shotgun`, `smg`. The night's `purchase_made` handler passed the shop id to `CombatAction.give_weapon`, which
  answered `unknown_weapon` (a rejection the night filters out), so a bought weapon was never carried and nothing
  failed loudly. `WeaponCatalog.catalog_id` is the one translation; `NightServer._deliver` is the one place that uses
  it. A test buys through the rules and asks the combat server what is carried.
- **Whoever owns the number prices it.** The reserve is the combat server's, so the rules cannot know the room in it;
  the server passes the room as `rounds` on the `buy` action and the rules price exactly that (fuel and grenades work
  the same way, their room is in the rules). A missing `rounds` buys the whole purchase, which keeps the action valid
  for a caller that does not know (the simulator).
- **Events from a direct call are not delivered.** `NightServer.buy` outside a `step` fills the outbox that the next
  `apply` or `step` resets; a test that wants the rules' events reads the array `buy` returns.
- **A `use` at a shop spot is a `buy` through the server.** `NightServer.use_target` answers the prompt (`weapon`, `ammo`,
  `crane`) and `_use` buys with `NightServer.buy`, so the card shows exactly the price and the rounds the purchase will
  charge (`ShopItem.ammo_price`, one formula for both). With the supply drop gone and the crowbar given at join, a
  player whose guns run dry still has something to swing and something to swap to; the autopilot swaps one edge at a
  time (a press every 20 ticks), because a `swap` is a cycle and a held button would spin through the weapons.
- **Movie Maker steps 6 physics ticks to a rendered frame at 10 fps.** A capture script that holds "20 frames" with
  `physics_frame` gets 3 pictures; hold 60 to 70 ticks for a second of picture. A tour that stays in the break needs no
  zombies and no tuning (the 12 s intro lasts more than the whole clip).
