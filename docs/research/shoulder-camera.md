# Shoulder camera

How Deadnight's over-the-shoulder camera is framed and moved, with *Star Wars Battlefront II* (2017) as the feel
target (maintainer feedback, 2026-11-01: closer to the character and much more fluid). The code is
`game/gameplay/player/third_person_camera.gd`; the numbers live in `player_tuning_default.tres`
([player controller](player-controller.md) has the earlier ones).

## What is public, and what is not

DICE has published no talk, slide or blog post on the Battlefront camera: searches of GDC and the Frostbite talks
found only unrelated ones (photogrammetry). The only public material is player and modder talk, and none of it holds
a measured offset, distance or spring value. So **every Battlefront number below is an estimate** from the way the
genre frames a shooter (a character about a third of the screen high, a camera hung just off one shoulder), tagged as
such. What *is* documented is the maths of the smoothing, which does not depend on the game.

## What Battlefront II is known to do

| Fact | Kind | Source |
| --- | --- | --- |
| Heroes are always third person; troopers can switch between first and third person. | Community guide | [Twinfinite](https://twinfinite.net/guides/s/) |
| Third person has a shoulder swap on a button (d-pad down on console). | Community guide | [Twinfinite](https://twinfinite.net/ps4/s/) |
| The camera is not mirrored between shoulders, and its height varies by character. | Modder's claim | [Nexus mod page](https://www.nexusmods.com/starwarsbattlefront22017/mods/8811) |
| Scoping a hero's blaster goes to first person, per the patch notes, as reported by a player. | Forum report | [EA forums](https://forums.ea.com/discussions/star-wars-battlefront-2-en/re-camera-scope-hero-bug/10841950) |
| Players say "raise the FOV if the camera feels too close"; one modder plays at 84, another suggests 55 to 75 for a head-height camera, a forum post recalls a default of 55. | Anecdote, not verified | [Nexus mod page](https://www.nexusmods.com/starwarsbattlefront22017/mods/8811), [EA forums](https://forums.ea.com/discussions/star-wars-battlefront-2-en/third-person-view-is-off-center/10917584) |
| Frosty Editor shows a camera rig with an `Offset` and a `BoomOffset` (x, y, z); one comment says the vanilla offset is `0, 1, 0`. | Single comment, not verified | [Nexus comment](https://www.nexusmods.com/dragonageinquisition/mods/4090?tab=posts) |

(Some of these pages answer HTTP 403 to scripts; the facts are from their search excerpts and are marked as such.)

Nothing public covers sprint FOV, camera lag, the aim transition time or the shoulder swap animation. The ideas
below are therefore our design, informed by the genre, not a reading of the game.

## Framing (estimated)

- **Offset and distance:** a boom of about 2 m with the camera 0.5 to 0.6 m off the shoulder puts the character at
  the lower left or right third of the frame, about a third of the screen height, and leaves the screen centre clear
  for a reticle. Deadnight's earlier 2.8 m arm with a 0.75 m offset showed a smaller soldier with more world around
  him; the maintainer asked for closer. *Estimated.*
- **FOV:** vertical 70 degrees in play, 55 to 60 aiming. Godot's `fov` is vertical, and the Battlefront figures
  above are unverified and do not say which axis they mean, so we do not copy them. *Estimated.*
- **Pitch limits:** the existing -60 to +50 degrees; no Battlefront figure is public.

## Easing: critically damped springs

A follow camera that snaps to its target copies every physics hitch to the screen. A camera that eases with a
critically damped spring reaches the target as fast as possible **without overshooting** ([Ryan Juckett, Damped
Springs](https://www.ryanjuckett.com/damped-springs/)). For damping ratio 1 and angular frequency `w` (rad/s), one
step of `dt` is, with `e = exp(-w dt)`, offset `x` and velocity `v` from the target:

```text
x' = (x (1 + w dt) + v dt) e        v' = (v (1 - w dt) - x w w dt) e
```

It is exact for any `dt`, so it is stable at 30, 60 or 144 frames per second, unlike an Euler spring or
`lerp(a, b, k)` with a constant `k`, which feels different at every frame rate. The error falls as `(1 + w t) e^(-w t)`;
95 percent is gone at `w t` of about 4.75 (our derivation from the article's formula), so a settle time T needs
`w = 4.75 / T`. Unlike the exponential ease the camera used before, the spring keeps the velocity, so a start and a stop
have no kink.

## Avoiding jitter between physics and render frames

The body moves in 60 Hz physics ticks; the screen draws at any rate. A camera that reads the body in `_process`
sees it jump once per tick (visible at 144 Hz). The cure is to **render a blend between the last two physics states**:
the leftover time over the tick length is a blend factor, and the renderer interpolates by it
([Glenn Fiedler, Fix Your Timestep](https://gafferongames.com/post/fix_your_timestep/)). Godot does this for nodes
([physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html);
the fraction is `Engine.get_physics_interpolation_fraction()`). The price is that the picture shows the body one tick
(16.7 ms) in the past; the springs hide that.

## Walls and the head

`SpringArm3D` sweeps a shape from the pivot and shortens the arm by `margin` so the camera stops short of a hit
([docs](https://docs.godotengine.org/en/stable/classes/class_springarm3d.html)). It only covers the boom: the
sideways shoulder offset has to be swept too (issue #76), or the lens can poke through a wall beside the player.
Pulling the camera in must be fast and release slowly (a sudden wall hit cannot wait for a spring, but the way out
should not pop). When the arm is short the body fades or hides so the lens is never inside the helmet (issue #157).

## What we tuned and why

Numbers are in `player_tuning_default.tres` (a `PlayerTuning`, the Camera and Camera motion groups); all of them are
estimates or design choices, none is a Battlefront measurement. The first column is the earlier camera.

| Value | Before | Now | Why |
| --- | --- | --- | --- |
| Pivot height | 1.55 m | 1.6 m | A little above the head, so the soldier sits lower in the frame and the horizon is above the reticle. |
| Arm (behind the pivot) | 2.8 m | 2.3 m | Closer, as asked: with the FOV change the soldier is a third larger on screen (2.8/2.3 times tan 37.5 over tan 35). Closer than this cuts the boots off. |
| Shoulder offset | 0.75 m | 0.6 m | The soldier stands left of centre (about 40 percent from the left edge in the tour capture) and the reticle stays clear. |
| FOV (vertical) | 75 | 70 | Less world around him; 70 vertical is about 102 horizontal at 16:9, not a fish-eye. Later 60 (issue #405: the maintainer found 70 too far outward). |
| Aim: arm, offset, FOV | 1.9 m, 0.6 m, 62 | 1.8 m, 0.65 m, 60 (the FOV is now 40, issue #405) | The research table suggested 1.3 m, 0.4 m, 55; that puts the right pad 5 degrees from the reticle (issue #109). A test needs 0.2 m of air between the body and the centre ray. |
| Follow spring | exponential, none | 22 rad/s on the ground plane, 10 vertically (95 percent in 0.22 s and 0.48 s) | A critically damped spring trails a steady runner by 2 v / w: 0.4 m at a run. The slower vertical follow keeps a jump from whipping the view. |
| Sprint | none | +6 degrees FOV (now +3; the default FOV is now 60, aim 40: issue #405), +0.15 m arm, follow 16 rad/s (0.9 m of lag at 7 m/s), eased at 13.5 rad/s (95 percent in 0.35 s) | Speed shows as the character drifting ahead on screen, then settling. The maintainer found the first pull-back (0.3 m, 9 rad/s, 0.53 s) too long and too slow: now half the distance, 1.5 times as fast ([character controller](character-controller.md)). |
| Aim zoom, shoulder swap | exponential 10 and 9 per second | springs, 24 and 16 rad/s (0.2 s and 0.3 s) | Same duration, but they start from rest and a half-done transition keeps its velocity when reversed. |
| Wall release | none (the arm moved with the wall) | pulled in at once, let out at 6 rad/s | A wall hit cannot wait; leaving one should not pop. |
| Hide the body | arm below 0.7 m | lens closer than 0.9 m to the head, shown again beyond 1.05 m | Measured to the head, not along the arm, so a shoulder-side wall counts too (issue #157). |

What changed in the way it works, not only the numbers:

- **The view turns raw, the world follows softly.** Yaw and pitch are the player's input applied as they come, so the
  reticle always sits where the shots go. Smoothing the view rotation (the research table suggested a 40 rad/s spring)
  would put the reticle behind the aim. Only the autopilot's steps are eased (`steer`, 18 rad/s), because a bot has no
  hand to smooth.
- **Interpolation by hand.** The rig records the body after each physics tick and draws the blend of the last two at
  the render frame's fraction. A test drives it at 30, 75, 144 and 240 Hz over a 60 Hz run: the frame-to-frame travel
  is perfectly even with the blend; without it the spring still hides most of the tick, but 2.7 percent of the travel
  is uneven at 144 Hz. The body is blended by the engine's own physics
  interpolation (on since #344), and the rig is switched off for it so the two do not stack:
  [physics interpolation](physics-interpolation.md).
- **The sweeps.** From the true head (never from the lagging pivot, which can be behind a corner): a sphere to the
  shoulder, then back along the view, then a straight sweep to the lens so the head is always in sight. A wall at the
  shoulder slides the camera in behind the player (issue #76); a wall behind brings it forward until the body hides.
- **Steady-state lag matters more than settle time.** Choosing a follow rate by "95 percent in 0.3 s" gave 0.5 m of
  lag at a run, which read as a floaty camera; the rate was raised until the lag at a run is about 0.4 m.

## Hip fire

Firing without aiming turns the body to the view and raises the weapon, and **does nothing to the camera**: no zoom, no
shoulder or arm change, no sprint effect eased out (the maintainer, 2026-11-02, testing the Discord Activity, #464: "When
a player hip fires let's remove the zoom effect at all. We'll just reserve the aim zoom just for aim as intended. We can
always revisit the zoom on hipfire again later on."). How it got here: #300 gave hip fire its own half zoom and the gun
jumped between poses; #417 made hip fire *the aim held for a moment* with one weight for the camera, the body and the
hands; #433 stopped a shot fired while aiming from starting that hold; #464 took the camera out of it. What other games
do, and what is and is not sourced, is in [hip fire](hip-fire.md). The numbers are on `PlayerTuning` (the *Hip fire*
group), so they are editable in the Godot editor:

| Value | Number | Why |
| --- | --- | --- |
| Hold | 0.8 s | The body and the hands keep the aim pose this long after the trigger is let go (`PlayerMotionState.holds_aim`). Longer than the rifle's 0.55 s interval, so a rifle fired steadily never swings the body in and out; the slowest weapon (0.9 s) lets go a little between shots and re-enters, which reads as a shotgun kick. The camera does not read it. |
| Turn speed | 8 rad/s (`aim_turn_speed`, one for the button and the shot) | A view 75 degrees away is faced in 0.16 s, 180 degrees in 0.4 s. The weapon turns with the body and with the pose weight, so the two add: a slower body turn keeps the weapon's peak at about 19 degrees a tick (the aim button turned it 78 degrees in one tick when the weapon switched poses). |
| Zoom, shoulder, arm, FOV | the aim button's only | 60 to 40 degrees and back at `aim_frequency` (24 rad/s, 95 % in 0.2 s), in and out. A shot never moves them, so letting go of the aim lets go of the zoom at once, with nothing held over (#428, #464). |

How it works:

- **The trigger is part of the player's command** (`PlayerCommand.fire`), because the body's facing is simulated state
  the server owns and a replay must agree on. `NightServer` sets it from the `NightCommand`'s own `fire` (a human, the
  autopilot and a remote client all send that), and a downed player's trigger does nothing. `PlayerMotionState.fire_age`
  is the seconds since the trigger was last held **without the aim button** (a shot fired while aiming does not restart
  it, #428); `holds_aim(hold)` is `aiming or fire_age < hold`, and the simulation asks it for the body's turn to the
  view and for the strafing velocity. The muzzle of a shot is rotated by this facing, so it leaves from a body that
  faces the target.
- **Shots are still the camera ray.** The camera's yaw and pitch are the input as before, and `AimResolver` aims the
  muzzle at what the camera ray hits; a test checks the camera's forward vector equals the view's yaw and pitch.
- **The camera reads the aim button only.** `ThirdPersonCamera.aiming` is the one input of its `_aim` spring: the zoom,
  the shoulder, the arm, the look's steadiness (`steady_amount()` is the same weight) and the sprint pull-back and sway
  (they ease out for the button, not for a shot, so a hip shot while sprinting leaves the framing as it was). The camera
  has no `aim_held` any more.
- **The weapon's pose has its own weight.** `PlayerAnimation` eases one weight (`aim_weight()`, `aim_frequency`) toward
  `holds_aim(hold)`, and the legs' aim gait and the hands read it. In the hands `WeaponHandsIK.aim_yaw` is the angle from
  the body's heading to the view by the weight, and `converge` (0 to 1) blends the aim basis toward the one that crosses
  the crosshair's ray, so neither input flips. For the aim button it is the same curve the camera's weight follows.
- **Sprint** is not cancelled by firing (the bots flee and shoot together, and the balance gate does not move).

## The downed camera

While the player is down the rig keeps no standing view: it sinks and tips toward the body lying at the player's
place (#532). Before, the pivot stayed at 1.6 m and the pitch stayed the player's, so the body lay at the bottom edge,
cut off, and looking down with the mouse raised the lens (the arm swings up with the pitch) without bringing it in.

| Value (`PlayerTuning`, *Downed camera*) | Number | Why |
| --- | --- | --- |
| `downed_pivot_height` | 0.8 m (standing 1.6, crouched 1.1) | About the height of the lying body's back plus room: the lens drops with it, to about 1.8 m. Lower puts the lens close to the ground and a car or a wall in the picture. |
| `downed_pitch_degrees` | 20 | Laid over the player's own pitch (never written into it): with the pivot at 0.8 m the body sits below the middle of the picture, and tipping brings it up to the lower left, whole, with room around it. |
| `downed_frequency` | 5 rad/s (95 % in 0.95 s) | Slower than the body's own fall (6 per second): the view arrives as the body settles, and the revive eases back at the same rate. |

How it works: `Player.tick` copies `PlayerAnimation.is_downed()` into `ThirdPersonCamera.downed`; the rig has one more
spring (`downed_amount()`, 0 to 1) that lerps the pivot height and tips the drawn pitch (`view_pitch()`; `pitch`
stays the player's). The pivot's own vertical spring follows the target on top, so a drop is two eases in a row.
`snap_to` starts at the final value for a player who spawns or teleports down. The aim ray (`aim_transform()`) is the
drawn view: a downed player has the weapon put away and no shot. Not framed: a player who looks up on purpose (that is
theirs), and what a car or a wall puts between the lens and the body (the wall sweep pulls the lens in as ever).
`game/tests/player/test_downed_camera.gd` drives a real down (the rules' blow) and a revive (a teammate holding use) and
projects every bone of the player's skeleton (fingers apart) through the real camera: all inside the frame, at four looks,
where the standing camera cuts some. The capture `game/tests/captures/downed_camera.tscn` saves the stages.

## Who owns the view (#702)

Every body is `player.tscn`, and its `Camera3D` is saved `current`; a camera that enters the tree as current takes the
viewport, so with bots the last body seated had the view ("my camera is stuck to a bot"). Only the person's body owns
a camera: `NightWorld.add_body` calls `Player.release_view()` on every body that is not the person's (a puppet does the
same). `game/tests/night/test_night_camera_owner.gd` asks the viewport's current camera which body owns it, after the
spawn, a bot downed and raised, the person downed and raised, a late seat, and through the Play screen's own path;
`tools/web_smoke/camera_owner.py` reads `view_is_players` from the page in the web job. Captures no longer need
`make_current()` for this; the capture `game/tests/captures/camera_owner_tour.tscn` plays the real Solo flow with 3 bots.

## A rig no one looks through (#938)

A body no one looks through does not run its rig in every drawn frame: a bot's (the `bot` flag of its join), a body
that draws nothing (a game server's), a puppet, and the autopilot's under the spectator camera
(`Player.make_viewless()` -> `ThirdPersonCamera.rest()`). Its `Player.tick` tells the rig the look instead
(`aim_along(head, command.yaw, command.pitch)`), which is all the weapon's pose reads; a bot's shot never read the rig
(its command carries the origin and the direction). `Player.look_through()` makes a body the view again (the
autopilot under the shoulder camera). The bodies a sweep passes through are a static list kept on `tree_entered` and
`tree_exiting`, not a group lookup in every step. `game/tests/night/test_viewless_rigs.gd` counts the rigs that
process in a built night (1 with a person and three bots, 0 under the spectator camera) and checks the rest's look and
the list. The cost: kit page `docs/godot/camera.md` ("A rig no one looks through"). Before this, a bot's rig kept the
spawn's yaw and pitch (0) for the whole night, and so did what read them.

## Things found the hard way

- `PhysicsDirectSpaceState3D.cast_motion` ignores a body the sweep already starts inside, so every sweep must start
  from a point known to be clear (the head, then the shoulder point), never from the lagging pivot alone.
- CSG walls (`use_collision`) are concave shapes: a capsule or a point lying inside a thin wall is not reported by
  `intersect_shape` or `intersect_point`. A sweep test that samples standing places must take them from the navigation
  mesh (`test_drive_in_camera_sweep.gd` does), not from "a body fits here": the first version sampled the lot's
  outside corner and the tops of walls and reported thousands of false failures.
- Movie Maker gives `_process` a fixed delta (0.1 s at 10 fps) with several physics ticks per frame, so an Euler or
  `lerp(a, b, k)` ease behaves differently in a capture than in play; the closed-form spring gives the same path.
