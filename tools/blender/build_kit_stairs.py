"""Build the small-map kit's stairs, rails and debris blocker (group 2, parts 19-23; issue #634).

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_kit_stairs.py -- [--out game/assets/smallmap] \
        [--fixtures game/world/smallmap/fixtures] [--sheet <scratch folder>] [--only a,b]

It writes, for each piece, `<out>/<name>.gltf` + `.bin` on the kit atlas (`<out>/smallmap_palette.png`, the drive-in
cells plus five; `smallmap_kit.py`), `<out>/stairs_kit.json` (triangles, budget, size), and the piece's fixture scene
`<fixtures>/<name>.tscn`: the model and its collision as hidden CSG boxes, computed here from the same numbers as the
mesh. With `--sheet` it also renders the pieces on the 0.5 m grid beside the Soldier and three drive-in props
(`stairs_sheet.png`) and each piece on its own (`piece_<name>.png`) into that folder.

Every number comes from docs/research/maps/small-map-art.md (Scale; Grid and conventions): 0.2 m risers, 0.3 m
treads (33.7 degrees), 1.4 m wide flights, a 3.0 m storey, a 1.0 m rail. Each piece stands on its origin, the middle
of its footprint on the floor, its room side (a stair's foot) facing Blender -Y (Godot +Z).

**Stairs walk on a hidden ramp.** The flight's collision is one box whose top runs through the middle of every tread
(height R/2 + u R/T at u metres from the first riser), from half a tread in front of the first riser up to the top
level half a tread past the last riser, then a flat strip to the top edge. The treads are only drawn. Fifteen
step-ups of 0.2 m would each lift the view (`PlayerTuning.step_height` is 0.3 m), and a ramp of 33.7 degrees is under
the body's 45 degree floor limit (tests/world/test_smallmap_stairs.gd walks them).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from palette_import import ensure_import
from smallmap_kit import BEVEL, BIG_BEVEL, RISE, STAIR_W, STOREY, TREAD, Piece, atlas_material, palette_image

SLOPE = RISE / TREAD  # 2/3: 33.7 degrees
ANGLE = math.degrees(math.atan(SLOPE))
RAIL_H = 1.0  # rail top over the nosing line (stairs) or the floor (flat)
PIPE_R = 0.028  # the pipe rail: thin against the heavy stair, as the reference's
TREAD_T = 0.07  # tread thickness
NOSING = 0.03  # how far a tread overhangs its riser
STRINGER_T = 0.08
STRINGER_D = 0.26  # stringer depth, square to its slope
STRINGER_UP = 0.06  # how far the stringer's top runs above the nosing line
HEADER_H = 0.2  # the slab the flight arrives at (a storey's 0.2 m floor)
LANDING = 1.4  # the L stair's landing, square
LANDING_RISERS = 8  # 1.6 m: the landing's height
X_IN = STAIR_W / 2 - STRINGER_T / 2  # a stringer's (and a rail's) centre line, from the flight's middle

# Godot's collision layers: the boards' layer is solid for players only (world/drive_in/barricade.gd BOARD_LAYER), so
# a thin rail stops a player but never a shot or the shoulder camera, as the speaker posts on the lot.
BOARD_LAYER = 2


# --- Building blocks --------------------------------------------------------------------------------------------------


def merge(dst, src, matrix=None):
    """Add `src`'s faces (their UVs kept) to `dst`, moved by `matrix`."""
    if matrix is not None:
        bmesh.ops.transform(src.bm, matrix=matrix, verts=src.bm.verts)
    me = bpy.data.meshes.new("tmp")
    src.bm.to_mesh(me)
    src.bm.free()
    dst.bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def prism(p, profile, x0, x1, colour, bevel=BEVEL):
    """A plank whose side is the convex polygon `profile` [(y, z), ...], from x0 to x1 (a stringer)."""
    tmp = bmesh.new()
    a = [tmp.verts.new((x0, y, z)) for y, z in profile]
    b = [tmp.verts.new((x1, y, z)) for y, z in profile]
    tmp.faces.new(a)
    tmp.faces.new(list(reversed(b)))
    n = len(profile)
    for i in range(n):
        j = (i + 1) % n
        tmp.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    b_off = min(bevel, abs(x1 - x0) * 0.3)
    if b_off > 0.002:
        bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=b_off, segments=1, affect="EDGES", profile=0.5)
    p._merge(tmp, colour, (0, 0, 0), (0, 0, 0))


def pipe(p, a, b, r, colour, sides=6):
    """A round bar from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, cap_tris=False, segments=sides, radius1=r, radius2=r, depth=d.length)
    m = Matrix.Translation((a + b) / 2) @ Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
    p._merge(tmp, colour, (0, 0, 0), (0, 0, 0))


def nosing(u):
    """The nosing line of a flight: the height of the tread edges, u metres from the first riser."""
    return RISE + u * SLOPE


# --- A flight, in its own frame: the foot's middle at the origin, climbing +Y, its left side towards -X -------------


def stringer_profile(rises, base):
    """The side of a stringer: plumb at the foot and at the top, its top STRINGER_UP over the nosings."""
    top_h = rises * RISE
    end = (rises - 1) * TREAD

    def top(u):
        return nosing(u) + STRINGER_UP

    drop = STRINGER_D / math.cos(math.radians(ANGLE))

    def bottom(u):
        return top(u) - drop

    pts = []
    if bottom(0) < base:
        pts += [(0.0, base)]
        pts += [(0.0, top(0))]
    else:
        pts += [(0.0, bottom(0)), (0.0, top(0))]
    clip = (top_h - RISE - STRINGER_UP) / SLOPE  # where the top line reaches the top level
    pts += [(clip, top_h), (end, top_h), (end, bottom(end))]
    if bottom(0) < base:
        pts += [((base - bottom(0)) / SLOPE, base)]
    return pts


def flight(p, rises, base=0.0, header=True):
    """Treads, risers, two stringers and (with `header`) the slab edge the last riser climbs to.

    `rises` risers of RISE climb to rises * RISE; the treads are rises - 1, the last riser is the header's (or the
    landing's) face. A small yaw on each tread keeps the flight hand-made without moving where a foot lands.
    """
    width = STAIR_W - 2 * STRINGER_T + 0.06  # housed 30 mm into each stringer
    for i in range(rises - 1):
        z = (i + 1) * RISE
        y = i * TREAD + TREAD / 2 - NOSING / 2
        yaw = (0.8, -0.6, 1.1, -0.9, 0.5, -1.2, 0.7)[i % 7]
        p.box((width, TREAD + NOSING, TREAD_T), (0, y, z - TREAD_T / 2), "Wood", BEVEL, rot=(0, 0, yaw))
        h = RISE - TREAD_T
        p.box((width - 0.06, 0.03, h), (0, i * TREAD + 0.015, i * RISE + h / 2), "DarkWood", 0.0)
    prof = stringer_profile(rises, base)
    for s in (-1, 1):
        prism(p, prof, s * X_IN - STRINGER_T / 2, s * X_IN + STRINGER_T / 2, "DarkWood")
    if header:
        top_h = rises * RISE
        p.box(
            (STAIR_W, TREAD, HEADER_H),
            (0, (rises - 1) * TREAD + TREAD / 2, top_h - HEADER_H / 2),
            "DarkWood",
            BIG_BEVEL,
        )


def rail_run(p, x, posts, u0, u1, height):
    """A pipe rail along a flight's side at `x`: posts at `posts` (u), a top rail and a mid rail from u0 to u1.

    `height(u)` is the line the rail follows (a flight's nosing line, or a floor); the posts stand on the stringer
    (or the floor) and carry the top rail RAIL_H over it.
    """
    for u in posts:
        foot = height(u) + (STRINGER_UP if height is nosing else 0.0)
        pipe(p, (x, u, foot), (x, u, height(u) + RAIL_H + 0.02), PIPE_R, "Grey")
        p.box((0.07, 0.07, 0.04), (x, u, foot + 0.02), "Rust", 0.0)  # the post's shoe
        p.box((0.075, 0.075, 0.05), (x, u, height(u) + RAIL_H - 0.005), "Rust", 0.0)  # the elbow at the top rail
    for frac in (1.0, 0.5):
        pipe(p, (x, u0, height(u0) + RAIL_H * frac), (x, u1, height(u1) + RAIL_H * frac), PIPE_R, "Grey")


def flight_rail(p, rises, x, newel_end=False):
    """The rail on a flight's side `x`: three posts (two when a newel post takes the top end)."""
    end = (rises - 1) * TREAD
    posts = [0.15, end / 2] + ([] if newel_end else [end - 0.15])
    rail_run(p, x, posts, 0.05, end if newel_end else end - 0.05, nosing)


# --- Collision, in Godot's frame ------------------------------------------------------------------------------------


def godot(v):
    """Blender (x, y, z) to Godot (x, z, -y)."""
    return Vector((v[0], v[2], -v[1]))


def slab(name, p0, p1, width, thick, layer=1, up_side=True):
    """A box whose top (or, with up_side False, bottom) face runs along the line p0 -> p1 (Blender points)."""
    g0, g1 = godot(p0), godot(p1)
    along = (g1 - g0).normalized()
    up = Vector((0, 1, 0))
    y = (up - along * up.dot(along)).normalized()
    x = y.cross(along)
    centre = (g0 + g1) / 2 + y * (-thick / 2 if up_side else thick / 2)
    return {
        "name": name,
        "size": (width, thick, (g1 - g0).length),
        "centre": tuple(centre),
        "basis": (tuple(x), tuple(y), tuple(along)),
        "layer": layer,
    }


def block(name, lo, hi, layer=1):
    """An upright box from corner lo to corner hi (Blender points)."""
    a, b = godot(lo), godot(hi)
    size = tuple(abs(b[k] - a[k]) for k in range(3))
    return {"name": name, "size": size, "centre": tuple((a + b) / 2), "basis": None, "layer": layer}


def flight_ramp(name, x0, x1, foot_y, rises, base_z=0.0):
    """The ramp of a straight flight climbing +Y: its top through the treads' middles (see the module's note)."""
    top_h = rises * RISE
    u0 = -TREAD / 2  # height 0 half a tread in front of the first riser
    u1 = (top_h - RISE / 2) / SLOPE  # the top level half a tread past the last riser
    p0 = Vector(((x0 + x1) / 2, foot_y + u0, base_z))
    p1 = Vector(((x0 + x1) / 2, foot_y + u1, base_z + top_h))
    return slab(name, p0, p1, abs(x1 - x0), 0.2), u1


def rail_blocker(name, x, foot_y, u0, u1, base_z=0.0):
    """A player-only blocker under a flight's rail: from the ramp up RAIL_H, 0.1 m thick."""
    ramp = lambda u: base_z + RISE / 2 + u * SLOPE
    p0 = Vector((x, foot_y + u0, ramp(u0)))
    p1 = Vector((x, foot_y + u1, ramp(u1)))
    thick = RAIL_H * math.cos(math.radians(ANGLE))
    return slab(name, p0, p1, 0.1, thick, BOARD_LAYER, up_side=False)


# --- The pieces -----------------------------------------------------------------------------------------------------

STRAIGHT_RUN = 15 * TREAD  # 4.5 m: fourteen treads and the header


def stair_straight(objs):
    """A straight timber flight for one storey: 15 risers of 0.2 m, 0.3 m treads, 1.4 m wide, the foot at -Y.

    A rail on each side as its own node (RailLeft at -X, RailRight at +X); the fixture shows the open side's only.
    """
    foot = -STRAIGHT_RUN / 2
    p = Piece("Flight")
    f = Piece("tmp")
    flight(f, 15)
    merge(p, f, Matrix.Translation((0, foot, 0)))
    objs.append(p)
    for side, name in ((-1, "RailLeft"), (1, "RailRight")):
        r = Piece(name)
        f = Piece("tmp")
        flight_rail(f, 15, side * X_IN)
        merge(r, f, Matrix.Translation((0, foot, 0)))
        objs.append(r)
    ramp, u1 = flight_ramp("Ramp", -STAIR_W / 2, STAIR_W / 2, foot, 15)
    end = 14 * TREAD
    return [
        ramp,
        block("Top", (-STAIR_W / 2, foot + u1, STOREY - HEADER_H), (STAIR_W / 2, -foot, STOREY)),
        rail_blocker("RailLeftBlocker", -X_IN, foot, 0.0, end),
        rail_blocker("RailRightBlocker", X_IN, foot, 0.0, end),
    ]


L_SIDE = (14 - (LANDING_RISERS - 1)) * TREAD  # 2.1: the upper flight's six treads and its header
L_SPAN = (LANDING_RISERS - 1) * TREAD + LANDING  # 3.5: the lower flight's seven treads and the landing


def stair_l(objs, hand="left"):
    """An L stair for one storey: eight risers to a 1.4 m landing at 1.6 m, a quarter turn, seven risers to 3.0 m.

    Built turning left (the upper flight runs towards -X) in a frame whose lower flight's foot is at x = 0, then
    centred on its footprint; `hand="right"` is its mirror. The rail runs on the inside of the turn, round a newel
    post at the landing's inner corner; the outside is meant to stand against two walls.
    """
    lo_rises = LANDING_RISERS
    hi_rises = 15 - LANDING_RISERS
    land_y = (lo_rises - 1) * TREAD  # 2.1: the landing's front edge
    land_z = lo_rises * RISE  # 1.6
    half = STAIR_W / 2
    p = Piece("Flight")
    f = Piece("tmp")
    flight(f, lo_rises, header=False)
    merge(p, f)
    # The landing: a timber frame, boards on top, four legs, the newel post at the inner corner.
    p.box((LANDING, LANDING, 0.17), (0, land_y + LANDING / 2, land_z - 0.03 - 0.085), "DarkWood", BIG_BEVEL)
    for i in range(6):
        w = LANDING / 6
        p.box((LANDING - 0.02, w - 0.012, 0.03), (0, land_y + w * (i + 0.5), land_z - 0.015), "Wood", 0.0)
    for x, y in ((half, land_y), (half, land_y + LANDING), (-half, land_y + LANDING)):
        sx, sy = -math.copysign(0.07, x), -math.copysign(0.07, y - land_y - LANDING / 2)
        p.box((0.12, 0.12, land_z - 0.2), (x + sx, y + sy, (land_z - 0.2) / 2), "DarkWood", BEVEL)
    newel = (-X_IN, land_y + STRINGER_T / 2)
    newel_h = land_z + RAIL_H + 0.1
    p.box((0.14, 0.14, newel_h), (*newel, newel_h / 2), "DarkWood", BEVEL)
    p.box((0.2, 0.2, 0.06), (*newel, newel_h + 0.03), "DarkWood", BEVEL)
    # The upper flight, from the landing's west edge towards -X, its foot in the middle of the landing's side.
    hi_foot = Matrix.Translation((-half, land_y + LANDING / 2, land_z)) @ Matrix.Rotation(math.radians(90), 4, "Z")
    f = Piece("tmp")
    flight(f, hi_rises, base=-0.2)
    merge(p, f, hi_foot)
    objs.append(p)
    # The rail: up the lower flight's left side to the newel, then up the upper flight's left side from it.
    r = Piece("Rail")
    f = Piece("tmp")
    flight_rail(f, lo_rises, -X_IN, newel_end=True)
    merge(r, f)
    f = Piece("tmp")
    end = (hi_rises - 1) * TREAD
    rail_run(f, -X_IN, [end / 2, end - 0.15], STRINGER_T, end - 0.05, nosing)
    merge(r, f, hi_foot)
    objs.append(r)
    shapes = []
    ramp1, u1 = flight_ramp("Ramp", -half, half, 0.0, lo_rises)
    shapes.append(ramp1)
    shapes.append(block("Landing", (-half, u1, land_z - 0.2), (half, land_y + LANDING, land_z)))
    # The upper ramp, in the flight's own frame and turned with it; it starts where the landing's box does (u1 - land_y
    # past the landing's front), so cutting the corner never meets a ledge between the two.
    _, v1 = flight_ramp("Ramp2", 0, 0, 0.0, hi_rises)
    hi_x = -half - v1
    shapes.append(
        slab(
            "Ramp2",
            Vector((-half + TREAD / 2, (u1 + land_y + LANDING) / 2, land_z)),
            Vector((hi_x, (u1 + land_y + LANDING) / 2, STOREY)),
            land_y + LANDING - u1,
            0.2,
        )
    )
    top_x = -half - L_SIDE
    shapes.append(block("Top", (top_x, land_y, STOREY - HEADER_H), (hi_x, land_y + LANDING, STOREY)))
    shapes.append(rail_blocker("RailBlocker", -X_IN, 0.0, 0.0, land_y))
    hi_end = (hi_rises - 1) * TREAD
    shapes.append(
        slab(
            "RailBlocker2",
            Vector((-half, land_y + STRINGER_T / 2, land_z + RISE / 2)),
            Vector((-half - hi_end, land_y + STRINGER_T / 2, land_z + RISE / 2 + hi_end * SLOPE)),
            0.1,
            RAIL_H * math.cos(math.radians(ANGLE)),
            BOARD_LAYER,
            up_side=False,
        )
    )
    shapes.append(
        block("Newel", (newel[0] - 0.07, newel[1] - 0.07, 0), (newel[0] + 0.07, newel[1] + 0.07, newel_h), BOARD_LAYER)
    )
    # Centre the footprint (x from -half - L_SIDE to half, y from 0 to L_SPAN) on the origin, and mirror for the right.
    shift = Vector((-(half + (-half - L_SIDE)) / 2, -L_SPAN / 2, 0))
    mirror = -1 if hand == "right" else 1
    m = Matrix.Diagonal((mirror, 1, 1, 1)) @ Matrix.Translation(shift)
    for o in objs:
        bmesh.ops.transform(o.bm, matrix=m, verts=o.bm.verts)
    return [move_shape(s, m) for s in shapes]


def move_shape(s, m):
    """A collision shape moved by `m` (a Blender-frame translation, maybe mirrored in x)."""
    g = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))  # Blender to Godot
    gm = g @ m.to_3x3() @ g.inverted()
    t = g @ m.to_translation()
    centre = gm @ Vector(s["centre"]) + t
    out = dict(s, centre=tuple(centre))
    if s["basis"] is not None:
        cols = [gm @ Vector(c) for c in s["basis"]]
        if gm.determinant() < 0:  # a mirror: keep the box's frame right-handed by flipping its x axis
            cols[0] = -cols[0]
        out["basis"] = tuple(tuple(c) for c in cols)
    return out


def rail_flat(objs):
    """A 2 m pipe rail on the floor, 1.0 m tall, along X: posts at +-0.5 m, so joined runs keep a post every metre."""
    r = Piece("Rail")
    f = Piece("tmp")
    rail_run(f, 0.0, [-0.5, 0.5], -1.0, 1.0, lambda u: 0.0)
    merge(r, f, Matrix.Rotation(math.radians(-90), 4, "Z"))  # the run along +Y turned to +X
    objs.append(r)
    return [block("Blocker", (-1.0, -0.05, 0), (1.0, 0.05, RAIL_H), BOARD_LAYER)]


def rail_sloped(objs):
    """A 2 m (plan) pipe rail at the stairs' slope, rising towards +X; its origin on the nosing line at its middle."""
    r = Piece("Rail")
    f = Piece("tmp")
    rail_run(f, 0.0, [-0.5, 0.5], -1.0, 1.0, lambda u: u * SLOPE)
    merge(r, f, Matrix.Rotation(math.radians(-90), 4, "Z"))
    objs.append(r)
    lo, hi = Vector((-1.0, 0, -SLOPE)), Vector((1.0, 0, SLOPE))
    return [slab("Blocker", lo, hi, 0.1, RAIL_H * math.cos(math.radians(ANGLE)), BOARD_LAYER, up_side=False)]


def landing_edge(objs):
    """The edge of an upper floor or a balcony, 2 x 0.3 m: a timber edge beam flush with the floor, a rail on it.

    The origin is on the floor's top at the middle of the edge's footprint; the floor (the room side) is at -Y, the
    drop at +Y. The beam fills the floor's 0.2 m slab; a fascia board covers its face.
    """
    p = Piece("Edge")
    p.box((2.0, 0.3, HEADER_H), (0, 0, -HEADER_H / 2), "DarkWood", BIG_BEVEL)
    for i in range(2):  # two boards on top, so it reads as the floor's end
        p.box((1.98, 0.14, 0.02), (0, -0.075 + i * 0.15, -0.01), "Wood", 0.0)
    p.box((2.0, 0.03, HEADER_H + 0.06), (0, 0.165, -HEADER_H / 2 - 0.03), "DarkWood", 0.0)  # the fascia
    objs.append(p)
    r = Piece("Rail")
    f = Piece("tmp")
    rail_run(f, 0.0, [-0.5, 0.5], -1.0, 1.0, lambda u: 0.0)
    merge(r, f, Matrix.Translation((0, 0.06, 0)) @ Matrix.Rotation(math.radians(-90), 4, "Z"))
    objs.append(r)
    return [
        block("Floor", (-1.0, -0.15, -HEADER_H), (1.0, 0.15, 0)),
        block("Blocker", (-1.0, 0.01, 0), (1.0, 0.11, RAIL_H), BOARD_LAYER),
    ]


DEBRIS_W, DEBRIS_H, DEBRIS_D = 1.4, 2.4, 1.0


def chunk(p, rng, at, size, colour):
    rot = (rng() * 30 - 15, rng() * 30 - 15, rng() * 90)
    p.box(size, at, colour, BEVEL, rot=rot)


def debris_blocker(objs):
    """Rubble and furniture filling a 1.4 x 2.4 m opening, 1.0 m deep: a purchase the game clears piece by piece.

    Six parts, one node each, named in the order they come away (Part1 first, the rubble last); each node's origin is
    its own middle, so the game can lift or throw it. The wall's plane is y = 0 (a 0.3 m wall, the room at -Y); what
    stands in the opening keeps inside its 1.4 m, what leans on the room side may lap the wall's face. The gaps at the
    top let the far room's light through (small-map-art.md, Lighting).
    """
    seed = [7]

    def rng():
        seed[0] = (seed[0] * 1103515245 + 12345) % 2**31
        return seed[0] / 2**31

    parts = []
    # 1. Two planks nailed across the top of the opening, on the room face, crossing.
    p = Piece("Part1_Planks")
    p.box((1.75, 0.045, 0.2), (0, -0.2, 2.05), "Wood", BEVEL, rot=(0, 14, 0))
    p.box((1.7, 0.045, 0.18), (0.02, -0.25, 1.8), "Wood", BEVEL, rot=(0, -11, 0))
    p.box((1.6, 0.045, 0.17), (-0.03, -0.2, 2.32), "DarkWood", BEVEL, rot=(0, 4, 0))
    parts.append(p)
    # 2. A chair, upside down on the table's edge, tipped back against the planks.
    p = Piece("Part2_Chair")
    c = Piece("tmp")
    c.box((0.45, 0.45, 0.05), (0, 0, 0.45), "Wood", BEVEL)
    for x in (-0.19, 0.19):
        for y in (-0.19, 0.19):
            c.box((0.045, 0.045, 0.45), (x, y, 0.225), "DarkWood", 0.0)
    for x in (-0.19, 0.19):
        c.box((0.045, 0.045, 0.45), (x, 0.19, 0.7), "DarkWood", 0.0)
    c.box((0.42, 0.04, 0.16), (0, 0.19, 0.84), "Wood", 0.012)
    merge(
        p,
        c,
        Matrix.Translation((-0.2, -0.3, 1.0))
        @ Matrix.Rotation(math.radians(160), 4, "X")
        @ Matrix.Rotation(math.radians(25), 4, "Z")
        @ Matrix.Translation((0, 0, -0.9)),
    )
    parts.append(p)
    # 3. A table tipped on its side: its top faces the room, its legs point into the opening.
    p = Piece("Part3_Table")
    t = Piece("tmp")
    t.box((1.3, 0.75, 0.05), (0, 0, 0.75), "Wood", BEVEL)
    t.box((1.16, 0.6, 0.1), (0, 0, 0.67), "DarkWood", BEVEL)
    for x in (-0.58, 0.58):
        for y in (-0.3, 0.3):
            t.box((0.065, 0.065, 0.68), (x, y, 0.34), "DarkWood", 0.0)
    merge(
        p,
        t,
        Matrix.Translation((0.05, -0.3, 0.62))
        @ Matrix.Rotation(math.radians(-4), 4, "Y")
        @ Matrix.Rotation(math.radians(90), 4, "X")
        @ Matrix.Translation((0, 0, -0.75)),
    )
    parts.append(p)
    # 4. A ceiling beam come down across the opening, corner to corner, charred at one end.
    p = Piece("Part4_Beam")
    p.box((0.16, 0.18, 2.0), (0.02, 0.08, 1.25), "DarkWood", BEVEL, rot=(0, 36, 0))
    p.box((0.17, 0.19, 0.35), (0.505, 0.08, 1.917), "Soot", BEVEL, rot=(0, 36, 0))
    parts.append(p)
    # 5. A chest of drawers on its back behind the table, wedged at an angle.
    p = Piece("Part5_Dresser")
    d = Piece("tmp")
    d.box((0.9, 0.45, 1.1), (0, 0, 0.55), "DarkWood", BEVEL)
    for i in range(3):
        d.box((0.78, 0.03, 0.28), (0, -0.235, 0.22 + i * 0.34), "Wood", 0.0)
    merge(
        p,
        d,
        Matrix.Translation((0.15, 0.25, 0.45))
        @ Matrix.Rotation(math.radians(-28), 4, "Y")
        @ Matrix.Rotation(math.radians(-12), 4, "X"),
    )
    parts.append(p)
    # 6. The rubble the rest stands on: broken block and brick, highest in the opening, spilling out on both sides.
    p = Piece("Part6_Rubble")
    for i in range(16):
        rr = 0.24 + 0.3 * rng()
        x = -0.58 + 1.16 * ((i * 0.618) % 1.0)  # spread across the opening, never in a row
        y = -0.42 + 0.84 * rng()
        z = rr * 0.25 + 0.22 * (1 - abs(y) / 0.5) * rng()  # highest in the wall's plane
        colour = ("Concrete", "Grey2", "Concrete", "Red", "Soot", "Concrete", "Red")[i % 7]
        size = (rr, rr * (0.6 + 0.4 * rng()), rr * 0.55)
        chunk(p, rng, (x, y, z), size, colour)
    parts.append(p)
    objs += parts
    return [block("Blocker", (-DEBRIS_W / 2, -DEBRIS_D / 2, 0), (DEBRIS_W / 2, DEBRIS_D / 2, DEBRIS_H))]


# name -> (builder, budget, the scene's script or None). Budgets are the style bible's: a stair is a large piece (5k),
# a rail, an edge and the blocker (six props of 0.5-1.7 m in one) are props of 1-3 m (1.5k).
PIECES = {
    "stair_straight": (stair_straight, 5000, "res://world/smallmap/kit_stair.gd"),
    "stair_l_left": (lambda objs: stair_l(objs, "left"), 5000, None),
    "stair_l_right": (lambda objs: stair_l(objs, "right"), 5000, None),
    "rail_flat": (rail_flat, 1500, None),
    "rail_sloped": (rail_sloped, 1500, None),
    "landing_edge": (landing_edge, 1500, None),
    "debris_blocker": (debris_blocker, 1500, None),
}


# --- Output -----------------------------------------------------------------------------------------------------------


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def to_object(piece, mat):
    o = piece.obj(mat)
    if piece.name.startswith("Part"):
        # A debris part's node has its origin at its own middle on its bottom, so the game can move it on its own.
        me = o.data
        pts = [v.co.copy() for v in me.vertices]
        mid = [(min(c[k] for c in pts) + max(c[k] for c in pts)) / 2 for k in range(2)]
        mid = Vector((*mid, min(c[2] for c in pts)))
        me.transform(Matrix.Translation(-mid))
        o.location = mid
    return o


def export(objs, out, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
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


def scene_name(name):
    return "".join(w.capitalize() for w in name.split("_"))


def fmt(v):
    return f"{v:.4f}".rstrip("0").rstrip(".") if abs(v) > 5e-5 else "0"


def write_fixture(path, name, shapes, script):
    """The fixture scene: the model, and each collision shape as a hidden CSG box (what the navigation, the camera
    probes and the player read; drive_in/fixtures as written by tools/world/drivein_props.py)."""
    out = ["[gd_scene format=3]", ""]
    if script:
        out += [f'[ext_resource type="Script" path="{script}" id="script"]']
    out += [f'[ext_resource type="PackedScene" path="res://assets/smallmap/{name}.gltf" id="model"]', ""]
    out += [f'[node name="{scene_name(name)}" type="Node3D"]']
    if script:
        out += ['script = ExtResource("script")']
    out += ["", '[node name="Model" parent="." instance=ExtResource("model")]', ""]
    for s in shapes:
        if s["basis"] is None:
            rows = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
        else:
            x, y, z = s["basis"]
            rows = tuple((x[i], y[i], z[i]) for i in range(3))  # a basis is written by rows
        nums = [fmt(v) for r in rows for v in r] + [fmt(v) for v in s["centre"]]
        out += [
            f'[node name="{s["name"]}" type="CSGBox3D" parent="."]',
            f"transform = Transform3D({', '.join(nums)})",
            "visible = false",
            "use_collision = true",
        ]
        if s["layer"] != 1:
            out += [f"collision_layer = {s['layer']}"]
        out += ["size = Vector3({}, {}, {})".format(*(fmt(v) for v in s["size"])), ""]
    path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8", newline="\n")


def render_sheet(folder, built, mat):
    """The pieces in a row on the 0.5 m grid, the Soldier (1.8 m) and three drive-in props at the left (Workbench,
    atlas colours), and each piece on its own from three quarters in front."""
    import build_kit_blockout as kb

    folder.mkdir(parents=True, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_cavity = True
    sc.display.shading.show_object_outline = True
    sc.world = bpy.data.worlds.new("W")
    sc.world.color = (0.03, 0.035, 0.06)
    for _name, objs in built:  # the straight stair as the fixture shows it: the rail on its open (left) side only
        for o in objs:
            o.hide_render = o.name.endswith("RailRight")
    # Each piece alone first, before the row moves them.
    for name, objs in built:
        others = [o for n, g in built if n != name for o in g]
        for o in others:
            o.hide_render = True
        mn, mx = kb.bounds(objs)
        cam = kb.ortho_camera(mn, mx, 35, elev=0.55, pad=1.25)
        cam.data.ortho_scale = max(mx - mn) * 1.6
        sc.render.resolution_x = sc.render.resolution_y = 900
        sc.render.filepath = str(folder / f"piece_{name}.png")
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)
        for o in others:
            o.hide_render = o.name.endswith("RailRight")
    groups = [kb.character("game/assets/characters/soldier/soldier.glb", 1.8)]
    compare = (
        "game/assets/drivein/trash_can.gltf",
        "game/assets/props/crate.gltf",
        "game/assets/drivein/ticket_booth.gltf",
    )
    for path in compare:
        before = set(bpy.data.objects)
        kb.kitlib.gltf_import(path)
        groups.append([o for o in bpy.data.objects if o not in before])
    groups += [objs for _n, objs in built]
    x = 0.0
    for objs in groups:
        mn, mx = kb.bounds(objs)
        x = math.ceil((x - 1e-6) * 2) / 2  # each starts on a grid line
        kb.place(objs, (x - mn.x, -(mn.y + mx.y) / 2, -mn.z))
        x += (mx.x - mn.x) + 0.5
    allobjs = [o for g in groups for o in g]
    mn, mx = kb.bounds(allobjs)
    kb.grid_floor(mat, Vector((math.floor(mn.x) - 0.5, -3.0, 0)), Vector((math.ceil(mx.x) + 0.5, 3.0, 0)))
    kb.ortho_camera(mn, mx, 24, elev=0.3)
    sc.render.resolution_x = 3200
    sc.render.resolution_y = 1000
    sc.render.filepath = str(folder / "stairs_sheet.png")
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="game/assets/smallmap")
    ap.add_argument("--fixtures", default="game/world/smallmap/fixtures")
    ap.add_argument("--sheet", default="", help="a folder for the contact sheet and the per-piece renders")
    ap.add_argument("--only", default="")
    a = ap.parse_args(argv)
    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(a.fixtures).resolve()
    fixtures.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    palette = out / "smallmap_palette.png"  # the kit's one atlas, shared with the walls
    img = palette_image(palette)
    ensure_import(palette)  # lossless, no mipmaps, Detect 3D off (tools/check_texture_imports.py)
    mat = atlas_material(img)
    only = set(filter(None, a.only.split(",")))
    report, built = {}, []
    for name, (fn, budget, script) in PIECES.items():
        if only and name not in only:
            continue
        pieces = []
        shapes = fn(pieces)
        objs = [to_object(p, mat) for p in pieces]
        bpy.context.view_layer.update()
        n = sum(tris(o) for o in objs)
        pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
        size = [round(max(c[k] for c in pts) - min(c[k] for c in pts), 2) for k in range(3)]
        info = {"tris": n, "budget": budget, "size_xyz_blender": size, "nodes": {o.name: tris(o) for o in objs}}
        print("PIECE", name, json.dumps(info))
        if n > budget:
            raise SystemExit(f"{name}: {n} tris over its budget {budget}")
        export(objs, out, name)
        write_fixture(fixtures / f"{name}.tscn", name, shapes, script)
        report[name] = info
        for o in objs:  # free the node names (Flight, RailLeft, ...) for the next piece's export
            o.name = f"{name}.{o.name}"
        built.append((name, objs))
    if not only:
        (out / "stairs_kit.json").write_text(
            json.dumps(report, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
        )
    if a.sheet:
        render_sheet(Path(a.sheet).resolve(), built, mat)
    print("STAIRS", out)


main()
