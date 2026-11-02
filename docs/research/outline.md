# Outline through walls

The last zombies of a round glow through walls, so the players can find them (issue #523). The component is
universal: any skinned or static mesh, no edit to its model. How it is built, what we measured, and the choices that
are the maintainer's.

## How it works

Compatibility has no post-process depth or normal buffers to detect edges in, and the web build is WebGL2, so the
outline is drawn with the **stencil buffer** (`stencil_mode` in a spatial shader, Godot 4.7). Each outlined mesh gets
one `material_overlay`, a chain of `ShaderMaterial` passes (`OutlineStyle.chain()`):

1. **Mask** (`outline_mask.gdshader`): no depth test, writes 1 into the stencil wherever the mesh is, draws nothing.
2. **Line**: 8 copies of one shader (`outline.gdshader`), each pushed `reach` pixels along one of 8 directions on the
   screen (in clip space, `clip.xy += direction * pixels * 2 / VIEWPORT_SIZE * clip.w`), drawn only where the stencil
   is not 1 and writing it as they go, so a pixel is coloured once. The union of the copies is a dilation of the
   silhouette: the same number of pixels wide at any distance, with no gaps at the hard edges of a low-poly mesh (the
   usual "inverted hull" pushed along normals splits there) and correct on a skinned mesh (the vertex function sees the
   pose). The inside stays unfilled.
3. **Glow**: 8 more copies at about 3.5 times the reach, with a low alpha, behind the line. With `glow = 0` they are
   left out of the chain.

Nothing is drawn for a mesh without the overlay: the zombie views make their `Outline` node at the first mark, and
`ZombieMarks` does no work while nobody is marked and the rule says nobody should be.

Thickness is in pixels of a 1080-high screen and is scaled by `VIEWPORT_SIZE.y / 1080`, so it reads the same in a
window, on a phone, and with the 3D resolution scale lowered.

## The rule

Every frame of the server carries `phase` and `remaining` (zombies still to spawn plus those alive). While the phase
is ACTIVE and `1 <= remaining <= mark_last` (`ZombieTuning.mark_last`, default 3), every zombie that is not dying is
outlined, on every client, because they all read the same frame. Counting the zombies still to spawn keeps the mark off
at the start of a round when few have come out yet. It clears when the round ends, when the count rises (a new round),
when a zombie dies, or when `ZombieMarks.enabled` is turned off. A parked body (`ZombieHorde` keeps them) is cleared.

## Tuning live

In a running game from the editor (Remote tab): `NightView/ZombieMarks` holds `mark_last`, `enabled` and `style`
(an `OutlineStyle`: `color`, `thickness`, `glow`). The style is one resource shared by every marked zombie, so a change
reaches every body in the same frame. The defaults are in `game/gameplay/outline/outline_style_default.tres` and
`zombie_tuning_default.tres`. Another use of the component (`Outline` node, `target`, `style`, `enabled`) can have a
style of its own.

## Measured

A crowd of 40 chasing in the lot (`tests/captures/crowd_cost_bench.tscn`, `--outline=N` outlines the N zombies nearest
the camera), the web export, medians of runs interleaved so a slow minute hits every row. Reproduce with
`tools/web_smoke/outline_cost.py`. Every outlined zombie is 17 passes (a mask, 8 line copies, 8 glow copies), so
17 draw calls a mesh, two meshes a zombie.

| Outlined | Chrome with the GPU: frame ms (p95) | Draw calls | SwiftShader (software GL): frame ms | Draw calls |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 2.66 (3.60) | 85 | 199 | 108 |
| 3 | 2.62 (3.60) | 136 | 239 | 158 |
| 8 | 2.56 (3.60) | 152 | 293 | 241 |
| 40 (all) | 3.36 (5.00) | 168 | not run | |

- With a GPU the default (3 outlined) is inside the noise: the 3.6 ms p95 does not move. Even all 40 cost under 1 ms.
- On the software renderer, which is bound by vertex and pixel work on the CPU and stands in for a very weak device,
  3 outlined cost 40 ms on a 199 ms frame (+20 %), 8 cost 94 ms. The cost is per pass, so `glow = 0` leaves out
  half of them, and fewer line copies (`OutlineStyle.DIRECTIONS`, 6 gives a visibly rougher edge at 3 px) is the other
  lever. The bench is a worst case: a frame that already takes 199 ms is not a frame anyone plays.
- The mark is only on for the last `mark_last` zombies of a round, so the cost is a few seconds of each round, never
  the whole night.
- Desktop (OpenGL, same bench, unpaced): 3 outlined add about 0.1 ms to a 1.1 ms frame.
- The shader programs (a mask and a skinned line) are built behind the loading screen: `NightWarmup` draws the
  staged zombie row outlined once, so the first mark does not hitch.

## Open choices (the maintainer's)

The defaults are the issue's reading; they are one-line changes in the two `.tres` files.

- **Look:** colour `#FF591F` (hot orange, reads against the night's blues and the brick), 3 px at 1080p, glow 0.6.
- **When it shows:** the last 3 including zombies still to spawn; emerging zombies (still under the ground) are
  outlined too, dying ones are not.
- **Who sees it:** every player; there is no per-player switch yet.
