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
  0.45 m/s, so a creeping zombie is still a slow walk, not half an idle. Past 4.4 m/s the run is played faster:
  1.42 at the dark runner's 6.25 m/s, 1.14 at the cap of 5.0.
- The footsteps follow (`ZombieVoiceTable.cycle_seconds` is the clip length over the same rate).
- The animation throttle needs nothing: the rate is a node in the tree, and the throttle advances the tree with the
  time it saved up, which a test checks against stepping every frame.

## Result

`test_zombie_gait` steps the real rig at 60 Hz and reads the planted foot: over the walker, runner and brute at rounds
1, 10 and 20, lit and dark, the median of ground speed over foot speed is 1.07 and every gait is between 0.7 and 1.8
(worst 1.68, the brute in the dark at the crossing). Before, the blend and the rate were the speed alone: the dark
runner's Run slid by 1.4 (6.25 over 4.4), and a mid-blend walker by 1.3.

## Left open

- No sprint clip: at 6.25 m/s the run is played at 1.42 times and reads as a very fast jog, not a sprint (the stride
  is 1.6 m; the arms and the lean do not change). An authored sprint clip (`tools/blender/build_zombie_clips.py`) is
  a follow-up issue.
- The walk and the run are not in phase, which is why they are not blended for long; a phase-matched pair would
  allow a smooth jog between them.
