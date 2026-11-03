"""The small-map kit's shared parts: its palette, its grid and sizes, and the box-and-cylinder builder.

Not run on its own: the kit's build scripts (and `build_kit_blockout.py`) put this folder on sys.path and import it, so
every piece lands on one atlas and one grid. Where each number comes from: docs/research/maps/small-map-art.md.
"""

import math

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

SWATCH_PX = 16
GRID = 5

# The drive-in palette, in its own cells (build_drivein_props.py), and five new swatches in the five cells it leaves
# empty, so a drive-in prop's UVs stay valid on this atlas.
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
    # New for the small map (cells 20-24).
    "Plaster": "#b3a588",
    "Sandbag": "#a88d62",
    "Chalk": "#ece6d2",
    "Rust": "#7d4b2f",
    "Soot": "#2f2c2a",
}

BEVEL = 0.03
BIG_BEVEL = 0.06  # walls and frames: buildings chamfer, about 100 mm at kit scale, 80 mm at ours

# The kit's sizes (metres, a player is 1.8 m). The page's scale table says where each comes from.
STOREY = 3.0  # floor to floor
CLEAR = 2.8  # floor to ceiling
WALL_T = 0.3
MODULE = 2.0
DOOR_W, DOOR_H = 1.4, 2.4
WIN_W, WIN_H, SILL = 1.2, 1.3, 0.9
STAIR_W, RISERS, TREAD = 1.4, 15, 0.3
RISE = STOREY / RISERS


class Piece:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def box(self, size, at, colour, bevel=BEVEL, rot=(0, 0, 0)):
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        bmesh.ops.scale(tmp, vec=Vector(size), verts=tmp.verts)
        b = min(bevel, min(size) * 0.3)
        if b > 0.002:
            bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=b, segments=1, affect="EDGES", profile=0.5)
        self._merge(tmp, colour, at, rot)

    def cyl(self, r, h, at, colour, sides=8, rot=(0, 0, 0), r2=None):
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
    img = bpy.data.images.new("kit_palette", size, size, alpha=False)
    img.colorspace_settings.name = "sRGB"
    px = [0.0] * (size * size * 4)
    for i, h in enumerate(PALETTE.values()):
        rgb = hex_rgb(h)
        col, row = i % GRID, i // GRID
        for y in range(SWATCH_PX):
            for x in range(SWATCH_PX):
                py = size - 1 - (row * SWATCH_PX + y)
                k = (py * size + col * SWATCH_PX + x) * 4
                px[k : k + 4] = [srgb_to_linear(c) for c in rgb] + [1.0]
    img.pixels = px
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    return img


def atlas_material(img, name="Kit", emit=None):
    m = bpy.data.materials.new(name)
    m.use_backface_culling = True
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.415
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*[srgb_to_linear(c) for c in hex_rgb(emit)], 1)
        bsdf.inputs["Emission Strength"].default_value = 6.0
    nt.nodes.active = tex  # Workbench's texture colour reads the active image node (kit lesson: black renders)
    return m
