# The web page's heap over a night (#834)

Issue #728 measured a 13-minute autopilot night in the web build and found the page's JS heap, after a forced garbage
collection, growing from 148 to 815 MB while the engine's own nodes, resources and video memory were flat. The
issue asked what holds it. The kit's page for what applies to every game is [The web page's
heap](https://ryubara.github.io/gdstudio/engines/godot/web-heap/); this page is Deadnight's numbers.

## Answer

It is not the `JavaScriptBridge` publishers (`WebProbe`, `ViewWebProbe`, the judder, flash and pad probes) and not the
profile's page recorder. It is the **touch controls redrawing every frame**.

- Emscripten gives every WebGL object the engine creates (buffers, vertex arrays, textures, programs, fences) an id
  from one shared counter and pads every id table to it with `null`. The tables never shrink. Each object ever
  created costs about eight slots, in the page's JS heap, until the page closes, however soon it is freed.
- `TouchControls._process` called `queue_redraw()` every frame, and `_draw` draws a stick and fourteen round buttons
  with `draw_circle` and `draw_arc`. In the Compatibility renderer each such command is a polygon with its own vertex
  array, vertex buffer and index buffer, built at every redraw and freed at the next. Measured in a running night with
  the touch layer up (a phone page): **116 buffers, 78 vertex arrays and 5 fences a frame**, none in the menu.
  About 200 objects a frame at 100 frames a second is the 50 MB a minute #728 saw.
- A desktop page has no touch layer, so it makes far fewer.

## What was done

- `TouchControls` redraws when a key of what `_draw` reads changes (what is held, the stick, the interact verb, the
  layout, opacity, scale, hand, the theme): `_redraw_if_changed`. A held button or a moving stick still redraws every
  frame it changes.
- `HudBanner` (the round banner with its chasing bulbs) redraws when the chase steps (5 a second), not every frame.
- Tests count the `draw` signal: idle touch controls draw fewer than 3 times in 30 frames, a held button and a moving
  stick are redrawn, the banner draws about ten times in two seconds, not sixty. All three fail on the code before.
- `tools/web_smoke/heap_soak.py` is the probe (below); `BenchAblation` has `hints=0` (the touch hints marked used: an
  autopilot never touches, so the "DRAG TO MOVE" labels would otherwise stay up and animate for the whole run, which
  a player's do not) and the soak uses it.

## Before and after

![Heap after a forced collection, before and after](web-heap-before-after.png)

Autopilot night, phone page (844 x 390 at ratio 3, touch on), unpaced Chrome, forced collection every 30 s, 12 minutes,
the same build apart from the change:

| | minute 1 | minute 3 | minute 6 | minute 12 | rate |
| --- | --- | --- | --- | --- | --- |
| before | 42 MB | 67 MB | 188 MB | 398 MB | 31 MB a minute |
| after | 21 MB | 24 MB | 40 MB | 67 MB | 3.9 MB a minute |

**It is 8 times slower, not flat.** The issue's bar (within 10 % from minute 3) is not met: from minute 3 the heap grows
43 MB in 9 minutes, and about 5 fence syncs a frame stay. The heap starts at 20 to 27 MB here, not the 148 MB of #728's
run (a different build and page); the rates, not the starting point, are comparable.

## What is left, and what it is

Creations a frame in a running night (WebGL `create*` calls divided by frames drawn):

| Build | buffers | vertex arrays | fences |
| --- | --- | --- | --- |
| before | 116 | 78 | 5.0 |
| touch controls fixed | 23 | 12 | 5.0 |
| and no touch hints | 15 | 7 | 5.0 |
| and the banner off | 2 | 1 | 5.0 |

- **Fences:** `bufferData` of a 272-byte state buffer, `fenceSync`, `deleteSync`, about 5 a frame (one per canvas or 3D
  render pass). They are the renderer's, are 5 ids a frame at 8 slots each (about 2 MB a minute at 100 frames a
  second), and fall to 0.4 only when most of the HUD is freed. Nothing in the game's scripts stops them.
- **The touch hints** ("DRAG TO MOVE", "DRAG TO LOOK") redraw every frame while up (their label pulses, drawn with
  circles and arcs): 8 buffers a frame, only until the player has used each control once, as the setting
  `controls/touch_hints_seen` remembers.
- **The banner** now redraws 5 times a second while it shows.
- A patch of Emscripten's `getNewId` in the exported `index.js` (no padding, so a table only holds what is made) was
  tried in the browser on both builds: 9.7 MB a minute on the unfixed build (against 31) and 3.2 MB a minute on the
  fixed one (against 3.9). The arrays stay holey but long, so a slot per id remains. It is not a fix, and the glue is
  not ours to edit.

## How it was found

The plan in the issue (switch the publishers and the recorder off one at a time) was never run: the first look at what
the page holds answered it.

1. `heap_soak.py` forces a collection (`HeapProfiler.collectGarbage`) every 30 s and reads `Runtime.getHeapUsage`:
   5 minutes, 27.8 to 221.8 MB.
2. `--sampling` runs V8's sampling heap profiler for the whole run and lists the stacks that allocated what is alive:
   eight stacks of 25 MB each, each `_emscripten_glGen{Buffers,Textures,Renderbuffers,Framebuffers,VertexArrays,FenceSync}`
   or `glCreate{Program,Shader}` through `getNewId`.
3. `--count-gl` wraps `WebGL2RenderingContext.create*` and `fenceSync`. The menu makes none; a running night 116, 78
   and 5 a frame, whatever the crowd (0 to 11 zombies), and the same with the HUD hidden (`ui=0`, which the touch layer
   undoes by showing itself again), the lights off, the labels or the particles freed.
4. A trace of the GL calls of five frames: the same unit, repeated, of `createBuffer`, `createVertexArray`,
   `bufferData(ARRAY_BUFFER, STATIC_DRAW)`, `createBuffer`, `bufferData(ELEMENT_ARRAY_BUFFER)`: canvas polygons.
5. Ablation by freeing nodes at the page's address (class names, `drop=`): every skinned character (29 skeletons) and
   all of the zombies, lights, particles and labels made no difference to the rate. Freeing the player's skeleton, or
   its `WeaponMount`, cut it to a tenth, and freeing every mesh under the player, or the weapon alone, did not; so did
   freeing parts of the HUD (the classes by halves) and, in the end, `TouchControls` and the banner.

Dead end worth not repeating: the player's skeleton and `WeaponMount` look like the cause because freeing them stops
the churn, but nothing under them is what churns. Why freeing them also stops it was not found (it also halves the
frame rate, so the night is not running as before); the answer was in the HUD.

## Reproducing

```text
godot --headless --path game --export-release Web ../build/web/index.html
gds quiet -- uv run --with playwright==1.64.1 python tools/web_smoke/heap_soak.py build/web scratch/out \
    --minutes 12 --unpaced --label after            # --sampling for the stacks, --count-gl for the creations
```

`heap_soak.py` prints one JSON row per collection and writes `<label>.json` (and `<label>_sampling.txt`). `gds quiet`
stops a command at 900 s: 12 minutes with the load is the longest one run.

## The fences and the redraws that were left (#883)

Issue #834 left about 8 ids a frame: 5 fence syncs, about 2 buffers and a vertex array. Where they came from:

- **A fence for each canvas pass.** The Compatibility renderer ends every canvas (the root, each `CanvasLayer`, empty
  or hidden too) with a fence sync whose WebGL id the page keeps. The game had three overlay layers (the controller
  hint, "turn your phone", the film) above the router's: they are now the last children of the router's own layer
  (`Main._add_overlays`, in that order, freed with the scene), so a night makes 2 fences a frame, not 5. The tours
  still give the prompt a layer of its own. `BenchAblation` has `canvas=1` (prints the passes), `views=0` and
  `off=A,B` to count what a pass costs.
- **Touch hints** drew their pulse (a dot and a ring, circles and arcs) again every frame. The pill is now drawn when
  it changes, and the pulse is a child `Node2D` whose position, scale and fade are set each frame (moving a drawn
  item makes no new command). Up or used, a night now makes the same buffers a frame (1.4 against 1.3 in a minute).
- The marquee's bulbs and the objective markers' polygons were also fixed here, and were then done better by #969
  and #1004 on `main` (the bulbs step, the shapes in one command), so this change keeps main's.

Autopilot night, phone page, unpaced Chrome, 12 minutes (about 160 000 frames), forced collection every 30 s, two
builds in parallel, `main` at the merge of #1021 against this change:

| Arm | fences a frame | buffers a frame | minute 3 | minute 12 | rate from minute 3 |
| --- | --- | --- | --- | --- | --- |
| `main`, hints up | 5.0 | 11.5 | 48.1 MB | 145.7 MB | 10.8 MB a minute |
| this change, hints up | 2.0 | 4.7 | 29.4 MB | 62.3 MB | 3.6 MB a minute |
| `main`, hints marked used (`hints=0`) | 5.0 | 4.7 | 33.4 MB | 82.2 MB | 5.4 MB a minute |
| this change, hints marked used | 2.0 | 4.7 | 29.4 MB | 62.2 MB | 3.6 MB a minute |

![Heap over a night, main and this change](web-heap-883.png)

A new player's night (hints up, the real case) grows 3 times slower; the #834 bar was on hints used, 1.5 times slower
than `main`. It is still not flat: 3.6 MB a minute, 62 MB at the end of a night. What remains is 2 fences (the router's
canvas and the 3D pass) and the buffers that grow as the night goes on (1.4 a frame in the first minute, 4.7 over
twelve: the round banner, damage and the markers while they show), about 7 ids a frame. A flat heap needs the renderer
to stop creating them (a newer engine or a template whose id tables are not padded), a maintainer's decision about the
pinned tool; at a phone's 30 frames a second the rate is a third of this.

## The probes in a player's page (#935)

The publishers were not the heap's cause, but they were still in every player's page: the judder, view and pad probes
read `window.deadnight` over the bridge in every frame (the pad probe also made an `Array`), and the snapshot wrote about
65 properties four times a second whether or not anyone read them. They are now added only when the page asks (`?probe`,
`WebProbe.asked`) and the snapshot writes only what changed.

`tools/web_smoke/bridge_calls.py` counts the bridge's traffic (software GL, 15 s windows, the plain page, no `?probe`):

| | menu | night (autopilot) |
| --- | --- | --- |
| before | 430 a second (3 119 reads, 3 249 writes, 145 evals in 15 s) | 141 a second |
| after | 9 a second (145 evals, no reads, no writes) | 4 a second |

What was left were `eval`s, removed in #983 (below): `GamepadProbe.in_frame`, `WebClipboard.read` and the touch
controls' safe-area read. Heap
after a forced collection, four minutes of an autopilot night on a desktop page (`heap_soak.py --plain`): 23.2 to
38.3 MB before (4.3 MB a minute), 23.9 to 38.2 MB after (4.0): unchanged, as #834 found.

## No evals in a player's page (#983)

Three things still ran a script in the page, 9 a second in the menu and 4 in a night:

- `GamepadProbe.in_frame` was meant to ask the page once (`static var _framed`) and asked at every read, about 5 a
  second. The cause: the web runtime hands a script's `true` back as the integer 1, so `framed == true` on that `int`
  is an invalid operation; a release build ends the function there without an error and the line that kept the answer
  never ran. Found by logging with a second `eval` after each statement; fixed with `GamepadProbe.truthy` (`bool()`),
  with a unit test of the types ([lesson](https://ryubara.github.io/gdstudio/engines/godot/web-export/#export-only)).
  It also means the "click the game once" hint never worked in a Discord frame before.
- `WebClipboard.read` (4 a second) was the snapshot's. The snapshot (`WebProbe.snapshot`, a walk of the screen's
  nodes four times a second) is now built only when the page asks (`WebProbe.asked`): a plain page gets no
  `window.deadnight` at all. `ControllerHint` reads the page only inside a frame.
- `TouchControls` read the safe area (a `div` made and measured in the page) every half second, 2 a second in a night,
  even for a mouse. It reads on a resize, and while the controls are wanted.

Every browser test that reads `window.deadnight` now gets the probes: `smoke.serve(folder)` puts
`window.deadnight_probe=true` in the head of the page it serves (`probing=False` serves the page a player opens:
`bridge_calls.py`, `heap_soak.py --plain`); a deployed build is opened with `smoke.probing(url)`.

| Software GL, 20 s windows | menu | night (autopilot) |
| --- | --- | --- |
| before (#982) | 9 a second | 4 a second |
| after | 1 eval in 20 s (0.05 a second) | 1 eval in 20 s (0.05 a second) |

The web job's ceiling is now 1 a second (`bridge_calls.py --max-per-second 1`).

## The marquee and the damage frame (#934)

The special-round marquee (`HudMarquee`) redrew every frame while it showed: 15 bulbs a row, two rows, plus the ticket's
two polygons and outline, 33 polygon commands a redraw. `HudDamage` redrew every frame while health was low or an arc
showed. Counted with the engine's `draw` signal on a real clock at 60 frames a second (the capture scene
`game/tests/captures/hud_marquee_redraw.tscn`, the break before round 5):

| Part | Before, draws a second | After |
| --- | --- | --- |
| Marquee | 60 | 3 (the bulbs' chase) |
| Damage frame, health 20 of 100 (a pulse) | 60 | 6 to 9 |
| An arc's life (1.3 s) | every frame, about 78 | 32 |

The marquee's letters flicker through their label's `modulate`, which the board does not redraw for, so the flicker is
not a reason to redraw. The five pictures a run saves are pixel-identical before and after for the marquee, and within
4 of 255 levels for the damage frame (its strength is drawn in steps of 8 levels). Not measured in the browser: a break
is about 15 s and a night has a special round every few rounds, so there is no minute with the marquee up to soak; the
polygons per redraw, with the 2.9 buffers and 1.9 vertex arrays a polygon cost in the touch controls, put the
unfixed marquee at about 160 WebGL objects a frame (some 37 MB a minute while it shows, 3 MB a break at 60 frames a
second) and the fixed one at a twentieth of that.
