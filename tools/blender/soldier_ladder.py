"""The wearable pieces of the level ladder (#1078, docs/design/progression.md): original, from the drive-in and the
B-movie, added to the modular Soldier by build_soldier_parts.py, which passes itself in as `lib` (Piece, uv_of, join...).

Wave one: Usher's jacket, Press lanyard, Cinema glasses, Saddle shoes, Overalls, Projectionist's visor, Bolo tie and
Coveralls. Kit metres at rest, front -Y. What each rests on is measured and written down on
docs/research/soldier-parts.md ("The ladder's pieces"):

- Every top has the same trunk under its collar, and the tall and the open collars coincide at their foot (z about
  1.45, r 0.20-0.235 at the front), so what goes round the neck rides there, whatever the top.
- A piece that lies on the trunk follows the bare trunk (`Surface`), not the vest: the vest's pouches and pads stand 7
  cm proud and are worn over it. Thicker, it would take the arms deeper in the carries that lay a forearm on the chest.
- What lies on the trunk borrows the trunk's skin (`borrow_skin`) instead of taking one bone, so it bends with it; a
  small rigid piece (a button, a card) takes one point's weights whole, so it stays flat.
- Her variants are made by her own field (build_soldier_parts.female_shape) like every top; a neck piece's hardware
  moves rigidly (`female_neck`).
"""

import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

# What borrow_skin takes weights from: the trunk by place, not by bone. The chest's edges and the shoulders are weighted
# to the arms, and move when the arms hang: a strap that skipped those faces stayed where it was and the top came
# through it. Past this |x| at the arms' height a face is the arm itself.
TRUNK_X, ARM_Z = 0.3, 1.26
STAND_OFF = 0.016  # how far a cloth piece stands off the surface it lies on: over the chords of its coarser grid
NECK_FOOT = (0.0, -0.03)  # the middle of the ring that goes round the collar's foot (x, y)
NECK_RING = (0.20, 0.205)  # its half widths: inside the vest's shoulder pads (x 0.205), outside either collar
NECK_TOP = 1.54  # how high it may ride at the back, on an open collar: a tall one's funnel goes on up and hides it
PART_FRONT = -0.255  # where the neck pieces hang, in front of the collar's foot and of the vest's pouches (y -0.233)
WAIST_POINTS = 16  # round the overalls' waist
STRAP_WIDTH = 0.07


class Surface:
    """Rays onto parts at rest (their meshes hold kit metres), for pieces that lie on them."""

    def __init__(self, *objs):
        points, polys = [], []
        for o in objs:
            start = len(points)
            points += [v.co.copy() for v in o.data.vertices]
            polys += [[start + i for i in p.vertices] for p in o.data.polygons]
        self.tree = BVHTree.FromPolygons(points, polys)

    def hit(self, start, direction):
        """The first point a ray meets, or None."""
        return self.tree.ray_cast(Vector(start), Vector(direction).normalized())[0]

    def front(self, x, z, off=STAND_OFF):
        """The point in front of the surface at (x, z)."""
        p = self.hit((x, -2, z), (0, 1, 0))
        return p + Vector((0, -off, 0))

    def front_over(self, x, z, reach, off=STAND_OFF):
        """`front`, resting on the highest of the surface within `reach` of (x, z): the trunk's folds stand up between
        the points of a coarser sheet and came through it."""
        points = [self.hit((x + dx, -2, z + dz), (0, 1, 0)) for dx in (-reach, 0, reach) for dz in (-reach, 0, reach)]
        y = min(p.y for p in points if p is not None)
        return Vector((x, y - off, z))

    def back(self, x, z, off=STAND_OFF):
        p = self.hit((x, 2, z), (0, -1, 0))
        return p + Vector((0, off, 0))


# --- shapes ----------------------------------------------------------------------------------------------------------


def _face(bm, verts, centre):
    """A face on `verts` turned away from `centre`."""
    f = bm.faces.new(verts)
    f.normal_update()
    if f.normal.dot(f.calc_center_median() - centre) < 0:
        f.normal_flip()
    return f


def ribbon(points, normals, width, thick, closed=False):
    """A flat strap along `points`: `normals` (one a point) say which way its face looks."""

    def make(bm):
        rings = []
        n = len(points)
        for i, (p, nor) in enumerate(zip(points, normals)):
            a = points[(i - 1) % n] if closed or i else p
            b = points[(i + 1) % n] if closed or i < n - 1 else p
            side = (b - a).cross(nor).normalized() * (width / 2)
            out = nor.normalized() * (thick / 2)
            rings.append([bm.verts.new(p + s * side + o * out) for s, o in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            mid = (points[i] + points[j]) / 2
            for k in range(4):
                m = (k + 1) % 4
                _face(bm, [rings[i][k], rings[i][m], rings[j][m], rings[j][k]], mid)
        if not closed:
            _face(bm, rings[0], points[1])
            _face(bm, rings[-1], points[-2])

    return make


def plate(outline, y, thick):
    """A closed flat shape: `outline` is (x, z), always counter-clockwise from the front, from y to y + thick (a
    clockwise outline, or swapped ends, turn it inside out: the eye then looks through it)."""

    def make(bm):
        y0, y1 = min(y, y + thick), max(y, y + thick)
        front = [bm.verts.new((x, y0, z)) for x, z in outline]
        back = [bm.verts.new((x, y1, z)) for x, z in outline]
        bm.faces.new(front)
        bm.faces.new(list(reversed(back)))
        n = len(outline)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((front[i], back[i], back[j], front[j]))
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")

    return make


def wrap(rows):
    """A band round the body: `rows` of points (each a closed ring, angle growing to +X at the front), bottom to top."""

    def make(bm):
        grid = [[bm.verts.new(p) for p in row] for row in rows]
        n = len(rows[0])
        for r in range(len(rows) - 1):
            for i in range(n):
                j = (i + 1) % n
                bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))

    return make


def panel(rows, depth):
    """A sheet lying on the front of the body: `rows` of points (columns growing to +X, rows upward), its rim turned
    `depth` back into the body, so it has no open edge to look under."""

    def make(bm):
        grid = [[bm.verts.new(p) for p in row] for row in rows]
        nr, nc = len(rows), len(rows[0])
        for r in range(nr - 1):
            for c in range(nc - 1):
                bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
        rim = grid[0] + [row[-1] for row in grid[1:]] + grid[-1][-2::-1] + [row[0] for row in grid[-2:0:-1]]
        back = [bm.verts.new(v.co + Vector((0, depth, 0))) for v in rim]
        centre = sum((v.co for v in rim), Vector()) / len(rim) + Vector((0, depth / 2, 0))
        for i in range(len(rim)):
            j = (i + 1) % len(rim)
            _face(bm, [rim[i], rim[j], back[j], back[i]], centre)

    return make


def brim(arc, inner, outer, thick):
    """A curved peak: `inner` and `outer` give an (x, y, z) at an angle of `arc` (a list of angles, front 0, growing to
    +X); closed below by a copy `thick` under it."""

    def make(bm):
        top = [[bm.verts.new(f(a)) for a in arc] for f in (inner, outer)]
        low = [[bm.verts.new(v.co - Vector((0, 0, thick))) for v in row] for row in top]
        n = len(arc)
        for i in range(n - 1):
            bm.faces.new((top[1][i], top[1][i + 1], top[0][i + 1], top[0][i]))
            bm.faces.new((low[0][i], low[0][i + 1], low[1][i + 1], low[1][i]))
            bm.faces.new((low[1][i], low[1][i + 1], top[1][i + 1], top[1][i]))
            bm.faces.new((top[0][i], top[0][i + 1], low[0][i + 1], low[0][i]))
        bm.faces.new((top[1][0], top[0][0], low[0][0], low[1][0]))
        bm.faces.new((top[0][-1], top[1][-1], low[1][-1], low[0][-1]))

    return make


# --- skin ------------------------------------------------------------------------------------------------------------


def _islands(me):
    """Lists of vertex indices, one per connected piece of a mesh."""
    links = {v.index: [] for v in me.vertices}
    for e in me.edges:
        a, b = e.vertices
        links[a].append(b)
        links[b].append(a)
    seen, out = set(), []
    for v in links:
        if v in seen:
            continue
        stack, island = [v], []
        seen.add(v)
        while stack:
            u = stack.pop()
            island.append(u)
            for w in links[u]:
                if w not in seen:
                    seen.add(w)
                    stack.append(w)
        out.append(island)
    return out


def on_trunk(p):
    return abs(p.center.x) < TRUNK_X or p.center.z < ARM_Z


def on_sleeve(p):
    """The sleeve only: the nearest face to a shoulder's top is the tall collar's flare, which turns with the head."""
    return abs(p.center.x) > 0.24 and p.center.z < 1.5


def borrow_skin(o, sources, rigid=0.0, where=on_trunk):
    """Give `o` the weights of the faces under it that pass `where`, over whatever bone it had. An island smaller than
    `rigid` metres takes the weights at its middle for all its vertices, so it stays flat."""
    polys = []
    for s in sources:
        for p in s.data.polygons:
            if where(p):
                polys.append((s, p))
    points, faces = [], []
    for s, p in polys:
        start = len(points)
        points += [s.data.vertices[i].co.copy() for i in p.vertices]
        faces.append(list(range(start, len(points))))
    tree = BVHTree.FromPolygons(points, faces)

    def weights_at(co):
        _loc, _nor, index, _dist = tree.find_nearest(co)
        s, p = polys[index]
        names = [g.name for g in s.vertex_groups]
        acc = {}
        share = poly_3d_calc([s.data.vertices[vi].co for vi in p.vertices], _loc)
        for vi, part in zip(p.vertices, share):
            for g in s.data.vertices[vi].groups:
                acc[names[g.group]] = acc.get(names[g.group], 0.0) + g.weight * part
        top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
        total = sum(w for _n, w in top)
        return {n: w / total for n, w in top if w / total > 0.02}

    o.vertex_groups.clear()
    me = o.data

    def put(vi, weights):
        for name, w in weights.items():
            group = o.vertex_groups.get(name) or o.vertex_groups.new(name=name)
            group.add([vi], w, "REPLACE")

    for island in _islands(me):
        cos = [me.vertices[vi].co for vi in island]
        lo = Vector([min(c[i] for c in cos) for i in range(3)])
        hi = Vector([max(c[i] for c in cos) for i in range(3)])
        if (hi - lo).length < rigid:
            shared = weights_at((lo + hi) / 2)
            for vi in island:
                put(vi, shared)
        else:
            for vi, co in zip(island, cos):
                put(vi, weights_at(co))


def hang_from_torso(o, below):
    """What hangs below the collar goes with the chest: a blend of the trunk's weights there left a card off its clip."""
    torso = o.vertex_groups.get("Torso") or o.vertex_groups.new(name="Torso")
    for v in o.data.vertices:
        if v.co.z < below:
            for g in o.vertex_groups:
                g.remove([v.index])
            torso.add([v.index], 1.0, "REPLACE")


def female_neck(o, lib, arm, rigid):
    """Her variant of a neck piece: the straps moved by her field; a small flat piece (a card, a slide) sheared, as much
    as her field moves its top at the top and as much as its most forward point at the bottom: it stays flat, stays on
    its clip and tilts out over her chest. Moved whole, the card left its clip."""
    f = o.copy()
    f.data = o.data.copy()
    f.name = f.data.name = o.name + "__" + lib.FEMALE
    bpy.context.collection.objects.link(f)
    me = f.data
    for island in _islands(me):
        moved = {vi: lib.female_shape(me.vertices[vi].co)[0] for vi in island}
        cos = [me.vertices[vi].co for vi in island]
        lo = Vector([min(c[i] for c in cos) for i in range(3)])
        hi = Vector([max(c[i] for c in cos) for i in range(3)])
        if (hi - lo).length < rigid:
            top = min(moved[vi].y - me.vertices[vi].co.y for vi in island if me.vertices[vi].co.z > hi.z - 0.01)
            low = min(moved[vi].y - me.vertices[vi].co.y for vi in island)
            for vi in island:
                v = me.vertices[vi]
                t = (hi.z - v.co.z) / max(hi.z - lo.z, 1e-6)
                v.co.y += top + (low - top) * t
        else:
            for vi in island:
                me.vertices[vi].co = moved[vi]
    for m in f.modifiers:
        if m.type == "ARMATURE":
            m.object = arm
    return f


# --- cuts and buttons on a kit top -----------------------------------------------------------------------------------


def cut_front(o, lib, half, swatch, z=(0.8, 1.44)):
    """Cut a straight band down the front of a top's trunk, x within +-half, and paint it (as cut_stripe's trousers:
    painting whole faces by their centre leaves teeth)."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active

    def front(f):
        c = f.calc_center_median()
        return f.normal.y < -0.15 and abs(c.x) < 0.33 and z[0] < c.z < z[1]

    for x in (-half, half):
        faces = [f for f in bm.faces if front(f)]
        geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(x, 0, 0), plane_no=(1, 0, 0))
    u = lib.uv_of(swatch)
    for f in bm.faces:
        if front(f) and abs(f.calc_center_median().x) < half:
            for loop in f.loops:
                loop[uv].uv = u
    bm.to_mesh(me)
    bm.free()


def _button(p, lib, at, r, swatch):
    """A flat round button standing on the surface at `at`, facing front."""
    y = at.y - 0.007
    p.add(lib.cyl(r, r * 0.85, 0.016, 5), swatch, at=(at.x, y, at.z), rot=lib.rx(90), bevel=0)


# --- wave one --------------------------------------------------------------------------------------------------------


def usher_jacket(lib, parts, arm, mat):
    """A bellhop's short mess jacket: a plastron down the front in the second colour with two rows of buttons, a braid
    on each shoulder and a half belt at the back, which is what the player's camera sees."""
    o = parts["torso", "usher"]
    cut_front(o, lib, 0.095, "secondary")
    on = Surface(o)
    p = lib.Piece()
    for z in (1.13, 1.22, 1.31):
        for sx in (-1, 1):
            _button(p, lib, on.front(sx * 0.06, z, 0.0), 0.021, "accent")
    y = on.back(0.0, 1.08, 0.0).y
    p.add(lib.cube((0.20, 0.03, 0.055)), "accent", at=(0, y - 0.004, 1.08), bevel=0)  # wider, the back curves away
    buttons = p.build("usher_buttons", "Torso", arm, mat)
    borrow_skin(buttons, [o], rigid=0.2)
    lib.join(o, buttons)
    for side, sx in (("L", 1), ("R", -1)):  # along the top of the upper arm, which is where they ride in every pose
        z = on.hit((sx * 0.33, 0.017, 1.57), (0, 0, -1)).z  # from under the tall collar's flare (r 0.33 at z 1.6)
        braid = lib.Piece().add(lib.cube((0.17, 0.11, 0.022)), "accent", at=(sx * 0.33, 0.017, z + 0.004), bevel=0.008)
        braid.add(lib.cube((0.028, 0.125, 0.016)), "accent_shade", at=(sx * 0.33, 0.017, z + 0.014), bevel=0)
        piece = braid.build(f"usher_braid_{side}", f"UpperArm.{side}", arm, mat)
        # The sleeve's weights, not the arm bone's: the shoulder's faces close up as the arm hangs and left it in the air.
        borrow_skin(piece, [o], rigid=0.3, where=on_sleeve)
        lib.join(o, piece)


def coveralls(lib, parts, arm, mat):
    """A mechanic's one-piece: a zip from the collar to the fork, two breast pockets, a name patch and a crew oval on
    the back. The legs are its own (`hides_legs`)."""
    o = parts["torso", "coveralls"]
    cut_front(o, lib, 0.017, "accent", z=(0.86, 1.46))
    on = Surface(o)
    p = lib.Piece()
    for sx in (-1, 1):
        at = on.front(sx * 0.125, 1.255, 0.0)
        p.add(lib.cube((0.125, 0.018, 0.11)), "primary_shade", at=(at.x, at.y - 0.004, at.z), bevel=0.006)
        p.add(lib.cube((0.135, 0.022, 0.03)), "primary", at=(at.x, at.y - 0.008, at.z + 0.052), bevel=0.006)
    at = on.front(0.125, 1.255, 0.0)
    p.add(lib.cube((0.075, 0.012, 0.03)), "white", at=(at.x, at.y - 0.016, at.z - 0.012), bevel=0)
    pull = on.front(0.0, 1.36, 0.0)
    p.add(lib.cube((0.024, 0.014, 0.05)), "metal", at=(0, pull.y - 0.006, pull.z), bevel=0.004)
    # The back slopes: the oval lies along it.
    low, high = on.back(0.0, 1.15, 0.0), on.back(0.0, 1.29, 0.0)
    back = (low + high) / 2
    tilt = lib.rx(math.degrees(math.atan2(high.y - low.y, high.z - low.z)))
    oval = [(0.13 * math.cos(a), 0.075 * math.sin(a)) for a in (math.tau * i / 12 for i in range(12))]
    p.add(plate(oval, 0.012, -0.03), "accent", at=back, rot=tilt, bevel=0)
    bar = [(-0.085, -0.015), (0.085, -0.015), (0.085, 0.015), (-0.085, 0.015)]
    p.add(plate(bar, 0.017, -0.012), "white", at=back, rot=tilt, bevel=0)
    bits = p.build("coverall_bits", "Torso", arm, mat)
    borrow_skin(bits, [o], rigid=0.32)
    lib.join(o, bits)


def overalls(lib, parts, arm, mat):
    """Bib overalls: a high waist over the top's hem, a bib, straps over the shoulders and brass clips. The straps pass
    under a tall collar's foot and over an open one; the vest's pouches and pads are worn over the bib."""
    o = parts["legs", "overalls"]
    jacket, trousers, shirt = parts["torso", "jacket"], parts["legs", "trousers"], parts["torso", "shirt"]
    lower = Surface(jacket, trousers)
    upper = Surface(shirt)
    # The waist: at three heights, with a lip into the body at the top and the bottom.
    centre = Vector((0, 0.015, 0))
    rows = []
    for z in (0.865, 0.955, 1.045):
        row = []
        for i in range(WAIST_POINTS):
            a = math.tau * i / WAIST_POINTS
            d = Vector((math.sin(a), -math.cos(a), 0))
            # The widest within the row's reach: below the hem a ray meets only the trousers, and the hem hung out.
            hits = [lower.hit(centre + d * 1.2 + Vector((0, 0, z + dz)), -d) for dz in (0.0, 0.02, 0.04)]
            far = max(Vector((h.x, h.y - centre.y)).length for h in hits)
            row.append(Vector((d.x * far, centre.y + d.y * far, z)) + d * (STAND_OFF + 0.004))
        rows.append(row)
    for row in rows:  # the hem's corners make the rays jump: ease them round
        radii = [Vector((p.x, p.y - centre.y)).length for p in row]
        for i, p in enumerate(row):
            r = max(radii[i], (radii[i - 1] + radii[(i + 1) % WAIST_POINTS]) / 2)
            d = Vector((p.x, p.y - centre.y, 0)).normalized()
            p.x, p.y = d.x * r, centre.y + d.y * r

    def lip(row, dz):
        return [Vector((p.x * 0.86, centre.y + (p.y - centre.y) * 0.86, p.z + dz)) for p in row]

    band = [lip(rows[0], 0.0), *rows, lip(rows[-1], 0.0)]
    p = lib.Piece().add(wrap(band), "secondary", bevel=0, smooth=True)
    # The bib: on the trunk from the waist to the chest, the corners cut in at the top.
    xs = (-1.0, -0.5, 0.0, 0.5, 1.0)  # +-0.5 is where her chest stands out
    zs = (1.03, 1.09, 1.145, 1.20, 1.255, 1.355)

    def half(z):
        return 0.19 - 0.05 * lib.ramp(z, 1.05, 1.355)

    bib = [[upper.front_over(x * half(z), z, 0.03) for x in xs] for z in zs]
    p.add(panel(bib, 0.05), "secondary", bevel=0, smooth=True)
    pocket = min(c.y for row in bib[2:5] for c in row[1:4])  # on the bib's most forward point under it
    p.add(lib.cube((0.17, 0.016, 0.115)), "secondary_shade", at=(0, pocket - 0.012, 1.205), bevel=0)
    # The straps: from the bib's top corners over the shoulder to the waist at the back.
    for sx in (-1, 1):
        path, normals = [], []
        stops = [
            (0.135, 12),
            (0.165, 66),
            (0.175, 90),
            (0.165, 118),
            (0.15, 140),
            (0.115, 170),
        ]
        for x, deg in stops:
            a = math.radians(deg)
            d = Vector((0, -math.cos(a), math.sin(a)))
            pivot = Vector((sx * x, 0.01, 1.03))
            across = (-STRAP_WIDTH / 2, 0.0, STRAP_WIDTH / 2)  # the highest under the whole width
            hits = [upper.hit(pivot + Vector((dx, 0, 0)) + d * 1.2, -d) for dx in across]
            reach = max((h - pivot).dot(d) for h in hits if h is not None)
            path.append(pivot + d * (reach + STAND_OFF))
            normals.append(d)
        tail = max((upper.back(sx * x, 1.05, STAND_OFF + 0.012) for x in (0.07, 0.105, 0.14)), key=lambda c: c.y)
        tail.x = sx * 0.105
        p.add(ribbon([*path, tail], [*normals, Vector((0, 1, 0))], STRAP_WIDTH, 0.016), "secondary", bevel=0)
        clip = min(c.y for row in bib[4:] for c in row)
        p.add(lib.cube((0.085, 0.022, 0.06)), "amber", at=(sx * 0.135, clip - 0.005, 1.33), bevel=0)
    top = p.build("overall_bib", "Torso", arm, mat)
    borrow_skin(top, [jacket, trousers], rigid=0.16)
    lib.join(o, top)


def _collar_ring(jacket, shirt):
    """The ring round the collar's foot: (points, normals), resting on whichever of the collars is higher there."""
    on = [Surface(jacket), Surface(shirt)]
    points, normals = [], []
    for i in range(12):
        a = math.tau * i / 12
        x, y = NECK_FOOT[0] + NECK_RING[0] * math.sin(a), NECK_FOOT[1] - NECK_RING[1] * math.cos(a)
        z = max(s.hit((x, y, 1.75), (0, 0, -1)).z for s in on)
        points.append(Vector((x, y, min(z, NECK_TOP) + 0.016)))
        normals.append(Vector((math.sin(a), -math.cos(a), 2.0)).normalized())
    return points, normals


def press_lanyard(lib, parts, arm, mat):
    """A press pass: a webbing strap round the collar's foot and down to a clip, a card with a dark bar and a coloured
    corner hanging on the chest."""
    ring, normals = _collar_ring(parts["torso", "jacket"], parts["torso", "shirt"])
    p = lib.Piece().add(ribbon(ring, normals, 0.03, 0.01, closed=True), "accent", bevel=0)
    clip = Vector((0, PART_FRONT, 1.285))
    for sx in (-1, 1):
        start = ring[sx % 12] + Vector((0, 0, -0.004))
        mid = Vector((sx * 0.05, PART_FRONT + 0.012, 1.34))
        path = [start, mid, clip + Vector((sx * 0.008, 0, 0.02))]
        p.add(ribbon(path, [Vector((0, -1, 0.3))] * 3, 0.026, 0.008), "accent", bevel=0)
    card = lib.Piece()
    card.add(lib.cube((0.03, 0.016, 0.05)), "metal", at=(0, PART_FRONT - 0.002, 1.275), bevel=0)
    y = PART_FRONT - 0.006
    card.add(lib.cube((0.125, 0.012, 0.165)), "white", at=(0, y, 1.175), bevel=0.005)
    card.add(lib.cube((0.125, 0.006, 0.045)), "black", at=(0, y - 0.0075, 1.22), bevel=0)
    card.add(lib.cube((0.05, 0.006, 0.05)), "grey", at=(-0.03, y - 0.0075, 1.155), bevel=0)
    card.add(lib.cube((0.038, 0.006, 0.014)), "accent", at=(0.035, y - 0.0075, 1.17), bevel=0)
    return p, card


def bolo_tie(lib, parts, arm, mat):
    """A western string tie: a cord round the collar's foot through a slide with a stone, two ends with metal tips."""
    ring, normals = _collar_ring(parts["torso", "jacket"], parts["torso", "shirt"])
    p = lib.Piece().add(ribbon(ring, normals, 0.016, 0.014, closed=True), "black", bevel=0)
    slide = Vector((0, PART_FRONT, 1.385))
    for sx in (-1, 1):
        path = [ring[sx % 12] + Vector((0, 0, -0.004)), slide + Vector((sx * 0.02, 0.006, 0.02))]
        p.add(ribbon(path, [Vector((0, -1, 0.3))] * 2, 0.016, 0.014), "black", bevel=0)
        end = Vector((sx * 0.032, PART_FRONT + 0.004, 1.21))
        path = [slide + Vector((sx * 0.016, 0.004, -0.05)), end]  # from under the slide: on her it would cross it
        p.add(ribbon(path, [Vector((0, -1, 0))] * 2, 0.016, 0.014), "black", bevel=0)
        p.add(lib.cyl(0.015, 0.009, 0.05, 4), "metal", at=(end.x, end.y, end.z - 0.024), rot=lib.rx(180), bevel=0)
    hard = lib.Piece()
    hexagon = [(0.052 * math.cos(a), slide.z + 0.062 * math.sin(a)) for a in (math.tau * i / 8 for i in range(8))]
    hard.add(plate(hexagon, slide.y - 0.012, 0.022), "metal", bevel=0)
    stone = [(0.034 * math.cos(a), slide.z + 0.042 * math.sin(a)) for a in (math.tau * i / 8 for i in range(8))]
    hard.add(plate(stone, slide.y - 0.019, 0.012), "accent", bevel=0)
    return p, hard


def cinema_glasses(lib, arm, mat):
    """Card glasses handed out at the box office for a 3-D picture: a printed white card frame, red and cyan lenses,
    a nose notch and straight card arms."""
    top, low, y = lib.EYE_Z + 0.098, lib.EYE_Z - 0.085, lib.FRONT - 0.035
    frame = [(-0.30, top - 0.012), (-0.31, low + 0.04), (-0.28, low), (-0.07, low), (-0.035, low + 0.05), (0.035, low + 0.05),
             (0.07, low), (0.28, low), (0.31, low + 0.04), (0.30, top - 0.012), (0.285, top), (-0.285, top)]  # fmt: skip
    p = lib.Piece().add(plate(frame, y, 0.014), "white", bevel=0)
    trim = [(-0.285, top + 0.003), (0.285, top + 0.003), (0.285, top - 0.022), (-0.285, top - 0.022)]
    p.add(plate(list(reversed(trim)), y - 0.002, 0.018), "accent", bevel=0)
    for sx, swatch in ((-1, "lens_red"), (1, "lens_cyan")):
        lens = [(0.065, low + 0.075), (0.09, low + 0.03), (0.255, low + 0.03), (0.275, low + 0.06), (0.262, top - 0.038),
                (0.08, top - 0.038)]  # fmt: skip
        pts = [(sx * x, z) for x, z in lens]
        p.add(plate(pts if sx > 0 else list(reversed(pts)), y - 0.0025, 0.004), swatch, bevel=0)
        p.add(lib.cube((0.012, 0.33, 0.032)), "white", at=(sx * 0.297, y + 0.165, lib.EYE_Z + 0.045), bevel=0)
    return p.build("eyewear__cinema", "Head", arm, mat)


def projectionist_visor(lib, arm, mat):
    """A booth operator's eyeshade: a band above the brows that clears every hair cut, a peak angled down over the eyes
    and a film reel pin on the front."""
    band_y, band_z = -0.02, 2.052
    arc = [math.radians(a) for a in range(-66, 67, 22)]

    def ring(rx, ry, z):
        return lambda a: (rx * math.sin(a), band_y - ry * math.cos(a), z)

    def peak(a):
        reach = 0.09 + 0.20 * math.cos(a) ** 2  # longest at the front, drawn in at the sides
        return (0.41 * math.sin(a), band_y - (0.395 + reach) * math.cos(a), band_z + 0.004 - reach * 0.36)

    # r 0.40: the bob is 0.38 wide at this height (its 18 sides' chords fall a few millimetres in).
    p = lib.Piece().add(lib.cyl(0.40, 0.395, 0.05, 18), "primary_shade", at=(0, band_y, band_z), bevel=0)
    p.add(brim(arc, ring(0.396, 0.388, band_z + 0.02), peak, 0.014), "primary", bevel=0, under="primary_shade")
    y = band_y - 0.402
    pin_z = band_z + 0.056
    p.add(lib.cyl(0.06, 0.06, 0.014, 10), "metal", at=(0, y, pin_z), rot=lib.rx(90), bevel=0)
    p.add(lib.cyl(0.018, 0.018, 0.02, 6), "black", at=(0, y - 0.003, pin_z), rot=lib.rx(90), bevel=0)
    for i in range(3):
        a = math.tau * i / 3 + 0.5
        p.add(lib.cube((0.022, 0.018, 0.022)), "black",
              at=(0.038 * math.cos(a), y - 0.002, pin_z + 0.038 * math.sin(a)), bevel=0)  # fmt: skip
    return p.build("headwear__visor", "Head", arm, mat)


SADDLE_Y = (-0.112, -0.016)  # the saddle across the instep: toe in front of it, heel behind
SOCK_Z = 0.135  # above this, a sock in the trousers' colour (the trousers come down over a low shoe)


def saddle_shoes(lib, parts, arm, mat):
    """A two-tone oxford: a white toe and heel, a saddle in the trim colour across the instep, white laces. Both
    colour lines are cut in: painted by face, the sock's edge was a row of teeth."""
    o = parts["feet", "saddle"]
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    white = Vector(lib.uv_of("white"))

    def upper(f):
        return (Vector(f.loops[0][uv].uv) - white).length < 1e-4

    for co, no in (((0, 0, SOCK_Z), (0, 0, 1)), *(((0, y, 0), (0, 1, 0)) for y in SADDLE_Y)):
        faces = [f for f in bm.faces if upper(f)]
        geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
    accent, sock = lib.uv_of("accent"), lib.uv_of("secondary")
    for f in bm.faces:
        if not upper(f):
            continue
        c = f.calc_center_median()
        u = sock if c.z > SOCK_Z else accent if SADDLE_Y[0] < c.y < SADDLE_Y[1] else None
        for loop in f.loops if u else ():
            loop[uv].uv = u
    bm.to_mesh(me)
    bm.free()
    on = Surface(o)
    for side, sx in (("L", 1), ("R", -1)):
        laces = lib.Piece()
        for y in (-0.085, -0.04):
            x = sx * 0.205
            hit = on.hit((x, y, 1.0), (0, 0, -1))
            laces.add(lib.cube((0.075, 0.014, 0.012)), "white", at=(x, y, hit.z + 0.003), rot=lib.rx(20), bevel=0)
        lib.join(o, laces.build(f"laces_{side}", f"Foot.{side}", arm, mat))


def build(lib, parts, arm, mat):
    """Dress the parts built from the kit body and return the new pieces, {(slot, part): object}."""
    usher_jacket(lib, parts, arm, mat)
    coveralls(lib, parts, arm, mat)
    overalls(lib, parts, arm, mat)
    saddle_shoes(lib, parts, arm, mat)
    new = {
        ("eyewear", "cinema"): cinema_glasses(lib, arm, mat),
        ("headwear", "visor"): projectionist_visor(lib, arm, mat),
    }
    trunk = [parts["torso", "jacket"], parts["torso", "shirt"]]
    for pid, make in (("lanyard", press_lanyard), ("bolo", bolo_tie)):
        straps, hardware = make(lib, parts, arm, mat)
        o = straps.build(f"neck__{pid}", "Torso", arm, mat)
        borrow_skin(o, trunk)
        hang_from_torso(o, 1.38)
        hard = hardware.build(f"{pid}_hardware", "Torso", arm, mat)
        lib.join(o, hard)
        new["neck", pid] = o
    return new
