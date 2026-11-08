# First-use hitches and the night's warm-up

The maintainer reported stutters in the deployed web build the first time something shows: the first shot, the first
zombie. This page is what was measured (issue #319), what Godot offers for the Compatibility renderer, and how the
night now pays for it behind a loading screen. General Godot knowledge is in the kit page
[First-use hitches](https://ryubara.github.io/gdstudio/engines/godot/first-use-hitches/).

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
2. **Sounds.** `Audio.preload_sound(id)` for every id of `SoundCatalog`, a few milliseconds a frame (most are found
   cached: the audio service loads them in the background while a menu is up, #509).
3. **The lot.** A camera of its own, in a 160 x 90 `SubViewport` of the night's world (the window's own 3D is off
   meanwhile and draws the night once at the end: a program does not depend on the picture's size and a renderer on
   the CPU pays for every pixel, #509), looks down on the whole lot from above. Every drawn node of the
   night is held out of the picture first and **brought back one new kind of material per frame** (`DrawReveal`, see
   "The first draw of the lot"), with every lamp lit; then two frames with every lamp dark (the lamps' lights hidden,
   then put back; the moon stays). A mesh's programs depend on the lights that reach it, and the generator can fail.
4. **The stage.** A node 150 m above the lot, out of reach of every lamp, under each of four light conditions (the moon
   alone, an omni light, a spot light, both): every zombie look near and far (the near and far meshes, by visibility
   range), each weapon's and grenade's scene (in the first condition they are brought in one kind of material at a time
   as well), then the night view's effects, **replayed through the view's own event handler**, one frame after each
   weapon's shot and each kind of event, from a sample of each event (`shot_fired` for each weapon in the catalogue,
   `damage_dealt` with every digit and a headshot, `projectile_burst`, a blast and gibs). Because the real handler runs,
   a reworked muzzle flash or impact is warmed without anyone editing the warm-up. The materials the effects made are
   **kept** for the whole night (the fix for the repeats above); the stage and the effect nodes are freed. Two things
   the ledger cannot see by itself are put on the stage on purpose, because the night hides them until they are used: a
   **copy of the prize crane** shown in its spin, grab and breakdown stages (the night's own crane stays invisible until
   the server's first frame, and the ledger records hidden nodes as if they were drawn), and the **repair hammer's
   model** (it is on the Soldier's hand mount, hidden until a repair; its path is in a hold file, not a dependency, so
   `WarmupManifest` names it). Touch controls are UI, not 3D, and are not warmed. A client that joined a game server
   keeps reading the link meanwhile (`Night._physics_process`), so the server's frames are not seconds old when the
   night starts (`test_night_online`). 5. The Effects and Voice buses are muted meanwhile, the player's camera is
   current again, the bar fills and the overlay fades. The HUD's portrait (a `SubViewport` with a world of its own,
   drawn once) is stopped until the lot is in: it draws the Soldier with shaders the lot builds anyway, and in its own
   early frame it met them all at once.

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

## The first draw of the lot (#347)

With the warm-up (#339) and baked navigation meshes (#348) in, Play still froze the web page once: one frame of 9.3 to
11.1 s (three runs on the deployed build) with 79 GL programs linked in it, and a second of 3.6 to 4.5 s for the
enemies and weapons. `WebProbe.mark` (the loading steps, written into `window.deadnight_marks`) lined the frames up
with the steps: the long frame was the first draw of the lot, the warm-up's first frame with its own camera. The
navigation bake, blamed in #335, takes 0.5 s in Chrome.

**Cause (Godot 4.7 `ShaderGLES3::_initialize_version`, and a spike with one cube per material in Chrome).** The first
time a shader is bound, the renderer builds all four of its variants (colour, colour instanced, depth, depth instanced)
at the *default* specialisation, in which no light type, lightmap or fog is disabled, area lights included; then it
builds the specialisation the draw asked for. The two colour programs of the default take 0.5 to 0.9 s each (ANGLE on
Direct3D 11, RTX 5080); the depth ones 10 ms; the one drawn with 90 to 170 ms.

| First bind of a shader (spike) | Two default colour programs | Drawn program |
| --- | --- | --- |
| `StandardMaterial3D`, Burley and GGX | 915 + 889 ms | 171 ms |
| Lambert, specular disabled | 594 + 523 ms | 140 ms |
| per-vertex shading (not our look) | 142 + 151 ms | 128 ms |
| unshaded | 29 + 36 ms | 30 ms |

`shadows_disabled`, `ambient_light_disabled`, `fog_disabled`, `force_lambert_over_burley`, the shadow filter and 4 / 8
lights per object / renderable change it by 0 to 20 %. The lot has nine lit shaders (the lot paint, textured kit props,
untextured, emissive, and the double-sided ones: a weapon, glass), so its first frame was nine pairs, 12 s of linking.

**Fix.** `DrawReveal` (`game/gameplay/night/warmup/draw_reveal.gd`) turns the renderer's instance of every drawn node
under the night off (not the node's `visible`) before the warm-up's camera is made current, then brings them back in
steps: the most used material first, each node at the step where the last of its materials is first met, so a step
meets one new material at most (`DrawLedger.keys_of`). The stage's props do the same in the first light condition, the
HUD portrait's `SubViewport` is stopped until the lot is in (it drew the Soldier's shaders in a frame of its own), the
effects are replayed one weapon and one kind of event per frame (their materials are kept at once, before the effect
frees itself), and the dark pass hides the lamps only (the moon is never switched off).

| Play pressed to a running night (web, Chrome, RTX 5080, fresh profile, 3 runs) | Before (main) | After |
| --- | --- | --- |
| Longest frame | 11.1, 9.3, 10.0 s | 2.0, 2.2, 2.3 s |
| Most programs linked in one frame | 79 | 11 |
| Frames over 1 s | 3, 2, 2 | 8, 8, 8 |
| Programs linked while playing | 0 | 0 |
| Longest frame while playing | 17 ms | 13 to 17 ms |
| Total time | 20.5, 17.6, 18.2 s | 19.1, 20.8, 22.4 s |

Charts: the frame times of both, one above the other, are attached to the pull request.

**The floor.** A frame cannot be shorter than the build of one lit shader (1.1 s for the lot paint, 1.7 to 1.9 s for a
textured Burley and GGX material): the engine builds the pair inside one bind and the browser cannot build half a
program. So the lot cannot go under 1 s by cutting the draw, and the total time does not shrink either: it is the sum
of the shaders. The bar now moves between them (18 steps for the lot, 9 for the stage) and the page is never stopped
for more than 2.3 s. What shortens it is fewer lit shaders: a material that differs in one setting from another (a
double-sided weapon texture, a glass pane, specular on in a few kit props) is one more pair of huge programs, 1.1 to
1.8 s. Merging them changes how things look, so it is for an artist's decision, not done here.

**The guard.** `tools/web_smoke/smoke.py` counts the programs linked in each page frame between Play and a running
night and fails above 12 (the count is the same on every GPU and on the CI software renderer, which a frame time is
not); `main` links 79. `tests/night/test_draw_reveal.gd` tests the order (one new material a step, every node back
once, nodes the game hid left alone) and `test_night_warmup.gd` that the lot comes in as many steps and nothing is left
out of the picture.

## Results of the first warm-up (#319)

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

## The flare's first shot (#483)

The maintainer's online report: the first flare shot hitched the client while its effect loaded, and the player was lost
after it (the hitch was the trigger; the desync is in [Multiplayer](multiplayer.md#a-client-that-freezes-483)). The flare
is in the warm-up since #463: the stage replays `projectile_spawned`, `projectile_burst` and `lure_started` through the
view's own handler, and the flare gun's shot like any weapon's. `test_a_first_flare_shot_draws_nothing_the_warm_up_did_not`
plays a real shot (muzzle flash, the flare in the air, its burst, the fire that calls the dead) after the warm-up and
asks the ledger for what is new: nothing is.

Frame times of the first flare shot on desktop (`game/tests/captures/flare_first_shot.tscn`, a window with the OpenGL
driver, the player's camera, the trigger a real mouse event; the frame list after the trigger, four runs):

| Warm-up | Worst frame after the trigger | Frames over 25 ms |
| --- | --- | --- |
| off | 19.6 and 21.3 ms | 0 |
| on | 15.7 and 16.4 ms | 0 |

So on desktop the unwarmed first shot costs one frame of about 20 ms and the warmed one has none: nothing large enough
for a second pull request. The browser was the open part, and it was different (#502).

### In Chrome: the flare's embers were never warmed (#502)

`tools/web_smoke/flare_first.py` plays a solo night in a fresh Chrome profile (RTX 5080, ANGLE on Direct3D 11), gives the
soldier the flare gun through the flash probe (`?probe=flash`), fires three times (the first; one 3.5 s later, while the
first fire still burns; one 10 s later, after it went out) and records every frame and every GL program linked after
each trigger. Three runs each, the warm-up on in both:

| Build | Worst frame in the 3 s after the 1st shot | Programs linked, 1st / 2nd / 3rd shot | Frames over 100 ms after the 1st shot |
| --- | --- | --- | --- |
| `main` before the fix | 1772, 1798 and 1858 ms | 10 / 0 / 8, in every run | 2 |
| with the fix | 7, 34 and 36 ms | 0 / 0 / 0, in every run | 0 |

- **What was linked.** Six programs of an unshaded standard material at its default and at the lights it is drawn with
  (30 ms each, the 210 to 330 ms frame half a second after the trigger), then the two programs that *move* the lure's
  `GPUParticles3D` embers (845 ms each, 0.55 s and 1.4 s after the trigger), then their draw programs. The first
  flare's fire builds them all, and so does a flare thrown after the first one's 8 s fire is out.
- **Why the warm-up missed them.** The sample lure was made to burn 0.2 s and a `LureView` counts its age in frame
  deltas; a warm-up frame that builds programs takes seconds, so it was freed on the frame after it started, before any
  frame drew it. And `_keep_materials` pins what a `MeshInstance3D` draws, not a `GPUParticles3D`'s process material or
  draw passes, so the shaders went with the effect. The `DrawLedger` only knew meshes, so the check said nothing was
  missing.
- **The fix.** The sample lure burns 60 s and `NightWarmup` frees it by hand after `SHOT_FRAMES + 1` frames (a system
  moves its particles in the frame after it starts and draws them in the next); the pins and the ledger cover
  particle systems (`DrawLedger.process_key`, each draw pass's material). 10 more programs link behind the loading
  screen (217 against 207, nothing in play), about 1.7 s more load with a GPU (19.2 s to 22.1 s in one run each) and
  the most programs in one frame stay at 11.
- **Checks.** `test_the_warm_up_draws_the_flares_embers_and_keeps_their_programs` and
  `test_the_check_notices_a_particle_system_the_warm_up_never_drew` (a headless run has fast frames, so only the
  pins, the ledger and the hand-freed sample are held there; the browser probe is the real test).

## The small map's lamps and light cards (#636)

The lamps and cards of the second map are drawn with the lot's own shaders and materials (`glow.gdshader`,
`beam.gdshader`, the kit atlas with an emission texture), extended with uniforms rather than new shader files, so they
build no program the warm-up does not already build. `test_the_lamps_and_cards_draw_nothing_the_nights_warm_up_does_not`
warms a night and finds every key of the five card scenes in its ledger. In the browser, the capture links its programs
in its first frames and none while it measures ([small map: art and kit](maps/small-map-art.md#lamps-and-light-cards)).

## Open

- **Every shot and kill** also cost a frame, for another reason (made and freed in the frame, sounds started):
  [The lag on every shot and kill](kill-spike.md).
- **Not covered**: the HUD's own (canvas) shaders and font glyphs for HUD numbers, which the browser run showed no
  links for in 20 s; other players' looks (the wardrobe parts) in a multiplayer night.
- **Navigation bake**: solved by shipping baked meshes (#348, #335); it was never the long frame (0.5 s, #347). Nothing
  is baked on the web path any more: the night's first mesh takes 15 ms and a bought door 15 ms, against 594 and 370 ms
  baked in the browser ([Zombies](zombies.md#the-meshes-are-baked-ahead-of-time-335)). The loading's longest frame is
  2.2 to 2.3 s, the build of one lit shader (see "The floor"), so the issue's goal of under 1 s needs fewer lit shaders,
  not navigation.
- **Loading time, cut (#509):** the warm-up now draws into a small picture, replays the effects once, finds the sounds
  loaded while the menu was up, and the lot has two lit shaders fewer; the numbers and what they showed are in
  [Web export](web-export.md#loading-a-night-509): 21.8 s to 7.2 s in the software renderer CI runs and 24.4 s to 18.1 s
  with a GPU.
- **Loading time** is the sum of the lit shaders (about 12 s of 19 in the browser, on this machine); the bar shows it.
  Fewer lit shaders is the only lever (see "The first draw of the lot").
