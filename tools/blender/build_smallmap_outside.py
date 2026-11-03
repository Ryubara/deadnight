"""Build the small-map kit's roof and outside pieces (group 5, issue #638): bare trees, a utility pole and its wire,
barbed wire, a fence post and the pitched roof, whole and broken.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_smallmap_outside.py -- [--out game/assets/smallmap] \
        [--only a,b] [--blend <file>]

Every piece is our own design in the kit's manner (`smallmap_kit.py`: chamfered boxes and low-sided cylinders, one
atlas, each face on one swatch). The outside is never walked by a player: it is seen through windows, broken walls and
holes in the roof, so the trees and poles also get a far level of detail (`<name>_far`) for the backdrop past the
playable bounds. Each piece stands on its origin (the middle of its footprint, on the ground; the roof's on the wall
top) and faces Blender -Y (Godot +Z). Each is written as `<out>/<name>.gltf` + `.bin` on `<out>/smallmap_palette.png`, and
the pieces the backdrop repeats also as `<name>.obj` (one Mesh, so a MultiMesh draws every copy at once). One `PIECE`
line per piece and `<out>/outside_pieces.json` give triangles, budget and size. Sizes and rules:
docs/research/maps/small-map-art.md.
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
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from palette_import import ensure_import
from smallmap_kit import BEVEL, Piece, atlas_material, palette_image

# --- Helpers ---------------------------------------------------------------------------------------------------------


def limb(p, a, b, r0, r1, colour, sides=6, caps=True):
    """A tapered cylinder from point `a` (radius r0) to point `b` (radius r1): a trunk, a branch, a wire."""
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler("XYZ")
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=caps, cap_tris=False, segments=sides, radius1=r0, radius2=r1, depth=d.length)
    p._merge(tmp, colour, (a + b) / 2, [math.degrees(x) for x in rot])


def prism(p, outline, depth, colour, at=(0, 0, 0)):
    """A flat polygon in the XZ plane (`outline`, (x, z) points, counter-clockwise seen from -Y) extruded `depth` along
    Y, centred on y = 0: a gable, a ragged board end."""
    tmp = bmesh.new()
    front = [tmp.verts.new((x, -depth / 2, z)) for x, z in outline]
    back = [tmp.verts.new((x, depth / 2, z)) for x, z in outline]
    tmp.faces.new(front)
    tmp.faces.new(list(reversed(back)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        tmp.faces.new((front[j], front[i], back[i], back[j]))
    bmesh.ops.triangulate(tmp, faces=[f for f in tmp.faces if len(f.verts) > 4])
    p._merge(tmp, colour, at, (0, 0, 0))


def sag(a, b, drop, n):
    """Points along a wire hung from `a` to `b` that sags `drop` metres at its middle (a parabola, close to a
    catenary at these sags)."""
    a, b = Vector(a), Vector(b)
    return [a.lerp(b, i / n) - Vector((0, 0, drop * 4 * (i / n) * (1 - i / n))) for i in range(n + 1)]


def wire(p, points, r, colour, sides=3):
    for a, b in itertools.pairwise(points):
        limb(p, a, b, r, r, colour, sides=sides, caps=False)


# --- Bare trees ------------------------------------------------------------------------------------------------------
# Three leafless trees, 4.5, 6 and 8 m tall: a chunky trunk that forks two or three times, the limbs few and thick
# (the props' trees are as chunky, and leafy). Winter bark is dark; the forks catch a little frost (Chalk).

TREES = {
    # name: (height, trunk radius, forks, limbs at the first fork, seed)
    "bare_tree_a": (4.5, 0.2, 3, 2, 11),
    "bare_tree_b": (6.0, 0.26, 3, 3, 23),
    "bare_tree_c": (8.0, 0.32, 3, 3, 37),
}


def _grow(rng, p, at, direction, length, radius, depth, spread, far):
    """One limb and, below `depth`, two forks off its end. Returns nothing; adds to `p`."""
    end = at + direction * length
    tip = radius * 0.62
    limb(p, at, end, radius, tip, "DarkWood", sides=4 if far else (6 if depth >= 2 else 5), caps=not far)
    if depth <= 0 or (far and depth <= 1):
        return
    yaw = rng.uniform(0, math.tau)
    for i in range(2):  # two forks, roughly opposite
        if i:
            yaw += math.pi + rng.uniform(-0.6, 0.6)
        tilt = spread + rng.uniform(-0.15, 0.15)
        side = Vector((math.cos(yaw), math.sin(yaw), 0))
        d = (direction * math.cos(tilt) + side * math.sin(tilt)).normalized()
        d.z = max(d.z, 0.25)  # winter limbs reach up, never droop below level
        _grow(rng, p, end, d.normalized(), length * rng.uniform(0.62, 0.74), tip, depth - 1, spread * 1.08, far)


def bare_tree(name, far=False):
    height, r, forks, first, seed = TREES[name]

    def build(p):
        rng = random.Random(seed)
        trunk_h = height * 0.42
        sides = 4 if far else 7
        lean = Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), 1)).normalized()
        top = Vector((0, 0, 0)) + lean * trunk_h
        limb(p, (0, 0, -0.1), top, r, r * 0.78, "DarkWood", sides=sides, caps=not far)
        if not far:
            # Root flare: three low wedges round the foot, and frost on the ground at it.
            for i in range(3):
                a = i * math.tau / 3 + rng.uniform(-0.3, 0.3)
                d = Vector((math.cos(a), math.sin(a), 0))
                limb(p, d * r * 0.4 + Vector((0, 0, 0.35)), d * r * 2.2, r * 0.55, r * 0.2, "DarkWood", sides=4)
            p.cyl(r * 1.9, 0.04, (0, 0, 0.02), "Chalk", sides=7)
        # The crown: `first` limbs off the trunk's top, each forking `forks - 1` more times.
        crown = height - trunk_h
        base_len = crown * 0.55
        for i in range(first):
            yaw = i * math.tau / first + rng.uniform(-0.4, 0.4)
            tilt = math.radians(rng.uniform(24, 34))
            d = Vector((0, 0, 1)) * math.cos(tilt) + Vector((math.cos(yaw), math.sin(yaw), 0)) * math.sin(tilt)
            _grow(rng, p, top, d.normalized(), base_len * rng.uniform(0.9, 1.05), r * 0.68, forks - 1, 0.45, far)
        if not far:
            # Frost along the top of the trunk's fork.
            p.box((r * 1.5, r * 1.5, 0.05), (top.x, top.y, top.z + 0.02), "Chalk", 0.0)

    return build


# --- Utility pole and wire --------------------------------------------------------------------------------------------
# A creosoted pole, 0.3 m across and 7 m tall, a 2 m crossbar with three glass insulators across the line (along Y),
# the wire running along +X. The wire is its own piece: one span of 12 m from this pole's insulators to the next's.

POLE_H = 7.0
POLE_R = 0.15
ARM_Z = 6.35
ARM_W = 2.0
INSULATORS = (-0.8, -0.28, 0.8)  # y on the crossbar; one off-centre, as old lines are
SPAN = 12.0
WIRE_SAG = 0.55
WIRE_Z = ARM_Z + 0.06 + 0.16  # the insulator's top


def utility_pole(far=False):
    def build(p):
        if far:
            p.box((0.26, 0.26, POLE_H), (0, 0, POLE_H / 2), "DarkWood", 0.0)
            p.box((0.12, ARM_W, 0.12), (0, 0, ARM_Z), "DarkWood", 0.0)
            return
        p.cyl(POLE_R, POLE_H, (0, 0, POLE_H / 2), "DarkWood", sides=8, r2=POLE_R * 0.8)
        p.cyl(POLE_R * 0.84, 0.06, (0, 0, POLE_H + 0.02), "Soot", sides=8)  # the cut top, weathered dark
        p.box((0.12, ARM_W, 0.12), (0, 0, ARM_Z), "DarkWood", BEVEL)
        for s in (-1, 1):  # braces from the pole up to the arm
            limb(p, (0, 0, ARM_Z - 0.6), (0, s * 0.55, ARM_Z - 0.06), 0.03, 0.03, "Grey2", sides=4, caps=False)
        for y in INSULATORS:
            p.cyl(0.015, 0.1, (0, y, ARM_Z + 0.08), "Grey2", sides=4)
            p.cyl(0.055, 0.12, (0, y, ARM_Z + 0.16), "Teal", sides=6, r2=0.035)  # green glass, as old lines have
        # Step bolts up the pole, the lowest out of reach, and a dented transformer can on the far side.
        for i in range(6):
            z = 2.6 + i * 0.55
            a = (i % 2) * math.pi
            limb(p, (0, 0, z), (math.cos(a) * 0.3, math.sin(a) * 0.3, z), 0.018, 0.018, "Grey2", sides=4, caps=False)
        p.cyl(0.22, 0.6, (0.32, 0, 5.3), "Grey", sides=8)
        p.cyl(0.24, 0.05, (0.32, 0, 5.62), "Grey2", sides=8)
        p.box((0.06, 0.08, 0.5), (0.12, 0, 5.3), "Grey2", 0.0)
        limb(p, (0.32, 0, 5.65), (0, INSULATORS[0], WIRE_Z), 0.012, 0.012, "Black", sides=3, caps=False)

    return build


def utility_wire(far=False):
    def build(p):
        for y in INSULATORS:
            pts = sag((0, y, WIRE_Z), (SPAN, y, WIRE_Z), WIRE_SAG, 4 if far else 8)
            wire(p, pts, 0.03 if far else 0.022, "Black", sides=3)

    return build


# --- Barbed wire ------------------------------------------------------------------------------------------------------
# A concertina coil, 2 m long and 0.8 m across, on two pickets; and a fence post with four barbed strands running 2 m
# to +X (the next post's place), so posts and runs make a fence of any length on the 0.5 m grid. A lone `fence_post`
# ends a run.

COIL_L, COIL_R, COIL_LOOPS = 2.0, 0.4, 9
POST_H = 1.6
STRANDS = (0.35, 0.7, 1.05, 1.4)
RUN = 2.0


def barbed_coil(p):
    rng = random.Random(5)
    seg = 8
    pts = []
    for i in range(COIL_LOOPS * seg + 1):
        t = i / seg * math.tau
        x = -COIL_L / 2 + COIL_L * i / (COIL_LOOPS * seg)
        r = COIL_R * (1 + rng.uniform(-0.06, 0.06))
        pts.append((x, math.sin(t) * r, COIL_R + math.cos(t) * r * 0.95))
    wire(p, pts, 0.012, "Grey", sides=3)
    for i in range(0, len(pts) - 1, 3):  # barbs: a short cross every few segments
        x, y, z = pts[i]
        p.box((0.07, 0.012, 0.012), (x, y, z), "Grey", 0.0, rot=(0, 0, 45))
    for x in (-COIL_L / 2 + 0.25, COIL_L / 2 - 0.25):  # the pickets, angle iron
        p.box((0.04, 0.04, 0.95), (x, 0, 0.42), "Rust", 0.0, rot=(0, 4, 0))
        p.box((0.04, 0.6, 0.04), (x, 0, 0.82), "Rust", 0.0)


def fence_post(p):
    p.box((0.12, 0.12, POST_H + 0.1), (0, 0, (POST_H + 0.1) / 2 - 0.05), "DarkWood", BEVEL)
    p.box((0.13, 0.13, 0.04), (0, 0, POST_H - 0.02), "Chalk", 0.0)  # frost on the top
    for z in STRANDS:
        p.box((0.02, 0.13, 0.03), (0, 0, z), "Grey2", 0.0)  # the staples


def wire_fence_far(p):
    """The run as the backdrop's yard fence draws it from 15 m and more: the post and four plain strands, no barbs
    (a barb is under half a pixel there)."""
    p.box((0.12, 0.12, POST_H + 0.1), (0, 0, (POST_H + 0.1) / 2 - 0.05), "DarkWood", 0.0)
    for k, z in enumerate(STRANDS):
        wire(p, sag((0.06, -0.065, z), (RUN - 0.06, -0.065, z), 0.04 + 0.03 * k, 2), 0.012, "Grey", sides=3)


def wire_fence(p):
    fence_post(p)
    rng = random.Random(9)
    for k, z in enumerate(STRANDS):
        drop = 0.04 + 0.03 * k
        pts = sag((0.06, -0.065, z), (RUN - 0.06, -0.065, z + rng.uniform(-0.02, 0.02)), drop, 4)
        wire(p, pts, 0.008, "Grey", sides=3)
        for i in range(1, 8):  # a barb every 0.25 m
            at = sag(pts[0], pts[-1], drop, 8)[i]
            p.box((0.05, 0.01, 0.01), at, "Grey", 0.0, rot=(0, 45, 0))
            p.box((0.05, 0.01, 0.01), at, "Grey", 0.0, rot=(0, -45, 0))


# --- A neon sign for the backdrop ------------------------------------------------------------------------------------
# The drive-in's roadside sign, seen across the fields: DRIVE-IN in pink tubes on a black board on two posts, an amber
# arrow under it. The tubes and the arrow sit on the atlas's Pink and Amber cells, which the backdrop's material makes
# glow. Our own lettering, a 3 x 5 stroke font; 1.4 m capitals, the board's face to -Y.

STROKES = {
    "D": [
        ((0, 0), (0, 4)),
        ((0, 4), (1.4, 4)),
        ((1.4, 4), (2, 3.3)),
        ((2, 3.3), (2, 0.7)),
        ((2, 0.7), (1.4, 0)),
        ((1.4, 0), (0, 0)),
    ],
    "R": [((0, 0), (0, 4)), ((0, 4), (2, 4)), ((2, 4), (2, 2)), ((2, 2), (0, 2)), ((0.9, 2), (2, 0))],
    "I": [((1, 0), (1, 4)), ((0.2, 4), (1.8, 4)), ((0.2, 0), (1.8, 0))],
    "V": [((0, 4), (1, 0)), ((1, 0), (2, 4))],
    "E": [((0, 0), (0, 4)), ((0, 4), (2, 4)), ((0, 2), (1.5, 2)), ((0, 0), (2, 0))],
    "-": [((0.3, 2), (1.7, 2))],
    "N": [((0, 0), (0, 4)), ((0, 4), (2, 0)), ((2, 0), (2, 4))],
}
NEON_U = 0.35  # one stroke-grid unit
NEON_WORD = "DRIVE-IN"
NEON_Z = 6.2  # the letters' baseline


def neon_sign(p):
    pitch = 3 * NEON_U
    width = len(NEON_WORD) * pitch - NEON_U
    for x in (-width / 2 + 0.6, width / 2 - 0.6):
        p.box((0.3, 0.3, NEON_Z), (x, 0.2, NEON_Z / 2), "Grey2", BEVEL)
    p.box((width + 0.8, 0.16, 4 * NEON_U + 0.9), (0, 0, NEON_Z + 2 * NEON_U), "Black", BEVEL)
    for i, ch in enumerate(NEON_WORD):
        x0 = -width / 2 + i * pitch
        for (ax, az), (bx, bz) in STROKES[ch]:
            a = (x0 + ax * NEON_U, -0.12, NEON_Z + az * NEON_U)
            b = (x0 + bx * NEON_U, -0.12, NEON_Z + bz * NEON_U)
            limb(p, a, b, 0.045, 0.045, "Pink", sides=4, caps=True)
    # The arrow under the board, pointing in to the lot.
    z = NEON_Z - 0.75
    limb(p, (-width / 2 + 0.6, -0.1, z), (width / 2 - 1.0, -0.1, z), 0.07, 0.07, "Amber", sides=4)
    for s in (-1, 1):
        limb(p, (width / 2 - 0.4, -0.1, z), (width / 2 - 1.1, -0.1, z + s * 0.45), 0.07, 0.07, "Amber", sides=4)


# --- The roof ---------------------------------------------------------------------------------------------------------
# A pitched roof in 2 m bays: the ridge along X, so bays line up along X as wall modules do, the slopes falling to -Y
# (the front) and +Y. A bay spans 8 m outside to outside of its walls (a 7.4 m room between 0.3 m walls: the Help
# room's 6.9 m and the formula's narrow rooms fit) at 30 degrees, with a 0.4 m overhang. The origin is the middle of the
# bay on the wall tops, so a bay sits on the walls at the storey's top (6.0 m for two storeys). From inside, through a
# hole in the ceiling or from the upper floor, the rafters, the tie beam and the plank sheathing show; from outside the
# tar-paper courses and the ridge cap. The broken bay loses a ragged patch of its front slope, rafters and all.

ROOF_SPAN = 8.0
PITCH = math.radians(30)
OVERHANG = 0.4
BAY = 2.0
RAFTER_X = (-0.5, 0.5)  # 1 m centres, so bays in a row keep the spacing
RAFTER_D = 0.2  # rafter depth (across the slope)
SHEATH = 0.05
COURSE = 0.05
COURSES = 5
LAP = 0.02

HALF = ROOF_SPAN / 2
PLATE_TOP = 0.14
# The rafters' top plane: their undersides rest on the wall plates' tops 0.15 m in from the wall's outer face.
LIFT = PLATE_TOP + RAFTER_D / math.cos(PITCH) - 0.15 * math.tan(PITCH)
RIDGE_Z = LIFT + HALF * math.tan(PITCH)
SLOPE_L = HALF / math.cos(PITCH) + OVERHANG


def _on_slope(s, u, w):
    """A point on slope `s` (-1 front, +1 back): `u` metres down from the ridge along the slope, `w` metres out of the
    rafters' top plane (positive is up, out of the roof). Returns (y, z)."""
    c, sn = math.cos(PITCH), math.sin(PITCH)
    return (s * (u * c + w * sn), RIDGE_Z - u * sn + w * c)


def _slope_box(p, s, u, size_u, size_w, x, size_x, w, colour, bevel=0.0):
    """A board on slope `s`: `size_u` along the slope from `u`, `size_w` thick, its underside `w` over the rafters'
    top plane."""
    y, z = _on_slope(s, u + size_u / 2, w + size_w / 2)
    p.box((size_x, size_u, size_w), (x, y, z), colour, bevel, rot=(s * -math.degrees(PITCH), 0, 0))


def _rafter(p, s, x, u0=0.0, u1=SLOPE_L, colour="DarkWood"):
    _slope_box(p, s, u0, u1 - u0, RAFTER_D, x, 0.1, -RAFTER_D, colour, 0.0)


def _frame(p):
    """What every bay has: the wall plates, the ridge beam, the tie beam, the fascia and the back slope whole."""
    for s in (-1, 1):
        p.box((BAY, 0.24, PLATE_TOP), (0, s * (HALF - 0.15), PLATE_TOP / 2), "DarkWood", BEVEL)  # the wall plate
    p.box((BAY, 0.12, 0.28), (0, 0, RIDGE_Z - 0.16), "DarkWood", BEVEL)  # the ridge beam
    p.box((0.12, ROOF_SPAN - 0.1, 0.2), (0, 0, PLATE_TOP + 0.1), "DarkWood", BEVEL)  # the tie beam, one a bay
    post = RIDGE_Z - 0.3 - (PLATE_TOP + 0.2)
    p.box((0.1, 0.1, post), (0, 0, PLATE_TOP + 0.2 + post / 2), "DarkWood", 0.0)  # the king post
    for s in (-1, 1):
        y, z = _on_slope(s, SLOPE_L, -0.1)
        p.box((BAY, 0.04, 0.24), (0, y + s * 0.02, z), "Wood", 0.0)  # the fascia board at the eaves


def _slope(p, s, holes=()):
    """The courses of a slope with `holes` left out: (x0, x1, u0, u1) rectangles on the slope that hold no sheathing
    and no tar paper (the boards stop at ragged ends)."""
    step = SLOPE_L / COURSES
    for i in range(COURSES):
        u0, u1 = i * step, (i + 1) * step
        spans = [(-BAY / 2, BAY / 2)]
        for x0, x1, h0, h1 in holes:
            if u1 <= h0 or u0 >= h1:
                continue
            cut = []
            for a, b in spans:
                if b <= x0 or a >= x1:
                    cut.append((a, b))
                    continue
                if a < x0:
                    cut.append((a, x0))
                if b > x1:
                    cut.append((x1, b))
            spans = cut
        for a, b in spans:
            if b - a < 0.05:
                continue
            # Boards at a bay's end run 20 mm into the next bay, so no crack opens on the sky between two bays.
            a, b = (a - LAP if a <= -BAY / 2 else a), (b + LAP if b >= BAY / 2 else b)
            mid = (a + b) / 2
            _slope_box(p, s, u0, step + 0.02, SHEATH, mid, b - a, 0.0, "Wood", 0.0)  # the plank sheathing
            # Tar paper, each course lapping the one below it: a slight tilt makes the step that reads as courses.
            _slope_box(p, s, u0 - 0.03, step + 0.04, COURSE, mid, b - a, SHEATH + 0.01 * (i % 2), "DarkGrey", 0.0)
    y, z = _on_slope(s, 0.08, SHEATH + COURSE + 0.02)
    p.box(
        (BAY + 2 * LAP, 0.18, 0.06), (0, y, z), "Grey2", 0.0, rot=(s * -math.degrees(PITCH), 0, 0)
    )  # the ridge cap's half


def roof_bay(p):
    _frame(p)
    for s in (-1, 1):
        for x in RAFTER_X:
            _rafter(p, s, x)
        _slope(p, s)


# The broken bay's hole on the front slope: x from -0.85 to 0.75, down the slope from 1.0 to 3.7 m.
HOLE = (-0.85, 0.75, 1.0, 3.7)


def roof_bay_broken(p):
    _frame(p)
    x0, x1, u0, u1 = HOLE
    _rafter(p, 1, RAFTER_X[0])
    _rafter(p, 1, RAFTER_X[1])
    _slope(p, 1)
    # The front slope: one rafter whole, the other snapped in the hole, its lower end hanging into the room.
    _rafter(p, -1, RAFTER_X[1])
    _rafter(p, -1, RAFTER_X[0], 0.0, 1.9)
    _rafter(p, -1, RAFTER_X[0], 3.2, SLOPE_L)
    y, z = _on_slope(-1, 1.9, -RAFTER_D / 2)
    limb(p, (RAFTER_X[0], y, z), (RAFTER_X[0] + 0.1, y - 0.35, z - 0.9), 0.06, 0.05, "Soot", sides=4)
    # Ragged ends: the courses stop at the hole's rectangle, and short boards of different lengths stick into it.
    _slope(p, -1, holes=[HOLE])
    rng = random.Random(3)
    step = SLOPE_L / COURSES
    for i in range(COURSES):
        cu0, cu1 = i * step, (i + 1) * step
        if cu1 <= u0 or cu0 >= u1:
            continue
        for side, edge in ((-1, x0), (1, x1)):
            stub = rng.uniform(0.15, 0.45)
            mid = edge + side * -stub / 2
            colour = "Soot" if rng.random() < 0.5 else "Wood"
            _slope_box(p, -1, cu0, step * rng.uniform(0.6, 0.95), SHEATH, mid, stub, 0.0, colour, 0.0)
    # Battens left across the hole, one broken; the charred lips of the hole.
    for u, whole in ((1.6, True), (2.5, False), (3.3, True)):
        if whole:
            _slope_box(p, -1, u, 0.08, 0.04, (x0 + x1) / 2, x1 - x0, 0.0, "DarkWood", 0.0)
        else:
            _slope_box(p, -1, u, 0.08, 0.04, x0 + 0.3, 0.6, 0.0, "DarkWood", 0.0)
    for u in (u0, u1):
        _slope_box(p, -1, u - 0.05, 0.1, 0.03, (x0 + x1) / 2, x1 - x0 + 0.1, SHEATH + COURSE, "Soot", 0.0)
    # A slab of tar paper torn loose, hanging over the lower edge of the hole.
    y, z = _on_slope(-1, u1, SHEATH + COURSE)
    p.box((0.7, 0.04, 0.5), (0.1, y - 0.05, z - 0.22), "DarkGrey", 0.0, rot=(-10, 0, 8))


def roof_gable(p):
    """The end wall under a row of bays: a plank pentagon from the wall top to the rafters' top plane, 0.2 m thick, in
    the XZ plane with its outside face to +Y. Turned 90 degrees about Z (Godot Y) it closes the end of a row; its
    width matches a bay's span, so it stands on the end wall."""
    prism(p, [(-HALF, 0.0), (HALF, 0.0), (HALF, LIFT), (0.0, RIDGE_Z), (-HALF, LIFT)], 0.2, "Wood")
    for i in range(1, 6):  # the boards' joints, proud strips on the outside face
        z = i * RIDGE_Z / 6
        w = 2 * HALF if z <= LIFT else 2 * HALF * (RIDGE_Z - z) / (RIDGE_Z - LIFT)
        p.box((w - 0.1, 0.03, 0.04), (0, 0.115, z), "DarkWood", 0.0)
    p.box((0.36, 0.04, 0.36), (0, 0.12, RIDGE_Z * 0.6), "Black", 0.0)  # a vent
    p.box((0.46, 0.05, 0.06), (0, 0.13, RIDGE_Z * 0.6 + 0.2), "DarkWood", 0.0)
    for s in (-1, 1):  # the barge boards along the slopes, over the overhang
        y, z = _on_slope(s, SLOPE_L / 2, SHEATH + COURSE - 0.1)
        p.box((SLOPE_L, 0.06, 0.24), (y, 0.13, z), "Wood", 0.0, rot=(0, s * math.degrees(PITCH), 0))


# --- The table ----------------------------------------------------------------------------------------------------

PIECES = {
    # name: (builder, triangle budget (style bible: 1-3 m 1.5k, over 3 m 5k; a far level of detail 300), also as .obj)
    "bare_tree_a": (bare_tree("bare_tree_a"), 1500, True),
    "bare_tree_b": (bare_tree("bare_tree_b"), 1500, True),
    "bare_tree_c": (bare_tree("bare_tree_c"), 1500, True),
    "bare_tree_a_far": (bare_tree("bare_tree_a", far=True), 300, True),
    "bare_tree_b_far": (bare_tree("bare_tree_b", far=True), 300, True),
    "bare_tree_c_far": (bare_tree("bare_tree_c", far=True), 300, True),
    "utility_pole": (utility_pole(), 1500, True),
    "utility_pole_far": (utility_pole(far=True), 300, True),
    "utility_wire": (utility_wire(), 800, True),
    "utility_wire_far": (utility_wire(far=True), 300, True),
    "barbed_coil": (barbed_coil, 1500, True),
    "fence_post": (fence_post, 800, True),
    "wire_fence": (wire_fence, 1500, True),
    "wire_fence_far": (wire_fence_far, 300, True),
    "neon_sign": (neon_sign, 5000, True),
    "roof_bay": (roof_bay, 5000, False),
    "roof_bay_broken": (roof_bay_broken, 5000, False),
    "roof_gable": (roof_gable, 1500, False),
}


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


def export_obj(o, out, name):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
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


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="game/assets/smallmap")
    ap.add_argument("--only", default="")
    ap.add_argument("--blend", default="", help="also save the built pieces in one .blend (for the contact sheet)")
    args = ap.parse_args(argv)
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    palette_path = out / "smallmap_palette.png"
    img = palette_image(palette_path)
    ensure_import(palette_path)  # lossless, no mipmaps, Detect 3D off (tools/check_texture_imports.py)
    mat = atlas_material(img)
    only = set(filter(None, args.only.split(",")))
    report_path = out / "outside_pieces.json"
    report = json.loads(report_path.read_text(encoding="utf-8")) if only and report_path.exists() else {}
    for name, (fn, budget, as_obj) in PIECES.items():
        if only and name not in only:
            continue
        p = Piece(name)
        fn(p)
        o = p.obj(mat)
        n = tris(o)
        xs = [v.co for v in o.data.vertices]
        lo = [round(min(c[k] for c in xs), 2) for k in range(3)]
        hi = [round(max(c[k] for c in xs), 2) for k in range(3)]
        info = {
            "tris": n,
            "budget": budget,
            "size_xyz_blender": [round(hi[k] - lo[k], 2) for k in range(3)],
            "min_xyz_blender": lo,
            "max_xyz_blender": hi,
        }
        print("PIECE", name, json.dumps(info))
        if n > budget:
            raise SystemExit(f"{name}: {n} tris over its budget {budget}")
        export(o, out, name)
        if as_obj:
            export_obj(o, out, name)
        report[name] = info
        if not args.blend:
            bpy.data.objects.remove(o, do_unlink=True)
    report_path.write_text(json.dumps(report, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=str(Path(args.blend).resolve()))


main()
