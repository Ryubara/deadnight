"""Build the small-map kit's cover and clutter props (group 3 of the parts list, issue #635).

Run with the pinned Blender, headless, from the repository root (absolute paths: Blender resolves relative ones
itself):

    blender -b --factory-startup -P tools/blender/build_smallmap_props.py -- \
        [--out game/assets/smallmap] [--fixtures game/world/smallmap/fixtures] [--only a,b] [--sheet <scratch folder>]

Every piece is our own, from chamfered boxes and low-sided cylinders on the kit's grid and atlas
(`tools/blender/smallmap_kit.py`; where each number comes from: docs/research/maps/small-map-art.md). Each stands on
its origin (the middle of its footprint, on the floor), the room side facing Blender -Y (Godot +Z), and is written
as `<out>/<name>.gltf` + `.bin` on the shared `smallmap_palette.png`, with a fixture scene
`<fixtures>/<name>.tscn` that holds the model and its hidden CSG collision. A piece over its triangle budget fails
the build. `<out>/smallmap_props.json` lists triangles, budgets and sizes.

`--sheet` then imports the written files back and renders contact sheets beside the Soldier (1.8 m), a zombie and
three drive-in props on the 0.5 m grid (`props_sheet.png`, `props_sheet_back.png`, `props_small.png`).
"""

import argparse
import itertools
import json
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from palette_import import ensure_import
from smallmap_kit import BEVEL, Piece, atlas_material, palette_image

PALETTE_FILE = "smallmap_palette.png"
SMALL = 0.015  # chamfer on parts of props under 1 m (none under 0.1 m)

# --- Helpers ---------------------------------------------------------------------------------------------------------


def recolour(p, n0, pick):
    """Put each face added since face `n0` on the swatch `pick(face)` names (the kit's one-swatch-a-face rule)."""
    from smallmap_kit import swatch_uv

    p.bm.faces.ensure_lookup_table()
    for f in p.bm.faces[n0:]:
        f.normal_update()
        u = swatch_uv(pick(f))
        for loop in f.loops:
            loop[p.uv].uv = u


def chunk(p, size, at, rng, rot=(0, 0, 0), jitter=0.14, soot=0.15):
    """A broken block: a chamfered box with its corners pushed about, mostly Concrete, a few faces charred.

    Fresh breaks are the lighter Plaster, never Grey2: at a grazing light Grey2 (#5f5f5f) went near black and the
    chunks read as holes."""
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    bmesh.ops.scale(tmp, vec=Vector(size), verts=tmp.verts)
    b = min(BEVEL, min(size) * 0.25)
    bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=b, segments=1, affect="EDGES", profile=0.5)
    for v in tmp.verts:
        v.co = Vector([c + rng.uniform(-jitter, jitter) * s for c, s in zip(v.co, size, strict=True)])
    n0 = len(p.bm.faces)
    p._merge(tmp, "Concrete", at, rot)

    def pick(f):
        if f.normal.z > 0.5:  # the top: dust, or a charred face now and then
            k = "Soot" if rng.random() < soot else "Concrete"
        else:
            k = rng.choice(("Concrete", "Concrete", "Concrete", "Plaster")) if f.calc_area() > 0.004 else "Concrete"
        return k

    recolour(p, n0, pick)


def bag(p, length, at, yaw, rng, deep=0.34, high=0.22):
    """A sandbag: a full chamfered pillow, its tied ends gathered, laid a little off square. Taller than its course
    (0.18 m) so each bag sags onto the one below: thin bags with gaps between courses read as logs."""
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    bmesh.ops.scale(tmp, vec=Vector((length, deep, high)), verts=tmp.verts)
    bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=0.06, segments=1, affect="EDGES", profile=0.5)
    for v in tmp.verts:
        if abs(v.co.x) > length / 2 - 0.07:  # the ends: gathered sideways only; pinched both ways they read as logs
            v.co.y *= 0.86
        elif v.co.z > high / 2 - 0.01:  # the top: a little lower than the middle of the sides, a filled sack's slump
            v.co.z -= 0.012
    p._merge(tmp, "Sandbag", at, (rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5), yaw + rng.uniform(-3, 3)))


def finish(p, centre=True):
    """Stand the piece on its origin: on the floor, and (`centre`) in the middle of its bounding box. A piece built
    around its own footprint (a cabinet with a drawer pulled out) passes `centre=False`."""
    xs = [v.co for v in p.bm.verts]
    lo = Vector([min(c[k] for c in xs) for k in range(3)])
    hi = Vector([max(c[k] for c in xs) for k in range(3)])
    shift = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z) if centre else (0, 0, -lo.z))
    bmesh.ops.translate(p.bm, vec=shift, verts=p.bm.verts)


def turn(p, rot):
    """Turn everything built so far about the origin (degrees, XYZ)."""
    m = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(p.bm, matrix=m, verts=p.bm.verts)


# --- Cover -----------------------------------------------------------------------------------------------------------


def sandbag_line(p, length, seed):
    """A sandbag line `length` long, 0.6 m deep, 0.9 m tall, in five courses: header courses (bags laid across) and
    stretcher courses (along), the top two one bag deep on the far side, so the room side has a step to lean on."""
    rng = random.Random(seed)
    course = 0.17  # a 0.22 m bag on a 0.17 m course: each sags onto the one below, the line stands 0.9 m
    for r in range(5):
        z = 0.1 + r * course
        if r in (0, 2):  # headers: bags across the line, 0.6 m long, side by side
            n = max(2, round(length / 0.31))
            pitch = length / n
            for i in range(n):
                x = -length / 2 + pitch * (i + 0.5)
                bag(p, 0.62, (x, 0, z), 90, rng, deep=pitch + 0.04)
        else:  # stretchers, staggered by half a bag against the course below
            ys = (-0.155, 0.155) if r == 1 else (0.155,)
            n = max(2, round(length / 0.56))
            pitch = length / n
            off = pitch / 2 if r % 2 else 0.0
            for y in ys:
                x = -length / 2 - off
                while x < length / 2 - 0.05:
                    a, b = max(x, -length / 2), min(x + pitch, length / 2)
                    if b - a > 0.2:
                        bag(p, b - a + 0.02, ((a + b) / 2, y, z), 0, rng)
                    x += pitch
                off = 0.0 if off else pitch / 2


def sandbags_2m(p):
    sandbag_line(p, 2.0, 635)


def sandbags_1m(p):
    sandbag_line(p, 1.0, 636)


def table(p, broken_leg=False):
    """A plank table, 1.6 x 0.8 m, its top 0.78 m up: four Wood boards on a DarkWood frame."""
    top_z = 0.78
    for i in range(4):
        y = -0.3 + i * 0.2
        p.box((1.6, 0.19, 0.045), (0, y, top_z - 0.0225), "Wood", SMALL)
    for s in (-1, 1):
        p.box((1.36, 0.035, 0.09), (0, s * 0.33, top_z - 0.09), "DarkWood", 0.0)  # the apron
        p.box((0.035, 0.6, 0.09), (s * 0.7, 0, top_z - 0.09), "DarkWood", 0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            h = top_z - 0.045
            if broken_leg and sx > 0 and sy < 0:
                h = 0.3  # snapped: the rest of it lies beside the table
                p.box((0.065, 0.065, h), (sx * 0.72, sy * 0.33, top_z - 0.045 - h / 2), "DarkWood", 0.0)
                continue
            p.box((0.065, 0.065, h), (sx * 0.72, sy * 0.33, h / 2), "DarkWood", 0.0)
    p.box((1.38, 0.04, 0.05), (0, 0, 0.16), "DarkWood", 0.0)  # the stretcher between the leg pairs
    for sx in (-1, 1):
        p.box((0.04, 0.62, 0.05), (sx * 0.72, 0, 0.16), "DarkWood", 0.0)


def table_upright(p):
    table(p)


def table_tipped(p):
    """The table knocked over for cover: the top stands on its long edge facing out (+Y), the legs into the room, one
    of them snapped off and lying on the floor."""
    table(p, broken_leg=True)
    turn(p, (-90, 0, 0))  # the top (z = 0.78) turns to face +Y
    finish(p)
    p.box((0.065, 0.42, 0.065), (0.42, -0.2, 0.0325), "DarkWood", 0.0, rot=(0, 0, 24))


def chair(p):
    """A plain wooden chair, 0.45 x 0.45 m, the seat at 0.45 m, the back to 0.9 m on the far side (+Y)."""
    seat = 0.45
    p.box((0.45, 0.43, 0.04), (0, -0.01, seat - 0.02), "Wood", SMALL)
    for sx in (-1, 1):
        p.box((0.04, 0.04, seat - 0.04), (sx * 0.19, -0.18, (seat - 0.04) / 2), "DarkWood", 0.0)
        p.box((0.04, 0.04, 0.9), (sx * 0.19, 0.19, 0.45), "DarkWood", 0.0, rot=(-4, 0, 0))
        p.box((0.03, 0.34, 0.03), (sx * 0.19, 0.0, 0.14), "DarkWood", 0.0)
    p.box((0.42, 0.035, 0.11), (0, 0.205, 0.82), "Wood", SMALL, rot=(-4, 0, 0))
    p.box((0.34, 0.025, 0.07), (0, 0.195, 0.64), "Wood", 0.0, rot=(-4, 0, 0))
    p.box((0.34, 0.03, 0.03), (0, -0.18, 0.2), "DarkWood", 0.0)


# --- Furniture -------------------------------------------------------------------------------------------------------


def filing_cabinet(p):
    """A steel filing cabinet, 0.5 x 0.6 x 1.3 m: four drawers on the room side, the second pulled out."""
    p.box((0.5, 0.58, 1.26), (0, 0.01, 0.67), "Grey", BEVEL)
    p.box((0.46, 0.54, 0.04), (0, 0.01, 0.02), "Rust", 0.0)  # the kick: rust where the mop reached
    for i in range(4):
        z = 0.2 + i * 0.3
        out = 0.14 if i == 2 else 0.0
        y = -0.29 - out
        if out:
            for s in (-1, 1):
                p.box((0.015, out, 0.22), (s * 0.2, -0.29 - out / 2 + 0.01, z), "DarkGrey", 0.0)
            p.box((0.4, out, 0.015), (0, -0.29 - out / 2 + 0.01, z - 0.1), "DarkGrey", 0.0)
            p.box((0.38, 0.12, 0.13), (0, -0.29 - out / 2 + 0.01, z - 0.02), "Cream", 0.0)  # files
        p.box((0.44, 0.03, 0.27), (0, y, z + 0.0), "Grey", SMALL)
        p.box((0.16, 0.035, 0.035), (0, y - 0.03, z + 0.03), "Chrome", 0.0)
        p.box((0.09, 0.012, 0.045), (0, y - 0.018, z + 0.09), "Cream", 0.0)  # the label holder


def shelf_rack(p):
    """A steel shelf rack, 1.2 x 0.45 x 2.0 m: four angle posts, five shelves with a lip, X-braced at the back and
    the ends (open at the front, the room side)."""
    w, d, h = 1.2, 0.45, 2.0
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((0.045, 0.045, h), (sx * (w / 2 - 0.0225), sy * (d / 2 - 0.0225), h / 2), "Grey", 0.0)
    for z in (0.1, 0.55, 1.0, 1.45, 1.96):
        p.box((w - 0.03, d - 0.03, 0.025), (0, 0, z), "Grey2", 0.0)
        p.box((w - 0.03, 0.025, 0.05), (0, -(d / 2 - 0.02), z + 0.01), "Grey", 0.0)
    # The braces: flat bars corner to corner in each half-height bay.
    for z0, z1 in ((0.1, 1.0), (1.0, 1.96)):
        bay = z1 - z0
        zc = (z0 + z1) / 2
        diag = math.hypot(w - 0.08, bay)
        ang = math.degrees(math.atan2(bay, w - 0.08))
        for s in (-1, 1):
            p.box((diag, 0.012, 0.03), (0, d / 2 - 0.006, zc), "Rust", 0.0, rot=(0, s * ang, 0))
        diag = math.hypot(d - 0.08, bay)
        ang = math.degrees(math.atan2(bay, d - 0.08))
        for sx in (-1, 1):
            for s in (-1, 1):
                p.box((0.012, diag, 0.03), (sx * (w / 2 - 0.006), 0, zc), "Rust", 0.0, rot=(s * ang, 0, 0))


def tall_cabinet(p):
    """A tall DarkWood cabinet, 1.0 x 0.5 x 2.2 m, open at the front: its recess (0.92 x 1.72 m, 0.3 m deep) holds a
    long gun's wall buy, the lot's amber plaque (1.7 x 0.9 m) stood on end at `PLAQUE_SLOT`, so the buy sits in
    furniture. A stepped crest with a round medallion on top. All ours."""
    w, d = 0.96, 0.46  # the carcass; the plinth and the cornice bring it to 1.0 x 0.5
    p.box((w + 0.02, d + 0.02, 0.12), (0, 0, 0.06), "DarkWood", BEVEL)  # the plinth
    for s in (-1, 1):
        p.box((0.02, d, 1.84), (s * (w / 2 - 0.01), 0, 0.12 + 0.92), "DarkWood", 0.0)  # the sides
    p.box((w, 0.04, 1.84), (0, d / 2 - 0.02, 0.12 + 0.92), "DarkWood", 0.0)  # the back
    p.box((w - 0.04, d - 0.04, 0.04), (0, 0, 0.14), "Wood", 0.0)  # the recess floor
    # The face frame: thin stiles and a head rail proud of the carcass, a lighter Wood bead along the head.
    fy = -d / 2 - 0.01
    for s in (-1, 1):
        p.box((0.03, 0.04, 1.84), (s * (w / 2 - 0.005), fy, 0.12 + 0.92), "DarkWood", 0.0)
    p.box((w + 0.01, 0.06, 0.08), (0, fy + 0.01, 1.92), "DarkWood", SMALL)
    p.box((w - 0.06, 0.02, 0.025), (0, fy - 0.03, 1.9), "Wood", 0.0)
    # The cornice and the crest: two steps, the middle raised, a round medallion facing the room.
    p.box((1.0, 0.5, 0.08), (0, 0, 2.0), "DarkWood", BEVEL)
    p.box((w - 0.1, d - 0.12, 0.05), (0, 0.03, 2.065), "DarkWood", SMALL)
    p.box((0.5, 0.12, 0.11), (0, -0.1, 2.145), "DarkWood", SMALL)
    p.cyl(0.07, 0.04, (0, -0.17, 2.13), "Wood", sides=8, rot=(90, 0, 0))
    for s in (-1, 1):
        p.box((0.09, 0.09, 0.06), (s * 0.37, -0.1, 2.12), "DarkWood", SMALL)


# --- Rubble ----------------------------------------------------------------------------------------------------------


def rubble(size, seed):
    def build(p):
        rng = random.Random(seed)
        x, y, z = size
        chunk(p, (x, y, z), (0, 0, z / 2), rng, rot=(rng.uniform(-6, 6), rng.uniform(-6, 6), rng.uniform(0, 25)))
        if x >= 0.3:  # the bigger ones carry a bent rebar stub and a smaller broken piece against them
            p.cyl(0.012, x * 0.5, (x * 0.25, 0, z * 0.85), "Rust", sides=4, rot=(0, 70, rng.uniform(0, 40)))
            s = x * 0.32
            chunk(p, (s, s * 0.8, s * 0.6), (-x * 0.45, y * 0.15, s * 0.3), rng, rot=(0, 0, rng.uniform(0, 30)))

    return build


rubble_a = rubble((0.17, 0.13, 0.11), 1)
rubble_b = rubble((0.26, 0.2, 0.16), 2)
rubble_c = rubble((0.36, 0.26, 0.2), 3)
rubble_d = rubble((0.48, 0.34, 0.27), 4)


def rubble_cone(p):
    """A heap of broken masonry 1.5 m across and 0.7 m high: a lumpy nine-sided mound with blocks, a charred board
    and a rebar on it."""
    rng = random.Random(5)
    tmp = bmesh.new()
    rings = ((0.75, 0.0), (0.62, 0.16), (0.42, 0.38), (0.2, 0.56), (0.04, 0.66))
    sides = 9
    verts = []
    for r, z in rings:
        ring = []
        for i in range(sides):
            a = 2 * math.pi * (i + rng.uniform(-0.15, 0.15)) / sides
            rr = r * rng.uniform(0.85, 1.1) if z > 0 else r * rng.uniform(0.93, 1.03)
            zz = z + (rng.uniform(-0.04, 0.04) if 0 < z else 0)
            ring.append(tmp.verts.new((math.cos(a) * rr, math.sin(a) * rr, zz)))
        verts.append(ring)
    for lo, hi in itertools.pairwise(verts):
        for i in range(sides):
            j = (i + 1) % sides
            tmp.faces.new((lo[i], lo[j], hi[j], hi[i]))
    tmp.faces.new(list(reversed(verts[0])))
    tmp.faces.new(verts[-1])
    n0 = len(p.bm.faces)
    p._merge(tmp, "Concrete", (0, 0, 0), (0, 0, 0))
    recolour(p, n0, lambda f: rng.choice(("Concrete", "Concrete", "Concrete", "Grey2", "Plaster")))
    for _ in range(6):  # blocks lying on its slopes
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.25, 0.6)
        h = 0.6 * (1 - r / 0.75) + 0.02
        s = rng.uniform(0.16, 0.3)
        chunk(p, (s, s * 0.7, s * 0.5), (math.cos(a) * r, math.sin(a) * r, h), rng, rot=(rng.uniform(-20, 20), 0, 0))
    p.box((1.1, 0.12, 0.035), (0.05, -0.1, 0.36), "Soot", 0.0, rot=(0, -26, 28))  # a charred board
    p.box((0.7, 0.1, 0.03), (-0.2, 0.25, 0.42), "Wood", 0.0, rot=(18, 14, -62))
    p.cyl(0.012, 0.8, (0.2, 0.2, 0.48), "Rust", sides=4, rot=(0, 58, 120))


# --- Period clutter (1958) -------------------------------------------------------------------------------------------


def radio(p):
    """A table radio set: a DarkWood case with a cream grille, a dial and two knobs. 0.42 x 0.22 x 0.27 m."""
    p.box((0.42, 0.22, 0.25), (0, 0, 0.135), "DarkWood", SMALL)
    p.box((0.4, 0.2, 0.02), (0, 0, 0.01), "Black", 0.0)  # the feet rail
    p.box((0.2, 0.012, 0.15), (-0.08, -0.111, 0.14), "Cream", 0.0)  # the speaker cloth
    for i in range(3):
        p.box((0.2, 0.008, 0.012), (-0.08, -0.118, 0.09 + i * 0.05), "DarkWood", 0.0)  # its bars
    p.box((0.13, 0.012, 0.06), (0.12, -0.111, 0.19), "Cream", 0.0)  # the dial
    p.box((0.006, 0.006, 0.05), (0.12, -0.12, 0.19), "Black", 0.0)
    for x in (0.08, 0.16):
        p.cyl(0.02, 0.025, (x, -0.12, 0.09), "Black", sides=6, rot=(90, 0, 0))
    p.box((0.16, 0.03, 0.025), (0, 0, 0.27), "Chrome", 0.0)  # the carry handle


def lantern(p):
    """A hurricane lantern: a red fount, a glass globe in a wire guard, a vented cap and a bail. 0.36 m tall."""
    p.cyl(0.085, 0.07, (0, 0, 0.035), "Red", sides=8)
    p.cyl(0.08, 0.02, (0, 0, 0.08), "Red", sides=8, r2=0.05)
    p.cyl(0.055, 0.06, (0, 0, 0.12), "Glass", sides=8, r2=0.07)
    p.cyl(0.07, 0.06, (0, 0, 0.18), "Glass", sides=8, r2=0.045)
    for i in range(4):  # the guard wires
        a = math.radians(45 + 90 * i)
        p.box((0.008, 0.008, 0.15), (math.cos(a) * 0.075, math.sin(a) * 0.075, 0.155), "Grey", 0.0)
    p.cyl(0.06, 0.04, (0, 0, 0.23), "Red", sides=8, r2=0.03)
    p.cyl(0.035, 0.03, (0, 0, 0.265), "Red", sides=6)
    p.box((0.13, 0.008, 0.008), (0, 0, 0.35), "Grey", 0.0)  # the bail, standing up
    for s in (-1, 1):
        p.box((0.008, 0.008, 0.12), (s * 0.065, 0, 0.29), "Grey", 0.0)
    for s in (-1, 1):  # the two tubes to the cap
        p.box((0.014, 0.014, 0.2), (s * 0.09, 0, 0.17), "Red", 0.0)


def helmet(p):
    """A steel helmet left on the floor: a low dome on a flared rim, a strap trailing. 0.33 x 0.29 x 0.16 m."""
    p.cyl(0.165, 0.016, (0, 0, 0.012), "Green", sides=10, r2=0.15)  # the rim, flared
    p.cyl(0.145, 0.06, (0, 0, 0.05), "Green", sides=10, r2=0.135)
    p.cyl(0.135, 0.05, (0, 0, 0.105), "Green", sides=10, r2=0.095)
    p.cyl(0.095, 0.03, (0, 0, 0.145), "Green", sides=10, r2=0.03)
    for s in (-1, 1):
        p.box((0.02, 0.1, 0.006), (s * 0.12, -0.12, 0.004), "DarkGrey", 0.0, rot=(0, 0, s * 25))
    turn(p, (6, -4, 15))
    finish(p)


# name: (builder, budget, blockers). Budgets are the style bible's classes: a prop under 1 m 800, 1-3 m 1.5k.
# Blockers are hidden CSG collision in Blender metres around the finished piece: "bbox" is its bounding box;
# ("box", size, centre) a box. None: walk-over dressing with no collision, as the lot's papers and debris.
PIECES = {
    "sandbags_2m": (
        sandbags_2m,
        1500,
        [("box", (2.0, 0.62, 0.55), (0, 0, 0.275)), ("box", (2.0, 0.32, 0.9), (0, 0.15, 0.45))],
    ),
    "sandbags_1m": (
        sandbags_1m,
        1500,
        [("box", (1.0, 0.62, 0.55), (0, 0, 0.275)), ("box", (1.0, 0.32, 0.9), (0, 0.15, 0.45))],
    ),
    "table": (table_upright, 1500, "bbox"),
    "table_tipped": (table_tipped, 1500, "bbox"),
    "chair": (chair, 800, "bbox"),
    "filing_cabinet": (filing_cabinet, 1500, "bbox"),
    "shelf_rack": (shelf_rack, 1500, "bbox"),
    "tall_cabinet": (tall_cabinet, 1500, "bbox"),
    "rubble_a": (rubble_a, 800, None),
    "rubble_b": (rubble_b, 800, None),
    "rubble_c": (rubble_c, 800, "bbox"),
    "rubble_d": (rubble_d, 800, "bbox"),
    "rubble_cone": (rubble_cone, 1500, [("cone", 0.72, 0.66)]),
    "radio": (radio, 800, None),
    "lantern": (lantern, 800, None),
    "helmet": (helmet, 800, None),
}

# The tall cabinet's recess, where a wall buy's plaque goes on end (Blender metres from the origin): see the fixture.
# The plaque's middle: against the back (inner face y = 0.19), on the recess floor (z = 0.16), 1.7 m tall.
PLAQUE_SLOT = (0, 0.13, 1.02)
CENTRED_BY_HAND = {"filing_cabinet"}  # the pulled-out drawer is not part of the footprint


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


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def camel(name):
    return "".join(w.capitalize() for w in name.split("_"))


def godot_vec(v):
    """Blender (x, y, z) to Godot (x, z, -y): Blender -Y is Godot +Z."""
    return (v[0], v[2], -v[1])


def fmt(x):
    return f"{x:.3f}".rstrip("0").rstrip(".") if abs(x) > 1e-6 else "0"


def fixture(name, blockers, lo, hi, root, folder):
    """The piece's fixture scene: the model and its hidden collision, as `game/world/drive_in/fixtures/`."""
    model = f"res://{(Path(root) / name).as_posix().split('game/', 1)[1]}.gltf"
    lines = [
        "[gd_scene format=3]",
        "",
        f'[ext_resource type="PackedScene" path="{model}" id="model"]',
        "",
        f'[node name="{camel(name)}" type="Node3D"]',
        "",
        '[node name="Model" parent="." instance=ExtResource("model")]',
    ]
    if blockers == "bbox":
        blockers = [("box", tuple(hi[k] - lo[k] for k in range(3)), tuple((hi[k] + lo[k]) / 2 for k in range(3)))]
    for i, b in enumerate(blockers or []):
        node = "Blocker" if len(blockers) == 1 else f"Blocker{i + 1}"
        if b[0] == "box":
            size, centre = godot_vec(b[1]), godot_vec(b[2])
            size = tuple(abs(s) for s in size)
            lines += [
                "",
                f'[node name="{node}" type="CSGBox3D" parent="."]',
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {', '.join(fmt(c) for c in centre)})",
                "visible = false",
                "use_collision = true",
                f"size = Vector3({', '.join(fmt(s) for s in size)})",
            ]
        else:  # a cone: CSGCylinder3D with cone on, its radius at the floor
            r, h = b[1], b[2]
            lines += [
                "",
                f'[node name="{node}" type="CSGCylinder3D" parent="."]',
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {fmt(h / 2)}, 0)",
                "visible = false",
                "use_collision = true",
                f"radius = {fmt(r)}",
                f"height = {fmt(h)}",
                "sides = 9",
                "cone = true",
            ]
    if name == "tall_cabinet":
        lines += [
            "",
            '[node name="PlaqueSlot" type="Marker3D" parent="."]',
            # Turned a quarter about Z, so the lot's plaque box (1.7 x 0.9 x 0.12) put under it stands on end.
            f"transform = Transform3D(0, -1, 0, 1, 0, 0, 0, 0, 1, {', '.join(fmt(c) for c in godot_vec(PLAQUE_SLOT))})",
        ]
    path = Path(folder) / f"{name}.tscn"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


# --- The contact sheets ----------------------------------------------------------------------------------------------


def sheets(out, sheet_dir, names):
    """Import the written files back and render them beside the game's characters and props on the 0.5 m grid."""
    import build_kit_blockout as kb
    import kitlib

    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = bpy.data.images.load(str(out / PALETTE_FILE))
    mat = atlas_material(img)
    root = Path(__file__).resolve().parents[2]
    soldier = root / "game/assets/characters/soldier/soldier.glb"
    zombie = root / "game/assets/characters/zombies/zombie_farmhand.glb"

    def load(path):
        before = set(bpy.data.objects)
        kitlib.gltf_import(str(path))
        return [o for o in bpy.data.objects if o not in before]

    def row(groups, gap=0.4):
        x = 0.0
        for objs in groups:
            mn, mx = kb.bounds(objs)
            kb.place(objs, (x - mn.x, -(mn.y + mx.y) / 2, -mn.z))
            x += (mx.x - mn.x) + gap

    def render(path, angle, elev, width, height, scale_pad):
        allobjs = [o for o in bpy.data.objects if o.type == "MESH" and o.name != "Grid"]
        mn, mx = kb.bounds(allobjs)
        for o in [o for o in bpy.data.objects if o.type == "CAMERA"]:
            bpy.data.objects.remove(o)
        cam = kb.ortho_camera(mn, mx, angle, elev=elev, pad=scale_pad)
        cam.data.ortho_scale = max(mx.x - mn.x, (mx.z - mn.z) * width / height) * scale_pad
        sc = bpy.context.scene
        sc.render.engine = "BLENDER_WORKBENCH"
        sc.display.shading.light = "STUDIO"
        sc.display.shading.color_type = "TEXTURE"
        sc.display.shading.show_cavity = True
        sc.display.shading.show_object_outline = True
        sc.render.resolution_x, sc.render.resolution_y = width, height
        sc.world = bpy.data.worlds.new("W")
        sc.world.color = (0.03, 0.035, 0.06)
        sc.render.filepath = str(sheet_dir / path)
        bpy.ops.render.render(write_still=True)

    big = [
        n
        for n in names
        if n
        in (
            "sandbags_2m",
            "sandbags_1m",
            "table",
            "table_tipped",
            "chair",
            "filing_cabinet",
            "shelf_rack",
            "tall_cabinet",
            "rubble_cone",
        )
    ]
    small = [n for n in names if n not in big or n in ("chair",)]
    groups = [kb.character(str(soldier), 1.8), kb.character(str(zombie), 1.63)]
    for p in (
        "game/assets/drivein/trash_can.gltf",
        "game/assets/drivein/picnic_table.gltf",
        "game/assets/props/crate.gltf",
    ):
        groups.append(load(root / p))
    for n in big:
        objs = load(out / f"{n}.gltf")
        if n == "tall_cabinet":  # the lot's plaque, on end in the recess: the buy fits
            pl = Piece("Plaque")
            pl.box((0.9, 0.12, 1.7), PLAQUE_SLOT, "Amber", 0.0)
            objs.append(pl.obj(mat))
        groups.append(objs)
    row(groups)
    allobjs = [o for g in groups for o in g]
    mn, mx = kb.bounds(allobjs)
    kb.grid_floor(mat, Vector((math.floor(mn.x) - 0.5, -2.0, 0)), Vector((math.ceil(mx.x) + 0.5, 2.0, 0)))
    render("props_sheet.png", 28, 0.32, 3000, 900, 1.04)
    render("props_sheet_back.png", 208, 0.32, 3000, 900, 1.04)
    # The small pieces, closer: the Soldier, a crate and the chair for scale.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = bpy.data.images.load(str(out / PALETTE_FILE))
    mat = atlas_material(img)
    groups = [kb.character(str(soldier), 1.8), load(root / "game/assets/props/crate.gltf")]
    groups += [load(out / f"{n}.gltf") for n in small]
    row(groups, gap=0.25)
    allobjs = [o for g in groups for o in g]
    mn, mx = kb.bounds(allobjs)
    kb.grid_floor(mat, Vector((math.floor(mn.x) - 0.5, -1.5, 0)), Vector((math.ceil(mx.x) + 0.5, 1.5, 0)))
    render("props_small.png", 24, 0.35, 2400, 1000, 1.06)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="game/assets/smallmap")
    ap.add_argument("--fixtures", default="game/world/smallmap/fixtures")
    ap.add_argument("--only", default="")
    ap.add_argument("--sheet", default="", help="a folder to render the contact sheets into")
    args = ap.parse_args(argv)
    out = Path(args.out).resolve()
    fixtures = Path(args.fixtures).resolve()
    out.mkdir(parents=True, exist_ok=True)
    fixtures.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    palette_path = out / PALETTE_FILE
    img = palette_image(palette_path)
    ensure_import(palette_path)
    mat = atlas_material(img)
    only = set(filter(None, args.only.split(",")))
    report_path = out / "smallmap_props.json"
    report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {}
    for name, (fn, budget, blockers) in PIECES.items():
        if only and name not in only:
            continue
        p = Piece(name)
        fn(p)
        finish(p, centre=name not in CENTRED_BY_HAND)
        o = p.obj(mat)
        n = tris(o)
        xs = [v.co for v in o.data.vertices]
        lo = [min(c[k] for c in xs) for k in range(3)]
        hi = [max(c[k] for c in xs) for k in range(3)]
        size = [round(hi[k] - lo[k], 2) for k in range(3)]
        info = {"tris": n, "budget": budget, "size_xyz_blender": size, "collision": blockers is not None}
        print("PROP", name, json.dumps(info))
        if n > budget:
            raise SystemExit(f"{name}: {n} tris over its budget {budget}")
        export(o, out, name)
        fixture(name, blockers, lo, hi, out.relative_to(out.parents[2]), fixtures)
        report[name] = info
        bpy.data.objects.remove(o, do_unlink=True)
    report_path.write_text(json.dumps(report, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    if args.sheet:
        sheet_dir = Path(args.sheet).resolve()
        sheet_dir.mkdir(parents=True, exist_ok=True)
        sheets(out, sheet_dir, [n for n in PIECES if not only or n in only])
    print("BUILT", out)


if __name__ == "__main__":
    main()
