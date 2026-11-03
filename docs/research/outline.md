# Outline through walls

The last zombies of a round are outlined through walls, so the players can find them (issue #523). The component is
universal: any skinned or static mesh, no edit to its model. How it is built, what we measured, and the choices that
are the maintainer's.

## How it works

Compatibility has no post-process depth or normal buffers to detect edges in, and the web build is WebGL2, so the
outline is drawn with the **stencil buffer** (`stencil_mode` in a spatial shader, Godot 4.7) and kept off the visible
parts with the **depth texture** (`hint_depth_texture`, which Compatibility copies for a shader that asks).
Each outlined mesh gets one `material_overlay`, a chain of `ShaderMaterial` passes (`OutlineStyle.chain()`):

1. **Mask** (`outline_mask.gdshader`): no depth test, writes 1 into the stencil wherever the mesh is, draws nothing.
2. **Line**: 8 copies of one shader (`outline.gdshader`), each pushed `reach` pixels along one of 8 directions on the
   screen (in clip space, `clip.xy += direction * pixels * 2 / VIEWPORT_SIZE * clip.w`), drawn only where the stencil
   is not 1 and writing it as they go, so a pixel is coloured once. The union of the copies is a dilation of the
   silhouette: the same number of pixels wide at any distance, with no gaps at the hard edges of a low-poly mesh
   (the usual "inverted hull" pushed along normals splits there) and correct on a skinned mesh (the vertex function
   sees the pose). The inside stays unfilled.

There is no glow: the line is the whole look (issue #617; the first version had a second, wider and fainter ring).

### Only where it is hidden

The mask has no depth test on purpose (a hidden part must still count as "the body" so the inside stays empty), so
the stencil alone outlines a body in the open too. Each line copy therefore decides per pixel whether the body
surface it stands for is hidden, from the depth texture, and discards the pixel when it is not:

- A copy's fragment shows a surface point of the body, which really lies `shift` away on the screen. The copy
  passes the **view depth of that point** (`own_depth`, from the vertex function) and the shader reads the scene's
  depth where the point really is (the pixel `shift` back) and where the copy lands. The line is drawn only when
  the scene is nearer than the point at both: the first keeps the line off a body that stands on the ground (the
  ground at the copy's pixel is nearer than the sole, though it hides nothing), the second cuts the line at an
  occluder's edge instead of letting it spill a line's width past it.
- The depth at the point's own pixel is checked on **five samples** (the pixel and four a pixel and a half round it),
  and all of them have to be nearer than the point: a surface that is only a rounding away (the ground beside a
  foot) does not count as hiding it.
- **Back faces are culled** in the line passes. With `cull_disabled` a copy's back face lies behind the body's own
  front face, which counted as "hidden by it" and drew a line on the soles of zombies in the open.
- The margin is `0.12 m + 0.01 m per metre + 4 times the depth step across the surface there` (the difference of the
  samples either side). Feet that sink a few centimetres into the ground are metres along the view where a far
  zombie sees the ground at a grazing angle: a flat `0.04 m per metre` still left specks under the feet of a zombie
  14 m away, and `0.12 m per metre` (1.8 m at 14 m) removed them but would stop a car 1.5 m in front of a zombie from
  hiding it. Scaling by the slope widens the margin only on grazing surfaces (the ground) and on the one-pixel step at
  an occluder's edge.
- Reading the depth texture is the one extra cost; the renderer copies the depth only for a frame that has a mesh
  wearing the overlay, so nothing is paid while nobody is marked.
- Compatibility's depth buffer holds 0 to 1 and the clip depth is `2 * depth - 1` (Forward+ and Mobile hold it as is).
  The reconstruction is `INV_PROJECTION_MATRIX * vec4(uv * 2 - 1, depth * 2 - 1, 1)`, and `VIEWPORT_SIZE` is only
  readable in `vertex` and `fragment`, not in helper functions (pass it in).

Proved by `tests/outline/test_outline_pixels.gd` (renders a box behind a counter, a wall or nothing and reads the
pixels: none in the open, none above the counter's edge, the line all round behind a wall, nothing farther from the
silhouette than the line's width) and by captures from the player's camera (`tests/captures/outline_tour.tscn`,
spots `open`, `half`, `near`, `far`; in the browser `tools/web_smoke/outline_capture.py`).

## The rule

Every frame of the server carries `phase` and `remaining` (zombies still to spawn plus those alive). While the phase
is ACTIVE and `1 <= remaining <= mark_last` (`ZombieTuning.mark_last`, default 3), every zombie that is not dying is
outlined, on every client, because they all read the same frame. Counting the zombies still to spawn keeps the mark off
at the start of a round when few have come out yet. It clears when the round ends, when the count rises (a new round),
when a zombie dies, or when `ZombieMarks.enabled` is turned off. A parked body (`ZombieHorde` keeps them) is cleared.

## Tuning live

In a running game from the editor (Remote tab): `NightView/ZombieMarks` holds `mark_last`, `enabled` and `style`
(an `OutlineStyle`: `color`, `thickness`). The style is one resource shared by every marked zombie, so a change
reaches every body in the same frame. The defaults are in `game/gameplay/outline/outline_style_default.tres` and
`zombie_tuning_default.tres`. Another use of the component (`Outline` node, `target`, `style`, `enabled`) can have a
style of its own.

## Measured

A crowd of 40 chasing in the lot (`tests/captures/crowd_cost_bench.tscn`, `--outline=N` outlines the N zombies nearest
the camera), the web export, medians of runs interleaved so a slow minute hits every row. Reproduce with
`tools/web_smoke/outline_cost.py`. Every outlined zombie is 9 passes (a mask and 8 line copies), so 9 draw calls a
mesh, two meshes a zombie (the first version, #580, had 8 more for the glow and no depth read).

| Outlined | Chrome with the GPU: frame ms (p95) | Draw calls | SwiftShader (software GL): frame ms | Draw calls |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 2.67 (3.70) | 85 | 243 | 105 |
| 3 | 6.51 (9.60) | 130 | 255 | 132 |
| 8 | 5.60 (8.20) | 166 | 265 | 176 |
| 40 (all) | 6.99 (12.10) | 189 | not run | |
| *#580, 3 (17 passes, no depth)* | *2.62 (3.60)* | *136* | *239 (of 199)* | *158* |

- **The depth read costs a fixed 3 to 4 ms of frame time on this GPU while anybody is outlined, not per zombie** (2.67
  to 6.51 ms with 3, 6.99 with all 40). A shader that does nothing but read the depth texture costs the same (2.87
  to 6.20 ms, 3 runs), so it is the engine's copy of the depth buffer for the shader (probably the multisample
  resolve: the project draws with 2x MSAA; not isolated), not the shader's arithmetic. It is paid only while the mark
  is on,
  the last `mark_last` zombies of a round, and nothing is paid when nobody is marked (the overlay is off, so no shader
  asks for the depth). 6.5 ms is still 150 frames a second here; a weak phone pays more for a depth copy (the copy
  ends the tile pass), which has not been measured: that is the open cost of the issue's choice of a depth test.
- On the software renderer, which is bound by vertex and pixel work on the CPU and stands in for a very weak device,
  the cost per outlined zombie is lower than before: 3 outlined add 12 ms on 243 (+5 %, they added 40 ms on 199 with
  17 passes), 8 add 22 ms. The cost is per pass, so fewer line copies (`OutlineStyle.DIRECTIONS`, 6 gives a visibly
  rougher edge at 3 px) is the lever. This run's baseline is slower than the first one's (243 against 199): compare
  the rows of one table, not across tables.
- Desktop (OpenGL) is not re-measured with a crowd: the desktop run of the bench leaves 2 of 40 alive, so its
  numbers say nothing about the cost of the outline. Its pictures are the captures of `outline_tour.tscn`.
- The shader programs (a mask and a skinned line) are built behind the loading screen: `NightWarmup` draws the
  staged zombie row outlined once, so the first mark does not hitch.

## Open choices (the maintainer's)

The defaults are the issue's reading; they are one-line changes in the two `.tres` files.

- **Look:** colour `#FF591F` (hot orange, reads against the night's blues and the brick), 3 px at 1080p, no glow.
- **When it shows:** the last 3 including zombies still to spawn; emerging zombies (still under the ground) are
  outlined too, dying ones are not.
- **Who sees it:** every player; there is no per-player switch yet.
