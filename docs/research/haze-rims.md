# Haze columns have a soft rim from the shoulder camera

Issue #854: upstairs on the second map a pale column stood as tall as the room beside the player, a hard-edged shell
from 1 to 4 m. The review that found it named the pendant lamps' haze cones (`UpperB/Lamp7`, `Lamp8`,
`UpperA/Lamp6`); it was the prize crane's beam.

## What it was

`PrizeCrane._make_beam` is a 36 m cylinder on its own inline shader, `blend_add` and `cull_disabled`, its alpha only
fading with height: the same brightness right across its width and no edge fade, so its rim was a hard step, and
nothing took it out of a camera standing in it. The crane's cabinet is on the ground floor and its beam stands up
through the room above (a landmark for the crane from far off, which it keeps). The pendant haze cones
(`beam.gdshader`) already fade where their surface turns edge-on and under 2 m from the eye, and read as warm, soft
beams.

Found by hiding every node on a shader one at a time and counting the pixels that change in the shell's region: the
shell was the one node with the crane's inline shader (tint 0.45, 0.8, 1.0). Kit lesson:
[a pale column was blamed on the wrong
node](https://ryubara.github.io/gdstudio/engines/godot/measuring-effects-on-screen/#a-soft-rim-and-which-node-it-is).

## The change

The crane's beam fades by the facing of its wall to the eye (`pow(abs(dot(NORMAL, VIEW)), 2)`, the same idea as
`beam.gdshader`'s) and by distance below 2.5 m (`BEAM_RIM_POWER`, `BEAM_NEAR_FADE` in `prize_crane.gd`, set as the
material's `rim_power` and `near_fade`). Its centre is as bright as before; no new node, mesh, light, shader or draw
call (#728). The pendant cones are not changed (below).

## Measured

`game/tests/captures/smallmap_haze_cones.tscn` puts the player's shoulder camera 1, 2, 3, 4, 6 and 8 m from each
column's axis (the first of eight bearings with the camera clear), the game frozen, and draws it with the column shown
and hidden (the body hidden too). The rim softness is, on each row the column spans, how many pixels its added
brightness takes to rise from 10 % to 90 % of that row's brightest, from each edge, as a share of the row's width; the
median over the rows. A hard edge reads 0.00 to 0.04, a soft fade 0.2 or more. 1920 by 1080, desktop, RTX 5080,
Compatibility, Godot 4.7.2.

| Camera to the axis | 1 m | 2 m | 3 m | 4 m | 6 m | 8 m |
| --- | --- | --- | --- | --- | --- | --- |
| Crane beam, before | in it (covers 100 %) | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| Crane beam, after | in it (covers 34 %, camera 1.4 m) | 0.34 | 0.27 | 0.23 | 0.12 | 0.31 |
| Lamp7 cone (unchanged) | 0.23 | 0.16 | 0.15 | 0.08 | 0.08 | 0.06 |
| Lamp8 cone | 0.19 | 0.15 | 0.16 | 0.20 | 0.08 | 0.15 |
| Lamp6 cone | 0.08 | 0.15 | 0.21 | 0.19 | 0.12 | n/a (no clear spot) |
| Shop lamp cone | 0.39 | 0.14 | 0.20 | 0.10 | 0.07 | 0.04 |

The cones were soft to begin with (0.08 to 0.39 at 1 to 4 m, a hard edge being under 0.04), so the lamp shaders are
left as they were: a harder fade at the cone's edge near the eye was tried (an exponent that grows nearer the camera)
and measured no softer, only dimmer (13 to 21 % fewer pixels lit at 1 to 4 m). From 6 m the crane beam is still a
faint column (a landmark), without the shell's edge.

`test_haze_rims.gd` holds the settings that were measured (the crane beam's `rim_power` and `near_fade`, the lamps'
near fade and one cone each, no extra mesh), and the measure itself on synthetic columns (a hard edge reads under
0.03, a soft one over 0.2). The pixels need a window, so they are measured by the capture, not in CI.

## Running it

```text
gds godot -- --path game res://tests/captures/smallmap_haze_cones.tscn -- --out=<folder> [--only=<lamp or crane>] [--old] [--diffs]
```

`--old` puts the crane's beam back as it was before #854 (`rim_power` and `near_fade` 0), for the before numbers and
pictures from the same build; `--diffs` writes the difference pictures. About eight minutes for everything.
