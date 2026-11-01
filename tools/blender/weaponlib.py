"""Part helpers for building weapons in the Toon Shooter kit's style (used by build_weapons.py).

Not run on its own. The numbers are the style bible's weapon rules (docs/design/style.md): kit scale (1 Blender unit
= 1 m), one-segment chamfers of about 17 mm on the parts that face the camera, many separate closed parts (never one
welded shell), flat colours as swatches of one shared palette atlas, roughness 0.415 and metallic 0.4.

Every weapon is built twice from the same description: `lod="near"` (gameplay: first person and world) and
`lod="far"` (no chamfers, fewer sides on round parts, the small detail parts left out).
"""

import itertools
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

BEVEL = 0.017  # metres: the kit guns' median chamfer
ROUGHNESS = 0.415
METALLIC = 0.4

# The weapon family palette: the kit's own weapon colours (sRGB), one swatch each in a 4 x 4 grid.
PALETTE = {
    "Grey": "#818491",
    "DarkGrey": "#414141",
    "Black": "#252525",
    "Wood": "#95703d",
    "Grey2": "#5f5f5f",
    "Red": "#8c3735",
    "DarkWood": "#6b4f2c",
    "Green": "#496321",
    "Yellow": "#d1ab46",  # the kit Yellow: the grenade's explosive band
}
GRID = 4  # swatches per side
SWATCH_PX = 8  # pixels per swatch side: the atlas is 32 x 32


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h):
    return tuple(int(h[i : i + 2], 16) / 255 for i in (1, 3, 5))


def swatch_uv(colour):
    """UV of the centre of a palette swatch (row 0 at the top of the image)."""
    i = list(PALETTE).index(colour)
    col, row = i % GRID, i // GRID
    return Vector(((col + 0.5) / GRID, 1 - (row + 0.5) / GRID))


def palette_image(path):
    """Write the palette atlas PNG (sRGB) and return the Blender image."""
    size = GRID * SWATCH_PX
    img = bpy.data.images.new("weapons_palette", size, size, alpha=False)
    px = [0.0] * (size * size * 4)
    for i, h in enumerate(PALETTE.values()):
        r, g, b = hex_rgb(h)
        col, row = i % GRID, i // GRID
        for y in range(SWATCH_PX):
            for x in range(SWATCH_PX):
                # Blender's pixel rows start at the bottom.
                py = size - 1 - (row * SWATCH_PX + y)
                k = (py * size + col * SWATCH_PX + x) * 4
                px[k : k + 4] = [r, g, b, 1.0]
    img.pixels = px
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    return img


def atlas_material(img):
    """The one weapon material: the palette atlas, unfiltered, roughness 0.415, metallic 0.4."""
    m = bpy.data.materials.get("Weapons") or bpy.data.materials.new("Weapons")
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


class Builder:
    """Collects the parts of one weapon as separate objects, then joins them into one mesh object."""

    def __init__(self, name, lod, material, chunk=(1.0, 1.0, 1.0)):
        """`chunk` scales every part about the origin before it is chamfered: the kit's chunky cross-sections come
        from drawing a weapon at real proportions and then fattening it across its length (1.5 for the kit's guns).
        """
        self.name, self.lod, self.material, self.chunk = name, lod, material, chunk
        self.parts = []
        self.near = lod == "near"

    # --- part primitives -------------------------------------------------------------------------------------------

    def _finish(self, bm, colour, bevel, detail):
        """Turn a bmesh into a part: chamfer it (near only), collapse its UVs onto the colour's swatch."""
        if detail and not self.near:
            bm.free()
            return None
        bmesh.ops.scale(bm, vec=self.chunk, verts=bm.verts)
        me = bpy.data.meshes.new(f"{self.name}_part")
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(o)
        if bevel and self.near:
            mod = o.modifiers.new("chamfer", "BEVEL")
            mod.width = bevel
            mod.segments = 1
            mod.limit_method = "ANGLE"
            mod.angle_limit = math.radians(40)
            mod.use_clamp_overlap = True
            dg = bpy.context.evaluated_depsgraph_get()
            new = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
            o.modifiers.clear()
            o.data = new
        uv = o.data.uv_layers.new(name="UVMap")
        s = swatch_uv(colour)
        for loop in uv.data:
            loop.uv = s
        self.parts.append(o)
        return o

    def box(self, center, size, colour, bevel=BEVEL, rot=None, detail=False):
        """A box of `size` (x, y, z) at `center`, optionally rotated by an Euler (radians, XYZ)."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        m = Matrix.Translation(center)
        if rot:
            m = m @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X")
        m = m @ Matrix.Diagonal((*size, 1))
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        return self._finish(bm, colour, bevel, detail)

    def cyl(self, p0, p1, radius, colour, segs=12, bevel=BEVEL, detail=False, radius1=None):
        """A cylinder (or a cone with `radius1` at p1) from p0 to p1."""
        if not self.near:
            segs = max(6, segs // 2)
        p0, p1 = Vector(p0), Vector(p1)
        axis = p1 - p0
        bm = bmesh.new()
        r1 = radius if radius1 is None else radius1
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=r1, depth=axis.length)
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation((p0 + p1) / 2) @ rot, verts=bm.verts)
        return self._finish(bm, colour, bevel, detail)

    def prism(self, profile, y0, y1, colour, bevel=BEVEL, detail=False):
        """A side profile [(x, z), ...] (counter-clockwise seen from -Y) extruded from y0 to y1."""
        bm = bmesh.new()
        vs = [bm.verts.new((x, y0, z)) for x, z in profile]
        face = bm.faces.new(vs)
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        moved = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0, y1 - y0, 0), verts=moved)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self._finish(bm, colour, bevel, detail)

    def lathe(self, profile, colour, segs=14, axis_x=0.0, axis_y=0.0, detail=False):
        """A round part turned about the Z axis from a profile [(radius, z), ...], bottom to top.

        The chamfers are in the profile itself (a short step in the radius), so it is never bevelled again.
        """
        if not self.near:
            segs = max(6, segs // 2)
            profile = [profile[0], *profile[1:-1:2], profile[-1]] if len(profile) > 4 else profile
        bm = bmesh.new()
        rings = []
        for r, z in profile:
            ring = []
            for i in range(segs):
                a = 2 * math.pi * i / segs
                ring.append(bm.verts.new((axis_x + r * math.cos(a), axis_y + r * math.sin(a), z)))
            rings.append(ring)
        for a, b in itertools.pairwise(rings):
            for i in range(segs):
                j = (i + 1) % segs
                bm.faces.new((a[i], a[j], b[j], b[i]))
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self._finish(bm, colour, 0, detail)

    def bar(self, points, width, thick, colour, y=0.0, bevel=0.0, detail=False):
        """A bent bar through side-view points [(x, z), ...]: one box per segment, overlapping at the joints."""
        for (x0, z0), (x1, z1) in itertools.pairwise(points):
            d = Vector((x1 - x0, 0, z1 - z0))
            ang = math.atan2(d.z, d.x)
            self.box(
                ((x0 + x1) / 2, y, (z0 + z1) / 2),
                (d.length + thick * 0.9, width, thick),
                colour,
                bevel=bevel,
                rot=(0, -ang, 0),
                detail=detail,
            )

    def arc(self, center, radius, a0, a1, n, width, thick, colour, y=0.0):
        """A bar bent along a circular arc in the side view (angles in degrees, 0 = +X, 90 = +Z)."""
        pts = []
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((center[0] + radius * math.cos(a), center[1] + radius * math.sin(a)))
        if not self.near:
            pts = pts[:: max(1, n // 3)] + ([pts[-1]] if n % max(1, n // 3) else [])
        self.bar(pts, width, thick, colour, y=y)

    # --- the finished weapon ---------------------------------------------------------------------------------------

    def join(self):
        """Join the parts into one object named after the weapon (the parts stay separate closed pieces)."""
        me = bpy.data.meshes.new(self.name)
        o = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(o)
        bm = bmesh.new()
        for p in self.parts:
            bm.from_mesh(p.data)
        bm.to_mesh(me)
        bm.free()
        # Keep the swatch UVs: bm.from_mesh merges UV layers of the same name.
        for p in self.parts:
            bpy.data.objects.remove(p)
        me.materials.append(self.material)
        for poly in me.polygons:
            poly.use_smooth = False
        return o
