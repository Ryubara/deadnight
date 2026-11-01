# First-use hitches and the night's warm-up

The maintainer reported stutters in the deployed web build the first time something shows: the first shot, the first
zombie. This page is what was measured (issue #319), what Godot offers for the Compatibility renderer, and how the
night now pays for it behind a loading screen. General Godot knowledge is in the kit page
[First-use hitches](https://github.com/Ryubara/gdstudio/blob/main/docs/godot/first-use-hitches.md).

## What Godot offers for the Compatibility renderer

| Feature | Renderer | In Deadnight |
| --- | --- | --- |
| Ubershaders, pipeline precompilation | Forward+ and Mobile (Vulkan, D3D12, Metal pipelines) | not available: WebGL2 has no pipeline objects |
| Shader baker (export option, since 4.5) | Forward+ and Mobile; "not supported on the web" | not available |
| Disk shader cache | native renderers only | the browser's own GPU program cache (Chrome profile) is all there is |
| Preload and draw once, behind a loading screen | all, and the docs' advice for Compatibility | **this work** |

Source: [Pipeline compilations](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html),
which says the page "only applies to the Forward+ and Mobile renderers", that the shader baker does not work on the
web, and that for Compatibility "you need to use the legacy approach of preloading" by showing every material, shader
and particle for at least one frame while the level loads. The same page (current) was read for 4.7; nothing in the
4.7 build we ship contradicts it.

## How it was measured

`tools/web_smoke/first_use.py` plays a night in Chrome the way a player does: menu, Play, then walk a square firing,
for 20 s from the moment the night runs. Each run uses a **fresh browser profile** (Chrome keeps a GPU program cache in
the profile, so a repeat visit hides the compiles). It records every `requestAnimationFrame` delta from the first
frame and, with a hook on WebGL, every program the page links (`linkProgram` and the `LINK_STATUS` read, with the
`#define` list of the program). Chrome 156 (stable channel), headless, real GPU (RTX 5080, ANGLE on Direct3D 11),
1280 x 720, the paced default. The first zombie reaches the player about 13.5 s into the night.

The page's counter is the real test: a frame that links programs stutters, and a program is linked only the first time
(or again, see below) something needs it.

## What was found (before)

Three runs, the build of `main` at the time:

| Run | Worst frame | p99 | Frames over 33 ms | Programs linked in the 20 s of play | Time spent linking |
| --- | --- | --- | --- | --- | --- |
| 1 | 396 ms | 58 ms | 47 | 296 | 794 ms |
| 2 | 400 ms | 58 ms | 45 | 295 | 715 ms |
| 3 | 392 ms | 54 ms | 44 | 289 | 705 ms |

- **The first frames of the night**: a 392 to 450 ms frame 0.45 s in (the first shot: 11 programs linked in it), then
  62 ms frames every time a new kind of thing appears.
- **Every few seconds, all night**: 100 to 130 ms frames at 4.5, 8.7, 12.8 and 17 s, each with 11 programs linked. The
  same programs, with the same `#define`s, were linked 50 times each. That is not first use, it is every use.
- **Cause of the repeats**: `ShotEffects` makes a new `StandardMaterial3D` for each flash, puff and spark and frees it
  0.2 to 0.35 s later. `BaseMaterial3D` shares one shader among all materials with the same settings and frees it with
  the last one, so each shot built the shader and every program of it (colour pass, depth pass, instanced forms; with
  and without light types) again. About 6 programs a shot.
- **Loading**: from pressing Play to a running night took 23.8 s in the browser, with a **single frame of 11.2 to
  12.2 s** (the lot's first navigation mesh is baked synchronously, `DoorNavigation.setup`), and nothing on screen to
  say so. See Open below.

## What the warm-up does

`NightWarmup` (`game/gameplay/night/warmup/`) runs inside `Night.start`, after the lot and the server exist and before
the night runs, behind `LoadingOverlay` (a bar and the step in words). The game turns it on (`NightScreen`); a headless
run skips it (nothing is drawn, so nothing is built).

1. **Load.** `WarmupManifest.resource_paths()` lists what to load: every zombie look (`ZombieModels.VARIANTS`), the
   shared extra clips, every weapon and grenade definition and **what each definition points at**
   (`ResourceLoader.get_dependencies`, so a weapon's model scene is picked up when it is added to its `.tres`). They are
   requested with `ResourceLoader.load_threaded_request` and polled every frame; the loaded resources are held.
2. **Sounds.** `Audio.preload_sound(id)` for every id of `SoundCatalog`, a few milliseconds a frame.
3. **The lot.** A camera of its own, made current, looks down on the whole lot from above for two frames with every
   lamp lit and for two frames with every lamp dark (lights hidden, then put back). A mesh's programs depend on the lights
   that reach it, and the generator can fail.
4. **The stage.** A node 150 m above the lot, out of reach of every lamp, under each of four light conditions (the moon
   alone, an omni light, a spot light, both): every zombie look near and far (the near and far meshes, by visibility
   range), each weapon's and grenade's scene, then the night view's effects, **replayed through the view's own event
   handler** from a sample of each event (`shot_fired` for each weapon in the catalogue, `damage_dealt` with every digit
   and a headshot, `projectile_burst`, a blast and gibs). Because the real handler runs, a reworked muzzle flash or
   impact is warmed without anyone editing the warm-up. The materials the effects made are **kept** for the whole
   night (the fix for the repeats above); the stage and the effect nodes are freed.
5. The Effects and Voice buses are muted meanwhile, the player's camera is current again, the bar fills and the overlay
   fades.

The night's own lights, environment and fog are used as they are: the stage is in the same world, seen by a second
camera, so the specialisations (`DISABLE_LIGHT_OMNI`, fog, radiance map) match the ones the night asks for.

## The check

`DrawLedger` turns a scene tree into strings: a mesh kind (plain, skinned, multimesh, text, CSG) with its material (a
shader's file, or the settings of a `StandardMaterial3D` that change its shader), and each light by type. The warm-up
records its tree after every shot. `tests/night/test_night_warmup.gd` plays a boss night for a minute with the bot,
records what the night draws, and fails when something is outside the warm-up's ledger, naming it. Another test adds a
material the warm-up never saw and expects the check to report exactly it (otherwise the check would prove nothing).
Also tested: the manifest names every look, weapon and the grenade; every sound is cached; progress never goes
backwards; the camera and lamps are as they were after.

## Results (after)

Same method, same machine, three runs each with a fresh profile:

| Web build, first 20 s of a night | Before | After |
| --- | --- | --- |
| Worst frame | 392, 396, 400 ms | 17, 25, 25 ms |
| p99 frame | 54 to 58 ms | 8 to 12 ms |
| Frames over 33 ms | 44 to 47 | 0 |
| GL programs linked while playing | 289 to 296 (705 to 794 ms in `linkProgram`) | **0** |
| Programs linked in all (loading included) | 394 | 169 |
| Play pressed to a running night | 23.8 s | 30.7 to 31.2 s |
| Largest single frame while loading | 11.2 to 12.2 s (the navigation bake) | 12.8 s (the same bake) |

The hitches before were the programs linking, one for one (each burst of 11 programs was a 100 ms frame; each
burst of 6 a 60 ms one). After, there is nothing left to link, and what is left of the frame times is the ordinary
jitter of a 4 ms frame.

Desktop, for comparison (`game/tests/captures/frame_log.tscn`, a window with the OpenGL driver, the bot firing through
the player's shoulder camera, dead arriving after half a second, 20 s): without the warm-up the first two frames took
191 ms and 62 ms (the first shot) and 3 frames were over 33 ms; with it the worst frame was 6.6 ms and none was over
33 ms. A native driver builds a program faster than ANGLE and the browser, so the hitch is smaller, but the same.

The loading screen takes about 7 s longer in the browser on this machine; most of it is the 170 programs linking, which
is what the player no longer pays during the night. The bar moves through the loading, the sounds and the drawing;
it cannot move during the navigation bake, which blocks the page (Open).

## Open

- **Not covered**: the HUD's own (canvas) shaders and font glyphs for HUD numbers, which the browser run showed no
  links for in 20 s; grenades and the flare in the night (the night does not draw them yet, #257: the blast is warmed
  because its code exists, and a night view that draws a projectile is picked up by the same check once it plays one);
  other players' looks (the wardrobe parts) in a multiplayer night.
- **Navigation bake**: the first bake of the lot is one 11 to 12 s main-thread frame in the browser. The comment in
  `NavmeshBaker` already says the world owner should ship a baked mesh. Follow-up: #335.
- **Loading time** grew by the warm-up (about 7 s of linking in the browser, on this machine); the bar shows it.
