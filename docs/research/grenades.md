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

## In the night (#351)

For a month grenades worked only in the test range below: `GrenadeServer` and `GrenadeThrower` were wired there and
nowhere else, while the keys, the HUD count, the shop item, the sounds and the Soldier's clips all existed, so the
game looked finished and a player's throw key did nothing. The wiring, now:

- **`NightServer` owns a `GrenadeServer` and one `GrenadeThrower` per player.** Each tick it tells the grenade server
  where the players and the dead stand, turns the `throw_over` / `throw_under` levels of the latest command into
  `cook` and `throw` actions (the hand is 1.45 m up and 0.35 m forward along the aim; the aim is the command's camera
  ray; the velocity is the body's), and steps the fuses. Its answer is filtered to `GRENADE_EVENTS`: the grenade
  server's answer also repeats the rules' events, which already ride the rules signal, so sending both would double
  every `grenade_count_changed` and every kill.
- **A refused cook ends the hold.** On `cook_rejected`, a drop, or a blast in the hand the thrower is `abandon()`ed,
  so a held key does not pull a pin every tick until it is let go (`no_grenades`, `wrong_phase`, `player_downed`).
- **The thrower's share of the blast reaches their health** through `RulesAction.blow` (40%, cover included); the
  zombies a blast hits are thrown and stunned through `ZombieSim.blast` (see Polish below).
- **The view is a copy of the grenade.** `NightView` makes a `GrenadeView` from `grenade_thrown` / `grenade_dropped`,
  steps its own `GrenadeState` on every `frame` event with the same `WorldCast`, and swaps it for a `BlastEffect` at
  `grenade_exploded`. It is drawn at twice its size with a trail: at real size a hand grenade is lost from the shoulder
  camera by the time it lands. Gibs come from `zombie_removed` with the `blast` zone.
- **The Soldier plays `Grenade_Cook` at the pin and `Grenade_Throw` / `Grenade_Toss` when the arm swings**
  (`PlayerAnimation.grenade`: `cook`, `throw`, `gone`); the gun goes down at the cook clip's
  `grenade_visible` and comes back at the throw clip's `done`.
- **Proof:** `tests/night/test_night_grenades.gd` presses the real key and follows the grenade to a dead zombie;
  `tests/night/test_input_matrix.gd` presses every gameplay action on every device (see [Input tests](input-tests.md)).

## Polish (#357)

- **The throw waits for the swing.** Letting go of the button does not release the grenade: `GrenadeThrower` starts a
  swing (`throw_started`, with `underarm`) and sends the `throw` action when the clip's release frame is reached,
  0.375 s for `Grenade_Throw` (frame 9 at 24 fps) and 0.4167 s for `Grenade_Toss` (frame 10): `NightTuning.grenade_release_over`
  and `_under`. The Soldier's clip starts on `throw_started`, so the grenade leaves the hand at the `release` event of
  the clip, not 0.4 s before it. The fuse burns during the swing, and a grenade that goes off in the hand cancels it
  (`abandon`). The range and the tests that call `GrenadeThrower` directly keep the default of no delay. The thrower
  takes the tick's `delta` for it (seconds, not ticks), so a swing is the same length at any tick rate.
- **The cook pose holds.** `Grenade_Cook` is 0.83 s long; the action node of the animation tree runs a custom timeline
  of 30 s (`use_custom_timeline`, `stretch_time_scale = false`, `loop_mode = LOOP_NONE`), which holds the clip's last
  frame while the button is down, and the one-shot is faded out by `gone`. Without it the arm dropped back to the aim
  pose after 0.8 s of a long cook.
- **The grenade is in the hand** from the cook clip's `grenade_visible` to the throw clip's `release` (or `gone`): the
  placeholder shell (`GrenadeView.add_placeholder`) at 0.55 scale on the same `WeaponMount` bone as the weapons, at the
  melee grip. It stays a placeholder until the artist's model and hold data (#285).
- **The arc preview** (`GrenadePreview`, a child of `Night`) runs `GrenadeArc.predict` from the same hand and aim as the
  server (`GrenadeThrower.launch`, one function for both) for as long as the grenade would burn if it were let go now
  (fuse less the cook so far less the swing), and draws it as dots with a ring of the blast's core radius where it goes
  off. A line one pixel wide was lost from the shoulder camera, so it is dots, drawn through walls. It follows the
  human's command in `Night.show_throw`, hides with no button held, none left or the player down, and decides nothing.
- **The blast throws and stuns the dead.** `blast_hit` carries `impulse` and `stun`: `ZombieSim.blast` holds the zombie
  in `STAGGER` for `stun` seconds (1.6 s for the frag grenade, against the bullet's 0.4 s) and gives it a ground speed
  along the impulse (the lift is ignored: the lot is flat) that slows at `ZombieTuning.push_decay`
  (14 m/s per second, capped at 8 m/s, so the 7 m/s of a blast in the core slides a zombie 1.75 m). The dying and the
  rising are left alone. The push does not look at walls (the separation push does not either).

- **The capture aims at a close blast.** At real size a grenade is small from the shoulder camera, and the capture
  threw over the far end of the lot. `tests/captures/grenade_throw.tscn` now uses the underarm key (`H`), cooks 1.2 s
  and tilts the camera while the key is held until the arc the preview draws comes down 6 m away (`_aim_close`), so
  the pin, the arc and its ring, the grenade in flight, the blast and the zombie thrown back all fill the frame. It
  keeps the real mouse out of the recording: the body is told `capture_mouse = false` the moment it enters the tree
  (`node_added`), before its `_ready` would capture the cursor. `test_night_grenades.gd` holds the same throw: a toss
  goes off within 9 m of the thrower, and a zombie 4 m from the centre gets a `blast_hit` with a stun (shorter than
  the core's, which is 1.6 s) and an impulse away from the blast.

## Open (not part of #357)

- The crawler's hit zones are the standing zombie's. A crawler is lower than its zones; a separate low `Hitbox` table
  is needed once the zombie behaviour (#17) swaps the mesh.
- The grenade model and its hold in the hand come from the artist (#285); `GrenadeView.model` is the seam, and the
  hand's placeholder is the same shell.
- A crawler pushed by a blast can end inside a wall: the sim has no walls to push against.

## Try it

`game/world/grenade_range/grenade_range.tscn` is the test range: zombies spawned by the real rules, a pillar, a low
barrier and a back wall. A script presses the throw button, cooks for 1.4 s and lets go; the throw bounces off the wall
and the blast kills three round-one zombies, cripples two (one by the legs, one by the health band) and leaves the one
behind the pillar untouched. To record it: `godot --path game --write-movie <folder>/range.png --fixed-fps 10
--quit-after 110 res://world/grenade_range/grenade_range.tscn`, and read the frames. `-- --log` prints every event.
The movie's own audio track came out silent here (the capture runs without a sound device), so the sounds are checked
by analysis instead: length, peak and where the energy sits (the blast has nine tenths of it under 150 Hz).
