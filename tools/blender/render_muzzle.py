"""Render a sheet of firearms with their `Muzzle` marker drawn: one row per model, a side view of the whole gun and a
close-up of the barrel end.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/render_muzzle.py -- \
        --model "Lever rifle=game/assets/weapons/lever_rifle/lever_rifle.glb" \
        --model "Lever rifle, far=game/assets/weapons/lever_rifle/lever_rifle_far.glb" \
        --out <workspace>/scratch/deadnight/<branch>/muzzle-sheet.png

Each `--model` is Title=path.glb. Where the file has a `Muzzle` node, a red ball marks its origin and a red arrow its
forward (Godot's -Z, which the glTF import brings back as the empty's local +Y in Blender); a model without one says
"no Muzzle" in red. The label gives the marker's position in Godot's axes (Y up), the numbers the game reads.
Workbench, the palette colours, outlines. Every cell is rendered on its own and the sheet is put together with numpy.
"""

import argparse
import math
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

SIDE = (1000, 360)  # px of the side view cell
CLOSE = (360, 360)  # px of the close-up cell
RED = (0.9, 0.05, 0.03)


def flat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    return m


def add_mesh_obj(name, mesh_op, mat, **kw):
    mesh_op(**kw)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


def marker(at, forward, size):
    """A ball at the muzzle and an arrow along its forward, `size` metres long."""
    red = flat("Marker", RED)
    add_mesh_obj("dot", bpy.ops.mesh.primitive_uv_sphere_add, red, radius=size * 0.14, location=at, segments=16)
    rot = Vector((0, 0, 1)).rotation_difference(forward).to_euler()
    shaft = size * 0.75
    add_mesh_obj("shaft", bpy.ops.mesh.primitive_cylinder_add, red, radius=size * 0.035, depth=shaft,
                 location=at + forward * (shaft / 2), rotation=rot, vertices=12)  # fmt: skip
    add_mesh_obj("head", bpy.ops.mesh.primitive_cone_add, red, radius1=size * 0.09, depth=size * 0.25,
                 location=at + forward * (shaft + size * 0.125), rotation=rot, vertices=12)  # fmt: skip


def text(body, loc, size, rgb):
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = body
    cu.size = size
    o = bpy.data.objects.new("label", cu)
    o.location = loc
    o.rotation_euler = (math.radians(90), 0, 0)  # face the camera on -Y
    o.data.materials.append(flat("Ink", rgb))
    bpy.context.scene.collection.objects.link(o)


def setup_render(path, res):
    scene = bpy.context.scene
    r = scene.render
    r.engine = "BLENDER_WORKBENCH"
    r.resolution_x, r.resolution_y = res
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_object_outline = True
    sh.object_outline_color = (0.1, 0.1, 0.1)
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.82, 0.82, 0.8)
    scene.view_settings.view_transform = "Standard"
    r.filepath = str(path)


def camera(loc, look_at, ortho=None, lens=50.0):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.location = loc
    cam.rotation_euler = (Vector(look_at) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.lens = lens
    cam.data.clip_start = 0.01
    cam.data.clip_end = 100
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam


def load(path):
    """Import a model; return its mesh objects, its Muzzle empty (or None) and its bounds."""
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    objs = [o for o in bpy.data.objects if o not in before]
    kitlib.apply_base_colours(objs, path)
    meshes = [o for o in objs if o.type == "MESH"]
    muzzle = next((o for o in objs if o.name.split(".")[0] == "Muzzle"), None)
    mn, mx = kitlib.bbox([p for o in meshes for p in kitlib.world_verts(o)])
    return meshes, muzzle, mn, mx


def render_cell(path, title, close, out):
    kitlib.reset()
    meshes, muzzle, mn, mx = load(path)
    tris = sum(kitlib.tris(o) for o in meshes)
    centre = (mn + mx) / 2
    length = mx.x - mn.x
    if muzzle:
        at = muzzle.matrix_world.translation.copy()
        fwd = (muzzle.matrix_world.to_3x3() @ Vector((0, 1, 0))).normalized()  # Godot -Z
    if close:
        if muzzle:
            target = at
            marker(at, fwd, 0.12)
        else:  # frame the barrel end anyway: the middle of the vertices on the front face
            front = [p for o in meshes for p in kitlib.world_verts(o) if p.x < mn.x + 0.01]
            target = sum(front, Vector()) / len(front)
        camera(target + Vector((-0.42, -0.24, 0.15)), target + Vector((-0.04, 0, 0)), lens=60)
        setup_render(out, CLOSE)
    else:
        if muzzle:
            marker(at, fwd, 0.18)
            g = tuple(round(c, 4) + 0.0 for c in (at.x, at.z, -at.y))  # Blender to Godot axes; + 0.0 drops -0
            f = tuple(round(c, 4) + 0.0 for c in (fwd.x, fwd.z, -fwd.y))
            where = f"Muzzle at ({g[0]:.3f}, {g[1]:.3f}, {g[2]:.3f}), -Z = ({f[0]:.0f}, {f[1]:.0f}, {f[2]:.0f})"
            print(f"MUZZLE {title}: godot {g}, forward {f}, front face x {mn.x:.4f}, tris {tris}")
        else:
            where = "no Muzzle"
            print(f"MUZZLE {title}: none, tris {tris}")
        width = 2.1
        height = width * SIDE[1] / SIDE[0]
        left = centre.x - width / 2 + 0.12
        text(f"{title}  ({tris} tris, {length:.2f} m)", (left, -0.6, mx.z + 0.06), 0.06, (0.02, 0.02, 0.02))
        text(where, (left, -0.6, mn.z - 0.12), 0.055, RED if not muzzle else (0.02, 0.02, 0.02))
        mid_z = (mx.z + 0.12 + mn.z - 0.14) / 2
        camera((centre.x - 0.08, -10, mid_z), (centre.x - 0.08, 0, mid_z), ortho=max(width, height))
        setup_render(out, SIDE)
    bpy.ops.render.render(write_still=True)


def read_png(path):
    img = bpy.data.images.load(str(path))
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", action="append", required=True, help="Title=path.glb")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)

    tmp = Path(tempfile.mkdtemp(prefix="muzzle-"))
    rows = []
    for i, spec in enumerate(args.model):
        title, path = spec.split("=", 1)
        side, close = tmp / f"{i}-side.png", tmp / f"{i}-close.png"
        render_cell(Path(path).resolve(), title, False, side)
        render_cell(Path(path).resolve(), title, True, close)
        rows.append((side, close))

    kitlib.reset()
    gap = 6
    w = SIDE[0] + gap + CLOSE[0]
    h = len(rows) * (SIDE[1] + gap) - gap
    sheet = np.ones((h, w, 4), dtype=np.float32) * 0.3
    for r, (side, close) in enumerate(rows):
        # Blender's pixel rows start at the bottom: row 0 of the sheet goes at the top.
        y0 = h - (r + 1) * SIDE[1] - r * gap
        sheet[y0 : y0 + SIDE[1], 0 : SIDE[0]] = read_png(side)
        sheet[y0 : y0 + CLOSE[1], SIDE[0] + gap : w] = read_png(close)
    out = bpy.data.images.new("sheet", w, h, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    out.filepath_raw = str(args.out)
    out.file_format = "PNG"
    out.save()
    print(f"wrote {args.out} ({w}x{h})")


main()
