# Mouse look under lag

Why the mouse look went "weird" when frames dropped, how it was measured, and what fixed it (issue #905). The
maintainer, playing a night with three bots in the editor: "our mouse movement gets a bit weird when it lags, no other
games do this when it lags". The general rules are in the kit's page "Mouse look at any frame rate"
(`docs/godot/mouse-look.md`); this page has the game's numbers.

## What the shooters do, and what we already did

- The mouse delta is a distance: `relative * radians_per_pixel * sensitivity`, once per event, never times the frame
  time. `Player._unhandled_input` does exactly that (`look_mouse`), and a stick is the only thing scaled by the frame
  time (`ThirdPersonCamera.step`). Neither was the fault.
- The view is placed on the drawn frame: `ThirdPersonCamera._process`. The rig is `PHYSICS_INTERPOLATION_MODE_OFF`, so
  the engine does not blend it a second time (`docs/research/physics-interpolation.md`).
- Smoothing is optional and in seconds: `LookSmoother` is the touch layer's alone (#598, #889). The mouse has none.
- Godot's own input accumulation (`Input.use_accumulated_input`, on) merges a frame's motions into one event at the
  start of the frame; the total is unchanged.

## Cause

`ThirdPersonCamera._place` assigned the child `Camera3D`'s `global_transform` and **then** moved its parent (the
`top_level` rig: new yaw, new pivot). A child keeps its local transform, so the lens was drawn at
`new_rig * old_rig^-1 * wanted`: the right view plus one more step of the rig's last turn, and its place swung round the
pivot by the same step. The rig's `yaw` and `pitch` (what a shot reads, what every look test read) were exact; only what
the renderer drew was wrong. With frames of equal size and a steady hand it is a constant lead of one frame's turn, which
nobody sees. With uneven frames, or a mouse that reports unevenly against them, the drawn turn per frame is
`2 s[k] - s[k-1]`: a frame without mouse turns the view **back** by the last step, and a long frame overshoots by its
whole turn and snaps back on the next. A lag spike is exactly that, which is why it only showed when it lagged.

Gamepad (the stick turns the same rig every frame) and touch (it sends mouse motions to the same rig) went through the
same place. It was there since the shoulder camera rework (#263).

## Measurement

`game/tests/captures/look_lag_probe.gd` replays one recorded mouse path (`look_path.txt`, 12 s, seeded, whole pixels
one a millisecond: flicks of 300 to 1200 pixels, slow tracking, pauses) through the real input path of a real night:
`Input.parse_input_event` for every millisecond since the last frame, handled at once, so the player's own
`_unhandled_input` turns the rig and the next frame draws it. The frame rate is held with `Engine.max_fps`, hitches are
`OS.delay_msec` in every nth frame, `--ticks=3` runs three night ticks a physics frame. It runs solo (`Night.start`)
and as a client of a game server on this machine (`Night.start_remote`, with its prediction and reconciliation), headless.
Each frame it writes the rig's yaw, the Camera3D's own yaw, the frame length, the physics ticks it ran and the path posted
so far. `tools/look/run_matrix.py` runs the matrix, `tools/look/analyse.py` prints the table,
`tools/look/plot_compare.py` draws the plots.

Columns: **fps** is the rate the run achieved (a headless night with its dead is not free, so the 30 and 15 runs
ran slower than their cap); **over** is the most, in degrees, the view that was drawn was from where the hand had put
it, in one frame; **back** the frames that turned the drawn view against the hand; **phantom** the frames that turned it
while the hand did not move. The rig's own yaw (**rig over**) was 0.000 degrees in every run, before and after, and every
run ended at the hand's total.

| Run (7 s) | Before: fps | over | back | phantom | After: fps | over | back | phantom |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| solo, cap 144 | 81 | 73.1 | 67 | 106 | 92 | 0.0 | 0 | 0 |
| solo, cap 60 | 53 | 88.2 | 54 | 52 | 42 | 0.0 | 0 | 0 |
| solo, cap 30 | 23 | 63.4 | 21 | 10 | 12 | 0.0 | 0 | 0 |
| solo, cap 15 | 15 | 81.6 | 11 | 9 | 4 | 0.0 | 0 | 0 |
| solo, 60 with a 120 ms hitch every 20th frame | 39 | 99.8 | 40 | 43 | 41 | 0.0 | 0 | 0 |
| solo, 144 with a 60 ms hitch every 10th frame | 64 | 75.6 | 48 | 79 | 42 | 0.0 | 0 | 0 |
| solo, 30, three night ticks a frame | 27 | 89.2 | 24 | 14 | 25 | 0.0 | 0 | 0 |
| client, cap 144 | 53 | 32.6 | 57 | 66 | 90 | 0.0 | 0 | 0 |
| client, cap 60 | 54 | 66.2 | 34 | 55 | 59 | 0.0 | 0 | 0 |
| client, cap 30 | 28 | 72.1 | 23 | 13 | 30 | 0.0 | 0 | 0 |
| client, cap 15 | 14 | 133.5 | 20 | 6 | 15 | 0.0 | 0 | 0 |
| client, 60 with a 120 ms hitch | 35 | 95.7 | 40 | 28 | 44 | 0.0 | 0 | 0 |
| client, 144 with a 60 ms hitch | 36 | 82.1 | 46 | 30 | 71 | 0.0 | 0 | 0 |
| client, 30, three night ticks a frame | 27 | 68.3 | 20 | 13 | 29 | 0.0 | 0 | 0 |

The "after" runs are noisy in fps only because the machine was shared; the point is the columns that are zero.

![The drawn view against the hand, before and after](mouse-look-under-lag.png)

The plot is the second of each run with the most mouse movement: the grey line is the turn the hand has asked for, the
dots are what the camera was drawn at in each frame. Before, the camera runs ahead of the hand on a long frame and jumps
back; after, every dot is on the line, at 60 fps, with a 120 ms hitch and as a client at 15 fps.

## The fix and its test

`_place` now sets the rig's transform first and the lens second (and says why). `tests/player/test_look_frames.gd` replays
a seeded path through the real input path over frames of 1/144, 1/60, 1/30 and 1/15 s and a seeded uneven run with 120 ms
hitches, steps the rig by hand (no real frame length is in it), and reads the Camera3D's transform: the drawn yaw is the
rig's at every frame, no frame turns against the hand or with none, every rate ends at the same total, the stick turns the
same total over a second at every rate, and a client of a game server over a real socket does the same. All six cases
failed on `main` (39 failed assertions) and pass. Touch keeps `LookSmoother` and its frame-independent total
(`tests/ui/touch/test_touch_player.gd`, unchanged and green).

## Found on the way

`InputEventMouseMotion.relative` is in the viewport's units, so the stretch scaled the turn with the window. It was its
own issue and is fixed: [Mouse sensitivity at every window size](mouse-look-window-size.md) (#928).
