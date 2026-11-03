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
- **A blast reaches its thrower's health** through `RulesAction.blow` (`PlayerBlast`: all of it in the hand and within
  1 m, less to nothing at the blast radius; the thrower alone, #856; #805,
  [the rule](../design/weapons.md#blast-on-players)); the zombies a blast hits are thrown and stunned through
  `ZombieSim.blast` (see Polish below).
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

## Weight, the dead in the way and the beep (#680)

Player feedback: the grenade floated and rolled, went through zombies, and had no fuse beep once it left the hand. What
changed (`frag.tres` is the only place for the numbers; every one is a test below):

| A level overarm throw from the hand, 2.65 s of flight on open ground | Before | After |
| --- | --- | --- |
| Where it first touches the ground | 8.4 m | 5.8 m |
| Where it lies | 22.3 m | 10.2 m |
| The longest lob (any pitch) | 25.7 m | 12.2 m |
| Underarm toss, where it lies | 8.3 m | 4.4 m |
| Highest point of a level throw | 1.57 m | 1.47 m |

- **Heavy, not slow.** Gravity 16 to 22 m/s2, the throw lifted 5 degrees (was 8) at 14 m/s (was 15), a floor bounce
  keeps 22% (was 42%) and loses 45% along the ground (was 20%), it lands under 2.5 m/s (was 1.4) and rolls with 9 m/s2
  of friction (was 3.5): it arrives, knocks once or twice and stays. The fuse is the same 3.0 s (a test pins it).
- **The dead are bodies.** `ZombieBump` is one upright capsule per zombie (0.4 m radius, 0.4 to 1.45 m up, sized by
  the zombie's `hit_scale` like its hit zones), tested in plain vectors against the positions the server has this
  tick. `GrenadeState.step(delta, cast, bodies)` takes the nearest hit of the world and of the dead; a zombie
  contact keeps 4% of the speed into the body, 5% along it and adds a 0.2 m/s shove out from it (`GrenadeDef`
  "Zombies"), so a throw at a zombie stops 0.2 to 0.9 m from it (tested over a grid of pitches and sides; the bound
  is 1 m), a lob that clears the head is not touched, and a grenade falling onto a head slides off to the feet. A
  start inside a body is ignored while it moves out and stops at once while it moves in, so a zombie at the
  thrower's chest cannot trap it.
- **Every client agrees.** A client flies its copy against the walls only (it has no way to know where the dead were this
  tick). The server says so when a zombie stops the grenade: `grenade_struck` carries the grenade's whole state at the end
  of that tick (`GrenadeState.to_dict`) and the view replaces its copy with it and skips its own step for that frame (the
  frame event follows the grenade's in the same tick). A test steps a copy through the real events and finds it within a
  millimetre of the server's grenade; a night test does it with the real input and the real view. `grenade_bounced`
  also names the zombie (`zombie_id`, -1 for the world) so the knock of the contact sounds.
- **The preview and the bots fly the same code.** `GrenadeArc.predict` takes the same `bodies` (the preview gets the
  client's zombies, frozen where they stand, so the dotted line stops at the first it meets). The bots' table of flights
  is made from the real arc, so it followed: they now throw 6 to 12 m out (overarm lobs up to a near-vertical 1.45
  rad; underarm only reaches 4.4 m and is never planned, a blast must be 6 m from the bot).
- **The beep** (`grenade_beep`, `tools/audio/recipes.py`; the old `grenade_tick` was a metal click heard only while the
  pin was in the hand): a clean 1.1 kHz tone with two harmonics, 60 ms, the same every time. `GrenadeSounds` keeps one
  chain per cook and per grenade in the air; on `grenade_thrown` (or `grenade_dropped`) the cook's chain becomes the
  grenade's, keeping its next beep due when it was, and each beep is placed at the grenade as the view draws it
  (`NightView.grenade_position`), so every client hears it from the grenade. It stops at `grenade_exploded` of its own
  id. The gap is `beep_gap_end + (beep_gap_start - beep_gap_end) * (left / fuse)^1.6` (`NightSoundTuning`): 0.5 s at the
  pin to 0.09 s at the blast, 14 to 16 beeps in a fuse, and its level swells from -3 to +2 dB.
- **Audio analysis** (`tools/audio/beep_report.py` on a 60 fps recording of `tests/captures/grenade_pack.tscn`, the
  game's own service and buses): 14 beeps from the pin to the blast, at 13.34 s, 13.84, 14.22, ..., 16.23 s; the gaps
  fall 0.50, 0.38, 0.36, 0.29, 0.23, 0.20, 0.18, 0.17, 0.11, 0.16, 0.12, 0.10, 0.11 s (the means of the three thirds
  are 0.38, 0.19 and 0.12 s; a beep found in a noisy mix can sit a frame off). The beep's tone peaks in the mix are -12
  dBFS in the hand, -16 dBFS in the air 4 m out, and -26 rising to -23 dBFS lying 8.5 m away behind a wall, against
  the blast's -5 dBFS peak and -14.6 dBFS over its first 100 ms: a cue under the shots that carries to the end.
- **Two things the analysis caught.** (1) The first beep was a 2.6 kHz tone at -2 dB: the grenade lying behind a wall
  came out at -40 to -80 dBFS, nothing at all, because the audio service takes 9 dB off a sound behind a wall and
  low-passes it at 1.1 kHz, and the web build, which has no filter, takes 13 dB. A warning has to carry through cover:
  the beep is lower (1.1 kHz, which the low-pass lets through) and `SoundDef.occlusion_scale` (0.35 for the beep, 1
  for everything else) makes cover take a third of the dulling. (2) At the start the beep in the hand was -9 dBFS at
  the ear, as loud as the blast's own 100 ms (-14.9 dBFS RMS over the beep's 100 ms), so the bank trim went from -2 to
  -9 dB. A recording at 10 frames a second could not show either: a sound schedule steps with the frames, so the beeps
  came out 0.1 s apart and stacked in one frame; read a fuse's timing at 60 (`--write-movie pack.avi --fixed-fps 60`,
  then `ffmpeg -vn -c:a pcm_s32le`).

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

## Blast on players (#805)

- **The cover ray met the players.** The grenade server asked the weapons' `WorldProbe.callable()` (walls, props and the
  bodies of players) whether the line from the blast to a chest was clear, so the ray ended inside the target's own
  capsule and every player "stood behind a wall" of themselves: a teammate 2 m away was never blasted, and the old 40%
  thrower share only worked because the thrower stood outside their own body. The server now asks `static_callable()`
  (walls, props, boards): a person is no cover for a person or for a zombie. Found by the two-client test, where the
  teammate stayed at full health beside a blast that downed the holder.
- **One curve for every blast that hurts a player** (`PlayerBlast`, `game/gameplay/rules/player_blast.gd`): a share of
  `max_health`, 1 inside a full radius, `(1 - t)^EASE_POWER` out to the edge, an `scale` for a weaker source. A caller
  gives its own full and edge radii and scale: the grenade `player_full_radius` and `blast_radius`, the ray gun's splash
  (#788) its own radii and `self_splash_share` as the scale. `NightServer._blast_player(player_id, damage, from, harm,
  by_id)` turns the damage into the rules' `blow`, which names `harm` and `by_id` in `player_hurt` and `player_downed`
  for the feed.
- **In the hand is a rule, not a distance.** The hand is 0.7 to 1.0 m from the chest the blast is measured to, so
  "within 1 m" would be luck: `BlastModel.against_player(..., held, ...)` takes all of the health for the thrower's own
  in-hand blast and skips the cover line.
- **A player on the ground is not counted** (the rules refuse a blow on a downed player). Until #856 the grenade a downed
  player dropped hurt the reviver at their side; now it hurts no one.
- **The bots' distance is the curve's.** A blast hurts out to 8 m, so "not where it reaches" is a share, not a radius:
  `BotGrenadier.HARMLESS_SHARE` (a tenth of the health, a graze that mends in 5 s) gives `harmless_apart` 5.8 m, and a
  test holds `SAFE_FROM_SELF` to it.

## Only the thrower (#856)

The maintainer's answer to #835's open question: a grenade hurts the player who threw it and nobody else.

- **Where it is decided:** `GrenadeServer._blast_players` looks at the thrower only (a downed thrower, or one gone from
  the server's list, takes nothing), so `player_blasted` carries the thrower's id and `own` is always true. A teammate
  is not looked at: no event, no `blow`, no `player_hurt`, no feed line. `NightServer._blast_player` keeps its signature
  for the ray gun's splash (#788), which is its shooter's own as well.
- **A reviver is safe from the grenade a downed player dropped:** the thrower is on the ground and the rules refuse a
  blow on them, so it hurts no one (it still hits the dead round it).
- **Bots kept the 7.5 m from every teammate (`SAFE_FROM_TEAMMATES` 6 m plus `THROW_MARGIN`), though it protected no
  health.** #856 measured it away and left it in because the bots then hurt themselves;
  [#872](#the-bots-and-their-own-grenade-872) fixed that and removed it. What #856 measured, with
  `test_bot_grenade_soak.gd`'s night (three bots follow a person round the lot) lengthened to 120 s on seeds 11 to 16,
  the thrower's own distance to each of its blasts read from the body (the soak now measures that, not "anyone"):

  | Arm | Blasts in 6 nights | Touched the thrower (any share) | Over 10% of the thrower's health | Worst share |
  | --- | --- | --- | --- | --- |
  | Clearance kept (main, and this change) | 18 and 21 (two runs) | 3 of 18 | 0 | 0.015 |
  | Clearance removed | 42 | 12 | 2 (0.37, 0.11) | 0.37 |
  | Removed, and 1.5 m more from the bot itself | 46 | 19 | 5 (0.11 to 0.49) | 0.49 |

  The committed soak (seeds 11 and 12, 90 s) failed with the clearance removed (worst 0.17 and 0.28 against its 0.1).
  The scripted night (a bot, a pack ten metres off, a person well clear) throws at tick 227 in every arm, so the
  clearance costs no throw where nobody stands near the pack. Runs are not repeatable to the blast (the same seed gave 5
  and 2 blasts in two baseline runs), so read the ratios. **Why the bots hurt themselves** (the 19 hits of the last arm,
  printed): in most the bot walks 2 to 8 m (usually 3 to 5) toward its own blast during the 3 s fuse, in 2 a zombie
  stopped the grenade short (`grenade_struck`). The clearance, by keeping the throws to packs far from the group the bots
  follow, hid that. #872 fixed the short landing
  and the walk into the blast (a bot holds still or steps out), then dropped the teammate clearance.

## The bots and their own grenade (#872)

Issue #856 left the bots a 7.5 m clearance from every teammate that protected nobody, because without it they
threw twice as often and then hurt themselves. This finished it: the clearance (`SAFE_FROM_TEAMMATES`, and `plan`
and `is_safe` taking the team) is gone, and the bots no longer hit themselves.

**Where the bots hurt themselves** (a probe in the soak's night that printed every blast touching its thrower: the bot's
distance to the real blast every half second, its note, the grenade's bounces; 12 nights, seeds 11 to 22, 120 s, three
bots following a person who walks a tour). Four causes, all in what the bot did after the order, none in the throw
itself:

1. **The order was forgotten after the pin was pulled.** `is_safe` took the team: a person who walked near the landing
   made the brain drop the order, but the motor only stops a throw while the view still turns, so the grenade flew while
   the brain had walked on to follow. With the clearance gone there is nothing to abort for but a zombie within 3 m.
2. **Nothing held the bot back from walking in.** After the order ended (2.5 s of the 3 s fuse) the bot followed the
   person again; it steps out of reach (7.3 m, a metre and a half past the harmless distance) only inside that reach, and
   a runner crosses the last 10 m of the blast in the 2 s that are left. It now stands and fights (`blast_wait`) while its
   own grenade is live within 20 m (`BotGrenadier.WAIT_RANGE`), except when reviving.
3. **Legs and the retreat moved it in.** Giving way to a person who walked at the bot (`BotLegs._give_way`) took 3 m of
   a still bot toward its blast, and a retreat chose the best heading by what flees the dead: a still blast weighs as one
   zombie, and the pack stood on the blast's side, so it ran at it (8.5 m to 3.4 m in 1.5 s, 0.17 and 0.5 of the health).
   `BotSteering.keep_out` now drops any heading that ends nearer to a point kept out of, from inside its reach, and the
   brain sends the same points to the legs in the intent (`BotIntent.keep_out`).
4. **The grenade lay where it was not aimed** (a wall or a prop above a lob, 3 to 6 m short, share 0.13 and 0.37). The
   bot now hears where its own grenade lies: `grenade_bounced` joined the events a bot may hear (every screen shows it),
   and `BotTeam` moves the bot's blast to the last bounce of the grenade its order made (`grenade_flying`,
   `grenade_lies`). A zombie in the way of a low arc, nearer than the safe distance, stops the throw
   (`BotGrenadier.arc_is_open` flies the dead with their speed through `ZombieBump`); a lob flies over them, as the real
   grenade does.

Also: `SAFE_FROM_SELF` went from 6 m to 7 m (planned at 6 m a blast that lands exactly there takes 11% of the health; at
7 m 2%), a zombie within 6 m still keeps the bot from throwing (`NEAR_ZOMBIE`, the old number), and each blast belongs to
its thrower (`BotTeam.blasts_near(..., owner)`): the other bots no longer step out of a grenade that cannot hurt them.

| 12 nights (seeds 11 to 22) | Blasts | Touched the thrower at all | Over 10% of its health | Worst share | Sum of shares |
| --- | --- | --- | --- | --- | --- |
| Before (main with #856) | 40 | 7 | 1 | 0.618 | 0.759 |
| After | 86 | 20 | 0 | 0.005 | 0.032 |

The self-damage per blast fell from 0.019 to 0.0004 of the thrower's health, and the throws a night rose from 3.3 to
7.2. Every touch left is a graze at 7 to 8 m. The scripted night still throws at tick 227. Runs are not repeatable to the
blast (the same seed gave 0 and 1 over 10% on the unchanged code), so these are ratios over twelve nights; a second set
(seeds 23 to 34) is below.

| 12 nights (seeds 23 to 34) | Blasts | Touched the thrower at all | Over 10% of its health | Worst share | Sum of shares |
| --- | --- | --- | --- | --- | --- |
| Before | 55 | 9 | 3 | 0.295 | 0.643 |
| After | 69 | 10 | 1 | 0.195 | 0.245 |

The one left over a tenth: the grenade hit a wall 0.7 m from the thrower (the arc check missed it) and the bot ran
from 1.4 m to 4.9 m before the fuse ended. Over the 24 nights: 95 blasts (4.0 a night) to 155 (6.5), and the thrower's
health taken 0.0148 to 0.0018 a blast. The Rookie parity cell at x4 (24 nights, round cap 16, simulator median 5)
beside the unchanged code: median 9 with a Kolmogorov distance of 0.56 before, median 9 and 0.42 after, so the doubled
throws did not move the bots away from the model.
