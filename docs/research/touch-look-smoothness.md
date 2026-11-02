# Touch look smoothness

Why a slow drag of the look finger turned the camera in jerks on a phone, how it was measured, and what fixed it
(issue #598, after #470 and #497 fixed the size of the turn and the two-finger flick).

## Cause

The touch layer turned the view the moment a finger sample arrived, in the frame the sample landed in. A touch screen
samples at 60 or 120 Hz and the page draws at another rate, so the number of samples per frame is uneven: some frames
turn a whole step and the frames between turn nothing. The drag's size, the gain curve, the dead zone and the aim assist
were not involved (a slow drag stays at gain 1, and no frame ever turned back). The earlier touch tests checked the
total turn and the biggest single frame, never how even the turns were.

## Method

`tools/web_smoke/touch_look_smooth.py` opens the web export in Chrome with phone emulation (779 x 360 CSS pixels, pixel
ratio 3, which the game scales to a 1168 x 540 unit canvas), starts a night, and holds one finger on the look area moving
at a steady 20 or 60 CSS px/s, one touch event every 16.7 ms (a 60 Hz screen) or 8.3 ms (120 Hz), horizontal or
diagonal. For every frame the browser draws, the game's `ViewWebProbe` records the camera's yaw and pitch
(`window.deadnight.viewRows`). The run reports, for the middle of the drag (the first and last 0.3 s are left out):
back steps, frames with no turn, the variation of the per-frame turn (standard deviation over the mean) and of the turn
per second, and the biggest frame over the mean. A second configuration slows the page's main thread four times
(`Emulation.setCPUThrottlingRate`), which gives the 20 to 40 ms frames of a mid-range phone, with several samples in
a frame and not always the same number.

It runs through `gds quiet`, and `--table <folder>` prints the numbers again from a run's frames.

## Numbers (Chrome with a GPU on the development machine)

| Case (steady 20 and 60 px/s, horizontal and diagonal) | Before: still frames | Before: variation | After: still frames | After: variation |
| --- | --- | --- | --- | --- |
| 60 Hz or 120 Hz finger, page at about 175 fps | 275 to 282 of ~420 | 1.38 to 1.41 | 0 | 0.15 to 0.21 |
| 120 Hz finger, page at about 30 fps (CPU x4) | 50 to 71 of ~100 | 1.00 to 1.05 | 0 | 0.31 to 0.41 |

No case had a back step, before or after. The biggest frame over the mean fell from 3.0 to 1.4 to 2.8 (one hitch frame of
the page itself, outside this change). On the 30 fps page the remaining variation is mostly the page's own uneven frame
times.

## What the fix is

`LookSmoother` (`game/ui/touch/look_smoother.gd`): the layer adds each sample's look to a waiting amount and turns the
view a share of it every frame, in proportion to the frame's length over a window of at least 40 ms and at least 2.5
frames (`TouchTuning.look_smoothing`, `look_smoothing_frames`). The sum is kept, so the view ends where the finger put it;
the delay is about the window. A first try with an exponential share (`1 - exp(-dt / tau)`) turned a long frame less than
its length asks, so the share is linear in the frame's length. Tests: `test_look_smoother.gd` (the shapes above, with the
unsmoothed drag as the contrast) and `test_touch_player.gd` (a steady drag through the real input path: no still frame,
no step back, variation under 0.35; it fails with the smoothing off at 1.42).

## A gotcha found on the way

The smoothed motion is sent from `_process`, not from the drag handler. Godot keeps a mouse motion in the input buffer
until the next frame and adds the next one to it under the first one's `device` (`InputEventMouseMotion.accumulate`), so
a stray copy of a finger waiting in the buffer swallowed the layer's own tagged motion and the player dropped both. The
layer now flushes the buffer before and after parsing its motion.
