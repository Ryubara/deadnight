# Character controller: omni movement

The maintainer, after playing: "we can't sprint while walking backwards. Our character controller needs improvements
for omni movement. It needs to feel good to play", with the third-person controller of Ghost Recon Wildlands as the feel
to reach. This page is our own design for that feel. [Player controller](player-controller.md) has the structure (the
command, the state, the simulation) and [shoulder camera](shoulder-camera.md) the camera; this is what the body does.

## What the reference does, and what we know of it

Original work: that game is studied for how it behaves; nothing of it is copied, and every number below is our own.

What public text says is thin. The control listings name Move, Sprint, Walk, Crouch, Crawl, Jump and Dive as the
movement actions, with aim (hold) apart in combat
([Gamepressure, PC controls](https://www.gamepressure.com/ghost-recon-wildlands/pc/z99808)); the Prima guide says
sprint is faster "but countered with more noise" and that aim is a full aim-down-sights view on hold
([Prima Games eGuide](https://primagames.com/eguides/tom-clancys-ghost-recon-wildlands-eguide/spec-ops-training/basic-gameplay),
read through a search summary: the page itself refused a fetch). No article, review or talk we could reach gives
turn rates, accelerations or the sprint-while-aiming rules. The conventions below are therefore the ones that
third-person shooters of its kind share, which engine docs and practitioners describe
([strafing against orient-to-movement](https://forums.unrealengine.com/t/allow-strafing-while-using-orient-rotation-to-movement/475956),
[a torso that tracks the aim over legs that follow the movement](https://docs.overdare.com/script-manual/tps-strafing-system)),
and the ones the maintainer described. **We have not measured the reference's footage frame by frame**; the maintainer
checks the feel by playing, and every value is an exported `PlayerTuning` field to tweak in the editor.

## Two modes

| | Free (not aiming) | Aiming |
| --- | --- | --- |
| Body faces | the way it travels | the view (strafe) |
| Camera | wide, follows; pulls out a little when sprinting | zoomed over the shoulder |
| Speed | run, or sprint in **any** direction | slow; slower backing away from the view |
| Turning | an arc at the turn rate, a pivot on a reversal | the body catches the view at once |

## The conventions and how we do them

| Convention | How we do it | Value (`PlayerTuning`) |
| --- | --- | --- |
| Free movement is relative to the camera, and the body turns to the input direction: holding back turns the character around to run toward the camera, it never backpedals | `_face` turns the body toward the wish direction (camera yaw + stick) at a fixed rate; no backward walk exists outside aiming | `turn_speed` 14 rad/s |
| Sprint works in every direction when not aiming (the body faces its travel, so a sprint toward the camera is a sprint like any other) | `_sprint_allowed` no longer asks for forward input | `sprint_speed` 7.0 in all directions; `sprint_min_input` 0.5 |
| The body and the velocity turn together, so it faces where it goes (no skating) and a change of direction is an arc | the velocity vector is rotated toward the wish at the same rate as the body, then its length follows the speed curve | `turn_speed` 14 (arc radius 0.34 m at a run), `sprint_turn_speed` 9 (0.78 m at a sprint: more weight) |
| A reversal is a plant-and-pivot, not an arc and not a moonwalk | wider than the pivot angle: the speed is shed along the old heading, the body turns on the spot faster than normal, and it does not hurry until it faces the way | `pivot_angle_degrees` 100, `pivot_turn_speed` 22 (180 degrees in 0.14 s), `pivot_brake` 40 m/s2, `pivot_walk_speed` 1.5 |
| Starting and stopping have weight: a sprint builds up and carries on a little, a run is snappier | two gain rates (to the run speed, above it) and two frictions (from a run, from a sprint); easing from a sprint to a run or an aim is gentler than a stop | `ground_acceleration` 38, `sprint_acceleration` 18, `ground_friction` 44, `sprint_friction` 30, `ground_deceleration` 30 |
| Aiming switches to a strafe: the body faces the view, moves slower, and backing away is slower still | `_face` turns to the view yaw; the velocity goes straight to the wish; the target speed is lerped to the backpedal scale by how far back the input points | `aim_turn_speed` 8, `aim_speed` 2.6, `aim_backpedal_scale` 0.75 |
| Aim cancels sprint | `sprinting` is false while `command.aim`; the speed eases down at `ground_deceleration` and the camera pull-back lets go | |
| Sprint after aim | release the aim and the sprint key held down sprints again at once (the gain rates apply from the aim speed) | |
| A nudge of the stick is not a sprint | the sprint key needs the input pushed past a threshold | `sprint_min_input` 0.5 |
| A sprint carries through a jump | `sprinting` stays true in the air while the key is held, so the camera does not flicker in and out of its pull-back | |
| Firing from the hip turns the body to the view | `holds_aim`: the same turn as the aim, kept for `hip_fire_hold` after the trigger (it comes before the travel turn in `_face`). Firing does not yet cancel a sprint | left for when #313 lands |
| Slopes and stairs | the body keeps `move_and_slide`'s defaults (45 degree floor, 0.1 m snap) and the player has no step-up: a low ledge needs a jump. Not changed here | step-up and a floor snap for sprinting down slopes: #78 |

## The numbers, before and after

All measured from the capture run (`tests/player/capture_omni.gd`, 60 Hz ticks, camera yaw 0) and the tests.

| | Before | After |
| --- | --- | --- |
| Sprint forward / sideways / backward | 7.0 / 4.8 (run) / 4.8 (run) | 7.0 / 7.0 / 7.0 |
| Time to run speed from standing | 0.13 s | 0.13 s |
| Time to sprint speed from standing | 0.18 s | 0.25 s |
| Stopping from a sprint (distance slid) | 7 m/s to 0 in 0.16 s (0.56 m) | about 0.7 m in 0.2 s (friction 30 above the run speed, then 44) |
| A forward sprint reversed to a back sprint | the sprint ends; the speed is 0.6 m/s at 0.2 s, then a run (4.8) the other way | the sprint continues; 0.9 m/s at 0.2 s, 7.0 at 0.45 s, facing 180 degrees |
| Pull-back of the sprint camera | 0.3 m, spring 9 rad/s (95 percent in 0.53 s) | 0.15 m, spring 13.5 rad/s (95 percent in 0.35 s) |

The sprint camera's other parts are unchanged: +6 degrees of FOV and the looser follow at 16 rad/s (0.9 m of lag at
7 m/s). The maintainer asked for the pull-back distance and time; whether the FOV kick wants the same cut is a feel
question for the next play.

## Animation: no sliding in any direction

The Soldier has one locomotion set, and the body always faces its travel when not aiming, so every sprint plays the
Run clip forward, its pace tied to the ground speed (`speed / run_clip_speed`, 1.63 at 7 m/s). Because the velocity
turns with the body, the two never part by more than a tick of turning. While aiming the body faces the view but moves
sideways or backward: the strafe and back clips of PR #330 are not merged, so those directions still play the forward
Run or Walk blend under the aim (the known gap of issue #74). The blend reads `state.velocity` only, so adding the
clips later changes `PlayerAnimation` and nothing in the simulation.

## Network and tests

All of it is in `PlayerSimulation`, a function of the command and the state, with the tuning resource as its only other
input: the replay and the server run the same code. The state gained nothing; `sprinting` and `facing` were already in
it. `tests/player/test_omni_movement.gd` runs the simulation through `PlayerCommand`s: sprint in the eight directions
(and not while aiming), the body's facing and heading, the turn rates, the arc, the pivot and its timing, the curves,
the strafe, and a 480-command replay (every direction, an aim, jumps) recorded as bytes and played again to the same
position, velocity and facing.

## Left for later

- Strafe, back and Walk_Shoot clips while aiming (PR #330), and a turn-in-place clip; none exists, so a pivot is the Run
  clip turning.
- Firing from the hip should end a sprint (PR #313 carries the state to know it).
- Step up low ledges and a floor snap on steep ramps at sprint speed (#78).
- A sprint limit is a design question (#236).
