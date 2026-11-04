# The HUD's draw cost (#948)

The performance sweep (#906) found the HUD at about 125 of 400 draw calls with a late-round crowd, 1.5 to 3 ms a frame,
nearly all of it drawing and not script. This page is what made the calls and what was done about them. What applies to
every game is the kit's page [Canvas draw calls](https://github.com/Ryubara/gdstudio/blob/main/docs/godot/canvas-draw-calls.md).

## Why a card cost 10 to 15 calls

In the Compatibility renderer only rects batch (`draw_rect`, textures, `draw_string`). Two things in the HUD were not
rects:

- **Every polygon, polyline and circle is a draw call and ends the rect batch around it.** A ticket (`HudStyle.draw_ticket`)
  was a shadow polygon, a paper polygon, an edge polyline and a stripe rect: four calls, plus the label rects between
  them split in two. A perk badge was six to eight, the six of them 48; a player's box and a slot cell three each; the
  round banner's thirty bulbs thirty circles.
- **A `Label` with an outline and a shadow is four calls** (shadow of the outline, shadow, outline, letters: two
  textures, alternating). The HUD has about thirty labels: 120 calls.

## What was done

- `HudShapes` (`ui/hud/hud_shapes.gd`) collects polygons, rects, lines, polylines and circles in one triangle array and
  draws it as one command (`RenderingServer.canvas_item_add_triangle_array`), in drawing order. Tickets, player boxes,
  slot cells, perk badges (frame and emblem), the banner (card and bulbs), the generator gauge (segments and bulbs) and
  the world markers (all of them in one command, their words in two) use it. A card is one call.
- `HudLabel` (`ui/hud/hud_label.gd`, what `HudStyle.label` makes) draws the outline itself, in a canvas item behind its
  own, and leaves the engine the shadow and the letters: two calls. Wrapped labels (the prompt, the objective, the
  banner's subtitle) draw theirs with a `TextParagraph` on the engine's breaks. The shadow of the outline is not drawn:
  it is a rim under the outline. A row that fades in by `self_modulate` (`HudRowStack`) goes through
  `HudLabel.set_enter_alpha`, which gives the outline the same alpha.
- The generator's low-fuel pulse is the alpha of a layer holding the lit segments (`HudFuel._lit`), not a redraw of the
  gauge every frame (its bulbs were polygons rebuilt sixty times a second).
- `HudMarkers` redraws when its picture changes (places in quarter units of the canvas, whole metres, words, state), not
  when the state holds a new float place, which is every frame for a marker that follows the world.

The picture is the same: the same triangles and the same glyphs, compared pixel by pixel in the `hud_cost` capture, at
the desktop and at the phone window, in a fight and at a round's start: at most one level of 255 in about 3,000 pixels
(the order the black runs of an outline are blended in). The 3D portraits are left out of the comparison: they are not
the same twice. The phone window found a rebuilt border that was identical at 1:1 and short 174 pixels at 0.36
scale (the corner of a thin line was not mitred).

## Numbers

`game/tests/captures/hud_cost.tscn`: a late-round HUD with nothing under it (a party of four at round 24, one down, 64
of 96 left, six perks, three weapons, the generator panel, three feed rows, three gains, three markers, a prompt), draw
calls of the frame, portraits left out so the two builds compare.

| Late-round HUD, draw calls | Before | After | |
| --- | ---: | ---: | ---: |
| Desktop 1920 x 1080, in a fight | 249 | 133 | -47% |
| Desktop, with the round banner up | 301 | 140 | -53% |
| Phone 844 x 390, touch layout, in a fight | 222 | 107 | -52% |
| Phone, with the round banner up | 272 | 112 | -59% |

By part, desktop, in a fight (a column is hidden alone and the frame counted again, so the rows overlap where parts
batch):

| Part | Before | After |
| --- | ---: | ---: |
| Slots and ammo | 41 | 26 |
| Points and health | 37 | 20 |
| Round and objective | 36 | 24 |
| Generator, feed, notices | 38 | 22 |
| Perk badges | 48 | 9 |
| Markers | 19 | 10 |
| Prompt | 17 | 12 |
| Gains | 12 | 9 |

In a real night (`BenchAblation`, `hudcost=1`: the autopilot at 1280 x 720, count 5, the dead standing at the platform's
ceiling of 40, the frame counted with the HUD up and hidden in turn, 16 times, so the lot's own changes average out; the
ceiling is 40, not the 64 the issue counted):

| Real night, 40 dead | Before | After |
| --- | ---: | ---: |
| The HUD's draw calls | 79.4 | 50.4 (-37%) |
| The whole frame's draw calls | 501 | 469 |
| Redraws of the HUD's items a frame (`draw` signals) | 1.43 | 1.02 |
| of them the markers, a frame | 0.75 | 0.36 |

An earlier pair of runs, with fewer repeats and before the wrapped labels and the markers were batched, read 71.5 to
51.6 and 75.6 to 54.6: the count of the lot moves by a few calls from run to run, so read the HUD's number to within
five. The part shares of a night are that noisy (a part of three calls reads -3 to +5), so the table above, which has
nothing under the HUD, is the one to read by part.

Idle HUDs redraw nothing: `test_hud_idle_redraws.gd` stands the late-round HUD still and counts the `draw` signals of
every item below it over a second of frames, with the low-fuel pulse running too (0), and shows a change redraws only
the card that changed.

## What is left

- The round's reel digits (about 4 calls each), the hit markers and damage numbers (the crosshair redraws each frame a
  hit is live, by design: a number is tied to a point of the world, 88 a second with the autopilot firing without
  stopping), the markers when the camera or a body moves (0.36 a frame while walking), and the downed teammate's ring
  (antialiased arcs).
- The slot strip's pictures are one call each (a texture apiece).
- The marquee and the damage frame (#934) are their own pull request.
- The web build was not measured here: the counts are the renderer's (`RasterizerCanvasGLES3`, the same on WebGL2), but
  the milliseconds are not.
