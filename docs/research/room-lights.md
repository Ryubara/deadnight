# A room's lamps light that room: render layers

Issue #841, the second half of #832 ([glows and lights stay on their side of a wall](glow-bleed.md)). The
Compatibility renderer casts no shadow, so an omni light reaches every surface inside its range, wall or not: the stand's
three lamps, the field's posts 5, 6 and 12, the booth's lower lamp and the second map's pendants lit the next room's
floors, ceilings and wall bases at 0.2 to 0.7 energy (the second map's pendants, up to 0.7 on the upper halls' wall
bases: a ground-floor lamp lit the wall above its own ceiling slab).

## What was tried

| Idea | Result |
| --- | --- |
| **A light layer per room** (`GeometryInstance3D.layers` on the boxes, `Light3D.light_cull_mask` on the lamps) | Taken. Works in the Compatibility renderer (a probe: a box on layer 2 is lit by a lamp with mask 1 and 2, a box on layer 4 stays black). Two integers in the scene: no draw call, no light, no shader program. |
| **A ceiling lamp as a downward spot** (`SpotLight3D` facing down, cone under 90 degrees) | Not taken. It cures the wall above the lamp, but takes the light off the ceiling over it too: the booth's ceiling lost the pool its lamp made (`tests/captures/room_lights_tour.tscn --spot`, frames in the pull request). It cannot cure a lamp through a side wall at all. |

## How the layers work here

- The default layer (1) is everything that moves or is not a floor, a wall or a ceiling of a room: the dead, the
  players, the props and every box that no lamp leaked on. A lamp that names layers keeps bit 1 (a test fails on one
  that does not): without it the dead standing in a lit room would be dark.
- A lamp that reached through a wall names **the default layer and its room's**; a floor, wall or ceiling that must not
  take that lamp is moved to a layer the lamp lacks. Lamps that never leaked keep every layer, so nothing else changed.
  The camera sees layers 1 to 20, so a box off layer 1 still draws.
- The generators write them (`tools/world/build_greybox.py` `RENDER_RULES` and `LIGHT_MASKS`, the second map's in
  `build_smallmap_greybox.py`); each map has its own few layers.

| Map | Layer | Holds | Lit by |
| --- | --- | --- | --- |
| Drive-in | 2, the stand | the stand's floors and its end walls | the stand's three lamps and the soda fountain's glow |
| Drive-in | 3, outdoors | the ground and alleys beside the stand, the booth's walls and roof above its ceiling | the posts 5, 6 and 12 (and the lamp up there) |
| Second map | 2 to 5, a room each | the room's floor and walls; a slab or a wall between two rooms is on both | the room's lamps (and the machines' glows in it) |
| Second map | 6, outdoors | the roof parapets, the notch's ground | no room's lamp |

## What it costs (the look)

A lamp that names layers loses every surface it cannot share a layer with. `GlowBleed.lost_lights` lists what each lamp
could see (no wall between) and lost, and `test_glow_bleed.gd` holds the table with a reason for each line:

- the stand's lamps no longer light the ground outside its doorway and window (0.23 and 0.53 energy; the sign's spot
  gives that ground 8 and the posts 1.5, and the doorway's own glow is a card);
- the second map's first hall lamp no longer lights, up the stairwell, the next hall's wall base and floor (0.56 and
  0.67), and the upper lamp no longer lights the wall and ceiling below it (what it did through the slab was the leak);
- the booth's upper room (frame 7 of the tour) is darker over its ceiling edges and north wall: the lower lamp's purple
  wash through the floor is gone and only its own lamp lights it.

Those, and what stopped leaking, are the "before" and "after" frames in the pull request, from the room behind the wall
and from inside each room, with the difference drawn.

## What stays (the table in `test_glow_bleed.gd`, each line with its reason)

| Lamp | Up to | Why |
| --- | --- | --- |
| Booth's lower lamp, the re-cut glow | 0.37, 0.26 | the booth's south, west and east walls are one box over both storeys; splitting one costs a draw call |
| Second map, upper hall lamp | 0.24 | one slab box is the upper hall's floor and the terrace past its south wall |

## What it costs (the frame)

Nothing that shows. The budget is [#728's](phone-frames.md): no new draw call and no new light.

- **Draw calls, objects and triangles are the same** in all 19 camera poses of the tour in both maps, with and without the
  layers (`--flat` against the layers, same build; for example 347 draw calls, 347 objects, 60 214 primitives in the
  stand's floor view either way). The scenes differ by property lines only (a `layers` line on 72 boxes and a
  cull mask on 19 lights, none added).
- **The web build on the phone page** (`tools/web_smoke/phone_frames.py`, 844 x 390, pixel ratio 3, touch, the autopilot
  night, frame limit lifted): the build from the branch before the change against the build after, alternating, three
  runs of each, the medians of the runs:

| Processor | | p50 | p95 | p99 | runs' p50 range |
| --- | --- | --- | --- | --- | --- |
| x1 (90 s) | before | 12.7 ms | 24.6 ms | 46.1 ms | 11.2 to 13.4 |
| x1 | after | 12.6 ms | 24.6 ms | 45.9 ms | 11.3 to 12.7 |
| x4 (120 s) | before | 187 ms | 455 ms | 639 ms | 171 to 233 |
| x4 | after | 171 ms | 347 ms | 479 ms | 126 to 252 |

- At x1 the two are the same. At x4 the machine's own spread (126 to 252 ms for the same build) is larger than any
  difference, so that row says only that nothing got worse by more than the noise. This is a stand-in for a phone, not a
  phone's frame rate ([phone-frames](phone-frames.md)).
- **A fixed pose on a desktop GPU** (`room_lights_tour.tscn --bench`, the median of 150 frames in each of ten poses of
  the second map, summed): seven runs a way, the layers ran 2.4 % slower than the flat scene; a second pass of four
  runs a way, with the boxes alone and the lights alone as extra arms, ran the layers 2.7 % faster than flat and each
  half as fast as the layers. The sign changed with the machine's mood, so there is no cost of the layers to find at
  this size (about 0.05 ms in a frame of 2 ms). The first map's ten poses differed by 0.1 %.
- **Lights per mesh** can only fall: a mesh that a lamp may not light has one light fewer in the 8-a-mesh cap of the
  Compatibility renderer. The cap test (`test_lot_light_cap.gd`) counts every lamp whatever its mask and still passes.

## Checking it

- `tests/world/test_glow_bleed.gd`: no lamp leaks beyond the table; no lamp loses a surface beyond the lost table; a
  lamp that names layers keeps the default one; a synthetic scene (a wall, a floor, an omni) shows that the check sees a
  leak and that a layer cures it.
- `tests/captures/room_lights_tour.tscn --map=lot|small [--flat] [--spot] --out=<folder>`: the same camera positions in
  both maps. `--flat` puts every box back on the default layer and every light on every layer (the "before"), in the same
  build, so two runs differ by the layers alone.
