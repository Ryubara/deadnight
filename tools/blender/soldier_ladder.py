"""The wearable pieces of the level ladder (#1078, docs/design/progression.md): original, from the drive-in and the
B-movie, added to the modular Soldier by build_soldier_parts.py, which passes itself in as `lib` (Piece, uv_of, join...).

Wave one: Usher's jacket, Press lanyard, Cinema glasses, Saddle shoes, Overalls, Projectionist's visor, Bolo tie and
Coveralls. Wave two: Roller skates, Swing skirt, Creature tee, Rubber boots, Creature mask, Film-strip scarf and Varsity
gold. Kit metres at rest, front -Y. What each rests on is measured and written down on
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

import itertools
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
WAIST_CENTRE = Vector((0, 0.015, 0))
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


def _hugging_rows(on, centre, zs, points, reach, start, off):
    """Closed rings round `centre` (x, y): each point `off` outside the widest of the surface within `reach` of its
    height, from rays that start `start` from the centre, the corners eased round."""
    rows = []
    for z in zs:
        row = []
        for i in range(points):
            a = math.tau * i / points
            d = Vector((math.sin(a), -math.cos(a), 0))
            # The widest within the row's reach: below the hem a ray meets only the trousers, and the hem hung out.
            hits = [on.hit(centre + d * start + Vector((0, 0, z + dz)), -d) for dz in reach]
            far = max(Vector((h.x - centre.x, h.y - centre.y)).length for h in hits if h is not None)
            row.append(Vector((centre.x + d.x * far, centre.y + d.y * far, z)) + d * off)
        rows.append(row)
    for row in rows:  # the hem's corners make the rays jump: ease them round
        radii = [Vector((p.x - centre.x, p.y - centre.y)).length for p in row]
        for i, p in enumerate(row):
            r = max(radii[i], (radii[i - 1] + radii[(i + 1) % points]) / 2)
            d = Vector((p.x - centre.x, p.y - centre.y, 0)).normalized()
            p.x, p.y = centre.x + d.x * r, centre.y + d.y * r
    return rows


def _waist(lower):
    """The high waist over the top's hem, at three heights, bottom to top."""
    zs, reach = (0.865, 0.955, 1.045), (0.0, 0.02, 0.04)
    return _hugging_rows(lower, WAIST_CENTRE, zs, WAIST_POINTS, reach, 1.2, STAND_OFF + 0.004)


def _lip(row):
    """A row drawn into the body."""
    c = WAIST_CENTRE
    return [Vector((p.x * 0.86, c.y + (p.y - c.y) * 0.86, p.z)) for p in row]


def overalls(lib, parts, arm, mat):
    """Bib overalls: a high waist over the top's hem, a bib, straps over the shoulders and brass clips. The straps pass
    under a tall collar's foot and over an open one; the vest's pouches and pads are worn over the bib."""
    o = parts["legs", "overalls"]
    jacket, trousers, shirt = parts["torso", "jacket"], parts["legs", "trousers"], parts["torso", "shirt"]
    lower = Surface(jacket, trousers)
    upper = Surface(shirt)
    # The waist: at three heights, with a lip into the body at the top and the bottom.
    rows = _waist(lower)

    band = [_lip(rows[0]), *rows, _lip(rows[-1])]
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


# --- wave two --------------------------------------------------------------------------------------------------------


def tube(rows, open_end=False):
    """A closed tube: `wrap` with an end on each side, for what a limb or a neck goes through. The limb comes out of
    the end, so nothing has to reach the limb's own surface, and a bare leg that is thinner shows no gap. `open_end`
    leaves the last row open."""

    def make(bm):
        grid = [[bm.verts.new(p) for p in row] for row in rows]
        n = len(rows[0])
        for r in range(len(rows) - 1):
            for i in range(n):
                j = (i + 1) % n
                bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
        centre = sum((v.co for row in grid for v in row), Vector()) / (n * len(grid))
        _face(bm, grid[0], centre)
        if not open_end:
            _face(bm, grid[-1], centre)

    return make


def _blend_skin(o, z, a, b):
    """`o`, on bone `a`, goes over to bone `b` down from z[1] to z[0]: what meets the foot bends with it."""
    low = o.vertex_groups.get(b) or o.vertex_groups.new(name=b)
    up = o.vertex_groups[a]
    for v in o.data.vertices:
        t = 1.0 - (v.co.z - z[0]) / (z[1] - z[0])
        t = min(max(t, 0.0), 1.0)
        if t > 0.0:
            low.add([v.index], t, "REPLACE")
            if t < 1.0:
                up.add([v.index], 1.0 - t, "REPLACE")
            else:
                up.remove([v.index])


FOOT_X = 0.207  # the middle of the foot's sole across (|x|), from 0.121 to 0.293


def _laces(o, lib, arm, mat, swatch, ys, x=FOOT_X):
    """Two bars across the instep, on the shoe's own surface (as the Saddle shoes')."""
    on = Surface(o)
    for side, sx in (("L", 1), ("R", -1)):
        laces = lib.Piece()
        for y in ys:
            hit = on.hit((sx * x, y, 1.0), (0, 0, -1))
            laces.add(lib.cube((0.075, 0.014, 0.012)), swatch, at=(sx * x, y, hit.z + 0.003), rot=lib.rx(20), bevel=0)
        lib.join(o, laces.build(f"laces_{side}", f"Foot.{side}", arm, mat))


SKATE_LIFT = 0.08  # how far the sole rises off the ground, to z 0.19 where the ankle stays as every shoe has it
WHEEL_R, WHEEL_W = 0.05, 0.052
WHEEL_YS = (-0.175, 0.03)  # front and back axle: toe stop in front, the heel over the back one
WHEEL_X = 0.082  # from the middle of the sole: half the wheel shows outside it, half is under it
WHEEL_Z = 0.028  # its lowest point is the kit sole's own, z -0.022


def roller_skates(lib, parts, arm, mat):
    """Quad skates from the rink behind the drive-in: a high cream boot on a plate, four wheels in the trim colour and
    a toe stop. The foot cannot rise, so the boot does: its sole is lifted by a shear that dies out at the ankle, where
    the skate meets every trouser leg exactly as the kit's boot does."""
    o = parts["feet", "skates"]
    for v in o.data.vertices:
        v.co.z += SKATE_LIFT * min(max((0.19 - v.co.z) / 0.213, 0.0), 1.0)
    _laces(o, lib, arm, mat, "accent", (-0.085, -0.04))
    for side, sx in (("L", 1), ("R", -1)):
        p = lib.Piece()
        cx = sx * FOOT_X
        p.add(lib.cube((0.15, 0.27, 0.02)), "metal", at=(cx, -0.07, 0.066), bevel=0)
        for y in WHEEL_YS:
            for out in (-1, 1):
                wheel = lib.cyl(WHEEL_R, WHEEL_R, WHEEL_W, 8)
                p.add(wheel, "accent", at=(cx + out * WHEEL_X, y, WHEEL_Z), rot=lib.ry(90), bevel=0)
        p.add(lib.cyl(0.03, 0.04, 0.075, 6), "accent_shade", at=(cx, -0.262, 0.035), rot=lib.rx(-20), bevel=0)
        lib.join(o, p.build(f"skate_{side}", f"Foot.{side}", arm, mat))


BOOT_POINTS = 10  # round a boot's leg
BOOT_ZS = (0.235, 0.34, 0.45)  # from the ankle (the trousers end at z 0.187) to a hand under the knee (0.56)
BOOT_AT = (0.19, 0.01)  # the middle of the leg (|x|, y)
BOOT_FOOT = (0.125, 0.15, -0.01)  # half width, half depth and y of the ring that goes down into the foot
BOOT_HEM = 0.16  # the shaft stays as wide as the trouser leg to under its hem (z 0.187), where it came through
BOOT_CUT = 0.125  # the kit's ankle goes above this: the shaft takes its place, and it came through the shaft
BOOT_WIDE = (1.28, 1.12, -0.08)  # the foot under it, wider and longer about this y: a shaft over the trouser leg
# (r 0.155) on the kit's foot (half width 0.086) read as a bucket on a child's shoe


def _grown(row, centre, by, dz):
    """A row moved out from `centre` by `by` metres and up by `dz`."""
    out = []
    for q in row:
        d = Vector((q.x - centre.x, q.y - centre.y, 0)).normalized()
        out.append(q + d * by + Vector((0, 0, dz)))
    return out


def _boot_foot(foot, sx):
    """The shaft's lowest ring: over the foot and sunk into it, so the shaft runs down into the toe."""
    row = []
    for i in range(BOOT_POINTS):
        a = math.tau * i / BOOT_POINTS
        x, y = sx * FOOT_X + BOOT_FOOT[0] * math.sin(a), BOOT_FOOT[2] - BOOT_FOOT[1] * math.cos(a)
        hit = foot.hit((x, y, 1.0), (0, 0, -1))
        row.append(Vector((x, y, (hit.z if hit else 0.03) - 0.008)))
    return row


def _widen_foot(o):
    """Takes off the kit's ankle and widens what is left, about the middle of each foot."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    gone = [f for f in bm.faces if f.calc_center_median().z > BOOT_CUT]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for v in bm.verts:
        mid = FOOT_X if v.co.x > 0 else -FOOT_X
        v.co.x = mid + (v.co.x - mid) * BOOT_WIDE[0]
        v.co.y = BOOT_WIDE[2] + (v.co.y - BOOT_WIDE[2]) * BOOT_WIDE[1]
    bm.to_mesh(me)
    bm.free()


def rubber_boots(lib, parts, arm, mat):
    """Wellingtons from the swamp set: a tall shaft over every trouser leg, a turned band at the top and a pull tab.
    The shaft is a closed tube the leg comes out of, its top painted dark as the boot's inside, so the shorts' thinner
    bare shin needs nothing of its own."""
    o = parts["feet", "rubber"]
    _widen_foot(o)
    on = Surface(parts["legs", "trousers"], parts["legs", "cuffed"])
    foot = Surface(o)
    for side, sx in (("L", 1), ("R", -1)):
        centre = Vector((sx * BOOT_AT[0], BOOT_AT[1], 0))
        # A ray from past the leg's edge: from further it meets the other leg first.
        rows = _hugging_rows(on, centre, BOOT_ZS, BOOT_POINTS, (-0.04, 0.0, 0.04), 0.185, STAND_OFF)
        rows[:0] = [_boot_foot(foot, sx), [Vector((q.x, q.y, BOOT_HEM)) for q in rows[0]]]
        p = lib.Piece().add(tube(rows), "accent", bevel=0, smooth=True)
        p.add(
            tube([_grown(rows[-1], centre, 0.012, -0.04), _grown(rows[-1], centre, 0.012, 0.012)]),
            "accent_shade",
            bevel=0,
        )
        dark = lib.uv_of("black")
        for f in p.bm.faces:
            if f.normal.z > 0.9 and f.calc_center_median().z > 0.44:
                for loop in f.loops:
                    loop[p.uv].uv = dark
        back = rows[-1][BOOT_POINTS // 2]
        p.add(lib.cube((0.05, 0.025, 0.1)), "accent_shade", at=(back.x, back.y + 0.018, back.z - 0.01), bevel=0)
        boot = p.build(f"boot_{side}", f"LowerLeg.{side}", arm, mat)
        # Only the ring in the foot bends with it: the shaft stays with the shin down past the trousers' hem, which
        # came through its front in a bent ankle when the blend reached z 0.26.
        _blend_skin(boot, (0.1, BOOT_HEM), f"LowerLeg.{side}", f"Foot.{side}")
        lib.join(o, boot)


SKIRT_HEM_Z = 0.6  # above the knee (0.56), which it clears in a stride, and over where the hanging hands reach
SKIRT_HEM = (0.445, 0.3)  # half widths: the legs stand out to |x| 0.336, y -0.147 to 0.167
SKIRT_MID_Z = 0.74
SKIRT_MID = (0.385, 0.25)  # close over the hips, where the swinging hands pass, and all the flare below them
SKIRT_ROOF_Z = 0.84  # where the inside closes: in the hips, the legs come through it
SKIRT_PLEAT = 0.03  # how far the pleats stand in and out at the hem
SKIRT_THIGH = 0.95  # the hem's share of the thigh's turn, growing from nothing at the hips: less, the knee passed it
SKIRT_SPLIT = 0.14  # |x| past which a point goes with one thigh alone
SKIRT_LEG_TOP = 0.62  # the bare legs end here, capped, under the skirt: a raised thigh came through its wall


def _skirt_ring(z, half, pleat=0.0):
    c = WAIST_CENTRE
    out = []
    for i in range(WAIST_POINTS):
        a = math.tau * i / WAIST_POINTS
        grow = 1.0 + pleat * (1 if i % 2 else -1)
        out.append(Vector((half[0] * grow * math.sin(a), c.y - half[1] * grow * math.cos(a), z)))
    return out


def _skin_to_thighs(o):
    """The skirt below the hips splits between the thighs, as culottes would: on the hips alone a knee in a stride came
    through it. Its middle goes half with each."""
    hips = o.vertex_groups.get("Hips") or o.vertex_groups.new(name="Hips")
    left = o.vertex_groups.get("UpperLeg.L") or o.vertex_groups.new(name="UpperLeg.L")
    right = o.vertex_groups.get("UpperLeg.R") or o.vertex_groups.new(name="UpperLeg.R")
    for v in o.data.vertices:
        if v.co.z > SKIRT_ROOF_Z:
            continue
        share = SKIRT_THIGH * (SKIRT_ROOF_Z - v.co.z) / (SKIRT_ROOF_Z - SKIRT_HEM_Z)
        for g in o.vertex_groups:
            g.remove([v.index])
        to_left = min(max((v.co.x + SKIRT_SPLIT) / (2 * SKIRT_SPLIT), 0.0), 1.0)
        hips.add([v.index], 1.0 - share, "REPLACE")
        if to_left > 0.0:
            left.add([v.index], share * to_left, "REPLACE")
        if to_left < 1.0:
            right.add([v.index], share * (1.0 - to_left), "REPLACE")


def _cut_legs(o):
    """Takes the legs off at SKIRT_LEG_TOP and caps them: what is left is the knees and the shins."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, SKIRT_LEG_TOP), plane_no=(0, 0, 1), clear_outer=True)
    rim = [
        e
        for e in bm.edges
        if e.is_boundary and abs(e.verts[0].co.z - SKIRT_LEG_TOP) < 1e-4 and abs(e.verts[1].co.z - SKIRT_LEG_TOP) < 1e-4
    ]
    bmesh.ops.holes_fill(bm, edges=rim, sides=0)
    bm.to_mesh(o.data)
    bm.free()


def swing_skirt(lib, parts, arm, mat):
    """A full skirt from the dance at the drive-in: a high waist over the top's hem like the Overalls, pleats that catch
    the light in flat facets, a band at the hem and bobby socks on bare legs. It is one closed shell: from the hem the
    inside goes up to a roof in the hips, which the legs come through, so nothing shows under it."""
    o = parts["legs", "swing"]
    worn_on = [parts["torso", "jacket"], parts["legs", "trousers"]]
    rows = _waist(Surface(*worn_on))
    _cut_legs(o)
    band = lib.Piece().add(wrap([*rows, _lip(rows[-1])]), "secondary_shade", bevel=0, smooth=True)
    waist = band.build("skirt_waist", "Hips", arm, mat)
    borrow_skin(waist, worn_on, rigid=0.16)
    lib.join(o, waist)
    hem = _skirt_ring(SKIRT_HEM_Z, SKIRT_HEM, SKIRT_PLEAT)
    trim = _skirt_ring(SKIRT_HEM_Z + 0.05, tuple(h * 0.975 for h in SKIRT_HEM), SKIRT_PLEAT)
    mid = _skirt_ring(SKIRT_MID_Z, SKIRT_MID, SKIRT_PLEAT * 0.6)
    roof = _skirt_ring(SKIRT_ROOF_Z, (0.3, 0.17))
    inner = _skirt_ring(SKIRT_HEM_Z + 0.002, tuple(h * 0.94 for h in SKIRT_HEM), SKIRT_PLEAT)
    p = lib.Piece()
    p.add(wrap([trim, mid, rows[0]]), "secondary", bevel=0)
    p.add(wrap([hem, trim]), "accent", bevel=0)
    # The inside, on the same turn: going down it the faces look at the axis. Its top is closed.
    p.add(tube([roof, inner, hem], open_end=True), "secondary_shade", bevel=0)
    skirt = p.build("skirt", "Hips", arm, mat)
    borrow_skin(skirt, worn_on)  # as the waist: its top ring on the bare Hips bone parted from the waist in any pose
    _skin_to_thighs(skirt)
    lib.join(o, skirt)


PRINT_ZS = (1.095, 1.155, 1.215, 1.275, 1.335)
PRINT_HALF = (0.085, 0.165, 0.185, 0.17, 0.115)  # the head on the shirt: a wide jaw under a low skull


def _facing(on, x, z, reach):
    """The y a flat print rests at on the sheet at (x, z)."""
    return on.front_over(x, z, reach, 0.02).y


def _dots(cx, cz, rx, rz, n):
    """A ring of `n` points about (cx, cz), counter-clockwise from the front."""
    return [(cx + rx * math.cos(a), cz + rz * math.sin(a)) for a in (math.tau * i / n for i in range(n))]


def creature_tee(lib, parts, arm, mat):
    """A souvenir shirt from the double bill: the night's monster printed big on the chest with bulging eyes and a
    jagged grin, its fins printed down the spine for the shoulder camera, and a ringed collar. It rests on the shirt
    above her chest's fullest line, so the print keeps its shape on both bodies."""
    o = parts["torso", "creature"]
    on = Surface(o)
    xs = (-1.0, -0.5, 0.0, 0.5, 1.0)
    sheet = [[on.front_over(x * half, z, 0.03, 0.012) for x in xs] for z, half in zip(PRINT_ZS, PRINT_HALF)]
    p = lib.Piece().add(panel(sheet, 0.03), "accent", bevel=0)
    for sx in (-1, 1):
        ex, ez = sx * 0.082, 1.262
        y = _facing(on, ex, ez, 0.05)
        p.add(plate(_dots(ex, ez, 0.056, 0.05, 8), y, 0.012), "amber", bevel=0)
        p.add(plate(_dots(ex, ez, 0.016, 0.04, 4), y - 0.004, 0.012), "black", bevel=0)
        fin = [(sx * 0.13 + 0.05 * sx * s, 1.325 + h) for s, h in ((1, 0.0), (0.3, 0.05), (-1, 0.0))]
        y = _facing(on, sx * 0.13, 1.33, 0.05)
        p.add(plate(fin if sx > 0 else list(reversed(fin)), y, 0.012), "accent_shade", bevel=0)
    gape = [(-0.125, 1.205), (-0.085, 1.165), (0.085, 1.165), (0.125, 1.205), (0.06, 1.19), (-0.06, 1.19)]
    y = _facing(on, 0.0, 1.185, 0.09)
    p.add(plate(gape, y, 0.012), "mouth", bevel=0)
    for x in (-0.06, -0.02, 0.02, 0.06):
        p.add(plate([(x - 0.017, 1.192), (x, 1.158), (x + 0.017, 1.192)], y - 0.004, 0.012), "white", bevel=0)
    # The spine: fins down the back, each lying along it, on the shirt's own surface (the back slopes).
    for z, w, h in ((1.33, 0.085, 0.085), (1.235, 0.075, 0.075), (1.145, 0.06, 0.06)):
        low, high = on.back(0.0, z, 0.0), on.back(0.0, z + h, 0.0)
        tilt = lib.rx(math.degrees(math.atan2(high.y - low.y, high.z - low.z)))
        p.add(plate([(-w, 0.0), (w, 0.0), (0.0, h)], 0.012, -0.03), "accent", at=low, rot=tilt, bevel=0)
    prints = p.build("creature_print", "Torso", arm, mat)
    borrow_skin(prints, [o], rigid=0.14)
    lib.join(o, prints)


def _star(cx, cz, r, inner=0.44):
    pts = []
    for i in range(10):
        a = math.pi / 2 + math.tau * i / 10
        k = r if i % 2 == 0 else r * inner
        pts.append((cx + k * math.cos(a), cz + k * math.sin(a)))
    return pts


def seated_star(cx, cz, r, seat, into):
    """A star lying on a curved surface: `seat(x, z)` gives each point's place, and its rim is turned along `into` under
    the surface. A flat star on the jacket's back lost its points under the curve."""

    def make(bm):
        rim = [bm.verts.new(seat(x, z)) for x, z in _star(cx, cz, r)]
        mid = bm.verts.new(seat(cx, cz))
        under = [bm.verts.new(v.co + into) for v in rim]
        n = len(rim)
        for i in range(n):
            j = (i + 1) % n
            _face(bm, [mid, rim[i], rim[j]], mid.co + into)
            _face(bm, [rim[i], under[i], under[j], rim[j]], mid.co)

    return make


VARSITY_STRIPES = ((0.415, 0.475),)  # across the sleeve, |x| at rest: under the shoulder, over the elbow; a second band
# went over the budget (each cut crosses the long sleeve faces)


def cut_sleeve(o, lib, bands, swatch, of="primary"):
    """Cuts `bands` (|x| at rest, the arms along X) round both sleeves and paints them: a ring laid over the sleeve stood
    clear of it, where the arm is thinner than the shoulder."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    key = Vector(lib.uv_of(of))

    def sleeve(f):
        return (Vector(f.loops[0][uv].uv) - key).length < 1e-4 and abs(f.calc_center_median().x) > 0.3

    for sx in (-1, 1):
        for x in (edge for band in bands for edge in band):
            faces = [f for f in bm.faces if sleeve(f) and f.calc_center_median().x * sx > 0]
            geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(sx * x, 0, 0), plane_no=(1, 0, 0))
    u = lib.uv_of(swatch)
    for f in bm.faces:
        if sleeve(f) and any(a < abs(f.calc_center_median().x) < b for a, b in bands):
            for loop in f.loops:
                loop[uv].uv = u
    bm.to_mesh(me)
    bm.free()


def varsity_gold(lib, parts, arm, mat):
    """The last rung's jacket: a gold body (a fixed swatch, so it reads gold on everyone) with sleeves in the look's own
    colour, two stripes on each arm, a star on the chest and a big one on the back for the shoulder camera."""
    o = parts["torso", "varsity"]
    on = Surface(o)
    cut_sleeve(o, lib, VARSITY_STRIPES, "white")
    p = lib.Piece()
    # Above her chest's fullest line: on it the star's points fell between the jacket's vertices and sank.
    p.add(seated_star(0.125, 1.335, 0.07, lambda x, z: on.front(x, z, 0.012), Vector((0, 0.03, 0))), "primary", bevel=0)
    p.add(seated_star(0.0, 1.235, 0.15, lambda x, z: on.back(x, z, 0.012), Vector((0, -0.03, 0))), "primary", bevel=0)
    bits = p.build("varsity_bits", "Torso", arm, mat)
    borrow_skin(bits, [o])
    lib.join(o, bits)


FILM_WIDTH = 0.105  # a frame across: the film's height on the neck
FILM_RING = (0.262, 0.255, 1.462)  # the band's middle: half widths and height; a tall collar's funnel comes out of it
FILM_POINTS = 12


def film_strip(p, lib, points, normals, width, thick, closed=False):
    """A strip of film on a `Piece`: a `ribbon` whose outer face shows the atlas's film frame once a segment, the rest
    black. Every frame is one quad: drawn in faces, the sprocket holes alone would take the whole far budget."""
    bm, layer = p.bm, p.uv
    u0, v0, u1, v1 = lib.uv_cell("film")
    black = lib.uv_of("black")
    rings = []
    n = len(points)
    for i, (at, nor) in enumerate(zip(points, normals)):
        a = points[(i - 1) % n] if closed or i else at
        b = points[(i + 1) % n] if closed or i < n - 1 else at
        side = (b - a).cross(nor).normalized() * (width / 2)
        out = nor.normalized() * (thick / 2)
        rings.append([bm.verts.new(at + s * side + o * out) for s, o in ((-1, -1), (1, -1), (1, 1), (-1, 1))])

    def paint(f, uv=None):
        for loop in f.loops:
            loop[layer].uv = uv(loop.vert) if uv else black

    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        mid = (points[i] + points[j]) / 2
        for k in range(4):
            m = (k + 1) % 4
            f = _face(bm, [rings[i][k], rings[i][m], rings[j][m], rings[j][k]], mid)
            if k == 2:  # the outer face

                def frame(v, ring=rings[i], next_ring=rings[j]):
                    return (u1 if v in next_ring else u0, v1 if v in (ring[3], next_ring[3]) else v0)

                paint(f, frame)
            else:
                paint(f)
    if not closed:
        for ring, towards in ((rings[0], points[1]), (rings[-1], points[-2])):
            paint(_face(bm, ring, towards))


def film_scarf(lib, parts, arm, mat):
    """A length of a reel's film thrown round the neck: one loop, and two ends down the chest, frame after frame."""
    p = lib.Piece()
    ring, normals = [], []
    for i in range(FILM_POINTS):
        a = math.tau * i / FILM_POINTS
        d = Vector((math.sin(a), -math.cos(a), 0))
        # A little lower at the front than behind: thrown on, not fitted.
        ring.append(Vector((FILM_RING[0] * d.x, FILM_RING[1] * d.y, FILM_RING[2] - 0.022 * math.cos(a))))
        normals.append((d + Vector((0, 0, 0.55))).normalized())  # it lies on the shoulders, looking out and up
    film_strip(p, lib, ring, normals, FILM_WIDTH, 0.09, closed=True)  # thick: its top closes the gap to the neck
    ends = lib.Piece()
    y = PART_FRONT
    for path in (
        [(0.105, -0.335, 1.45), (0.125, y - 0.016, 1.345), (0.112, y, 1.24), (0.128, y, 1.135), (0.118, y, 1.03)],
        [(-0.085, -0.335, 1.45), (-0.105, y - 0.016, 1.345), (-0.092, y, 1.24), (-0.108, y, 1.135)],
    ):
        points = [Vector(c) for c in path]
        film_strip(ends, lib, points, [Vector((0, -1, 0.12))] * len(points), FILM_WIDTH * 0.9, 0.012)
    o = p.build("neck__film", "Neck", arm, mat)
    tails = ends.build("film_ends", "Neck", arm, mat)
    hang_from_torso(tails, 1.38)
    lib.join(o, tails)
    return o


MASK_POINTS = 14
MASK_Y = -0.03
# The head's shell, bottom to top: (z, half width, half depth). Wider than the jaw (r 0.34) and the tall collar's top
# (r 0.36), so the head turns inside it; its floor is above the vest's pads (z 1.59) and under the chin (z 1.637).
MASK_RINGS = ((1.605, 0.375, 0.365), (1.68, 0.425, 0.415), (1.82, 0.43, 0.42), (1.96, 0.395, 0.39),
              (2.10, 0.325, 0.33), (2.215, 0.20, 0.205))  # fmt: skip
MASK_LIP = 0.012  # how far the mouth stands proud of the shell's vertices (the shell's chords fall in about 11 mm)
# The crest down the middle, on the shell's midline, brow to nape: (y, z, base half length, height).
MASK_CREST = ((-0.325, 2.135, 0.075, 0.085), (-0.185, 2.215, 0.08, 0.1), (-0.03, 2.225, 0.085, 0.115),
              (0.13, 2.215, 0.085, 0.115), (0.265, 2.12, 0.085, 0.11), (0.345, 1.985, 0.085, 0.105),
              (0.395, 1.84, 0.075, 0.085))  # fmt: skip
MASK_GILLS = (1.73, 1.8, 1.87)  # three slits a side, behind the fans, where the shoulder camera sees them


def _shell_at(z):
    """The mask's half width and depth at a height."""
    for (z0, w0, d0), (z1, w1, d1) in itertools.pairwise(MASK_RINGS):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            return w0 + (w1 - w0) * t, d0 + (d1 - d0) * t
    raise ValueError(z)


def _on_mask(deg, z, out=0.0):
    w, d = _shell_at(z)
    a = math.radians(deg)
    return Vector(((w + out) * math.sin(a), MASK_Y - (d + out) * math.cos(a), z))


def creature_mask(lib, arm, mat):
    """A rubber head from the second feature: a wide toad's skull, two bulging eyes under angry brows, a gash of a mouth
    with teeth that do not match, a crest of fins from the brow to the nape, gill slits and a fan at each ear. It hides
    the hair and the eyewear: nothing worn on the head fits inside. The floor is closed, so the neck comes out of a
    closed shell."""
    rows = []
    for z, _w, _d in MASK_RINGS:
        rows.append([_on_mask(360 * i / MASK_POINTS, z) for i in range(MASK_POINTS)])
    p = lib.Piece().add(tube(rows), "primary", bevel=0, smooth=True, under="primary_shade")
    for sx in (-1, 1):
        at = _on_mask(sx * 30, 2.0, -0.01)
        p.add(lib.sphere(0.098, 8, 5), "amber", at=at, bevel=0, smooth=True)
        pupil = (at.x + sx * 0.012, at.y - 0.09, at.z)
        p.add(lib.cube((0.032, 0.014, 0.1)), "black", at=pupil, rot=lib.ry(-sx * 10), bevel=0)
        brow = _on_mask(sx * 24, 2.105, -0.004)
        p.add(lib.cube((0.215, 0.09, 0.05)), "primary_shade", at=brow, rot=lib.ry(-sx * 18) @ lib.rz(sx * 22), bevel=0)
        fan = [(0.0, 0.07), (0.0, -0.07), (0.1, -0.1), (0.17, -0.03), (0.17, 0.05), (0.1, 0.12)]
        points = [(sx * x, z) for x, z in fan]
        p.add(plate(points if sx > 0 else list(reversed(points)), -0.02, 0.04), "accent",
              at=_on_mask(sx * 90, 1.85, -0.03), rot=lib.rz(sx * 25), bevel=0)  # fmt: skip
        for z in MASK_GILLS:
            p.add(
                lib.cube((0.14, 0.03, 0.022)),
                "primary_shade",
                at=_on_mask(sx * 122, z, -0.004),
                rot=lib.rz(sx * 122),
                bevel=0,
            )
    degs = tuple(range(-64, 65, 16))
    low = [_on_mask(a, 1.665 + 0.0005 * abs(a), MASK_LIP) for a in degs]
    high = [_on_mask(a, 1.765 + 0.0009 * abs(a) - 0.05 * (1 - abs(a) / 64), MASK_LIP) for a in degs]
    p.add(panel([low, high], 0.1), "mouth", bevel=0)
    for deg, length in ((-44, 0.075), (-27, 0.1), (-10, 0.06), (9, 0.09), (28, 0.065), (45, 0.1)):
        z = 1.765 + 0.0009 * abs(deg) - 0.05 * (1 - abs(deg) / 64)
        p.add(lib.cyl(0.0, 0.03, length, 4), "white", at=_on_mask(deg, z - length / 2, MASK_LIP), bevel=0)
    for deg in (-34, 34):
        z = 1.665 + 0.0005 * abs(deg)
        p.add(lib.cyl(0.03, 0.0, 0.085, 4), "white", at=_on_mask(deg, z + 0.04, MASK_LIP), bevel=0)
    for y, z, half, height in MASK_CREST:
        # Standing on the shell, leaning the way it faces there, its foot sunk into it.
        lean = math.degrees(math.atan2(-(y - MASK_Y) / 0.40, (z - 1.90) / 0.33))
        fin = [(-half, -0.06), (half, -0.06), (half * 0.9, 0.0), (half * 0.55, height)]
        p.add(plate(fin, -0.034, 0.068), "accent", at=(0, y, z), rot=lib.rx(lean) @ lib.rz(90), bevel=0)
    return p.build("headwear__creature", "Head", arm, mat)


def build(lib, parts, arm, mat):
    """Dress the parts built from the kit body and return the new pieces, {(slot, part): object}."""
    usher_jacket(lib, parts, arm, mat)
    coveralls(lib, parts, arm, mat)
    overalls(lib, parts, arm, mat)
    saddle_shoes(lib, parts, arm, mat)
    roller_skates(lib, parts, arm, mat)
    rubber_boots(lib, parts, arm, mat)
    swing_skirt(lib, parts, arm, mat)
    creature_tee(lib, parts, arm, mat)
    varsity_gold(lib, parts, arm, mat)
    new = {
        ("eyewear", "cinema"): cinema_glasses(lib, arm, mat),
        ("headwear", "visor"): projectionist_visor(lib, arm, mat),
        ("headwear", "creature"): creature_mask(lib, arm, mat),
        ("neck", "film"): film_scarf(lib, parts, arm, mat),
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
