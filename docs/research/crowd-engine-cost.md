# The crowd's engine cost at the desktop ceiling

[#949](https://github.com/Ryubara/deadnight/issues/949), from the performance sweep of #906. The sweep wrote down "about
8 ms of a 20 ms frame is the engine drawing and animating the crowd" as what was left after the labelled script. This
page measures it. The method and the general findings are in the kit's `docs/godot/crowds.md` ("What a crowd costs at
the ceiling, in the real night").

## Method

The real night (`AutopilotRun`, the shipped rules, lot, HUD, lights and sounds), round 12, 3x, three bots, the desktop
ceiling (cap 99), windowed on an RTX 5080 (Compatibility, 1280 x 720), steady state (at least 70 dead standing),
a row a second from the sampler of the profile pull request (frame, process and physics time, draw calls, triangles).
Arms, run one after the other so the machine's load falls on both: the night as it is; `dead=0` (the dead hidden from
drawing, their views still moving and animating); `anim=0` (the animation throttle stopped); the throttle before and
after this change (six pairs, the order flipped in the second three). `census=1` prints a line a second: the views by
distance band and throttle tier, the animations advanced a frame, the renderer's CPU and GPU time for the viewport.
The arguments are in `game/tools/bench/ablation.gd`. Machine shared with other agents' runs: a time is read as a ratio of
arms run together, and counts come first.

## What the engine spends on the dead

| Arm (two runs, medians) | Frame | Render CPU | Render GPU | Draw calls | Triangles | Advances a frame |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| the night as it was | 17.0 ms | 2.46 ms | 0.87 ms | 427 | 146 k | 9.4 |
| the dead hidden from drawing | 15.8 ms | 2.28 ms | 0.78 ms | 420 | 104 k | 9.3 |
| the throttle stopped | 14.6 ms | 2.2 ms | 0.7 ms | 423 | 142 k | 0 |

- **Drawing the dead is small**: 7 to 20 draw calls and 25 to 40 thousand triangles of 427 and 140 thousand, 0.2 ms of
  the renderer's CPU time, 1.2 ms of frame. The 135 skeletons of the sweep were 92 standing and the pooled bodies, and
  the pooled ones are hidden and not advanced (`ZombieView.park`).
- **The crowd is not on screen.** The census of a steady second at 87 views: 3 within 14 m of the camera, 7 within 24 m,
  10 within 40 m and **67 beyond 40 m**; 4 to 27 in the frustum. The throttle's tiers (every frame, 3rd, 6th,
  12th) put 69 views at period 12 and made 7 of the 9.4 advances a frame there.
- **An animation advance** (the blend tree and the 50-bone skeleton update) takes about **41 microseconds of CPU**
  (92 views advanced in a loop, headless: 34 microseconds for `tree.advance`, 7 for the skeleton's update on the frame's
  flush). The ablation put the animation at 1 to 2.4 ms of the frame, more than 9.4 x 41 microseconds: the rest is the
  skinned meshes' work in the renderer, which a stopped throttle also removes for the dead in view.

## What changed

`AnimationThrottle` has a tier for the dead nobody can see: no point of the body (feet, chest, head with its reach) in
the camera's frustum, and the view is **not advanced at all** (`PERIOD_UNSEEN`), looked at again every 4th frame and
advanced at once when seen, with at most a quarter second of catch-up (a swing that began out of view still plays from
its start; a starting phase longer than that is kept). In view, past 40 m a zombie is advanced every 12th frame (it was
every 6th). Nothing else moved: the server, the wire, the views' mode and gait still follow every entry.

## Cost

| | Before | After |
| --- | ---: | ---: |
| Animations advanced a frame at 82 to 89 dead (census, 3 runs each) | 9.4 | **2.8** |
| CPU of the advances (41 microseconds each) | 0.39 ms | 0.11 ms |
| Frame median, pooled seconds of 6 pairs (76 and 78 seconds) | 16.0 ms | 15.2 ms |
| Frame mean | 16.8 ms | 16.85 ms |
| Draw calls, triangles | 425, 138 k | 429, 138 k |

The frame times are inside the machine's noise (the runs' medians went from 11.8 to 23.2 ms for the same code): the
saving that is proved is the **advances (-70 %) and their CPU (-0.28 ms a frame on the desktop)**; a browser is about
three times slower per call (crowds spike), so about 0.8 ms there, and a crowd that stands closer to the camera saves
less. It scales with the dead out of view (the throttle's loop over the views and the `RETIER` test remain, 0.5 ms).
The scenes that put the dead in front of the camera (the crowd at the boards, a turn into a crowd) lose nothing: the
pictures below.

## The look

`game/tests/captures/crowd_turn.tscn` (`--zombies=99 --warmup=45`, `--fixed-fps 60`): the camera at a player's eye looks
away from the crowd and turns to it over 18 frames, a picture at the frames round the turn, before and after this
change. The dead that were out of view are in a walking pose (not the bind pose) the frame they come in, and after the
turn the two runs differ only in the phase of each stride. A late-round night from the player's own camera shows few
dead, because they queue at the boards 30 to 60 m away (the census above).

## Not done

- The 8 ms is not explained: the dead are 1.2 ms of drawing and 1 to 2.4 ms of animation. The frame's remainder is the lot
  (400 draw calls), the HUD (1.5 to 3 ms, [#948](https://github.com/Ryubara/deadnight/issues/948)), the physics server and
  the waits. A GPU capture would split it; the sweep's labelled script (12 ms) is the larger part of the frame.
- A shared far pose or a lower bone count for the dead in view past 40 m: they are 10 to 20 of the 99 and advance at
  period 12.
