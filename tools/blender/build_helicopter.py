"""Build Deadnight's rescue helicopter (#1057): the arrival cutscene's aircraft, our own design.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_helicopter.py -- [--out game/assets/helicopter]

An invented 1958 utility machine in the style bible's look (chunky shapes, flat colours, one-segment chamfers; it
copies no real aircraft and no game's model): a lofted hull with a bubble canopy, a boxy cabin with a wide open door
on its +X side, a tapering tail boom, skids, an engine hump, a two-bladed main rotor and a small tail rotor. It is
modelled at game scale (metres, a player is 1.8 m) on one palette atlas and one material, every face on one swatch.

The pieces are a contract with the game; Blender (x, y, z) is Godot (x, z, -y):

- The origin is on the ground plane under the mast, the skids' bottom at height 0, the nose to Blender +Y (Godot -Z).
- `Body`: everything that does not spin.
- `MainRotor`: origin at the mast top, spins about its Z (Godot Y).
- `TailRotor`: origin at its hub on the +X side of the fin, spins about its X (Godot X).
- `RopeAnchor`: an empty under the hoist's pulley at the top edge of the door, outside the door's plane, so a rope
  hung straight down clears the sill and the skid.
- `Searchlight`: an empty under the belly at the lamp's lens, in front of the skid's cross tube; its -Z in Godot
  points straight down, so a SpotLight3D under it shines at the ground.

All of them are flat in one export (`<out>/helicopter.gltf` + `.bin` on `helicopter_palette.png`). The build reads
the glTF back, fails if a node moved or the Searchlight stopped pointing down, and writes `<out>/helicopter.json`.
A `PROP` line gives triangles and size.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from palette_import import ensure_import

ROUGHNESS = 0.415  # the kit's
METALLIC = 0.0  # paint; the kit's 0.4 reads as dark at night
SWATCH_PX = 16
GRID = 4
BUDGET = 1500  # shown for a few seconds on phones

# The kit's colours and the drive-in's cream and glass (style bible, Colour and materials), near the 1958 lot's paint.
PALETTE = {
    "Olive": "#496321",  # the kit's military Green
    "OliveLight": "#5c6d37",  # the Soldier's olive, for what the camera sees from above
    "OliveDeep": "#3a4f1b",
    "Cream": "#e6d8b0",
    "Grey": "#818491",
    "Grey2": "#5f5f5f",
    "DarkGrey": "#414141",
    "Black": "#252525",
    "Glass": "#5d7891",
    "Red": "#8c3735",
    "Lamp": "#f2dc8c",
}

BEVEL = 0.03  # parts of 1-3 m
BIG_BEVEL = 0.08  # the style bible's chamfer for large props

# The hull's profile, nose to tail: (y, belly z, roof z, half width, how round the section is, 0 boxy to 1 round).
HULL = [
    (3.60, 1.30, 1.80, 0.30, 1.0),  # the nose's tip
    (3.38, 0.98, 2.18, 0.72, 1.0),
    (2.95, 0.80, 2.60, 1.02, 1.0),
    (2.35, 0.72, 2.88, 1.18, 0.8),
    (1.20, 0.70, 3.00, 1.22, 0.0),  # the cabin, the door between these two stations
    (-1.20, 0.70, 3.00, 1.22, 0.0),
    (-2.05, 0.88, 3.00, 1.12, 0.25),
    (-2.85, 1.70, 2.98, 0.72, 0.6),
    (-3.60, 2.22, 2.92, 0.36, 0.8),  # the boom's root
    (-4.95, 2.40, 2.93, 0.25, 0.8),
    (-5.25, 2.44, 2.93, 0.23, 0.8),  # the red band
    (-6.00, 2.55, 2.95, 0.17, 0.8),  # the boom's end
]
DOOR_SEG = 4  # the hull segment the door is cut out of (y +1.2 to -1.2)
# One side of a section, bottom to top: (fraction of the half width, fraction of the height). The section is this and
# its mirror; the door's sill and top and the cream stripe's two edges are rows, so paint and hole fall on real edges.
ROWS = [
    (0.62, 0.00),
    (0.92, 0.045),
    (1.00, 0.13),  # the door's sill
    (1.00, 0.47),  # the stripe
    (1.00, 0.56),
    (1.00, 0.88),  # the door's top: 1.72 m clear, the Soldier stands 1.75
    (0.86, 0.97),
    (0.52, 1.00),
]
RING = 2 * len(ROWS)
DOOR_X = HULL[DOOR_SEG][3]
SILL_Z = HULL[DOOR_SEG][1] + ROWS[2][1] * (HULL[DOOR_SEG][2] - HULL[DOOR_SEG][1])
DOOR_TOP_Z = HULL[DOOR_SEG][1] + ROWS[5][1] * (HULL[DOOR_SEG][2] - HULL[DOOR_SEG][1])
DOOR_HALF_Y = HULL[DOOR_SEG][0]

SKID_X = 1.15  # the rail's middle: its outer face stays inside the rope's line
MAST_TOP = 3.9
ROTOR_R = 4.25
TAIL_HUB = (0.3, -5.85, 3.0)
TAIL_R = 0.72
ROPE_X = 1.42  # 0.13 m past the sill's frame (1.29) and 0.2 m past the skid's outer face (1.22)
ROPE = (ROPE_X, 0.0, 2.7)
LAMP = (0.0, 2.25, 0.47)  # the lens's face: the cross tube is at y 1.45


class Part:
    """Collects the parts of one mesh in one bmesh with a UV layer, every face on its part's swatch. Coordinates are
    the helicopter's own; the object is built round `origin`, so its pivot is there and its node sits there."""

    def __init__(self, name, origin=(0, 0, 0)):
        self.name = name
        self.origin = Vector(origin)
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def box(self, size, at, colour, bevel=BEVEL, rot=(0, 0, 0)):
        """A box of `size` (x, y, z) centred at `at`, rotated by `rot` (degrees, XYZ) about its centre."""
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        bmesh.ops.scale(tmp, vec=Vector(size), verts=tmp.verts)
        b = min(bevel, min(size) * 0.3)
        if b > 0.002:
            bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=b, segments=1, affect="EDGES", profile=0.5)
        self._merge(tmp, colour, at, rot)

    def cyl(self, r, h, at, colour, sides=8, rot=(0, 0, 0), r2=None):
        """A cylinder (or a cone with top radius `r2`) of height `h` along Z, centred at `at`, then rotated."""
        tmp = bmesh.new()
        bmesh.ops.create_cone(
            tmp, cap_ends=True, cap_tris=False, segments=sides, radius1=r, radius2=r if r2 is None else r2, depth=h
        )
        self._merge(tmp, colour, at, rot)

    def prism(self, outline, x0, x1, colour):
        """A flat plate: the (y, z) `outline`, thick from x0 to x1 (the fins)."""
        tmp = bmesh.new()
        lo = [tmp.verts.new((x0, y, z)) for y, z in outline]
        hi = [tmp.verts.new((x1, y, z)) for y, z in outline]
        tmp.faces.new(lo)
        tmp.faces.new(hi)
        n = len(outline)
        for i in range(n):
            j = (i + 1) % n
            tmp.faces.new((lo[i], lo[j], hi[j], hi[i]))
        self._merge(tmp, colour, (0, 0, 0), (0, 0, 0))

    def loft(self, stations, paint, skip=None, cap_front="Olive", cap_rear="Olive"):
        """A shell through `stations` (`HULL`'s form), nose first. `paint(segment, edge)` names each quad's swatch,
        where edge runs round the section from the bottom of the +X side; `skip(segment, edge)` leaves a hole. A
        `None` cap leaves that end open. Wound by hand, normals out: a hole has no closed island to recalculate."""
        rings = [[self.bm.verts.new(p) for p in section(s)] for s in stations]
        for i in range(len(rings) - 1):
            for k in range(RING):
                if skip and skip(i, k):
                    continue
                j = (k + 1) % RING
                face = self.bm.faces.new((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]))
                self._paint(face, paint(i, k))
        if cap_front:
            self._paint(self.bm.faces.new(list(reversed(rings[0]))), cap_front)
        if cap_rear:
            self._paint(self.bm.faces.new(rings[-1]), cap_rear)

    def quad(self, corners, colour):
        """One face seen from the side its corners turn anticlockwise (the cabin's inside walls)."""
        self._paint(self.bm.faces.new([self.bm.verts.new(c) for c in corners]), colour)

    def _paint(self, face, colour):
        u = swatch_uv(colour)
        for loop in face.loops:
            loop[self.uv].uv = u

    def _merge(self, tmp, colour, at, rot):
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)  # each piece is closed; the hull's holes never come here
        m = Matrix.Translation(Vector(at)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
        bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        n0 = len(self.bm.faces)
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        self.bm.faces.ensure_lookup_table()
        for f in self.bm.faces[n0:]:
            self._paint(f, colour)

    def obj(self, material):
        bmesh.ops.translate(self.bm, vec=-self.origin, verts=self.bm.verts)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = False
        me.materials.append(material)
        o = bpy.data.objects.new(self.name, me)
        o.location = self.origin
        bpy.context.scene.collection.objects.link(o)
        return o


def section(station):
    """The ring of a hull station: its +X side bottom to top, then the -X side top to bottom."""
    y, belly, roof, half, round_ = station
    side = []
    for fx, fz in ROWS:
        ellipse = max(0.3, math.sqrt(max(0.0, 1 - (2 * fz - 1) ** 2)))
        side.append(((fx * (1 - round_) + ellipse * round_) * half, y, belly + fz * (roof - belly)))
    return side + [(-x, py, z) for x, py, z in reversed(side)]


def height(k):
    """An edge of the ring as its row up the side, the same on both sides: 0-6 the side, 7 the roof, -1 the belly."""
    return -1 if k == RING - 1 else min(k, RING - 2 - k)


def hex_rgb(h):
    return tuple(int(h[i : i + 2], 16) / 255 for i in (1, 3, 5))


def swatch_uv(name):
    i = list(PALETTE).index(name)
    col, row = i % GRID, i // GRID
    return Vector(((col + 0.5) / GRID, 1 - (row + 0.5) / GRID))


def palette_image(path):
    size = GRID * SWATCH_PX
    img = bpy.data.images.new("helicopter_palette", size, size, alpha=False)
    img.colorspace_settings.name = "sRGB"
    px = [0.0] * (size * size * 4)
    for i, h in enumerate(PALETTE.values()):
        rgb = hex_rgb(h)
        col, row = i % GRID, i // GRID
        for y in range(SWATCH_PX):
            for x in range(SWATCH_PX):
                py = size - 1 - (row * SWATCH_PX + y)  # Blender's pixel rows start at the bottom
                k = (py * size + col * SWATCH_PX + x) * 4
                px[k : k + 4] = [*rgb, 1.0]  # a byte image's `pixels` are its stored values: the sRGB hex as it is
    img.pixels = px
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    ensure_import(path)  # lossless, no mipmaps, Detect 3D off (tools/check_texture_imports.py)
    return img


def atlas_material(img):
    m = bpy.data.materials.new("Helicopter")
    m.use_backface_culling = True
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    bsdf.inputs["Metallic"].default_value = METALLIC
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


# --- The model -------------------------------------------------------------------------------------------------------


def hull_paint(i, k):
    h = height(k)
    if i == 9:
        return "Red"  # the band that says tail from above
    if h == 3:
        return "Cream"  # the belt line, nose to tail
    if h <= 1:
        return "OliveDeep"
    if i <= 2:
        return "OliveLight" if h == 7 else "Glass"  # the bubble with a frame down its middle
    if i == 3 and h in (4, 5):
        return "Glass"  # the cockpit's side windows
    if i >= 3 and h == 7:
        return "OliveLight"  # the roof, boom included: what the camera sees most of
    return "Olive"


def door_hole(i, k):
    return i == DOOR_SEG and k in (2, 3, 4)


def hump_paint(i, k):
    h = height(k)
    if i in (1, 2) and h in (3, 4):
        return "DarkGrey"  # the cooling louvres
    return "Olive" if h <= 5 else "Grey2"


def hump_hidden(_i, k):
    return height(k) <= 0


def cabin(p):
    """The cabin behind the open door: inward faces on the hole's edges, then what the door shows."""
    x0, x1, y0, y1, z0, z1 = -0.98, DOOR_X, -DOOR_HALF_Y, DOOR_HALF_Y, SILL_Z, DOOR_TOP_Z
    y0, y1 = sorted((y0, y1))
    p.quad(((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)), "Grey2")  # the floor
    p.quad(((x0, y0, z1), (x0, y1, z1), (x1, y1, z1), (x1, y0, z1)), "Black")  # the ceiling
    p.quad(((x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)), "Black")  # the far wall
    p.quad(((x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)), "Black")  # the bulkheads
    p.quad(((x1, y0, z0), (x0, y0, z0), (x0, y0, z1), (x1, y0, z1)), "Black")
    # A bench along the far wall, two red first-aid boxes on the floor.
    p.box((0.46, 2.0, 0.09), (-0.74, 0, z0 + 0.48), "Cream", 0.0)
    for y in (-0.8, 0.8):
        p.box((0.36, 0.08, 0.46), (-0.74, y, z0 + 0.23), "Grey", 0.0)
    p.box((0.34, 0.5, 0.3), (0.0, -0.8, z0 + 0.15), "Red", 0.0)
    # The door's frame: cream round the opening, so it reads as a door from the air; a steel sill.
    w = 0.09
    p.box((w, 2 * DOOR_HALF_Y + w, w), (DOOR_X, 0, z1), "Cream", 0.0)
    p.box((0.14, 2 * DOOR_HALF_Y + w, w), (DOOR_X, 0, z0), "Grey", 0.0)
    for y in (-DOOR_HALF_Y, DOOR_HALF_Y):
        p.box((w, w, z1 - z0), (DOOR_X, y, (z0 + z1) / 2), "Cream", 0.0)


def hoist(p):
    """The rescue hoist over the door: an arm out of the shoulder, a stay from the roof, the pulley block at its tip."""
    ax, az = ROPE_X, 2.85
    p.box((ax + 0.1 - 0.8, 0.16, 0.14), ((ax + 0.1 + 0.8) / 2, 0, az), "DarkGrey", 0.0)
    x0, z0, x1, z1 = 0.62, 3.04, ax - 0.02, az + 0.04
    a = math.degrees(math.atan2(z0 - z1, x1 - x0))
    p.box((math.hypot(x1 - x0, z1 - z0), 0.07, 0.07), ((x0 + x1) / 2, 0, (z0 + z1) / 2), "Grey", 0.0, rot=(0, a, 0))
    p.box((0.16, 0.14, 0.13), (ax, 0, ROPE[2] + 0.075), "Red", 0.0)


def skids(p):
    for s in (-1, 1):
        x = s * SKID_X
        p.box((0.14, 4.3, 0.14), (x, -0.1, 0.07), "DarkGrey", 0.0)  # the rail
        y0, z0, y1, z1 = 2.0, 0.07, 2.5, 0.36
        a = math.degrees(math.atan2(z1 - z0, y1 - y0))
        p.box(
            (0.14, math.hypot(y1 - y0, z1 - z0) + 0.1, 0.14),
            (x, (y0 + y1) / 2, 0.09 + (z1 - z0) / 2),
            "DarkGrey",
            0.0,
            rot=(a, 0, 0),
        )
    for y in (1.45, -1.45):
        p.box((1.5, 0.12, 0.12), (0, y, 0.62), "Grey2", 0.0)  # the cross tube under the belly
        for s in (-1, 1):
            x0, x1, z0, z1 = s * 0.74, s * SKID_X, 0.62, 0.12
            a = math.degrees(math.atan2(z0 - z1, x1 - x0))
            p.box(
                (math.hypot(x1 - x0, z1 - z0) + 0.1, 0.12, 0.12),
                ((x0 + x1) / 2, y, (z0 + z1) / 2),
                "Grey2",
                0.0,
                rot=(0, a, 0),
            )


def tail(p):
    p.prism([(-5.2, 2.86), (-6.02, 2.8), (-6.42, 3.76), (-6.02, 3.76)], -0.06, 0.06, "Olive")  # the fin
    p.prism([(-6.02, 3.76), (-6.42, 3.76), (-6.47, 3.88), (-6.1, 3.88)], -0.065, 0.065, "Red")  # its cap
    p.prism([(-5.4, 2.6), (-6.0, 2.56), (-6.26, 2.12), (-6.0, 2.12)], -0.05, 0.05, "OliveDeep")  # the ventral fin
    p.box((1.8, 0.46, 0.06), (0, -4.55, 2.62), "OliveLight", 0.0)  # the stabiliser
    for s in (-1, 1):
        p.box((0.06, 0.5, 0.3), (s * 0.9, -4.55, 2.62), "Cream", 0.0)  # its end plates
    p.box((0.2, 0.34, 0.34), (TAIL_HUB[0] - 0.12, TAIL_HUB[1], TAIL_HUB[2]), "DarkGrey", 0.0)  # the tail gearbox
    p.box((0.08, 3.1, 0.07), (0, -3.35, 2.945), "DarkGrey", 0.0)  # the drive shaft's cover


def engine(p):
    stations = [
        (1.05, 2.96, 3.1, 0.44, 1.0),
        (0.6, 2.96, 3.48, 0.72, 0.4),
        (-0.7, 2.96, 3.54, 0.76, 0.2),
        (-1.5, 2.96, 3.3, 0.56, 0.6),
        (-2.1, 2.96, 3.03, 0.26, 1.0),
    ]
    p.loft(stations, hump_paint, skip=hump_hidden, cap_front="Olive", cap_rear="Olive")
    p.cyl(0.13, 0.5, (0, 0, MAST_TOP - 0.25), "Grey", sides=8)  # the mast
    p.cyl(0.3, 0.1, (0, 0, 3.58), "DarkGrey", sides=8)  # its collar on the hump
    p.cyl(0.11, 0.5, (0.42, -1.75, 3.2), "Black", sides=6, rot=(80, 0, 0))  # the exhaust, off to the door side's rear
    p.cyl(0.1, 0.16, (0, -0.72, 3.6), "Red", sides=6)  # the beacon on the crown


def searchlight(p):
    x, y, z = LAMP
    p.box((0.14, 0.14, 0.2), (x, y, z + 0.27), "DarkGrey", 0.0)  # the bracket off the belly
    p.cyl(0.21, 0.2, (x, y, z + 0.13), "Grey2", sides=8)
    p.cyl(0.24, 0.05, (x, y, z + 0.045), "Black", sides=8)  # the bezel
    p.cyl(0.18, 0.03, (x, y, z + 0.015), "Lamp", sides=8)  # the lens, its face at the empty


def body(p):
    p.loft(HULL, hull_paint, skip=door_hole, cap_front="OliveDeep", cap_rear="Red")
    cabin(p)
    hoist(p)
    skids(p)
    tail(p)
    engine(p)
    searchlight(p)
    # The closed side: two windows, so the -X side is not a blank wall.
    for y in (-0.62, 0.62):
        p.box((0.04, 0.96, 0.46), (-DOOR_X, y, 2.28), "Glass", 0.0)


def main_rotor(p):
    z = MAST_TOP
    p.cyl(0.3, 0.2, (0, 0, z), "DarkGrey", sides=8)
    p.cyl(0.14, 0.14, (0, 0, z + 0.16), "Grey2", sides=8)
    p.box((1.3, 0.24, 0.1), (0, 0, z), "Grey2", 0.0)  # the blade grips
    tip = 0.32
    for s in (-1, 1):
        root = 0.55
        length = ROTOR_R - tip - root
        p.box((length, 0.38, 0.06), (s * (root + length / 2), 0, z), "Grey", 0.0)
        p.box((tip, 0.38, 0.06), (s * (ROTOR_R - tip / 2), 0, z), "Black", 0.0)


def tail_rotor(p):
    x, y, z = TAIL_HUB
    p.cyl(0.1, 0.16, (x, y, z), "DarkGrey", sides=6, rot=(0, 90, 0))
    tip = 0.14
    for s in (-1, 1):
        root = 0.06
        length = TAIL_R - tip - root
        p.box((0.03, 0.17, length), (x, y, z + s * (root + length / 2)), "Grey", 0.0)
        p.box((0.03, 0.17, tip), (x, y, z + s * (TAIL_R - tip / 2)), "Red", 0.0)


# --- Export and check ------------------------------------------------------------------------------------------------


def godot(v):
    """Blender (x, y, z) as Godot (x, y up, z)."""
    return [round(v[0], 3), round(v[2], 3), round(-v[1], 3) + 0.0]


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def export(objects, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLTF_SEPARATE",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_keep_originals=True,
        export_normals=True,
    )


def check_gltf(path, expected):
    """Read the file the game will load: every node at its place, nothing parented, the Searchlight aimed down."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    nodes = {n["name"]: n for n in data["nodes"]}
    roots = [data["nodes"][i]["name"] for i in data["scenes"][0]["nodes"]]
    if sorted(roots) != sorted(expected):
        raise SystemExit(f"the export's root nodes are {roots}, not {sorted(expected)}")
    for name, want in expected.items():
        got = nodes[name].get("translation", [0, 0, 0])
        if max(abs(a - b) for a, b in zip(got, want)) > 0.001:
            raise SystemExit(f"{name} is at {got}, not {want}")
    x, y, z, w = nodes["Searchlight"]["rotation"]
    down = Quaternion((w, x, y, z)) @ Vector((0, 0, -1))
    if (down - Vector((0, -1, 0))).length > 0.001:
        raise SystemExit(f"Searchlight's -Z points along {tuple(down)}, not straight down")
    for name in ("MainRotor", "TailRotor"):
        if nodes[name].get("rotation") or nodes[name].get("scale"):
            raise SystemExit(f"{name} has a rotation or a scale of its own: the game spins it about its axis")
    # The rotors' bounds, as stored, are centred on the node: each turns in place.
    for name, axes in (("MainRotor", (0, 2)), ("TailRotor", (1, 2))):
        acc = data["accessors"][data["meshes"][nodes[name]["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
        for a in axes:
            if abs(acc["min"][a] + acc["max"][a]) > 0.01:
                raise SystemExit(f"{name} is off its hub on axis {a}: {acc['min']} {acc['max']}")
    print("CHECK", Path(path).name, "nodes", {n: nodes[n].get("translation") for n in expected}, "down", tuple(down))


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="game/assets/helicopter")
    args = ap.parse_args(argv)
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mat = atlas_material(palette_image(out / "helicopter_palette.png"))

    parts = {}
    for name, origin, fn in (
        ("Body", (0, 0, 0), body),
        ("MainRotor", (0, 0, MAST_TOP), main_rotor),
        ("TailRotor", TAIL_HUB, tail_rotor),
    ):
        p = Part(name, origin)
        fn(p)
        parts[name] = p.obj(mat)
    rope = bpy.data.objects.new("RopeAnchor", None)
    rope.location = ROPE
    light = bpy.data.objects.new("Searchlight", None)
    light.location = LAMP
    # The export turns local +Y into Godot's -Z (the style bible's Muzzle): +Y of this empty points at the ground.
    light.rotation_euler = (-math.pi / 2, 0, 0)
    for o in (rope, light):
        o.empty_display_size = 0.3
        bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.update()

    counts = {n: tris(o) for n, o in parts.items()}
    total = sum(counts.values())
    pts = [o.matrix_world @ v.co for o in parts.values() for v in o.data.vertices]
    mn = [min(c[k] for c in pts) for k in range(3)]
    mx = [max(c[k] for c in pts) for k in range(3)]
    body_pts = [v.co for v in parts["Body"].data.vertices]
    bmn = [min(c[k] for c in body_pts) for k in range(3)]
    bmx = [max(c[k] for c in body_pts) for k in range(3)]
    if abs(bmn[2]) > 0.001:
        raise SystemExit(f"the skids' bottom is at {bmn[2]}, not 0")
    if total > BUDGET:
        raise SystemExit(f"{total} tris over the budget {BUDGET}")

    gltf = out / "helicopter.gltf"
    export([*parts.values(), rope, light], gltf)
    nodes = {o.name: godot(o.location) for o in (*parts.values(), rope, light)}
    check_gltf(gltf, nodes)

    report = {
        "tris": counts,
        "total_tris": total,
        "budget": BUDGET,
        "size_m": {
            "body_x_y_z_godot": [round(bmx[0] - bmn[0], 2), round(bmx[2] - bmn[2], 2), round(bmx[1] - bmn[1], 2)],
            "all_at_rest_x_y_z_godot": [round(mx[0] - mn[0], 2), round(mx[2] - mn[2], 2), round(mx[1] - mn[1], 2)],
        },
        "nodes_godot": nodes,
        "searchlight_minus_z_godot": [0, -1, 0],
        "main_rotor_radius": ROTOR_R,
        "tail_rotor_radius": TAIL_R,
        "door": {
            "x": DOOR_X,
            "sill_y": round(SILL_Z, 3),
            "top_y": round(DOOR_TOP_Z, 3),
            "z_from": -DOOR_HALF_Y,
            "z_to": DOOR_HALF_Y,
        },
        "skid_outer_x": SKID_X + 0.07,
    }
    (out / "helicopter.json").write_text(
        json.dumps(report, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    print("PROP", "helicopter", json.dumps(report))


if __name__ == "__main__":
    main()
