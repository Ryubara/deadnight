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
camera at seven spots (looking up at the screen, across the lot, up the avenue, over the flank, in the yard and the
back lot), with the dead lined up 25 m away at one. Each spot holds ten frames, so frame `10 * spot + 9` is the
settled shot:

```text
godot --path game res://tests/captures/night_look_tour.tscn --write-movie <abs>/look.png --fixed-fps 10 --quit-after 85
```

Add `-- --hud` to draw the real HUD over the night.
