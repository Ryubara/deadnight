# Night environment

How the lot's night look is built and why (issue #176): the sky, fog, ambient, moon and tonemap in
`game/world/drive_in_greybox.tscn`, written by `tools/world/build_greybox.py` (the constants are at its top). The
design side is [the lot](../design/map.md#light-and-dark).

## What was wrong

The issue read the pale blue above the lot in the autopilot frames as a daytime sky. It is not the sky: the greybox
already had a flat near-black `background_color` and no `Sky`. The pale blue is the **screen**, a 32 x 12 m emissive
panel seen from 5 m at the apron where the player spawns (`before/` frame 0 of the capture tour). What was missing was
a sky at all: the horizon was a black void, the far walls and cars ended in a hard line, and nothing gave the night a
depth or a moon.

## What it is

| Part | Setting | Why |
| --- | --- | --- |
| Sky | `Sky` with a `ShaderMaterial` on `night_sky.gdshader`, `radiance_size` 32 | gradient, horizon haze, a faint glow over the screen, about 150 stars and a moon in about one shader |
| Moon | a disc in the sky shader and a `DirectionalLight3D`, no shadows, over the screen (north, 38 degrees up) | the player faces it at the start; its light shines on the faces the player sees |
| Ambient | flat colour `#4d5c8c`, energy 0.24 | cool, and low enough that lamp pools show |
| Fog | exponential, `#16224a`, density 0.013, `fog_sky_affect` 0 | 28 % at 25 m (a zombie still reads), 79 % at 120 m (the far wall sinks into the sky) |
| Tonemap | filmic | the screen and lamps roll off instead of clipping |

The sky shader reads no clock and no light, so Godot bakes its radiance once (see below); the moon's direction is a
shader parameter that the generator writes from the same constant as the light's transform, and a test keeps them
equal (`test_night_environment.gd`).

## What Compatibility does and does not do

- **`fog_sky_affect` defaults to 1**: with fog on, the whole sky is painted the fog colour (a flat blue wall) until it
  is set to 0. Match the sky's horizon colour to the fog colour by hand instead.
- **The renderer's limits**: no volumetric fog, SDFGI, SSR, SSAO or SSIL; a test fails if one is turned on. Shadows are
  off for the moon (see [greybox and captures](greybox-and-captures.md#lights-on-a-big-floor-compatibility)).
- **Glow and adjustments were tried and dropped.** Glow (threshold 0.85, intensity 0.6) added a faint halo to the lamp
  heads and the moon, not enough to justify the extra post-processing passes on a weak web GPU. `adjustment_contrast`
  1.1 crushed the player's silhouette to black wherever no lamp reached: the shadow side of the player needs the
  ambient.
- **`TIME` or a `LIGHT0_*` read in a sky shader** makes Godot redraw the sky's radiance cubemap every frame. This sky
  uses neither, so the cubemap is made once; a test fails if either word appears in the shader.

## Frame time

Measured in Chrome 156 on an RTX 5080 (ANGLE D3D11, WebGL2), 1280 x 720, the web export of `main` against the export
of this branch, with the smoke run (`tools/web_smoke/smoke.py --gpu`), each twice, one shared machine:

| Run | Night frame mean / p50 / p95 | Worst second p95 | Console errors |
| --- | --- | --- | --- |
| Paced (display 180 Hz), `main`, 2 runs | 5.9 / 5.6 / 6.5 ms and 5.8 / 5.6 / 6.5 ms | 12.1 and 10.7 ms | 0 |
| Paced, this branch, 2 runs | 6.1 / 5.6 / 10.2 ms and 5.7 / 5.6 / 6.3 ms | 11.8 and 6.7 ms | 0 |
| Unpaced (`--disable-gpu-vsync --disable-frame-rate-limit`), `main`, 2 runs | 3.3 / 2.8 / 6.1 ms and 3.2 / 2.7 / 5.2 ms | 10.7 and 10.8 ms | 0 |
| Unpaced, this branch, 2 runs | 3.0 / 2.6 / 5.0 ms and 3.8 / 2.9 / 7.1 ms | 9.4 and 13.7 ms | 0 |

The medians of the two builds are within the run-to-run spread of the same build (2.6 to 2.9 ms against 2.7 to
2.8 ms): no measurable cost on a desktop GPU. The paced run says nothing on its own (every frame waits for the display);
the unpaced run is the one that shows GPU time. A weak laptop GPU is not measured (see #82); the costs there would be the
sky shader (a full-screen pass over the sky pixels, drawn once per frame, a dozen instructions and one hash per
star cell) and the fog (a few instructions in every material), so glow, SSAO and the other post passes stay off.

An unpaced run needs Chrome's own GPU: the headless Chromium shell is always software-rendered, and on SwiftShader the
numbers measure the CPU.

## Capturing it

`game/tests/captures/night_look_tour.tscn` runs the real night in the manual mode and puts the player's own shoulder
camera at ten spots (looking up at the screen, across the lot, up the avenue, over the flank, in the yard and the
back lot, then the stand powered, the screen's circuit off and the entrance's marquee), with the dead lined up 25 m
away at one. Each spot holds ten frames, so frame `10 * spot + 9` is the settled shot:

```text
godot --path game res://tests/captures/night_look_tour.tscn --write-movie <abs>/look.png --fixed-fps 10 --quit-after 110
```

Add `-- --hud` to draw the real HUD over the night.

## The night closes in with the round

Issue #314. The rules' `RoundTuning.ambient_for_round` (0.60 in round 1, 0.035 less each round, 0.15 from round 14) is
read by `NightLight` (`game/world/drive_in/night_light.gd`), a node the night adds beside its view. It listens to the
client's events only (`break_started.next_round`, `round_started.round`, and the first `frame` for a client that joins
late), so the server changes nothing and a client of any kind (loopback, or a socket) darkens the same way.

| Part | Round 1 | Darkest (round 14 on) |
| --- | --- | --- |
| Ambient energy | the scene's own 0.24 | 0.35 of it (0.084) |
| Moon energy | the scene's own 0.36 | 0.5 of it |
| Sky (`background_energy_multiplier`) and fog colour (`fog_light_energy`) | 1 | 0.5, both together (the fog is matched to the horizon by hand) |
| Fog density | the scene's own 0.013 | 1.7 times it (28 % to 42 % at 25 m) |

Round 1 is the look in the table above, untouched; each round blends the scene's numbers toward the darkest by
`(0.60 - level) / (0.60 - 0.15)`, so a change to the generator's constants moves both ends. A change of round eases
over 12 s (`EASE_SECONDS`) from the break that announces it, so there is no pop; the lamps' lights and pool quads are
not touched, so the pools hold while the field around them sinks. Only `Environment` energies and a fog density change,
so nothing new for the Compatibility renderer or the web build, and the HUD (a 2D layer) is not lit by any of it.

- **A scene's resources are shared by every copy of it.** The `Environment` is a sub-resource of the greybox scene, so
  an edit through one night's node would darken every later night in the process (the menu's preview, the next
  match, other tests). `NightLight` duplicates the environment before it changes it; a test makes a second lot after
  round 14 and reads the original numbers.
- **Readable at the darkest round** (`test_night_light.gd`): ambient plus moon above 0.2 (round 1 has 0.6), fog at 25 m
  under 50 %, sky and fog still matched. The capture `night_closes_in.tscn` puts the dead 7 m and 25 m ahead of the
  player's shoulder camera with the HUD on, one run for each round (`-- --round=N`): at round 14 the player, the dead at
  25 m against the stand's wall, the lamp heads and their pools all still read. Mean frame luma of the 1080p capture
  went from 45.5 (round 1, and `main`) to 33.4 (round 14).

## Lamps and glow (issue #244)

The lighting pass on top of the environment above. The sky, fog, ambient and moon are untouched; this is what the
lot's own lights and emissive surfaces do. Compatibility lights a mesh with at most 8 omni and 8 spot lights, has no
cheap shadows and no volumetric fog, so what a lamp *looks* like is mostly additive quads, and the few real lights are
kept for lighting the dead and the player.

| Part | What it is | Cost |
| --- | --- | --- |
| Lamp light | sodium `#ffb866`-ish omni, energy 2.8, range 11, attenuation 1.4 (`lamp_post.tscn`) | one light per post, as before |
| Pool on the asphalt | additive flat quad, 15 m, radial falloff (`glow.gdshader`) | one transparent quad per lit post, no light slot |
| Lens and halo | emissive lens under a dark housing, plus a billboard glow quad (same shader) | two small quads |
| Screen face | `screen.gdshader`: drifting patches of cool and warm light, vignette, grain at 12 Hz; `LotScreen` adds a slow flicker | one shader on the existing panel |
| Projector beam | `ProjectorBeam`: a 29-vertex elliptical cone of additive haze from the booth's port to the screen (`beam.gdshader`), a halo at the lens | one draw; the booth's spot (below) is its only light |
| Neon | `LotNeonSign` over the concession door: tubes, `Label3D`, halo, and an omni that hangs on the concession circuit | one light, only while powered |
| Windows | `GlowPane`: an additive pane in each front window of the stand | one quad each |
| Breaker posts | a billboard halo round the lamp, green on and dull red off, so a post reads across the lot | one quad each |
| Dim post | `LampPost.dim` (0 to 1, 1 by default) scales a post's light, lens, halo and pool together; the six lamps over the breach aprons use 0.4 (#850) | none: the same light and quads at lower energy |

What carries the circuits: every glowing thing is a `LightFollower` that reads the **lamp it follows** (its
`light_energy` over the energy the scene gave it, 0 when `LotLamps` hid it), so a switched circuit, a failing tank and
the screen's afterglow reach the glow with no second path to keep in step. The flicker's phase is the frame's own delta
(Movie Maker steps it at a fixed rate) and every flicker curve is a function of the phase alone, so a test calls
`advance` and gets the same light. A lamp that is only seen (the sign's) carries `metadata/decor` and lights no ground
for the dead's slowdown (`LotLamps.lit_at`).

A dimmed post is dimmed at its source: `LampPost` multiplies its `Light`'s energy once in `_ready` (so `LotLamps`, which
reads the energy when it gathers the lamps, drives the lower level through a flicker and a switch like any other) and
the three glow energies in `set_glow`. The rules do not see it: `lit_at` asks only for a lamp's position, so a dim lamp
lights its 6 m for the dead's pace exactly as a bright one does. Moving a lamp's *reach* with its level would be a rule
change (`LightTuning.lamp_reach` is one number for the lot), not a lighting one.

- **The cap per mesh is tested** (`test_lot_light_cap.gd`, helpers in `light_cap.gd`): with every circuit on, every
  mesh a light shades is reached by at most 8 lights (the project's `max_lights_per_object`; omni by sphere, spot by
  its cone's box), and by at most 6 so a fight has room. Counted: the root of every CSG tree and every
  `MeshInstance3D` or `MultiMeshInstance3D` with a surface that is not unshaded (a standard material set to unshaded,
  or a shader with `unshaded` in it), so the kit's props, the cars and the lot's boxes are all in; the pool and halo
  quads, which ignore lights, are not. A failing run names the mesh and its lights. The 320 m `Outskirts` slab is
  exempt: every lamp reaches it and it is near-black.
- **Room for a fight**: a muzzle flash (`ShotEffects`, 5 m), a blast (`BlastEffect`, 1.6 x the blast radius) and a
  grenade's lamp (`GrenadeView`, 3 m) are `OmniLight3D` nodes made at run time. A mesh near a fight gains one flash and
  one blast or lamp, so the lot's own lights may reach a mesh with `limit - 2` (`DYNAMIC_HEADROOM`), and no mesh is
  excused from it. Another test reads every script and scene of the project for a light and fails on one that is not
  in its table, and checks that each weapon's shot, a blast and a grenade add exactly one light.
  The first run of the stronger test found 8 on two ground tiles, 7 on four more; no prop or car is above 6.
  The blast's light is freed when its fade ends (0.7 s) and the whole effect when its scorch has faded (7 s)
  (`BlastEffect`, #929): before that, an energy-0 blast light kept its slot on every mesh near the blast for the rest of
  the night, so a few blasts at one chokepoint could push the lot's own lamps past the cap.
- **The booth's spot** (`ProjectionBooth/Lamps/ProjectorBeam`, issue #840) is the beam's one real light: a
  `SpotLight3D` (energy 6, 7 degrees, range 100) 0.1 m inside the booth's north wall behind the port, facing the
  screen 70 m off. Two things about it are not obvious. A spot's forward is its -Z, so the builder's `yaw 180` turned it
  to the road and it lit the booth's south door and the plaza through the wall (0.9 energy at most, found by
  `GlowBleed`; Compatibility has no shadow to stop it). And a mesh is lit by the box of the cone, not its shape
  (`LightCap.reaches`): aimed at the middle of the screen the cone's lower edge dipped under the stand's roof (4.3 m)
  and the cars, a seventh light on meshes the cap leaves six for. Its pitch is therefore its half-angle (the lower edge
  runs level at 5.4 m): the axis meets the screen's face 14 m up, the cone covers the middle of the screen, and the
  stand, the cars and the ground are outside its box. What it visibly lights is the screen's frame and the posts in
  its path: the screen's face is unshaded (`screen.gdshader`) and takes no light. `tests/world/test_projector_spot.gd`
  holds the aim, the level edge and that no wall or roof of the lot is inside the cone;
  `tests/captures/projector_spot_tour.tscn` shoots the lot from the field, the road and the booth (`--hide-spot` frees
  the light for a second run to count what it alone changes: free it, do not hide it, see the lesson).
- **The prize crane's lamp** (`PrizeCrane`, one `OmniLight3D`, 4.6 m since #830: in front of the prize board it
  reached a seventh light onto the stand's floor at 5 m) is counted at each crane spot by
  `test_the_crane_at_any_of_its_spots_keeps_the_lot_within_the_budget`: a crane is built at every spot, its lamp joins
  the lot's and its own meshes join the lit ones, and no mesh is over the fight budget. Beside the stand the lamp is one
  more light on the stand's floor and roof, which is why they are cut in four (below): each piece stays at 6 or fewer.
- **Tiles are sized to the lights** (issue #318). Compatibility counts lights per mesh, so a big ground box is reached
  by every lamp near any part of it, and the field's middle (eight lamps, the screen's 34 m glow, the stand's three
  inside lamps and its sign all overlap there) had tiles reached by 7 and 8. A search over cuts of the middle
  (`tools/world/build_greybox.py`, `FIELD_CORE_X` and `FIELD_CORE_Z`) found the fewest tiles that keep each at 6 or
  fewer: 12 tiles between x -16 and 16 in rows at z -38, -22 and -10 (the lamp rows), where 16 m tiles had been, and
  the dark flanks stay wide. 5 was not reachable by any cut searched: ScreenGlow and the sign reach every tile of the
  middle. The stand's floor and roof are each cut in four at x -4 and z 1 (`STAND_CUT_X`, `STAND_CUT`): the field's
  posts, the sign and the stand's own lamps reach the front, the midway's court lamp the back, the prize crane's lamp
  (beside the west wall) the west back, and no piece gets all of them. Cut in two it was 6 until the crane arrived
  (#274) and 7 with it; on a 0.5 m grid x -4, z 1 is the one cut that leaves floor and roof both at 6. Lamps, ranges
  and energies are untouched, so the picture and the rules' lit ground (`LotLamps.lit_at`, which counts lamp
  positions) did not change.
  Rejected: moving the midway's court lamp 4 m south (it drops out of the stand's floor and roof but takes 4 m2 of the
  midway's lit ground), shorter interior and sign ranges (the light would still reach through the wall: there are no
  shadows), and pool quads in place of lamp posts (a post is a lamp for the rules).
  Cost: 12 more CSG boxes (the field 24 to 30 tiles, the stand's floor and roof three more each) is 12 more draw calls
  of about 1,100 lit meshes. Chrome on an RTX 5080, `smoke.py --gpu --unpaced`, 1280 x 720, a 45 s night, the web
  export of `main` against this branch, three runs each, alternating, on a shared machine:

  | Build | Night frame mean | p50 | p95 (median second) | Worst second p95 |
  | --- | --- | --- | --- | --- |
  | `main`, 3 runs | 2.8 / 2.9 / 2.5 ms | 2.5 / 2.6 / 2.2 ms | 3.9 / 4.0 / 3.5 ms | 6.5 / 9.1 / 5.9 ms |
  | this branch, 3 runs | 2.7 / 2.9 / 2.7 ms | 2.5 / 2.7 / 2.3 ms | 3.7 / 4.1 / 3.7 ms | 5.3 / 6.4 / 5.6 ms |

  No difference beyond the run-to-run spread (the spread of one build is larger than the gap between the two).
- **Twenty hand-placed lamps, more cuts** (#703, #719). The maintainer added 20 lamp posts round the field in the
  editor (`FIELD_LAMPS` in the builder holds their numbers: `Lamp9` to `Lamp28`, and `Lamp1` and `Lamp2` moved), which put
  the midway's ground, the back lot's, the yard's (with the crane's lamp) and the stand's roof at 7 and 8. Lamps, ranges
  and energies are as they set them; the tiles were cut again, by a search that dumps every light and mesh box to a
  file and tries cuts on a 0.5 or 1 m grid with the test's reach rule: the midway in six tiles (cuts x -8, z 19 and 30),
  the back lot in three (z 10 and 24, from four), the yard in three (z 12 and 25, from four), the stand's roof in six
  (one more cut, z 4.6). No cut lies within 1.3 m of a fuel stand or shop spot (`test_lot_fuel.gd` wants the stand a
  metre inside one tile). Two more CSG boxes than before (18 against 16), and the same pictures: nine night views
  before and after differ only in the projector screen's animated noise.
- **Pools are quads, not light range.** Raising the lamp range to 14 m to get a bigger pool put 12 lights on one tile.
  The pool is now the quad, the light stays at 11 m.
- **The screen shows the circuit.** With `screen_lot` off the face keeps the 0.3 afterglow of its lamp and the posts,
  halos and pools go dark: the lit and dark halves of the lot read apart at a glance (capture `screen_circuit_off`).
- **Capturing it**: `night_look_tour.tscn` now has ten spots; the last three throw a breaker (`circuits` in the spot's
  dictionary: the stand on, then the screen's circuit off), through `NightState.apply_events` so the client sees the
  event as it does in play. `--quit-after 110`.

### Frame time of the lighting pass

Chrome on an RTX 5080 (ANGLE D3D11, WebGL2), 1280 x 720, `smoke.py --gpu --unpaced` (new flag: no vsync, no frame cap,
so the frame time is the GPU's work), a 45 s night, the web export of `main` against this branch, each twice, on a shared
machine (other agents were rendering; the run-to-run spread is as large as the difference):

| Build | Night frame mean | p50 | p95 (median second) | Worst second p95 | Console errors |
| --- | --- | --- | --- | --- | --- |
| `main`, run 1 / 2 | 4.0 / 3.5 ms | 3.5 / 2.8 ms | 7.4 / 8.3 ms | 31.4 / 24.7 ms | 0 |
| this branch, run 1 / 2 | 4.1 / 4.3 ms | 3.5 / 3.2 ms | 8.5 / 11.7 ms | 11.1 / 40.9 ms | 0 |

The pass costs roughly 0.1 to 0.8 ms of GPU time on a desktop card: about 25 small alpha-blended quads (pools, halos), the
screen shader (a dozen sin calls a pixel over the screen's area) and one 29-vertex cone, with no new light and no shadow.
The pools are the part to watch on a weak GPU: each is 15 m across, so a lot seen from the avenue overdraws the asphalt
a few times. A laptop GPU is still unmeasured (#82).
