# Grenades

What building the server-side grenades (`game/gameplay/grenades/`) taught us. The design and the numbers are in
[Weapons: Grenades](../design/weapons.md#grenades); the shooting they sit beside is [Weapon firing](weapon-firing.md).

## Shape that worked

- **Same pattern again: a `RefCounted`, actions in, events out.** `GrenadeServer.apply(action)` takes a dictionary
  from `GrenadeAction` and answers with events. `tick` and `targets` are spelled like the combat server's, so a host
  sends the same step and the same target list to both. The server is a sibling of `CombatServer`, not a change to it:
  the weapons code needed no edit for grenades.
- **The world is two Callables.** `world_cast(from, to) -> {distance, normal}` for the flight (a bounce needs the
  surface normal, which the shots' `world_ray` does not give) and the shots' `world_ray` for cover. `WorldCast` is the
  ten lines that touch the physics server; tests pass a floor and a wall as plain functions.
- **One stepping function serves the server, the client and the preview.** `GrenadeState.step` is a pure function of
  the def and the world, so the arc preview (`GrenadeArc.predict`), the client's prediction and the server's grenade
  are the same code on the same input and land on the same point (tested for the exact vector, not a tolerance).
- **The sphere is a ray, lengthened by its radius.** One ray per step, up to four contacts per step, the contact point
  pushed out 2 mm along the normal so the next ray does not start inside the surface. It cannot tunnel through a floor
  however hard it is thrown (tested at 60 m/s), and a corner is approximated, which a grenade can afford.
- **Rolling is its own state, not a very small bounce.** A floor bounce slower than `rest_speed` lands the grenade
  (`grounded`): from then on gravity acts along the slope only, friction slows it, and each step feels for the floor
  below, so a ledge ends the roll and a slope carries it. Bouncing down to nothing with restitution alone jitters
  forever at 60 Hz.
- **Cooking is a function of the command stream.** `GrenadeThrower` reads the `throw_over` / `throw_under` levels of
  each `PlayerCommand` and answers with `cook` and `throw` actions, with a `snapshot()` / `restore()` pair so a
  reconciliation can replay from any tick. The fuse itself is the server's: the cook time of a throw is the server's
  clock since the `cook` action, so a client cannot claim a longer fuse than it spent.
- **Cover is a line check per hit part.** The blast stands 25 cm above the grenade and looks at the middle of each of
  the six `Hitbox` shapes. A part with a wall nearer than the part (less 12 cm) takes nothing, so low cover shields the
  legs and leaves the head, and a pillar shields the whole body. Falloff is by the distance to each part's surface.
- **The rules take one `explosion` per blast, not a `hit` per zombie.** The server turns a blast into a list of
  `{zombie_id, damage, leg_damage}` sorted by id, so the rules apply them in one fixed order, pay, kill, and decide the
  crippling in one place. The rules never see geometry.
- **Crippling is two rules and a seeded roll.** Leg damage past a fraction of the zombie's full health always cripples
  a survivor; a survivor left inside a health band cripples by a roll from its own stream (`CRIPPLE_STREAM`), drawn
  only for a zombie in the band, so the stream depends on the blasts alone and the snapshot carries its state.
  The leg rule needs the legs to carry more than their natural share: with legs at 30% of the blast a zombie could not
  take a quarter of its health on the legs and live, so the legs carry half of a low blast.

- **The client's numbers are hints.** The first server took the hand and the velocity of a throw as sent: a hand 60 m
  away dropped the blast there, 2000 m/s launched at 1015 m/s, and a NaN hand made `maxf(NaN - r, 0)` zero, so every
  zombie in sight stood at the centre. Now the server derives the hand from its own player position (kept within
  1 m of it), clamps the carried speed, refuses non-finite input, and `falloff` / `BlastModel` give no damage for a
  distance that is not finite. Each probe of the review is a test in `test_authority.gd`.
- **State that can be asked of the rules is not copied.** The server's own list of living zombies (learned from spawn
  events) was empty for a server made mid-night; it asks `GameRules.has_zombie` now, so nothing is missed on a restore.
  What only the grenade server knows (cooks, grenades in flight, the clock, the next id, the last positions it was
  given) is `to_dict` / `from_dict` / `to_bytes` beside the rules' snapshot (restore the rules first), in
  `test_snapshot.gd`.
- **A missing `world_cast` is said once.** The constructor reports it (`push_error`) and the flight then runs over open
  ground instead of failing on every tick.

## Things that bit

- **A script error stalls a GdUnit run.** The runner is started with `-d`, so any runtime error (a test indexing a
  spawn list that is still empty) drops into the debugger prompt and waits for the timeout. Check the log for `Debugger
  Break` before believing a quiet run.
- **A zombie list is empty early.** Round one spawns the first zombie after 1.5 s and then one per 2.4 s; a test that
  wants several runs the rules for 20 s first.
- **Type inference on a Variant.** `var cooked := now - dict["x"]` does not compile (the right side is a Variant);
  write `var cooked: float = ...`.
- **Effects shorter than a frame.** At 10 fps a frame is 0.1 s; the blast, the ring and the gibs last 0.5 to 1.4 s so a
  capture sees them.

## Open

- Player health does not exist yet; `player_blasted` carries the damage, knockback and stun for it.
- The crawler's hit zones are the standing zombie's. A crawler is lower than its zones; a separate low `Hitbox` table
  is needed once the zombie behaviour (#17) swaps the mesh.
- The grenade model and the Soldier's throw clip come from the artist; `GrenadeView.model` is the seam.

## Try it

`game/world/grenade_range/grenade_range.tscn` is the test range: zombies spawned by the real rules, a pillar, a low
barrier and a back wall. A script presses the throw button, cooks for 1.4 s and lets go; the throw bounces off the wall
and the blast kills three round-one zombies, cripples two (one by the legs, one by the health band) and leaves the one
behind the pillar untouched. To record it: `godot --path game --write-movie <folder>/range.png --fixed-fps 10
--quit-after 110 res://world/grenade_range/grenade_range.tscn`, and read the frames. `-- --log` prints every event.
The movie's own audio track came out silent here (the capture runs without a sound device), so the sounds are checked
by analysis instead: length, peak and where the energy sits (the blast has nine tenths of it under 150 Hz).
