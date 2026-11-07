# Why the muzzle flash read weak, and how it was measured

The maintainer, playing, found the muzzle flash weaker than it should be and asked for the cause to be looked into
(issue #408). #322 had reworked it and #323 had put it on each gun's `Muzzle`; both were checked by a test of
its frames and its position and by a close-up capture next to the gun. Nobody had measured it from the shoulder camera.
This page is the measure, the cause, and what the numbers are now. The design is in [Shot feedback](../design/shot-feedback.md#how-strong-the-flash-must-be).

## How it was measured

`game/tests/captures/flash_probe.gd` plays the real night (`Night`, the combat server, the view) from the shoulder camera
at 60 fps in Movie Maker: the soldier stands in the open, fires one shot of each gun, and **for every drawn frame the
flash is up** `FlashMeter` (`game/core/flash_meter.gd`) reads the frame back, draws it again with only the flash's light,
and once more with no flash, and compares the three. So the numbers are the flash's own pixels (its quads) and its own
wash of light, exactly, in the renderer in use, with no guess from colour:

- *area* and *height* of the pixels the quads changed (by 16 of 255 or more), at 1280 by 720;
- *hot pixels* (changed and at least 200 of 255), the *brightest* pixel and the mean rise;
- the *wash* of the light (pixels it lifted by 4 or more) and how far the **whole picture** brightens, flash and light
  together (so "not blinding" is a number).

The same meter runs in the browser build (`FlashWebProbe`, only with `?probe=flash` in the address, driven by
`tools/web_smoke/flash.py` in headless Chrome with the machine's GPU, 1280 by 720, ANGLE on Direct3D 11, RTX 5080)
and keeps the page's clock and the frame time, so the flash's life in milliseconds is measured too. A diagnostic run
with `--no-depth` draws the flash with the depth test off, to say what the gun and the body hide.
`--spawn` and `--look-down` shoot from where the night starts and with the view tilted down, as the browser's first
view is.

## The candidates the issue listed, one by one

| Candidate | Finding |
| --- | --- |
| Lifetime against the frame rate | **Part of it.** The flash was drawn for 2 frames: 33 ms at 60 fps, 37 to 53 ms in the browser (frames of 16 to 27 ms), 14 ms on a 144 Hz screen. Counted in frames on purpose, so the same on every screen, but a fast screen made it a blink. |
| Light energy and range | Not the cause where it was measured: on the ground ahead the light lifted 11 000 to 22 000 pixels by 29 to 38 of 255 and the whole picture by 4 to 6 of 255 (hip). It could fail in another way, see the last row. |
| Glow, tonemapping, the Compatibility renderer on the web | **Not a cause.** The flash's brightest pixel was 255 on the desktop and 248 to 255 in the browser; hot pixels were there. The Compatibility renderer has no glow, and the design does not lean on it. |
| Additive blend washed out by fog or the night grade | **Not a cause.** The shader is `fog_disabled`, and there is no grade pass over the picture; the mean rise of the flash's pixels was 140 to 175 of 255. |
| Size at the shoulder camera's distance | **The main cause.** A 0.20 to 0.42 m flash at about 2.8 m from the lens, with a 70 degree view, is a star 5 to 15 % of the screen's height; with what hid of it, the pixels the flash changed were **0.018 to 0.144 % of the screen** (hip) and 0.042 to 0.294 % (aimed): a 40 by 25 pixel star on a 1280 by 720 screen. |
| Hidden behind the hands or the gun | **The second cause, and the biggest for the small guns.** The quads lay in the muzzle's own plane, facing the camera; the gun, the fist and the arm round the muzzle are nearer the shoulder camera than that plane, and the depth test hid them. With the depth test off (the diagnostic run) the flash covered 1.4 times (pistol) to 7.9 times (flare gun) the pixels: the SMG's flash showed 26 % of itself, the flare gun's 13 %. |
| Occlusion by the world | Not seen: nothing stood between the lens and the muzzle in the open. A flash lifted toward the camera cannot be behind a wall the lens can see. |
| A light cap culling the flash light | **Not the cap, but the same kind of fault.** The first version of the new light sat 0.25 m along the barrel; in the browser's first view, which looks down on the soldier, the rifle and shotgun pointed at the ground, the light went under the floor and lit 1 500 pixels instead of 60 000. The cap itself held: `test_lot_light_cap` keeps room for one flash light, and 19 other lights were on at the spawn. |

## What the flash does now

| Change | Why |
| --- | --- |
| Drawn `camera_lift` (0.7 m) toward the camera from the muzzle, scaled by the same ratio so it looks the same size | the gun and hands can no longer hide it; a flash lifted along the line of sight keeps its place on the screen |
| Sizes 0.30, 0.32, 0.34, 0.42, 0.58 m (were 0.20, 0.22, 0.24, 0.30, 0.42) | 1.4 to 1.5 times, so the star is 10 to 24 % of the screen's height |
| A flat disc of glow behind the big star (`halo`), inside the same quad and shader | reads at a distance and in the dark in the toon style; no glow post effect, no new draw call, no new program |
| At least 3 frames and 60 ms (`frames`, `seconds`); it bursts to 1.15 times its size and dies down to 0.65 | 3 frames at 60 fps and in the browser, 9 at 144 Hz; the burst reads as fire |
| The light: warm, energy 2.0, range 3.4 m, 0.15 m ahead along the ground and 0.3 m above the muzzle | never under the floor; one light still, held by one flash at a time |
| Placed by the muzzle's drawn place (`get_global_transform_interpolated` of the parent) and physics interpolation off on the flash | the muzzle is drawn between ticks; the flash no longer lags a tick behind it at 144 Hz |

### Measured, before to after

Desktop, 1280 by 720, 60 fps, shoulder camera, from the open spot the probe finds. Hip:

| Weapon | Frames seen | Area of the screen | Height of the screen | Hot pixels | Whole picture brightens (of 255) |
| --- | --- | --- | --- | --- | --- |
| pistol | 2 to 3 | 0.07 % to 0.976 % | 6.11 % to 15.0 % | 538 to 2908 | 4.73 to 6.64 |
| smg | 2 to 3 | 0.026 % to 0.377 % | 5.56 % to 14.03 % | 198 to 1328 | 3.99 to 4.76 |
| rifle | 2 to 3 | 0.081 % to 0.552 % | 7.92 % to 17.5 % | 628 to 1395 | 4.07 to 4.87 |
| shotgun | 2 to 3 | 0.144 % to 1.04 % | 15.14 % to 24.31 % | 1055 to 2838 | 4.14 to 5.27 |
| flare_gun | 2 to 3 | 0.018 % to 0.676 % | 6.67 % to 16.11 % | 114 to 1940 | 3.71 to 4.68 |

Aimed (the aim button held, the zoomed view):

| Weapon | Frames seen | Area of the screen | Height of the screen | Hot pixels | Whole picture brightens (of 255) |
| --- | --- | --- | --- | --- | --- |
| pistol | 2 to 3 | 0.042 % to 0.925 % | 6.67 % to 16.94 % | 315 to 2793 | 2.52 to 3.76 |
| smg | 2 to 3 | 0.083 % to 0.817 % | 7.08 % to 18.06 % | 666 to 2684 | 2.87 to 4.05 |
| rifle | 2 to 3 | 0.191 % to 1.133 % | 10.97 % to 22.08 % | 1463 to 3464 | 3.39 to 4.64 |
| shotgun | 2 to 3 | 0.294 % to 1.987 % | 17.36 % to 30.14 % | 2206 to 5983 | 3.61 to 5.36 |
| flare_gun | 2 to 3 | 0.06 % to 1.237 % | 8.47 % to 20.14 % | 456 to 3505 | 2.42 to 3.91 |

In the browser (headless Chrome, the machine's GPU, the first view from where the night starts, which looks down on the
soldier), before to after:

| Weapon | Frames seen | Area of the screen | Height of the screen | Hot pixels | Whole picture brightens | Drawn for (ms, no measuring) |
| --- | --- | --- | --- | --- | --- | --- |
| pistol | 1 to 3 | 0.002 % to 0.275 % | 1.25 % to 9.58 % | 11 to 700 | 5.9 to 9.84 | 40.8 to 68.9 |
| smg | 2 to 3 | 0.007 % to 0.211 % | 2.5 % to 10.69 % | 52 to 613 | 5.13 to 8.97 | 37.4 to 47.7 |
| rifle | 2 to 3 | 0.019 % to 0.315 % | 4.17 % to 12.64 % | 157 to 671 | 3.66 to 8.41 | 50.1 to 109.2 |
| shotgun | 2 to 3 | 0.085 % to 0.734 % | 11.11 % to 18.47 % | 739 to 2106 | 2.88 to 8.05 | 53.2 to 74.7 |
| flare_gun | 2 to 3 | 0.007 % to 0.436 % | 5.42 % to 12.08 % | 49 to 1141 | 6.14 to 10.03 | 42.3 to 86.8 |

The flash is up for 3 frames where it was 2 in every row; no weapon's flash is under a floor of
`game/tests/captures/flash_floors.json` any more, and every one was under before. The picture as a whole brightens by at
most 10 of 255 (4 %) in the browser's down-looking view where the light lands on the ground close by (it was 3 to 6
before), well under the ceiling of 13.

## Frame cost

The flash is the same three quads and one light, and one shader whose program the warm-up draws already (the halo is
two more lines in the same shader, not a second program). No new allocation or material per shot: the quads, the
materials and the light are made when the flash is. Measured in the browser (headless Chrome, the machine's GPU, not
paced, `flash.py --bench 8`: the trigger held for 8 s with the SMG, the shotgun and the pistol, two runs each, before and
after): mean frame 4.3 to 4.7 ms before and 4.3 to 5.1 ms after, p95 4.3 to 8.4 ms in both, 1 600 to 1 900 frames per
run, **no GL program linked while firing in any run** (the halo is two lines in the same shader, not a second program),
and the occasional 45 to 90 ms frame in both builds (the per-shot spike that the open pull request #402 removes; this
change neither adds to it nor removes it).

## Things that bit

- **`force_draw` inside `frame_post_draw` calls `frame_post_draw` again.** The meter guards with a flag
  (`FlashMeter.busy`); without it the probe recursed to a stack overflow.
- **The camera speaks in the window's units, the image in pixels.** `unproject_position` answers in the stretched
  1920 by 1080 even with `--resolution 1280x720`; scale by image size over `get_visible_rect().size`. Movie Maker
  writes 1920 by 1080 whatever `--resolution` says, and the file number is `Engine.get_frames_drawn()` at the post-draw
  call, with no offset.
- **A close-up capture does not show this.** The flash looked fine from the side, next to the gun. Measure an effect
  from the camera the player has.
- **A light placed along a barrel goes where the barrel goes.** Put it above the floor by its own offset.
- **A flash made of a few percent of its own size in pixels needs a floor in pixels,** not in metres: the unit test holds
  the metres (how big, how long, how clear), the probe holds the pixels.

## Sources

- Godot docs: [Compatibility renderer feature list](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html),
  [Physics interpolation](https://docs.godotengine.org/en/latest/tutorials/physics/interpolation/index.html),
  `RenderingServer.frame_post_draw`, `RenderingServer.force_draw`, `Node3D.get_global_transform_interpolated`.
- [Shot feedback research](shot-feedback.md): what the genre does with a flash, and why it is a sprite and not a light.
