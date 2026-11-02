# The Run clip's planted-foot speed

`PlayerTuning.run_clip_speed` is the ground speed at which the Run clip's feet stay put: the Run end of the locomotion
blend plays at ground speed over it, so a body running at that speed has feet that do not slide. It was 5.5 m/s,
estimated from the foot bone's travel (#14). It is now measured (#75), and a test fails when it drifts.

## How it is measured

`game/tests/player/test_run_gait.gd` plays the clip alone on the Soldier, at the game's scale (0.8) and facing, stepped
at 60 Hz by hand, and reads both foot bones off the skeleton each tick.

- A foot is **planted** while it is within 5 cm of its own lowest point in the cycle (the ankle bone rides about 2 cm
  above the floor, so this is the whole contact, heel to toe). A stance shorter than three ticks is ignored.
- A stance's speed is the distance the foot sweeps in the body's frame, from its first planted tick to its last,
  over the time between them; the clip's speed is the mean of both feet's stances. A net distance, not the median of
  tick-to-tick speeds: the foot speeds up through contact (3.4 m/s at the heel, 6.3 at the toe), and it is the average
  that the ground has to match.
- The sweep is toward the back of the body (the test checks the direction), so a foot that is planted stays under
  the ground rather than ahead of it.

| Clip (0.708 s, 17 frames) | Planted foot | Note |
| --- | ---: | --- |
| `Run` | **4.28 m/s** | in the game; `run_clip_speed` is 4.3 |
| `Run_Gun` | 3.23 m/s | unused (the Rifle and Shotgun clips hold the gun over `Run`); a shorter stride, 0.75 of the Run |
| `Walk` | not measured | built from the Run at 60% of its stride, in the clip build |

The cycle is 0.708 s long, so one cycle covers 3.03 m at 4.28 m/s and a footfall comes every 1.52 m:
`PlayerTuning.step_distance` is 1.5 (it was 1.9, half of the old 5.5 m/s cycle), so the footstep sound and the sprint
sway, which count footfalls from it, land when a foot does.

## What it changed

At the 4.8 m/s run the old value played the clip at 0.87 of its rate and the planted foot moved at 3.74 m/s on
ground going by at 4.8: a skate of 22% (the ratio of the ground to the foot was 1.28). The sprint (7 m/s) was the same
share. Measured on the real animation tree (the same test, the player moved by state alone):

| Ground speed | Planted foot, before (5.5) | Planted foot, after (4.3) |
| ---: | ---: | ---: |
| 4.8 m/s (run) | 3.77 m/s | 4.82 m/s |
| 7.0 m/s (sprint) | 5.61 m/s | 7.31 m/s |

The test lets the foot be 6% off the ground (the clip's feet are not a constant speed through contact, and the blend
is fully Run above 2.2 m/s). The cost is cadence: the run plays 1.12x and the sprint 1.63x (they were 0.87x and 1.27x),
so footfalls come at 3.2 a second running and 4.7 sprinting (2.5 and 3.7 before). The sprint sway follows the same
count ([the sprint sway](../design/camera-shake.md#the-sprint-sway)).

![The planted foot against the ground at a 4.8 m/s run, before and after](run-clip-speed.png)

## Left open

- Other players' footsteps (`footstep_sounds.gd`'s own `STEP_DISTANCE`, 1.9 m) should read the tuning's
  `step_distance`; the footsteps pull request has landed, so this is the follow-up to make.
- Below the run (the Walk to Run blend, 0.45 to 0.95 of the blend) the Walk plays at its own pace; no check covers it.
