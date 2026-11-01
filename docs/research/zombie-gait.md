# Zombie gait: feet that keep up with the ground

The dead's pace runs from 0.5 m/s (a round 1 brute) to 6.25 m/s (a late runner in the dark), but the walk and run
clips cover one ground speed each. Played at their authored rate they slid: the Run clip at 6 m/s moved its feet at
about 4.4 m/s. This page is how the gait follows the speed now (`ZombieRig`), and what the measurements were.

## What the clips cover

Measured on the rig (a walker, scaled by the game's 1.3): the planted foot's backward travel in the stance frames
(the foot within 20 % of its own lift from its lowest point), median over the cycle. Other variants are the same
clips on a body scaled by their height, so their speed is the walker's times `ZombieModels.HEIGHTS`
(brute 1.136 against the walker's 0.963 on the Walk, runner 4.68 against 4.38 on the Run).

| Clip | Length | Ground speed it covers | Note |
| --- | ---: | ---: | --- |
| `Walk` | 1.33 s | 0.97 m/s | stance 60 % of the cycle |
| `Run` | 0.67 s | 4.4 m/s | stance 23 %: a flight phase, so the median is stable only from 0.2 to 0.3 of the lift |
| `Sprint` | 0.67 s | 6.5 m/s | authored (#278): the foot sweeps at one speed, a stable reading ([below](#the-sprint)) |
| `Crawl` | 1.67 s | 1.1 m/s | read on the hands (`LowerArm`), the feet of a crawler are dragged |
| `Boss_Walk` | 1.67 s | 1.1 m/s | the file is already at the headliner's size |

## What the rig does with it

- The move state is a blend space (idle 0, walk 0.97, run 4.4) behind a time scale; the crawl state is the clip behind
  one. `ZombieView` sets both from the entry's speed (`blend_position`, `gait_rate`), only when the speed changes by
  a step, as the blend was set before.
- Blending walk and run poses is not linear in feet speed: the clips are different lengths and out of phase, so a
  half-and-half blend was slower than its position said and its planted foot slid up to 80 % (measured). So the gait
  crosses over between 1.4 and 3.0 m/s (`CROSS_FROM`, `CROSS_TO`, smoothstep) where the walk is played at about 1.45
  and the run at about 0.7, whose cadences are alike (a 0.9 to 1.0 s cycle), and the rate is solved from the weighted
  strides over the weighted cycle (`blend_speed`), so that the blend covers exactly the ground speed.
- The rate is limited to 0.5 to 1.6. Below the walk (a round 1 brute at 0.48 m/s) the idle fades in only under
  0.45 m/s, so a creeping zombie is still a slow walk, not half an idle.
- Past the run the sprint comes in: `Run` (4.4) and `Sprint` (6.5) share the 16-frame cycle and step together, so the
  blend between them is linear in ground speed and plays at rate 1 (`sprint_weight`). The dark runner at 6.25 m/s
  (5.84 on a walker's scale) is 69 % sprint at rate 1.0, where it was the run at 1.42; past 6.5 the sprint is
  played faster.
- The footsteps follow (`ZombieVoiceTable.cycle_seconds` is the clip length over the same rate).
- The animation throttle needs nothing: the rate is a node in the tree, and the throttle advances the tree with the
  time it saved up, which a test checks against stepping every frame.

## Result

`test_zombie_gait` steps the real rig at 60 Hz and reads the planted foot: over the walker, runner and brute at rounds
1, 10 and 20, lit and dark, the median of ground speed over foot speed is 1.09 (1.07 before the sprint) and every gait
is between 0.7 and 1.8 (worst 1.68, the brute in the dark at the crossing). Before, the blend and the rate were the
speed alone: the dark runner's Run slid by 1.4 (6.25 over 4.4), and a mid-blend walker by 1.3.

## The sprint

`Sprint` (`tools/blender/build_zombie_clips.py`, #278) is built from the kit Run frame by frame:

- **The kit Run already reaches as far as the legs do.** Thigh 0.24 m and shin 0.26 m (kit scale) with the hips about
  0.4 m up leave a planted foot about 0.3 m either side of the hip, which is the kit's contact. A 1.5 times longer
  stride on the ground was out of reach by up to 0.18 m (the boot stretches off the shin), and pulling the feet back
  into reach lifted the touchdown off the ground.
- **So the contact is shorter, not longer.** Each foot sweeps the kit's contact length at one steady speed (7.0 m/s,
  2.7 frames instead of 4), touches down and lifts off already moving at it, and the kit's swing fills the rest of
  the cycle, 1.25 times higher. The zombie flies further between steps: at the same cadence the footprints are 6.5 /
  4.4 times further apart.
- The hips drop 5 cm, the trunk leans 22 degrees more (Body, Abdomen, Torso; the head comes back to look ahead), the
  arm swing is 1.6 times the Run's with 18 degrees more elbow bend. The legs are solved to meet the feet by a two-bone
  solve in the kit knee's plane (Blender's IK cannot: the imported bones' tails are arbitrary).
- **Measured** the same way as the others: 6.52 m/s in Godot (`test_each_clip_covers_the_speed_its_blend_point_says`),
  6.6 in Blender's copy of the measure (`ground_speed` in `clips.json`), against the 7.0 sweep: the touchdown frame
  is interpolated with the swing frame before it. The kit Run reads 4.4 in Godot but 5.7 in Blender: its planted foot
  barely moves at touchdown and then sweeps fast, so its median flips with the sampling. A steady sweep does not.

Side views of the Run and the Sprint, frame by frame: `tools/blender/render_gait.py`; in Godot, lanes at the Run's
speed, 5.4 m/s and a round 20 dark runner, and the same runners from the shoulder camera:
`game/tests/captures/zombie_sprint.tscn`.

## Left open

- The walk and the run are not in phase, which is why they are not blended for long; a phase-matched pair would
  allow a smooth jog between them.
- The crossover over-steps at some speeds between the cases the test checks: a round 8 walker under the lights
  (2.32 m/s) has its feet at 3.6 m/s, a slide of 0.65 against the test's 0.7 floor
  ([movement speeds](movement-speeds.md#what-the-chase-clips-show), `tests/captures/gait_at_speeds.tscn`).
