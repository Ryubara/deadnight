"""Build Deadnight's drive-in props, the ones the Toon Shooter kit has none of, in the kit's manner.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_drivein_props.py -- [--out game/assets/drivein] [--only a,b]

Every prop is our own design, built from chamfered boxes and low-sided cylinders (the style bible's look: chunky
shapes, one-segment chamfers, flat colours; docs/design/style.md). All of them share one palette atlas
(`<out>/drivein_palette.png`, 16 px swatches) and one material, each face collapsed onto one swatch (the zombie's
pattern). They are modelled at game scale (metres, a player is 1.8 m), stand on their origin (the middle of the
footprint, at the ground) and face Blender -Y, which is Godot +Z, unless the prop says otherwise. Each is written as
`<out>/<name>.gltf` + `.bin`; one `PROP` line per file and `<out>/drivein_props.json` give triangles and size.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROUGHNESS = 0.415  # the kit's
METALLIC = 0.0  # paint, wood and enamel; the kit's 0.4 reads as dark at night
SWATCH_PX = 16
GRID = 5

# The drive-in palette (sRGB): the kit's colours (style bible, Colour and materials) and the 1958 lot's paint, the
# UI's cream and amber included, one swatch each.
PALETTE = {
    "Grey": "#818491",
    "Grey2": "#5f5f5f",
    "DarkGrey": "#414141",
    "Black": "#252525",
    "Cream": "#e6d8b0",
    "Yellow": "#d1ab46",
    "Amber": "#e8a33a",
    "Red": "#8c3735",
    "SignRed": "#b8322e",
    "Blue": "#3b4b8c",
    "Teal": "#3f7f7a",
    "Green": "#496321",
    "Wood": "#95703d",
    "DarkWood": "#6b4f2c",
    "Chrome": "#b4b8c2",
    "Glass": "#5d7891",
    "Popcorn": "#f2dc8c",
    "Screen": "#d9d9d0",
    "Concrete": "#9a968c",
    "Pink": "#c8707a",
}

BEVEL = 0.03  # props 1-3 m keep near-hard edges; a thin chamfer catches the light at night
BIG_BEVEL = 0.08  # buildings and big props (style bible: about 100 mm at kit scale)


class Prop:
    """Collects the parts of one prop in one bmesh with a UV layer, every face on its part's swatch."""

    def __init__(self, name):
        self.name = name
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

    def _merge(self, tmp, colour, at, rot):
        m = Matrix.Translation(Vector(at)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
        bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        n0 = len(self.bm.faces)
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        self.bm.faces.ensure_lookup_table()
        u = swatch_uv(colour)
        for f in self.bm.faces[n0:]:
            for loop in f.loops:
                loop[self.uv].uv = u

    def obj(self, material):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = False
        me.materials.append(material)
        o = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(o)
        return o


def hex_rgb(h):
    return tuple(int(h[i : i + 2], 16) / 255 for i in (1, 3, 5))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def swatch_uv(name):
    i = list(PALETTE).index(name)
    col, row = i % GRID, i // GRID
    return Vector(((col + 0.5) / GRID, 1 - (row + 0.5) / GRID))


def palette_image(path):
    size = GRID * SWATCH_PX
    img = bpy.data.images.new("drivein_palette", size, size, alpha=False)
    img.colorspace_settings.name = "sRGB"
    px = [0.0] * (size * size * 4)
    for i, h in enumerate(PALETTE.values()):
        rgb = hex_rgb(h)
        col, row = i % GRID, i // GRID
        for y in range(SWATCH_PX):
            for x in range(SWATCH_PX):
                py = size - 1 - (row * SWATCH_PX + y)  # Blender's pixel rows start at the bottom
                k = (py * size + col * SWATCH_PX + x) * 4
                # Float pixels are linear in a byte sRGB image's buffer: convert so the PNG holds the sRGB value.
                px[k : k + 4] = [srgb_to_linear(c) for c in rgb] + [1.0]
    img.pixels = px
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    return img


def atlas_material(img):
    m = bpy.data.materials.new("DriveIn")
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


# --- The props -------------------------------------------------------------------------------------------------------


def speaker_post(p):
    """A pole with a window speaker hung each side (+X and -X): one post serves the two cars beside it."""
    p.cyl(0.16, 0.08, (0, 0, 0.04), "Concrete", sides=8)
    p.cyl(0.045, 1.3, (0, 0, 0.7), "Grey", sides=6)
    p.box((0.16, 0.16, 0.16), (0, 0, 1.38), "Grey2", 0.02)
    p.box((0.5, 0.05, 0.05), (0, 0, 1.3), "Grey2", 0.0)
    for s in (-1, 1):
        x = s * 0.33
        p.box((0.12, 0.26, 0.3), (x, 0, 1.18), "Grey2", 0.03)  # the speaker's body, its face to +-X
        p.box((0.03, 0.2, 0.22), (x + s * 0.06, 0, 1.18), "Chrome", 0.01)  # the grille
        p.box((0.02, 0.12, 0.04), (x + s * 0.075, 0, 1.18), "Black", 0.0)  # its slot
        p.box((0.06, 0.06, 0.08), (x, 0, 1.36), "Grey2", 0.0)  # the hook


def ticket_booth(p):
    """The ticket booth at the gate: a 2.4 m square kiosk with glass all round, a roof lip and a sign on top."""
    p.box((2.2, 2.2, 1.05), (0, 0, 0.525), "SignRed", BIG_BEVEL)
    p.box((2.24, 2.24, 0.12), (0, 0, 1.08), "Cream", 0.03)  # the window sill band
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((0.16, 0.16, 0.95), (sx * 1.02, sy * 1.02, 1.6), "Cream", 0.03)
    p.box((2.0, 2.0, 0.9), (0, 0, 1.6), "Glass", 0.0)
    p.box((0.9, 0.35, 0.06), (0, -1.25, 1.12), "Chrome", 0.02)  # the ticket shelf, road side
    p.box((2.0, 2.0, 0.12), (0, 0, 2.1), "Cream", 0.0)
    p.box((2.6, 2.6, 0.22), (0, 0, 2.25), "SignRed", 0.05)  # the roof, overhanging
    p.box((2.1, 2.1, 0.14), (0, 0, 2.43), "Cream", 0.04)
    # The sign: a cream board in a red frame with a row of block letters, facing the road.
    p.box((0.1, 0.1, 0.5), (-0.7, 0, 2.7), "Grey2", 0.0)
    p.box((0.1, 0.1, 0.5), (0.7, 0, 2.7), "Grey2", 0.0)
    p.box((2.2, 0.16, 0.62), (0, 0, 3.15), "SignRed", 0.04)
    p.box((2.0, 0.2, 0.44), (0, 0, 3.15), "Cream", 0.0)
    for i in range(7):
        p.box((0.17, 0.24, 0.28), (-0.78 + i * 0.26, 0, 3.15), "SignRed", 0.0)
    p.box((0.5, 0.18, 0.18), (0, 0, 3.55), "Amber", 0.03)  # a lamp housing on the crown


def concession_counter(p):
    """The stand's counter: 10 m by 2 m by 1 m, red enamel with a cream band, chrome trim and a steel top."""
    p.box((9.8, 1.8, 0.14), (0, 0, 0.07), "Black", 0.0)  # the kick plate
    p.box((10.0, 1.9, 0.72), (0, 0, 0.5), "SignRed", BEVEL)
    p.box((10.04, 1.94, 0.12), (0, 0, 0.62), "Cream", 0.02)
    p.box((10.2, 2.0, 0.08), (0, 0, 0.92), "Chrome", 0.02)
    p.box((10.24, 2.04, 0.06), (0, 0, 0.87), "Grey2", 0.0)
    for i in range(9):
        x = -4.0 + i * 1.0
        for sy in (-1, 1):
            p.box((0.06, 0.04, 0.55), (x, sy * 0.96, 0.46), "Chrome", 0.0)
    # Napkin holders and straw jars on the top, far side out of the way of the popcorn machine.
    for x in (-1.2, 1.4, 3.6):
        p.box((0.18, 0.1, 0.16), (x, -0.55, 1.04), "Chrome", 0.01)
        p.cyl(0.07, 0.24, (x + 0.3, -0.55, 1.08), "Glass", sides=6)


def menu_board(p):
    """The menu board on the wall behind the counter: 4 m by 1.4 m, its face to -Y (Godot +Z)."""
    p.box((4.2, 0.1, 1.6), (0, 0, 0.8), "DarkWood", 0.03)
    p.box((4.0, 0.12, 1.24), (0, 0, 0.72), "Black", 0.0)
    p.box((4.0, 0.14, 0.26), (0, 0, 1.46), "SignRed", 0.0)  # the header
    for i in range(8):
        p.box((0.24, 0.16, 0.14), (-1.4 + i * 0.4, 0, 1.46), "Cream", 0.0)
    for col, x0 in enumerate((-1.85, 0.15)):
        for row in range(4):
            z = 1.12 - row * 0.26
            w = (1.0, 0.8, 1.15, 0.7)[(row + col) % 4]
            p.box((w, 0.14, 0.09), (x0 + w / 2, 0, z), "Cream", 0.0)  # an item
            p.box((0.32, 0.14, 0.09), (x0 + 1.5, 0, z), "Amber", 0.0)  # its price
    # Three pictures along the bottom: a popcorn box, a cup, a hot dog.
    p.box((0.34, 0.14, 0.12), (-1.2, 0, 0.26), "Popcorn", 0.0)
    p.box((0.3, 0.14, 0.18), (-1.2, 0, 0.12 + 0.0), "SignRed", 0.0)
    p.box((0.22, 0.14, 0.3), (0, 0, 0.2), "Teal", 0.0)
    p.box((0.5, 0.14, 0.14), (1.2, 0, 0.2), "Amber", 0.0)
    p.box((0.42, 0.15, 0.06), (1.2, 0, 0.2), "SignRed", 0.0)


def popcorn_machine(p):
    """A counter-top popcorn machine: 0.7 m wide, 0.5 m deep, 0.95 m tall, its glass case open to the counter."""
    p.box((0.7, 0.5, 0.14), (0, 0, 0.07), "SignRed", 0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((0.04, 0.04, 0.56), (sx * 0.33, sy * 0.23, 0.42), "Chrome", 0.0)
    p.box((0.62, 0.42, 0.18), (0, 0, 0.23), "Popcorn", 0.04)  # the heap
    p.box((0.62, 0.42, 0.04), (0, 0, 0.5), "Glass", 0.0)  # a back pane, seen through the open front
    p.box((0.6, 0.02, 0.5), (0, 0.22, 0.42), "Glass", 0.0)
    p.cyl(0.12, 0.12, (0, 0, 0.6), "Grey", sides=8)  # the kettle
    p.cyl(0.02, 0.1, (0, 0, 0.7), "Chrome", sides=4)
    p.box((0.74, 0.54, 0.12), (0, 0, 0.76), "SignRed", 0.03)  # the hood
    p.box((0.7, 0.5, 0.06), (0, 0, 0.85), "Cream", 0.02)
    p.box((0.56, 0.08, 0.16), (0, -0.12, 0.95), "Amber", 0.02)  # the name plate on top
    p.box((0.3, 0.09, 0.08), (0, -0.12, 0.95), "SignRed", 0.0)


def projector(p):
    """The booth's 35 mm projector on its pedestal: a lamphouse, the lens to +Y (towards the screen), two reels."""
    p.box((0.9, 1.1, 0.1), (0, 0, 0.05), "DarkGrey", 0.02)
    p.box((0.42, 0.5, 0.75), (0, 0, 0.47), "Grey2", 0.04)
    p.box((0.52, 1.0, 0.46), (0, 0, 1.06), "Grey", 0.05)  # the mechanism
    p.box((0.46, 0.44, 0.44), (0, -0.62, 1.12), "DarkGrey", 0.05)  # the lamphouse at the back
    p.cyl(0.07, 0.3, (0, -0.62, 1.48), "Black", sides=6)  # its chimney
    p.cyl(0.1, 0.36, (0, 0.66, 1.06), "Black", sides=8, rot=(90, 0, 0))  # the lens
    p.cyl(0.12, 0.06, (0, 0.85, 1.06), "Chrome", sides=8, rot=(90, 0, 0))
    for y, z in ((0.32, 1.68), (-0.3, 1.68)):
        p.box((0.06, 0.08, 0.4), (0, y * 0.6, 1.4), "Grey2", 0.0)  # the reel arm
        p.cyl(0.36, 0.06, (0, y, z), "Chrome", sides=12, rot=(0, 90, 0))
        p.cyl(0.1, 0.1, (0, y, z), "Black", sides=6, rot=(0, 90, 0))
    p.box((0.04, 0.6, 0.04), (0.29, 0.0, 1.32), "Black", 0.0)  # the film path, side on


SCREEN_W = 32.0  # the screen panel (greybox ScreenPanel): 32 x 12, its middle 10 m up, at Godot z -48
SCREEN_H = 12.0


def screen_frame(p):
    """The screen's frame and back truss, its legs and the stays behind. The origin is the ground under the
    screen's middle, the screen faces -Y (Godot +Z, the cars); the truss is behind it, +Y (north)."""
    bot, top = 10.0 - SCREEN_H / 2, 10.0 + SCREEN_H / 2
    half = SCREEN_W / 2
    # The border round the panel: a cream frame with a red inner lip.
    for z in (bot - 0.4, top + 0.4):
        p.box((SCREEN_W + 1.6, 1.4, 0.8), (0, 0.0, z), "Cream", BIG_BEVEL)
    for x in (-half - 0.4, half + 0.4):
        p.box((0.8, 1.4, SCREEN_H + 1.6), (x, 0.0, 10.0), "Cream", BIG_BEVEL)
    p.box((SCREEN_W + 0.3, 0.3, 0.2), (0, -0.62, bot - 0.05), "SignRed", 0.0)
    p.box((SCREEN_W + 0.3, 0.3, 0.2), (0, -0.62, top + 0.05), "SignRed", 0.0)
    # The back: posts every 4 m, three girts, a cross brace in each bay.
    posts = [-half + i * 4.0 for i in range(9)]
    for x in posts:
        p.box((0.35, 0.35, top - 0.6), (x, 1.3, (top + 0.6) / 2 - 0.0), "Grey2", 0.04)
    for z in (bot + 0.5, 10.0, top - 0.5):
        p.box((SCREEN_W, 0.25, 0.3), (0, 1.3, z), "Grey2", 0.03)
    seg = 4.0
    for x0 in posts[:-1]:
        for z0, z1 in ((bot + 0.5, 10.0), (10.0, top - 0.5)):
            L = math.hypot(seg, z1 - z0)
            a = math.degrees(math.atan2(z1 - z0, seg))
            p.box((L, 0.12, 0.14), (x0 + seg / 2, 1.38, (z0 + z1) / 2), "Grey", 0.0, rot=(0, -a, 0))
    # The legs: two concrete pylons (the greybox's ScreenLegs, 1.4 x 1.6 x 4.2 at x +-10).
    for x in (-10.0, 10.0):
        p.box((1.4, 1.6, 4.2), (x, 0, 2.1), "Concrete", BIG_BEVEL)
        p.box((1.6, 1.8, 0.2), (x, 0, 4.1), "Grey", 0.04)
    for x in (-14.0, -6.0, 6.0, 14.0):
        p.box((0.4, 0.4, bot), (x, 1.3, bot / 2), "Grey2", 0.03)  # posts down to the ground
    # The stays: raking braces from the truss down to footings behind (the greybox's ScreenStays at x +-14).
    for x in (-14.0, 14.0):
        z0, y0 = 9.0, 1.3
        z1, y1 = 0.2, 8.3
        L = math.hypot(y1 - y0, z1 - z0)
        a = math.degrees(math.atan2(y1 - y0, z0 - z1))
        p.box((0.3, 0.3, L), (x, (y0 + y1) / 2, (z0 + z1) / 2), "Grey", 0.03, rot=(a, 0, 0))
        p.box((0.9, 0.9, 0.5), (x, y1, 0.25), "Concrete", 0.05)


def marquee(p):
    """The marquee at the entrance: a lit board on two posts, an arrow on the crown, facing -Y (the road)."""
    for x in (-2.6, 2.6):
        p.box((0.36, 0.36, 5.6), (x, 0, 2.8), "Grey2", 0.04)
        p.box((0.6, 0.6, 0.3), (x, 0, 0.15), "Concrete", 0.04)
    p.box((6.2, 0.5, 2.6), (0, 0, 4.2), "SignRed", BIG_BEVEL)
    p.box((5.6, 0.56, 2.0), (0, 0, 4.2), "Cream", 0.0)
    # Two rows of block letters on the face (both sides).
    for row, z in enumerate((4.62, 3.82)):
        n = 7 if row == 0 else 9
        w = 5.0 / n
        for i in range(n):
            p.box((w * 0.62, 0.6, 0.5), (-2.5 + w * (i + 0.5), 0, z), "Black" if row else "SignRed", 0.0)
    # Bulbs round the frame.
    for i in range(14):
        x = -2.9 + i * (5.8 / 13)
        for z in (2.98, 5.42):
            p.box((0.12, 0.6, 0.12), (x, 0, z), "Amber", 0.0)
    for i in range(5):
        z = 3.35 + i * 0.42
        for x in (-3.0, 3.0):
            p.box((0.12, 0.6, 0.12), (x, 0, z), "Amber", 0.0)
    # The crown: a stepped arrow pointing in, at the gate.
    p.box((2.4, 0.4, 0.5), (-0.4, 0, 5.75), "Amber", 0.04)
    p.box((0.8, 0.4, 0.8), (1.2, 0, 5.75), "Amber", 0.04, rot=(0, 45, 0))
    p.box((1.6, 0.44, 0.22), (-0.6, 0, 5.75), "SignRed", 0.0)


def trash_can(p):
    """A ribbed steel can with a domed lid: 0.6 m across, 0.95 m tall."""
    p.cyl(0.28, 0.86, (0, 0, 0.43), "Green", sides=10)
    for z in (0.12, 0.43, 0.74):
        p.cyl(0.3, 0.06, (0, 0, z), "DarkGrey", sides=10)
    p.cyl(0.31, 0.06, (0, 0, 0.89), "Grey", sides=10)
    p.cyl(0.26, 0.08, (0, 0, 0.96), "Grey", sides=10, r2=0.12)
    p.box((0.16, 0.04, 0.05), (0, 0, 1.02), "Grey2", 0.0)
    p.box((0.22, 0.03, 0.12), (0, -0.285, 0.55), "Cream", 0.0)  # a painted panel


def picnic_table(p):
    """A picnic table with its benches: 1.8 m long (X), 1.5 m across, the top 0.75 m up."""
    for y in (-0.24, 0.0, 0.24):
        p.box((1.8, 0.22, 0.06), (0, y, 0.74), "Wood", 0.015)
    for y in (-0.62, 0.62):
        p.box((1.8, 0.26, 0.05), (0, y, 0.44), "Wood", 0.015)
    for x in (-0.65, 0.65):
        for s in (-1, 1):  # the A-frame legs
            p.box((0.08, 0.08, 0.86), (x, s * 0.28, 0.38), "DarkWood", 0.0, rot=(s * 28, 0, 0))
        p.box((0.08, 1.5, 0.08), (x, 0, 0.38), "DarkWood", 0.0)  # the bench bearer
        p.box((0.08, 0.66, 0.06), (x, 0, 0.68), "DarkWood", 0.0)


PROPS = {
    # name: (builder, triangle budget: under 1 m 800, 1-3 m 1.5k, over 3 m 5k)
    "speaker_post": (speaker_post, 800),
    "ticket_booth": (ticket_booth, 1500),
    "concession_counter": (concession_counter, 5000),
    "menu_board": (menu_board, 1500),
    "popcorn_machine": (popcorn_machine, 800),
    "projector": (projector, 1500),
    "screen_frame": (screen_frame, 5000),
    "marquee": (marquee, 5000),
    "trash_can": (trash_can, 800),
    "picnic_table": (picnic_table, 1500),
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


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="game/assets/drivein")
    ap.add_argument("--only", default="")
    ap.add_argument("--blend", default="", help="also save the built props in one .blend (for the contact sheet)")
    args = ap.parse_args(argv)
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    palette_path = out / "drivein_palette.png"
    img = palette_image(palette_path)
    mat = atlas_material(img)
    only = set(filter(None, args.only.split(",")))
    report = {}
    for name, (fn, budget) in PROPS.items():
        if only and name not in only:
            continue
        p = Prop(name)
        fn(p)
        o = p.obj(mat)
        n = tris(o)
        xs = [v.co for v in o.data.vertices]
        size = [round(max(c[k] for c in xs) - min(c[k] for c in xs), 2) for k in range(3)]
        info = {"tris": n, "budget": budget, "size_xyz_blender": size}
        print("PROP", name, json.dumps(info))
        if n > budget:
            raise SystemExit(f"{name}: {n} tris over its budget {budget}")
        export(o, out, name)
        report[name] = info
        if not args.blend:
            bpy.data.objects.remove(o, do_unlink=True)
    (out / "drivein_props.json").write_text(
        json.dumps(report, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=str(Path(args.blend).resolve()))


main()
