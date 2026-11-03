"""Build the small-map kit's walls, openings and floors (group 1 of docs/research/maps/small-map-art.md, issue #633).

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_smallmap_walls.py -- [--out game/assets/smallmap] \
        [--fixtures game/world/smallmap/fixtures] [--only a,b] [--blend <file>]

Every piece is our own design in the drive-in props' manner: chamfered boxes, low-sided cylinders and extruded
outlines, one atlas (`smallmap_palette.png`, the drive-in cells plus the small map's five, from `smallmap_kit.py`),
one material, each face on one swatch. Sizes are the page's scale table: wall modules 1, 2 and 3 m wide, 2.8 m tall,
0.3 m thick on the ground floor (Concrete, the `blocks` CSG walls' tint) or 0.2 m above (Plaster); 60 mm chamfers on
wall pieces and frames, 30 mm on smaller parts, none on parts under 0.1 m. Each piece stands on its origin (the
middle of its footprint, on the floor) and its room side faces Blender -Y (Godot +Z).

It writes `<out>/<name>.gltf` + `.bin` for each piece (and `window_board.obj`, which the barricade draws as a plain
Mesh), `<out>/smallmap_walls.json` (triangles, budget and size per piece; a piece over its budget fails the build),
and a fixture scene per piece in `--fixtures`: the model and its collision as hidden CSG boxes (what navigation and
the camera tests read), as `game/world/drive_in/fixtures/`. Openings a player must not pass but the dead (or shots)
may carry their blockers on the boards' layer (`world/drive_in/barricade.gd` BOARD_LAYER).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from palette_import import ensure_import
from smallmap_kit import (
    BEVEL,
    BIG_BEVEL,
    CLEAR,
    DOOR_H,
    DOOR_W,
    MODULE,
    SILL,
    WALL_T,
    WIN_H,
    WIN_W,
    Piece,
    atlas_material,
    palette_image,
    swatch_uv,
)

UPPER_T = 0.2  # upper-floor walls: timber and plaster
LINING = 0.05  # a frame's lining in the reveal: the masonry hole is the clear opening plus two linings
GLAZED_W, GLAZED_H = 1.6, 1.4
BARRED_W, BARRED_H = 2.0, 2.4
WIDE_W, WIDE_MODULE = 2.0, 3.0
ARCH_SPRING = 2.0  # the segmental arch springs here and peaks at DOOR_H: a 0.4 m rise over 1.4 m
ARCH_FACETS = 8
BEAM_W, BEAM_H = 0.36, 0.4
PILLAR = 0.5
TRIM = 0.3
BOARD_L, BOARD_H, BOARD_T = 1.5, 0.19, 0.05
BOARDS = 5
BOARD_LAYER = 2  # world/drive_in/barricade.gd: players collide with it, shots and the navigation do not

SMALL = 1500  # the style bible's budgets: a prop of 1-3 m
LARGE = 5000  # over 3 m


class Kit(Piece):
    """The kit's builder plus outlines: a flat face (an outline with holes, in the X-Z plane) pushed through a wall."""

    def plate(self, outer, holes=(), thick=WALL_T, colour="Concrete", bevel=BIG_BEVEL, y=0.0, reveal=None):
        """Fill `outer` minus `holes` (lists of (x, z)) and extrude it `thick` along Y, centred on `y`.

        Only the outline's edges are chamfered, never the seams inside the face, so one plate reads as one cast
        piece. `reveal` colours the faces inside the holes and along the outline's broken parts: a function of a
        face's centre and normal returning a swatch, or None for the plate's colour.
        """
        tmp = bmesh.new()
        edges = []
        for loop in [outer, *holes]:
            vs = [tmp.verts.new((x, y - thick / 2, z)) for x, z in loop]
            edges += [tmp.edges.new((vs[i], vs[(i + 1) % len(vs)])) for i in range(len(vs))]
        bmesh.ops.triangle_fill(tmp, use_beauty=True, use_dissolve=False, edges=edges, normal=(0, -1, 0))
        faces = list(tmp.faces)
        r = bmesh.ops.extrude_face_region(tmp, geom=faces)
        moved = [g for g in r["geom"] if isinstance(g, bmesh.types.BMVert)]
        bmesh.ops.translate(tmp, vec=(0, thick, 0), verts=moved)
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
        sharp = [e for e in tmp.edges if e.is_manifold and e.calc_face_angle(0.0) > 0.05]
        if bevel > 0.002:
            bmesh.ops.bevel(tmp, geom=sharp, offset=bevel, segments=1, affect="EDGES", profile=0.5, clamp_overlap=True)
        n0 = len(self.bm.faces)
        self._merge(tmp, colour, (0, 0, 0), (0, 0, 0))
        if reveal:
            self.bm.faces.ensure_lookup_table()
            for f in self.bm.faces[n0:]:
                f.normal_update()
                name = reveal(f.calc_center_median(), f.normal)
                if name:
                    u = swatch_uv(name)
                    for loop in f.loops:
                        loop[self.uv].uv = u

    def prism(self, outline, y0, y1, colour, bevel=BEVEL):
        """One convex or concave outline in X-Z, from y0 to y1, chamfered all round."""
        self.plate(outline, (), thick=y1 - y0, colour=colour, bevel=bevel, y=(y0 + y1) / 2)


def rect(x0, x1, z0, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def wall_colour(thick):
    return "Concrete" if thick > 0.25 else "Plaster"


# --- Frames --------------------------------------------------------------------------------------------------------


def lining(p, w, z0, z1, thick, head=True, sill=False):
    """DarkWood linings in a masonry hole whose clear opening is `w` wide from z0 to z1, and a casing round it on both
    faces (proud by 40 mm, 120 mm wide), so the clear opening stays exactly the kit's size."""
    d = thick + 0.02
    for s in (-1, 1):
        p.box(
            (LINING, d, z1 - z0 + (LINING if head else 0)),
            (s * (w + LINING) / 2, 0, (z0 + z1 + (LINING if head else 0)) / 2),
            "DarkWood",
            0.012,
        )
    if head:
        p.box((w + 2 * LINING, d, LINING), (0, 0, z1 + LINING / 2), "DarkWood", 0.012)
    if sill:
        p.box((w, d, LINING), (0, 0, z0 - LINING / 2), "DarkWood", 0.012)
    cw = 0.12
    for face in (-1, 1):
        y = face * (thick / 2 + 0.02)
        top = z1 + LINING + (cw if head else 0)
        bottom = z0 - LINING if sill else z0  # a window's casing stops on its cast sill
        for s in (-1, 1):
            p.box((cw, 0.04, top - bottom), (s * (w / 2 + LINING + cw / 2), y, (top + bottom) / 2), "DarkWood", 0.015)
        if head:
            p.box((w + 2 * LINING + 2 * cw, 0.04, cw), (0, y, z1 + LINING + cw / 2), "DarkWood", 0.015)


# --- The pieces ------------------------------------------------------------------------------------------------------
# Each takes the piece and returns its collision in Godot's frame (x, y up, z = -Blender y): a list of
# (kind, size, centre, layer), kind "box" for a hidden CSG box.


def solid(size, centre):
    return ("box", size, centre, 1)


def player_only(size, centre):
    return ("box", size, centre, BOARD_LAYER)


def body(size, centre):
    """A StaticBody3D on the boards' layer: blocks players only, and the navigation (which reads CSG) never sees it."""
    return ("body", size, centre, BOARD_LAYER)


def door_narrow(thick):
    def build(p):
        """A 2 m wall module with a doorway: clear 1.4 x 2.4 m inside a DarkWood frame, a cast lintel over it."""
        hw = DOOR_W / 2 + LINING
        top = DOOR_H + LINING
        outer = [(-1, 0), (-hw, 0), (-hw, top), (hw, top), (hw, 0), (1, 0), (1, CLEAR), (-1, CLEAR)]
        p.plate(outer, thick=thick, colour=wall_colour(thick))
        lining(p, DOOR_W, 0, DOOR_H, thick)
        jamb = (MODULE - DOOR_W) / 2
        return [
            solid((jamb, CLEAR, thick), (-(DOOR_W + jamb) / 2, CLEAR / 2, 0)),
            solid((jamb, CLEAR, thick), ((DOOR_W + jamb) / 2, CLEAR / 2, 0)),
            solid((DOOR_W, CLEAR - DOOR_H, thick), (0, (CLEAR + DOOR_H) / 2, 0)),
        ]

    return build


def door_purchase(p):
    """The purchase door's leaf, 1.36 x 0.08 x 2.36 m, Yellow: four planks, two ledges and a brace on the room face,
    strap hinges, a pull and a cream plate for the price. Its origin is the middle of its foot."""
    w, h, t = DOOR_W - 0.04, DOOR_H - 0.04, 0.05
    n = 4
    pw = w / n
    for i in range(n):
        p.box((pw - 0.012, t, h - 0.01 * (i % 2)), (-w / 2 + pw * (i + 0.5), 0.015, h / 2), "Yellow", 0.015)
    for z in (0.42, h - 0.42):
        p.box((w - 0.08, 0.03, 0.18), (0, -0.025, z), "Yellow", 0.012)
        p.box((0.5, 0.012, 0.05), (-w / 2 + 0.27, -0.045, z), "Black", 0.0)  # strap hinge
    span = h - 0.84 - 0.18
    ang = math.degrees(math.atan2(span, w - 0.3))
    p.box((math.hypot(span, w - 0.3) - 0.14, 0.03, 0.14), (0, -0.025, h / 2), "Yellow", 0.012, rot=(0, -ang, 0))
    p.box((0.42, 0.02, 0.22), (0, -0.05, 1.55), "Cream", 0.008)
    p.box((0.04, 0.05, 0.22), (w / 2 - 0.14, -0.06, 1.05), "Black", 0.0)
    return [solid((w, h, 0.08), (0, h / 2, 0))]


def opening_wide(p):
    """A 3 m module with a 2.0 x 2.4 m opening between rooms under a cast lintel, proud of both faces."""
    hw, hm = WIDE_W / 2, WIDE_MODULE / 2
    outer = [(-hm, 0), (-hw, 0), (-hw, DOOR_H), (hw, DOOR_H), (hw, 0), (hm, 0), (hm, CLEAR), (-hm, CLEAR)]
    p.plate(outer, thick=WALL_T, colour="Concrete")
    p.box((WIDE_W + 0.6, WALL_T + 0.06, CLEAR - DOOR_H), (0, 0, (CLEAR + DOOR_H) / 2), "Concrete", BIG_BEVEL)
    for s in (-1, 1):  # a plinth block at the foot of each reveal, where carts and boots knocked it
        p.box((0.22, WALL_T + 0.06, 0.3), (s * (hw + 0.11), 0, 0.15), "Concrete", BEVEL)
    jamb = (WIDE_MODULE - WIDE_W) / 2
    return [
        solid((jamb, CLEAR, WALL_T), (-(WIDE_W + jamb) / 2, CLEAR / 2, 0)),
        solid((jamb, CLEAR, WALL_T), ((WIDE_W + jamb) / 2, CLEAR / 2, 0)),
        solid((WIDE_W, CLEAR - DOOR_H, WALL_T), (0, (CLEAR + DOOR_H) / 2, 0)),
    ]


def arch_points():
    """The arch's intrados: ARCH_FACETS straight facets from springing to springing, its crown at DOOR_H."""
    half, rise = DOOR_W / 2, DOOR_H - ARCH_SPRING
    r = (half * half + rise * rise) / (2 * rise)
    cz = DOOR_H - r
    a = math.asin(half / r)
    pts = [(r * math.sin(-a + 2 * a * i / ARCH_FACETS), cz + r * math.cos(-a + 2 * a * i / ARCH_FACETS))
           for i in range(ARCH_FACETS + 1)]  # fmt: skip
    return pts, r, cz


def arch(p):
    """A 2 m module with a segmental arch, 1.4 m wide, springing at 2.0 m and 2.4 m at the crown (8 facets), its
    ring of eight voussoirs proud of both faces."""
    pts, r, cz = arch_points()
    hw = DOOR_W / 2
    outer = [(-1, 0), (-hw, 0), *pts, (hw, 0), (1, 0), (1, CLEAR), (-1, CLEAR)]
    p.plate(outer, thick=WALL_T, colour="Concrete")
    ring = 0.24
    for i in range(ARCH_FACETS):
        a0, a1 = pts[i], pts[i + 1]
        quad = []
        for (x, z), k in ((a0, 0.012), (a1, -0.012)):
            # each stone shrinks a little along the arc, so the joints read
            ang = math.atan2(x, z - cz) + k / r
            quad.append((r * math.sin(ang), cz + r * math.cos(ang)))
        out = [(x * (r + ring) / r, cz + (z - cz) * (r + ring) / r) for x, z in quad]
        p.prism([quad[0], quad[1], out[1], out[0]], -WALL_T / 2 - 0.03, WALL_T / 2 + 0.03, "Concrete", BEVEL)
    for s in (-1, 1):  # impost blocks where the arch springs
        p.box((0.3, WALL_T + 0.06, 0.14), (s * (hw + 0.15), 0, ARCH_SPRING - 0.07), "Concrete", BEVEL)
    jamb = (MODULE - DOOR_W) / 2
    return [
        solid((jamb, CLEAR, WALL_T), (-(DOOR_W + jamb) / 2, CLEAR / 2, 0)),
        solid((jamb, CLEAR, WALL_T), ((DOOR_W + jamb) / 2, CLEAR / 2, 0)),
        solid((DOOR_W, CLEAR - ARCH_SPRING, WALL_T), (0, (CLEAR + ARCH_SPRING) / 2, 0)),
    ]


def board_slots(thick):
    """Where the five boards go on the room face, bottom to top: (x, z, tilt in degrees), in the window's frame."""
    out = []
    for i in range(BOARDS):
        z = SILL + 0.17 + i * (WIN_H - 0.34) / (BOARDS - 1)
        out.append((0.03 * (-1) ** i, z, (-4, 3, -2, 5, -3)[i]))
    return out


def window_zombie(thick):
    def build(p):
        """A 2 m module with the zombie window: clear 1.2 x 1.3 m, the sill at 0.9 m, a DarkWood frame and a cast sill
        proud of both faces. The boards (window_board) sit across its room face; a player-only blocker fills the
        opening so nobody climbs out when they are down."""
        hw = WIN_W / 2 + LINING
        z0, z1 = SILL - LINING, SILL + WIN_H + LINING
        colour = wall_colour(thick)
        p.plate(rect(-1, 1, 0, CLEAR), [rect(-hw, hw, z0, z1)], thick=thick, colour=colour)
        lining(p, WIN_W, SILL, SILL + WIN_H, thick, sill=True)
        p.box((WIN_W + 0.5, thick + 0.14, 0.08), (0, 0, z0 - 0.04), "Concrete", BEVEL)  # the sill, proud
        p.box((WIN_W + 0.5, thick + 0.06, 0.16), (0, 0, z1 + 0.2), "Concrete", BEVEL)  # the lintel, proud
        jamb = (MODULE - WIN_W) / 2
        top = SILL + WIN_H
        return [
            solid((MODULE, SILL, thick), (0, SILL / 2, 0)),
            solid((MODULE, CLEAR - top, thick), (0, (CLEAR + top) / 2, 0)),
            solid((jamb, WIN_H, thick), (-(WIN_W + jamb) / 2, SILL + WIN_H / 2, 0)),
            solid((jamb, WIN_H, thick), ((WIN_W + jamb) / 2, SILL + WIN_H / 2, 0)),
            body((WIN_W, WIN_H, thick), (0, SILL + WIN_H / 2, 0)),
        ]

    return build


def window_board(p):
    """One board for the zombie window, 1.5 x 0.19 x 0.05 m, Wood: one end sawn square, the other split at an angle.
    Centred on its own middle, as the barricade's boards are (it moves them)."""
    p.box((BOARD_L - 0.1, BOARD_T, BOARD_H), (-0.05, 0, 0), "Wood", 0.012)
    p.prism([(BOARD_L / 2 - 0.1, -BOARD_H / 2), (BOARD_L / 2, -BOARD_H / 2 + 0.05), (BOARD_L / 2 - 0.03, BOARD_H / 2),
             (BOARD_L / 2 - 0.1, BOARD_H / 2)], -BOARD_T / 2, BOARD_T / 2, "Wood", 0.01)  # fmt: skip
    for x in (-BOARD_L / 2 + 0.12, BOARD_L / 2 - 0.16):  # nail heads
        p.box((0.025, 0.012, 0.025), (x, -BOARD_T / 2 - 0.004, 0), "DarkGrey", 0.0)
    return [body((BOARD_L, BOARD_H, BOARD_T), (0, 0, 0))]


def window_glazed(thick):
    def build(p):
        """A 2 m module with a glazed window (not an entry): 1.6 x 1.4 m, the sill at 0.9 m, a DarkWood frame with a
        mullion and two transoms, six panes, one of them broken out and one cracked to a shard."""
        hw = GLAZED_W / 2 + LINING
        top = SILL + GLAZED_H
        p.plate(
            rect(-1, 1, 0, CLEAR), [rect(-hw, hw, SILL - LINING, top + LINING)], thick=thick, colour=wall_colour(thick)
        )
        lining(p, GLAZED_W, SILL, top, thick, sill=True)
        p.box((GLAZED_W + 0.4, thick + 0.14, 0.08), (0, 0, SILL - LINING - 0.04), "Concrete", BEVEL)
        bar = 0.07
        p.box((bar, 0.08, GLAZED_H), (0, 0, SILL + GLAZED_H / 2), "DarkWood", 0.015)
        rows = (SILL, SILL + 0.6, SILL + 1.0, top)  # a tall lower pane, two short upper ones
        for z in rows[1:-1]:
            p.box((GLAZED_W, 0.08, bar), (0, 0, z), "DarkWood", 0.015)
        for c, (x0, x1) in enumerate(((-GLAZED_W / 2, -bar / 2), (bar / 2, GLAZED_W / 2))):
            for r in range(3):
                z0, z1 = rows[r] + (bar / 2 if r else 0), rows[r + 1] - (bar / 2 if r < 2 else 0)
                if (c, r) == (1, 0):
                    continue  # broken out
                if (c, r) == (0, 1):  # cracked: a shard left in the bottom corner
                    p.prism([(x0, z0), (x1, z0), (x0 + 0.22, z1 - 0.08), (x0, z1 - 0.18)], -0.01, 0.01, "Glass", 0.0)
                    continue
                p.box((x1 - x0, 0.02, z1 - z0), ((x0 + x1) / 2, 0, (z0 + z1) / 2), "Glass", 0.0)
        return [solid((MODULE, CLEAR, thick), (0, CLEAR / 2, 0))]

    return build


def barred(p):
    """A 2 m module, 2.0 x 2.4 m of bars under a cast lintel (it stands between pillars): round Rust bars every 0.2 m
    in a flat-bar frame, one bar bent. Players and the dead are kept out; shots and the eye go through."""
    hw = BARRED_W / 2
    p.box((BARRED_W, WALL_T, CLEAR - BARRED_H), (0, 0, (CLEAR + BARRED_H) / 2), "Concrete", BIG_BEVEL)
    p.box((BARRED_W, WALL_T, 0.12), (0, 0, 0.06), "Concrete", BEVEL)  # the curb the bars stand in
    for z in (0.14, 0.9, 1.7, BARRED_H - 0.03):
        p.box((BARRED_W - 0.04, 0.05, 0.06), (0, 0, z), "Rust", 0.0)
    for s in (-1, 1):
        p.box((0.06, 0.06, BARRED_H - 0.12), (s * (hw - 0.03), 0, 0.12 + (BARRED_H - 0.12) / 2), "Rust", 0.0)
    n = 9
    for i in range(n):
        x = -hw + 0.2 * (i + 1)
        if i == 6:  # bent out by something that tried
            mid = 1.3
            for z0, z1, lean in ((0.12, mid, 1), (mid, BARRED_H, -1)):
                ln = z1 - z0
                p.cyl(0.022, math.hypot(ln, 0.09), (x, -0.045, (z0 + z1) / 2), "Rust", sides=6,
                      rot=(lean * math.degrees(math.atan2(0.09, ln)), 0, 0))  # fmt: skip
            continue
        p.cyl(0.022, BARRED_H - 0.12, (x, 0, 0.12 + (BARRED_H - 0.12) / 2), "Rust", sides=6)
    return [
        solid((BARRED_W, CLEAR - BARRED_H, WALL_T), (0, (CLEAR + BARRED_H) / 2, 0)),
        player_only((BARRED_W, BARRED_H, 0.12), (0, BARRED_H / 2, 0)),
    ]


# The broken wall's outline: a ragged hole of six big facets and a ragged top that dips in the middle and meets the
# neighbouring modules at full height at both ends.
BROKEN_HOLE = [(-0.62, 1.02), (-0.36, 0.7), (0.18, 0.76), (0.46, 1.18), (0.3, 1.74), (-0.34, 1.8)]
BROKEN_TOP = [(1, CLEAR), (0.78, CLEAR), (0.62, 2.52), (0.3, 2.34), (-0.05, 2.44), (-0.42, 2.22), (-0.7, 2.6),
              (-0.82, CLEAR), (-1, CLEAR)]  # fmt: skip


def broken(thick):
    def build(p):
        """A 2 m module blown through: a ragged hole of six facets (a player cannot climb it, the eye and shots pass)
        and a ragged top; the broken faces show the wall's darker core."""
        outer = [(-1, 0), (1, 0), *BROKEN_TOP]

        def core(c, n):
            if abs(n.y) > 0.5:
                return None  # the wall's faces, chamfers included
            if abs(c.x) > 0.97 or c.z < 0.03:
                return None  # the module's own ends and foot meet its neighbours
            if c.z > CLEAR - 0.03 and abs(n.z) > 0.9:
                return None  # the unbroken top at both ends
            return "Grey2"

        p.plate(outer, [BROKEN_HOLE], thick=thick, colour=wall_colour(thick), reveal=core)
        # Chunks hanging on in the hole's edge and on the top, a bar of reinforcement poking out.
        p.box((0.22, thick * 0.7, 0.16), (-0.5, 0.0, 0.8), "Grey2", BEVEL, rot=(0, 28, 0))
        p.box((0.2, thick * 0.6, 0.14), (0.42, 0.01, 1.62), "Grey2", BEVEL, rot=(0, -35, 0))
        p.cyl(0.012, 0.42, (0.05, 0.0, 1.88), "Rust", sides=4, rot=(0, 72, 0))
        hx0 = min(x for x, _ in BROKEN_HOLE)
        hx1 = max(x for x, _ in BROKEN_HOLE)
        hz0 = min(z for _, z in BROKEN_HOLE)
        hz1 = max(z for _, z in BROKEN_HOLE)
        low = min(z for _, z in BROKEN_TOP)
        return [
            solid((MODULE, hz0, thick), (0, hz0 / 2, 0)),
            solid((hx0 + 1, hz1 - hz0, thick), ((-1 + hx0) / 2, (hz0 + hz1) / 2, 0)),
            solid((1 - hx1, hz1 - hz0, thick), ((1 + hx1) / 2, (hz0 + hz1) / 2, 0)),
            solid((MODULE, low - hz1, thick), (0, (low + hz1) / 2, 0)),
            player_only((hx1 - hx0, hz1 - hz0, thick), ((hx0 + hx1) / 2, (hz0 + hz1) / 2, 0)),
        ]

    return build


def pillar(p):
    """A 0.5 m square pillar, floor to ceiling (2.8 m): a stepped plinth and a stepped cap under the beams' soffit."""
    p.box((0.64, 0.64, 0.1), (0, 0, 0.05), "Concrete", BEVEL)
    p.box((0.58, 0.58, 0.1), (0, 0, 0.15), "Concrete", BEVEL)
    p.box((PILLAR, PILLAR, CLEAR - 0.2), (0, 0, 0.2 + (CLEAR - 0.2) / 2), "Concrete", BIG_BEVEL)
    cap = CLEAR - BEAM_H  # the cap sits under a beam's soffit
    p.box((0.58, 0.58, 0.08), (0, 0, cap - 0.18), "Concrete", BEVEL)
    p.box((0.64, 0.64, 0.1), (0, 0, cap - 0.05), "Concrete", BEVEL)
    return [solid((0.64, 0.2, 0.64), (0, 0.1, 0)), solid((PILLAR, CLEAR, PILLAR), (0, CLEAR / 2, 0))]


def beam(length):
    def build(p):
        """A cast beam, 0.36 x 0.4 m, under the ceiling (its soffit at 2.4 m), with a shallow haunch at each end."""
        p.box((length, BEAM_W, BEAM_H), (0, 0, CLEAR - BEAM_H / 2), "Concrete", BIG_BEVEL)
        for s in (-1, 1):
            x = s * (length / 2 - 0.15)
            p.prism([(x - 0.15 * s, CLEAR - BEAM_H), (x + 0.15 * s, CLEAR - BEAM_H), (x + 0.15 * s, CLEAR - BEAM_H - 0.12)][::s],
                    -BEAM_W / 2 + 0.03, BEAM_W / 2 - 0.03, "Concrete", BEVEL)  # fmt: skip
        return [solid((length, BEAM_H, BEAM_W), (0, CLEAR - BEAM_H / 2, 0))]

    return build


def trim_corner(p):
    """The block corner where two ground-floor walls meet: a 0.3 m core with quoins proud of both faces, long and
    short in turn."""
    p.box((TRIM, TRIM, CLEAR), (0, 0, CLEAR / 2), "Concrete", BIG_BEVEL)
    n = 7
    h = CLEAR / n
    for i in range(n):
        long_x = i % 2 == 0
        size = (TRIM + 0.16 if long_x else TRIM + 0.06, TRIM + 0.06 if long_x else TRIM + 0.16, h - 0.025)
        p.box(size, (0, 0, h * (i + 0.5)), "Concrete", BIG_BEVEL)
    return [solid((TRIM, CLEAR, TRIM), (0, CLEAR / 2, 0))]


def trim_end(p):
    """The end of a free-standing ground-floor wall: a pilaster 0.3 m wide, proud of both faces, with a plinth and a
    cap band."""
    d = WALL_T + 0.06
    p.box((TRIM, d, CLEAR), (0, 0, CLEAR / 2), "Concrete", BIG_BEVEL)
    p.box((TRIM + 0.06, d + 0.06, 0.24), (0, 0, 0.12), "Concrete", BEVEL)
    p.box((TRIM + 0.06, d + 0.06, 0.16), (0, 0, CLEAR - BEAM_H - 0.08), "Concrete", BEVEL)
    return [solid((TRIM, CLEAR, d), (0, CLEAR / 2, 0))]


# The broken floor edge: board rows from the intact side (+Y) to the broken edge (-Y) and how far each survives.
FLOOR_ROWS = 10
FLOOR_BROKEN = {  # row -> the board pieces still there, as (x0, x1); rows not listed are whole
    6: [(-1.0, 0.62)],
    7: [(-1.0, 0.18), (0.38, 1.0)],
    8: [(-1.0, -0.34), (0.55, 1.0)],
    9: [(-1.0, -0.66)],
}
FLOOR_JOISTS = [(-0.8, -0.86), (-0.4, -0.62), (0.0, -1.0), (0.4, -0.7), (0.8, -0.94)]  # (x, where it ends in y)


def floor_edge(p):
    """An upper floor's broken edge, 2 x 2 x 0.2 m: DarkWood joists running out to the hole, some snapped short,
    Wood boards across them ending raggedly, and the plaster ceiling below broken back further. The floor's top is
    the origin's height; the hole faces -Y."""
    for x, y_end in FLOOR_JOISTS:
        length = 1.0 - y_end
        p.box((0.08, length, 0.16), (x, 1.0 - length / 2, -0.11), "DarkWood", BEVEL)
        p.box((0.08, 0.1, 0.12), (x, y_end - 0.03, -0.12), "DarkWood", 0.01, rot=(24, 0, 0))  # the splintered end
    row = 2.0 / FLOOR_ROWS
    for r in range(FLOOR_ROWS):
        y = 1.0 - row * (r + 0.5)
        for x0, x1 in FLOOR_BROKEN.get(r, [(-1.0, 1.0)]):
            p.box((x1 - x0 - 0.006, row - 0.012, 0.03), ((x0 + x1) / 2, y, -0.015), "Wood", 0.008)
    # The plaster ceiling underneath, broken back further than the boards, in two ragged pieces.
    p.box((1.2, 1.1, 0.02), (-0.4, 1.0 - 0.55, -0.2), "Plaster", 0.0)
    p.box((0.8, 1.35, 0.02), (0.6, 1.0 - 0.675, -0.2), "Plaster", 0.0)
    return [solid((2.0, 0.2, row * 6), (0, -0.1, -(1.0 - row * 3)))]


PIECES = {
    # name: (builder, budget)
    "wall_door_narrow": (door_narrow(WALL_T), SMALL),
    "wall_door_narrow_upper": (door_narrow(UPPER_T), SMALL),
    "door_purchase": (door_purchase, SMALL),
    "wall_opening_wide": (opening_wide, SMALL),
    "wall_arch": (arch, SMALL),
    "wall_window_zombie": (window_zombie(WALL_T), SMALL),
    "wall_window_zombie_upper": (window_zombie(UPPER_T), SMALL),
    "window_board": (window_board, SMALL),
    "wall_window_glazed": (window_glazed(WALL_T), SMALL),
    "wall_window_glazed_upper": (window_glazed(UPPER_T), SMALL),
    "wall_barred": (barred, SMALL),
    "wall_broken": (broken(WALL_T), SMALL),
    "wall_broken_upper": (broken(UPPER_T), SMALL),
    "pillar": (pillar, SMALL),
    "beam_2": (beam(2.0), SMALL),
    "beam_4": (beam(4.0), LARGE),
    "beam_6": (beam(6.0), LARGE),
    "trim_corner": (trim_corner, SMALL),
    "trim_end": (trim_end, SMALL),
    "floor_edge_broken": (floor_edge, SMALL),
}

# Drawn as a plain Mesh by the barricade (it pools copies of its boards' meshes), so also written as .obj.
OBJ = {"window_board"}


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def export(o, out, name):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(
        filepath=str(Path(out) / f"{name}.gltf"),
        export_format="GLTF_SEPARATE",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_keep_originals=True,
        export_normals=True,
    )
    if name in OBJ:
        bpy.ops.wm.obj_export(
            filepath=str(Path(out) / f"{name}.obj"),
            export_selected_objects=True,
            export_materials=False,
            forward_axis="NEGATIVE_Z",
            up_axis="Y",
            export_triangulated_mesh=True,
            export_normals=True,
            export_uv=True,
        )


# --- Fixtures --------------------------------------------------------------------------------------------------------


def scene_name(name):
    return "".join(w.capitalize() for w in name.split("_"))


def fmt(v):
    return f"{round(v, 4):g}"


def vec(v):
    return "Vector3({}, {}, {})".format(*[fmt(c) for c in v])


def xform(c):
    return "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {}, {}, {})".format(*[fmt(v) for v in c])


def write_fixture(path, name, shapes, models, extra=()):
    """The model and its collision: hidden CSG boxes (layer 1, or the boards' layer for player-only CSG) and, for a
    blocker the navigation must not see, a StaticBody3D on the boards' layer."""
    bodies = [s for s in shapes if s[0] == "body"]
    out = ["[gd_scene format=3]", ""]
    out.append(f'[ext_resource type="PackedScene" path="{models}/{name}.gltf" id="model"]')
    out.append("")
    for i, (_k, size, _c, _l) in enumerate(bodies, start=1):
        out += [f'[sub_resource type="BoxShape3D" id="shape{i}"]', f"size = {vec(size)}", ""]
    out += [f'[node name="{scene_name(name)}" type="Node3D"]', ""]
    out += ['[node name="Model" parent="." instance=ExtResource("model")]', ""]
    boxes = [s for s in shapes if s[0] == "box"]
    for i, (_k, size, c, layer) in enumerate(boxes, start=1):
        node = "Blocker" if len(boxes) == 1 else f"Blocker{i}"
        out += [f'[node name="{node}" type="CSGBox3D" parent="."]', f"transform = {xform(c)}", "visible = false",
                "use_collision = true"]  # fmt: skip
        if layer != 1:
            out.append(f"collision_layer = {layer}")
        out += [f"size = {vec(size)}", ""]
    for i, (_k, _size, c, layer) in enumerate(bodies, start=1):
        node = "PlayerBlocker" if len(bodies) == 1 else f"PlayerBlocker{i}"
        out += [f'[node name="{node}" type="StaticBody3D" parent="."]', f"transform = {xform(c)}",
                f"collision_layer = {layer}", "collision_mask = 0", ""]  # fmt: skip
        out += [f'[node name="Shape" type="CollisionShape3D" parent="{node}"]', f'shape = SubResource("shape{i}")', ""]
    out += list(extra)
    Path(path).write_text("\n".join(out).rstrip() + "\n", encoding="utf-8", newline="\n")


def board_markers(thick):
    """Marker3Ds where the five boards go, on the room face (Godot +Z), for whoever builds the window's barricade."""
    out = []
    zf = thick / 2 + 0.04 + BOARD_T / 2  # clear of the casing
    for i, (x, z, tilt) in enumerate(board_slots(thick), start=1):
        a = math.radians(tilt)
        c, s = math.cos(a), math.sin(a)
        # A tilt about Godot's +Z (the board lies along X, a little off level).
        t = f"Transform3D({fmt(c)}, {fmt(s)}, 0, {fmt(-s)}, {fmt(c)}, 0, 0, 0, 1, {fmt(x)}, {fmt(z)}, {fmt(zf)})"
        out += [f'[node name="BoardSlot{i}" type="Marker3D" parent="."]', f"transform = {t}", ""]
    return out


def write_board_scene(path, models):
    """The window's board as the barricade wants it (world/drive_in/board.tscn's shape): a StaticBody3D on the
    boards' layer with a Shape and a Mesh child, the mesh a plain ArrayMesh on the kit atlas."""
    out = [
        "[gd_scene format=3]",
        "",
        f'[ext_resource type="ArrayMesh" path="{models}/window_board.obj" id="mesh"]',
        f'[ext_resource type="Texture2D" path="{models}/smallmap_palette.png" id="palette"]',
        "",
        '[sub_resource type="StandardMaterial3D" id="kit"]',
        'albedo_texture = ExtResource("palette")',
        "roughness = 0.415",
        "texture_filter = 0",
        "",
        '[sub_resource type="BoxShape3D" id="shape"]',
        f"size = {vec((BOARD_L, BOARD_H, BOARD_T))}",
        "",
        '[node name="Board" type="StaticBody3D"]',
        f"collision_layer = {BOARD_LAYER}",
        "collision_mask = 0",
        "",
        '[node name="Shape" type="CollisionShape3D" parent="."]',
        'shape = SubResource("shape")',
        "",
        '[node name="Mesh" type="MeshInstance3D" parent="."]',
        'mesh = ExtResource("mesh")',
        'material_override = SubResource("kit")',
    ]
    Path(path).write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")


def models_res(out):
    """`res://` path of the models folder (the game project is the folder holding project.godot)."""
    for parent in [out, *out.parents]:
        if (parent / "project.godot").exists():
            return "res://" + out.relative_to(parent).as_posix()
    return "res://assets/smallmap"


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="game/assets/smallmap")
    ap.add_argument("--fixtures", default="game/world/smallmap/fixtures")
    ap.add_argument("--only", default="")
    ap.add_argument("--blend", default="", help="also save the built pieces in one .blend")
    args = ap.parse_args(argv)
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(args.fixtures).resolve()
    fixtures.mkdir(parents=True, exist_ok=True)
    res = models_res(out)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    palette = out / "smallmap_palette.png"
    img = palette_image(palette)
    ensure_import(palette)  # lossless, no mipmaps, Detect 3D off (tools/check_texture_imports.py)
    mat = atlas_material(img, "SmallMap")
    only = set(filter(None, args.only.split(",")))
    report_path = out / "smallmap_walls.json"
    report = json.loads(report_path.read_text(encoding="utf-8")) if only and report_path.exists() else {}
    for name, (fn, budget) in PIECES.items():
        if only and name not in only:
            continue
        p = Kit(name)
        shapes = fn(p)
        o = p.obj(mat)
        n = tris(o)
        xs = [v.co for v in o.data.vertices]
        size = [round(max(c[k] for c in xs) - min(c[k] for c in xs), 3) for k in range(3)]
        info = {"tris": n, "budget": budget, "size_xyz_blender": size}
        print("PIECE", name, json.dumps(info))
        if n > budget:
            raise SystemExit(f"{name}: {n} tris over its budget {budget}")
        export(o, out, name)
        report[name] = info
        if name == "window_board":
            write_board_scene(fixtures / f"{name}.tscn", res)
        else:
            thick = UPPER_T if name.endswith("_upper") else WALL_T
            extra = board_markers(thick) if name.startswith("wall_window_zombie") else ()
            write_fixture(fixtures / f"{name}.tscn", name, shapes, res, extra)
        if not args.blend:
            bpy.data.objects.remove(o, do_unlink=True)
    report_path.write_text(json.dumps(report, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=str(Path(args.blend).resolve()))


main()
