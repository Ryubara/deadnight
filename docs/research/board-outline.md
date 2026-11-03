# The outline of a missing board

Issue #902. A player must see that an entry needs mending, on every window and breach alike. Before, only six of the
second map's windows read as "a boarded window" when torn, by accident: their moon shaft (`MoonShaft`) drew a faint card
in the opening striped by five rails, which looked like the boards. The other six entries and the drive-in's six fence
breaches showed nothing.

## What it is

`BoardOutline` (`game/world/drive_in/board_outline.gd`, shader `board_outline.gdshader`) is made by `Barricade._ready`
from its own boards: the front face of each board's mesh, in the barricade's space, a hair (6 mm) in front. It draws one
quad for each board that is **not up**, so with `up` planks on it is the top `5 - up` slots; planks go back bottom to
top (the rules' count adds one a repair, the lowest `count` slots are up). Nothing is drawn at full boards. The moon
shafts are lighting again, unchanged.

| Choice | Why |
| --- | --- |
| A frame (4 cm), a faint fill and a nail at each end, additive and unshaded, in the moon's colour `#9db4e8`, energy 0.3 | the night's own family (`glow.gdshader`, the moon cards): a cool ghost of a plank that does not read as a real light |
| UV 0..1 across the face and **UV2 = the face's size in metres** | one shader for 1.5 m window boards and 4.1 m fence boards, with the same stroke width |
| One `ArrayMesh` a barricade, rebuilt from at most five quads when the count changes; one shared `ShaderMaterial` | a torn barricade is one draw call, a whole one none; no `_process`, no per-instance parameters (instance uniforms are not relied on in Compatibility) |
| Constant energy (not the moon's `NightLight` dimming) | it is a prompt: it stays readable as the rounds darken the night |
| Built at runtime from the boards, not written into the scenes | no generated scene changes: the builders (`build_greybox.py`, `build_smallmap_greybox.py`) need no edit, the walking meshes no re-bake |

## Cost

`tests/captures/board_outline.tscn`, the shoulder camera (60 degrees, where a player mending the entry stands, 3 m
inside), 1600 x 900, RTX 5080; "without" hides the outlines (what the game drew before). Draw calls and primitives are
the frame's `RenderingServer` counts.

| View | Draw calls without / with | Primitives without / with | Outline quads | Screen the quads cover |
| --- | --- | --- | --- | --- |
| Second map, start_1 (had the moon look), 0 boards | 51 / 52 | 16,640 / 16,650 | 5 | 2.4 % |
| Second map, start_2 (had nothing), 0 boards | 35 / 36 | 13,226 / 13,236 | 5 | 2.4 % |
| Second map, all 12 entries, 0 boards | +1 each | +10 each | 5 | 2.1 to 3.4 % |
| Drive-in breach `e`, 0 boards | 21 / 22 | 9,593 / 9,603 | 5 | 14.4 % (4.1 m boards at 3 m) |

At most one more draw call and ten triangles for the barricade in view; the others out of the frustum draw nothing, and
a mended one draws nothing. The share is the quads' projected area (the fill shades every pixel of it, additive: one
layer, under the depth test, so a plank behind a wall costs nothing). The second map's moon shafts and pools cover more.

Phone page (`tools/web_smoke/board_outline_web.py`: 844 x 390 at a pixel ratio of 3, touch, the mobile agent, Chrome
on the GPU, WebGL2): both maps load and draw the outline with no console error; the page links 116 programs on the
second map and 94 on the drive-in, the same with the outlines drawn and hidden (the material is made at load, so the
new program is in both counts); the share on screen is 2.0 % and 11.8 %.

Not measured: a real phone, and SwiftShader (fill cost).
