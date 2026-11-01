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
camera at nine spots (looking up at the screen, across the lot, up the avenue, over the flank, in the yard and the
back lot, then the stand powered and the screen's circuit off), with the dead lined up 25 m away at one. Each spot
holds ten frames, so frame `10 * spot + 9` is the settled shot:

```text
godot --path game res://tests/captures/night_look_tour.tscn --write-movie <abs>/look.png --fixed-fps 10 --quit-after 100
```

Add `-- --hud` to draw the real HUD over the night.

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
| Projector beam | `ProjectorBeam`: a 29-vertex elliptical cone of additive haze from the booth's port to the screen (`beam.gdshader`), a halo at the lens | one draw, no light |
| Neon | `LotNeonSign` over the concession door: tubes, `Label3D`, halo, and an omni that hangs on the concession circuit | one light, only while powered |
| Windows | `GlowPane`: an additive pane in each front window of the stand | one quad each |
| Breaker posts | a billboard halo round the lamp, green on and dull red off, so a post reads across the lot | one quad each |

What carries the circuits: every glowing thing is a `LightFollower` that reads the **lamp it follows** (its
`light_energy` over the energy the scene gave it, 0 when `LotLamps` hid it), so a switched circuit, a failing tank and
the screen's afterglow reach the glow with no second path to keep in step. The flicker's phase is the frame's own delta
(Movie Maker steps it at a fixed rate) and every flicker curve is a function of the phase alone, so a test calls
`advance` and gets the same light. A lamp that is only seen (the sign's) carries `metadata/decor` and lights no ground
for the dead's slowdown (`LotLamps.lit_at`).

- **The cap per mesh is tested** (`test_lot_lighting.gd`): with every circuit on, no CSG box of the lot is reached by more
  than 8 lights (omni by sphere, spot by its cone's box). The first run found 11 on one 24 m field tile; the field's
  ground is now tiled at 16 m, as `floor_tiles` already says it must be. The 320 m `Outskirts` slab is exempt: every
  lamp reaches it and it is near-black.
- **Pools are quads, not light range.** Raising the lamp range to 14 m to get a bigger pool put 12 lights on one tile.
  The pool is now the quad, the light stays at 11 m.
- **The screen shows the circuit.** With `screen_lot` off the face keeps the 0.3 afterglow of its lamp and the posts,
  halos and pools go dark: the lit and dark halves of the lot read apart at a glance (capture `screen_circuit_off`).
- **Capturing it**: `night_look_tour.tscn` now has nine spots; the last two throw a breaker (`circuits` in the spot's
  dictionary: the stand on, then the screen's circuit off), through `NightState.apply_events` so the client sees the
  event as it does in play. `--quit-after 100`.

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
