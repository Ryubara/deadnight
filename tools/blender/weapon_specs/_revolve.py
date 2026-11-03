"""A round part turned about an axis along X (a barrel's), for the weapon modules (#797). Not a weapon: its name
starts with `_`, so `build_weapons.py` never builds it. `weaponlib.Builder.lathe` turns about Z only; a tank lying
along the gun, a flared nozzle or a bezel ring with a hole needs the turn along the barrel.

    import sys; sys.path.insert(0, str(Path(__file__).resolve().parent)); from _revolve import revolve_x
"""

import itertools
import math

import bmesh


def revolve_x(b, profile, colour, segs=14, y=0.0, z=0.0, closed=False, detail=False, far=None):
    """Turn a profile [(x, radius), ...] about the line (y, z) along X.

    Open (`closed=False`): the first and last rings are capped, like `Builder.lathe` (a tank with rounded ends).
    Closed: the profile is a loop and its last point joins the first, so the part has a hole along its axis (a bezel
    ring, a nozzle's flare). The chamfers are in the profile; the part is never bevelled again. The far level halves
    the sides (at least 6) and turns `far` when given: a shorter profile of the same outline, drawn by hand, because
    keeping every other point of a rounded end (as `Builder.lathe` does) made the tank's two ends unlike.
    """
    if not b.near:
        segs = max(6, segs // 2)
        profile = far or profile
    bm = bmesh.new()
    rings = []
    for x, r in profile:
        ring = []
        for i in range(segs):
            a = 2 * math.pi * (i + 0.5) / segs
            ring.append(bm.verts.new((x, y + r * math.cos(a), z + r * math.sin(a))))
        rings.append(ring)
    pairs = list(itertools.pairwise(rings))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for ra, rb in pairs:
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return b._finish(bm, colour, 0, detail)
