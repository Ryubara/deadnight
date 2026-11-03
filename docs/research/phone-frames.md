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

## Batching the lot's still meshes (#728)

`LotBatcher` (`game/world/batch/`) folds the drive-in's still scenery into a few meshes when a night builds the map:
the models of props, fixtures, cars and wrecks, the lamp posts' poles, the solid CSG boxes' meshes and the parts of the
three machines that never move (`still_meshes()` on each). `MeshBatch` sorts the pieces into 12 m cells and, in a cell,
by material (a signature of every stored property, so two imported models that wear one palette share a surface) and
builds one `MeshInstance3D` per cell. A box is hidden, not removed: it stays the wall. Nothing in the scene files
changes, a prop moved in the editor moves in the night, and what a script or the rules reach (doors, barricades, lamp
bulbs, the screen, the moving parts of the machines) is left alone. A map asks for it (`MapInfo.batch_still`, only the
lot); a headless game server does not batch.

- **Lights decide the cells.** The Compatibility renderer lights a mesh by its box with at most 8 lights, so a cell
  that more than 6 of the map's lights reach (the cap less the room a fight needs, as `test_lot_light_cap.gd` holds)
  is split in four, and pieces that stand in one place (a floor and the ceiling over it) are packed by what they add to
  the reach. Without this a view differed on 70 % of its pixels because the renderer kept other lights for a bigger box.
- **Same picture:** 14 views (the field, the aisles, the machines, the plaza, two overhead) rendered before and after
  under the lights a night starts with differ by a mean of 0 to 0.0006 on 0 to 0.14 % of the pixels; the largest
  region (the machines' breathing glow, a frame apart) is under 1 %. The same view rendered twice differs by up to 4 %,
  so that is noise (`tools/lot/batch_capture.gd`, attached to the pull request).
- **Counts** (14 capture views, summed): draw calls 5 427 to 3 828 (29 % fewer), triangles 964 000 to 1 325 000 (37 %
  more: a cell is drawn whole, so a view draws what is behind the frustum edge). That trade helps a processor-bound
  phone and may hurt a weak GPU, which was not measured. `batch_report.gd`: 867 pieces into 448 surfaces, built in 170
  to 190 ms at the start of a night.

CPU x4, 10 minutes in one page, `?batch=toggle` flips between the nodes and the batches every 20 s, the order shuffled
each round (`--arms "unbatched:2:0:0,batched:2:0:1"`), 4 s dropped after each switch:

| Arm | frames | p50 | p95 | p99 | draw calls | 3D draw calls | objects | process ms | render CPU ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nodes | 4 613 | 46.8 | 109.3 | 172.3 | 628 | 441 | 1 098 | 46.8 | 9.9 |
| batched | 3 867 | 48.2 | 111.3 | 157.0 | 488 | 302 | 946 | 47.8 | 9.2 |

**No win in the median, said plainly.** Draw calls fell 22 % and render CPU 7 %, the median and p95 are inside noise and
p99 fell 9 %. The batched arm also met more zombies on screen (4.1 alive against 3.2), which is the script cost, so the
two are not clean. The frame at x4 is script and physics (47 and 21 ms), not draw calls. For scale, hiding the whole lot
moved the median 93 to 62 ms (draw calls 834 to 240) in the earlier ablation, so the lot's meshes cost something and
this batch took about a quarter of its calls. The cell size was swept (8, 12, 16, 24 m): bigger cells save a few calls
and draw many more triangles; 12 m is the pick. A range of sight for small props (`?smallrange=D`, in the bench
only) saves 150 to 250 more calls in views but is not on: it hides the far props.

## The heap growth over a night (#728)

`performance.memory.usedJSHeapSize` rises and falls with the browser's collector (93, 158, 117 MB in three samples a few
seconds apart), so it says nothing alone. `phone_frames.py --gc` forces a collection every minute
(`HeapProfiler.collectGarbage`) and reads the heap after it next to the engine's own monitors (`WebProbe` publishes
objects, nodes, orphans, resources, texture and buffer memory when the page is a profile). One 13-minute run of the
autopilot night at full speed (89 000 frames, no throttle, batched map):

| Minute | JS heap after a forced GC | Engine objects | Nodes | Orphans | Resources | Texture MB | Buffer MB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 148 MB | 12 491 | 3 479 | 0 | 2 244 | 60.2 | 53.2 |
| 5 | 448 MB | 12 722 | 3 493 | 0 | 2 255 | 62.7 | 53.2 |
| 9 | 679 MB | 12 935 | 3 516 | 0 | 2 268 | 64.5 | 53.6 |
| 13 | 815 MB | 13 506 | 3 636 | 0 | 2 268 | 65.0 | 54.9 |

- **It is not in the engine.** Nodes, orphans, resources and the video memory the engine counts are flat (nodes +4 %,
  texture +8 %, no orphans), and the object count moves with the crowd. The page's heap after a forced collection
  grows 148 to 815 MB, about 50 MB a minute at full speed, and slows after minute 10 (811 to 815 MB in the last three).
- **So it is something the page holds** that a collection cannot free. Candidates: the `JavaScriptBridge` objects the
  probe and the game publish every few frames (`WebProbe`, `ViewWebProbe`, the judder and flash probes), the profile's
  own page recorder (not ruled out: no run without it), or the engine's own interop. It is **not found or fixed
  here**: the issue's third item moved to [#834](https://github.com/Ryubara/deadnight/issues/834). The earlier figure
  of 100 to 185 MB in 10 minutes was an unforced reading and mixed garbage with what stays.

## What is not done, and why

- The processor cost of a night is mostly script and physics (47 and 21 ms of a 47 to 60 ms frame at x4), not the draw
  calls the batch cut; the next lever is there (see the batching section for what was measured).
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
