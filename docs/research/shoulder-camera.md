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
| FOV (vertical) | 75 | 70 | Less world around him; 70 vertical is about 102 horizontal at 16:9, not a fish-eye. |
| Aim: arm, offset, FOV | 1.9 m, 0.6 m, 62 | 1.8 m, 0.65 m, 60 | The research table suggested 1.3 m, 0.4 m, 55; that puts the right pad 5 degrees from the reticle (issue #109). A test needs 0.2 m of air between the body and the centre ray. |
| Follow spring | exponential, none | 22 rad/s on the ground plane, 10 vertically (95 percent in 0.22 s and 0.48 s) | A critically damped spring trails a steady runner by 2 v / w: 0.4 m at a run. The slower vertical follow keeps a jump from whipping the view. |
| Sprint | none | +6 degrees FOV, +0.3 m arm, follow 16 rad/s (0.9 m of lag at 7 m/s), eased at 9 rad/s | Speed shows as the character drifting ahead on screen, then settling. |
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
  is uneven at 144 Hz.
- **The sweeps.** From the true head (never from the lagging pivot, which can be behind a corner): a sphere to the
  shoulder, then back along the view, then a straight sweep to the lens so the head is always in sight. A wall at the
  shoulder slides the camera in behind the player (issue #76); a wall behind brings it forward until the body hides.
- **Steady-state lag matters more than settle time.** Choosing a follow rate by "95 percent in 0.3 s" gave 0.5 m of
  lag at a run, which read as a floaty camera; the rate was raised until the lag at a run is about 0.4 m.

## Hip fire

Firing without aiming (maintainer feedback, 2026-11-01, #300): the shot already lands on the reticle, but the body kept
its walking facing and the view stayed wide, unlike other third-person shooters. Now, while the trigger is held without
the aim button, and for a short time after, **the body turns to the view** and **the camera eases part of the way into
the aim view**. What other games do, and what is and is not sourced, is in [hip fire](hip-fire.md). The numbers are
on `PlayerTuning` (the *Hip fire* group), so they are editable in the Godot editor:

| Value | Number | Why |
| --- | --- | --- |
| Turn speed | 22 rad/s | Just under the aim turn (24): a 180 degree swing takes 0.14 s (9 ticks), so the first shot of a burst leaves from a body that already faces the target, and the turn is still visible. Not an instant snap: the soldier's shoulders would pop. |
| Hold | 0.6 s | The body keeps facing the view this long after the trigger is let go. The slowest weapon fires every 0.9 s, the rifle every 0.55 s, so single shots inside a fight do not swing the body back to the run direction between them; two seconds would look stuck. |
| Zoom share | 0.5 | Halfway between the hip view and the full aim view: arm 2.3 to 2.05 m, FOV 70 to 65, shoulder 0.60 to 0.625 m. Enough to read as settling in; the aim view (arm 1.8 m, FOV 60) stays the precise one. |
| Zoom delay | 0.8 s | After the last shot before the zoom lets go. Longer than the 0.55 s rifle interval, so a rifle fired steadily never pulses the view in and out; the slowest weapon (0.9 s) lets go a little between shots and re-zooms, which reads as a shotgun kick. |
| Zoom in, out | 14, 7 rad/s | Springs: 95 % in 0.34 s in and 0.68 s out. The way out is half as quick, so the view does not snap back between two bursts; the way in is a little slower than the aim's 24 (0.2 s), because a shot is not a decision to aim. |

How it works:

- **The trigger is part of the player's command** (`PlayerCommand.fire`), because the body's facing is simulated state
  the server owns and a replay must agree on. `NightServer` sets it from the `NightCommand`'s own `fire` (a human, the
  autopilot and a remote client all send that), and a downed player's trigger does nothing. `PlayerMotionState.fire_age`
  is the seconds since the trigger was last held; the simulation turns the body to `command.yaw` at the hip-fire speed
  while `fire_age < hip_fire_hold` (aiming keeps its own, faster turn and wins). The muzzle of a shot is rotated by this
  facing, so it now leaves from a body that faces the target.
- **Shots are still the camera ray.** The camera's yaw and pitch are the input as before, the zoom only moves the lens
  along its arm, and `AimResolver` aims the muzzle at what the camera ray hits; a test checks the camera's forward
  vector equals the view's yaw and pitch while zoomed.
- **The camera** keeps a separate spring (`_hip`, 0 or 1) next to the aim spring; the placement reads
  `zoom_amount() = aim + (1 - aim) * hip * hip_fire_zoom`, so pressing aim during a burst continues smoothly to the
  full aim view, and releasing everything goes back to the hip view. The look sensitivity still reads only the aim
  amount: a burst from the hip does not slow the view.
- **Sprint** is not cancelled by firing (the bots flee and shoot together, and the balance gate does not move): the
  sprint pull-back and the hip-fire zoom add.

## Things found the hard way

- `PhysicsDirectSpaceState3D.cast_motion` ignores a body the sweep already starts inside, so every sweep must start
  from a point known to be clear (the head, then the shoulder point), never from the lagging pivot alone.
- CSG walls (`use_collision`) are concave shapes: a capsule or a point lying inside a thin wall is not reported by
  `intersect_shape` or `intersect_point`. A sweep test that samples standing places must take them from the navigation
  mesh (`test_drive_in_camera_sweep.gd` does), not from "a body fits here": the first version sampled the lot's
  outside corner and the tops of walls and reported thousands of false failures.
- Movie Maker gives `_process` a fixed delta (0.1 s at 10 fps) with several physics ticks per frame, so an Euler or
  `lerp(a, b, k)` ease behaves differently in a capture than in play; the closed-form spring gives the same path.
