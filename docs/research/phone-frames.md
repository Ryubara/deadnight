# Phone frames: the cap, the profile and what helped (#689)

A player said the game is flawless on a desktop and lags a little in the Discord Activity on a phone, and asked for the
frame rate to follow the phone's refresh rate. This page is what was measured and what changed.

## Is there a frame cap?

No. Nothing in the project limits the frame rate: no `application/run/max_fps`, no low-processor mode, no physics
tick tied to the render loop. The web build's main loop is the browser's `requestAnimationFrame`, so the game draws
once per display refresh (the Activity's webview, like any Chrome, gives 60 or 120 Hz as the phone allows). The
setting "Vertical sync" does nothing on the web (the browser owns it). With the page's frame pacing off
(`--disable-frame-rate-limit`, `--disable-gpu-vsync`) a desktop Chrome ran the night at 95 to 117 frames a second, so
the game itself does not hold a rate down. Nothing to remove.

The lag is cost, not a cap: a phone cannot finish a frame in 8 or 16 ms.

## How the phone was stood in for

No phone can be driven from here, so `tools/web_smoke/phone_frames.py` runs Chrome as a phone: a page of
844 x 390 with a pixel ratio of 3 (a canvas of 2532 x 1170, what a phone of this class gives the engine), touch on,
the phone user agent, the autopilot night (`?autopilot&count=1`, the crowd grows like a real night) and every
`requestAnimationFrame` delta recorded for minutes. Two weaknesses of a phone are stood in for separately, and
neither stands in for all of it:

- **CPU:** Chrome's CPU throttling (`Emulation.setCPUThrottlingRate`, 3 or 4 times slower). A fast desktop GPU stays
  fast, so this shows script, physics and driver cost but hides fill cost.
- **GPU:** SwiftShader (`--software`, a GPU that draws on the CPU). It is slow at filling pixels the way a weak phone
  GPU is, so it shows fill cost, at an absolute speed that is nothing like a phone's (about 3 frames a second).

Read each result as a ratio between two ways of drawing, never as the frame rate a phone will get.

**Compare inside one page, interleaved.** Runs one after another on this shared machine disagreed by 10 times for the
same setup (the same build at the same pixel ratio gave a median of 28.8 ms in one run and 309 ms in the next,
when other programs started). `--arms name:pixel-ratio-cap:msaa,...` switches a running page between the ways of
drawing every
`--block` seconds (4 s are dropped after each switch, the canvas is reallocated), so every arm sees the same minutes
and the same crowd.

## What a frame costs

The lot at the start of a night, seen by the renderer: about 770 draw calls (620 of them in the 3D view), 150 000
triangles and 1 100 objects (`WebProbe` publishes them as `draw_calls`, `primitives`, `objects` when the page is a
profile). The lot has 76 parked cars (five paints, one surface each) and 1 259 mesh surfaces and 30 lights
in all, so the count is the number of things standing there, not a few heavy ones.
The labelled script work (`PerfProbe`) adds up to about 3 ms a frame at full speed (the server tick 0.5 ms, the
pump 0.4 ms, the crowd 0.1 ms, the audio calls 0.1 ms): the bots and the rules are not what a phone struggles with.

Taking one thing out of the picture (CPU x1, unpaced, p50 / p95 in ms, 45 seconds each, so rough):

| Taken out | p50 | p95 | Draw calls |
| --- | --- | --- | --- |
| nothing | 12.7 | 29.2 | 770 |
| multisampling (2x) | 11.4 | 16.6 | 777 |
| every light | 11.5 | 16.1 | 826 |
| the HUD and touch layer | 11.1 | 16.9 | 706 |
| the whole field area | 11.6 | 27.9 | 732 |
| fog | 12.3 | 29.1 | 826 |
| resolution scale 67 % | 30.1 | 45.5 | 826 |
| resolution scale 50 % | 30.1 | 47.7 | 775 |

- **Resolution scale below 100 % makes the web build slower, not faster** (2.4 times in Chrome, the 3D view is drawn
  into its own texture, then stretched), so it is not the phone's setting. The slider in the settings is for desktops.
- Lights and the HUD cost mostly in the slow frames (p95), not the median, and both are the look, so they stay.
- Culling every mesh beyond 40 m (`cull=40`) cut draw calls from 733 to 507 and triangles from 141 000 to 52 000, for a
  median of 14.5 to 13 ms on a fast GPU. A real gain only for a weak one, and it hides the far buildings too;
  left as an option, not done.

## The changes and what each won

`PhoneRender` (`game/core/phone_render.gd`) does two things, only on a touch device:

1. **The page reports a pixel ratio of at most 2** (a script in `html/head_include` of the web export, overriding
   `window.devicePixelRatio`; `?dprcap=N` sets another number for a test). Godot sizes its canvas by the ratio, so a
   ratio of 3 drew 2532 x 1170 pixels and 2 draws 1688 x 780: 56 % of the pixels. The browser stretches the canvas the
   rest of the way, and 326 pixels to the inch is past what the eye sees at arm's length. Touch positions come from the
   canvas rectangle, not the ratio, so the controls land where they did (checked in a frame capture).
2. **No multisample anti-aliasing on the 3D view** on a phone: the stair-steps it smooths are under one real pixel
   there, and the multisample buffer is the biggest piece of a fill-bound frame.

Measured in one page, three arms interleaved over 10 minutes (30 s blocks):

| GPU stand-in (SwiftShader, CPU x1) | frames | p50 | p95 | p99 | max |
| --- | --- | --- | --- | --- | --- |
| before: ratio 3, 2x MSAA | 314 | 565 ms | 753 | 797 | 1 185 |
| ratio capped at 2, 2x MSAA | 616 | 303 ms | 379 | 595 | 667 |
| after: ratio capped at 2, no MSAA | 830 | 212 ms | 296 | 325 | 356 |

So the pixel cap alone is 1.9 times and the cap with no multisampling 2.7 times faster in a fill-bound frame, and the
99th percentile falls 2.5 times. Per-minute medians of each arm stayed flat over the 10 minutes (590, 583, 580, 436,
697, 678, 681, 453 ms for "before"): no drift. Heat cannot be reproduced in emulation; a real phone that throttles
will see its limit later with fewer pixels to fill, which is the point of the change, but that is a claim, not a
measurement.

| CPU stand-in (Chrome GPU, CPU x4, 10 minutes) | frames | p50 | p95 | p99 |
| --- | --- | --- | --- | --- |
| before | 1 420 | 99.5 ms | 330 | 503 |
| ratio capped at 2, 2x MSAA | 1 193 | 105.6 ms | 395 | 653 |
| after | 1 192 | 117.8 ms | 344 | 536 |

**No win here, and it is said plainly:** with a fast GPU and a slowed CPU the three arms are inside the noise (the
per-minute medians of one arm swing from 23 to 1 238 ms when the machine is busy). The change helps where the pixels
are the limit and does nothing where the processor is. A phone that is CPU-bound will not feel it.

## What is not done, and why

- The processor cost of a night (the draw-call count above, the crowd's views, the audio) is the other half of a phone's
  lag and is not changed by this pull request: a CPU-throttled profile of the lot is roughly 100 to 130 ms a frame at
  x4. The next step is fewer, larger meshes (the lot's props merged by area into `MultiMesh` or one mesh) and distance
  culling of small props; a follow-up issue holds it.
- A real phone has not been used. Run `phone_frames.py` on desktop Chrome with remote debugging pointed at a phone
  when one is at hand.

## Reproducing

```text
godot --headless --path game --export-release Web ../build/web/index.html
gds quiet -- uv run --with playwright==1.64.1 python tools/web_smoke/phone_frames.py build/web scratch/out \
    --minutes 10 --unpaced --software --block 30 \
    --arms "before:3:2,capped_only:2:2,after:2:0" --label software
```

`--throttle N` slows the processor, `--real` goes through the menu to a solo night instead of the autopilot, and
`--query "count=1&scale=67&msaa=0&lights=0&ui=0&fog=0&hide=Field&cull=40&perf=1"` leaves things out or turns
`PerfProbe` on (`BenchAblation`, `game/tools/bench/ablation.gd`, only for the autopilot run). The profile's costs are
read only when the page sets `window.deadnight_bench`, so a player's page pays nothing for them.
