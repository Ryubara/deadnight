"""Render a turntable contact sheet: each model in a row, seen from several turns, at one scale.

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/render_turntable.py -- \
        --model "Lever rifle=game/assets/weapons/lever_rifle/lever_rifle.glb" \
        --model "Kit Shotgun=<bundle>/models/TyWl27dUz6.glb" --model "Kit Sniper=<bundle>/models/ZXBI8Hr3I0.glb" \
        --out <workspace>/scratch/deadnight/<branch>/turntable-lever_rifle.png

Each `--model` is Title=path.glb. Every model is shown at its own world size (1 Blender unit = 1 m) in the kit's
weapon axes (long along X, up +Z; models that stand up along +Z, blades and handles, are laid down first, like
render_sheet.py's side view), turned about the vertical axis by each `--turns` angle and tipped `--tilt` degrees
toward the camera so the top reads. Workbench studio light with the texture colours (the palette atlas shows; kit
flat materials show their glTF base colour), orthographic, outlines, a 1 m ruler, and a label per row with the title,
triangle count and length.
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

LABEL_W = 0.75  # metres of label column at the left


def load(path):
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    objs = [o for o in bpy.data.objects if o not in before]
    kitlib.apply_base_colours(objs, path)
    body, held, stray = kitlib.split_parts(objs)
    for o in held + stray:
        bpy.data.objects.remove(o)
    gone = {o.name for o in held + stray}
    return [o for o in objs if o.name not in gone], body


def orient(objs, body, turn, tilt, upright=False):
    """Lay an upright model down (unless `upright`), turn it about Z, tip it toward the camera; return its bbox."""
    roots = [o for o in objs if o.parent is None]
    pts = [p for o in body for p in kitlib.world_verts(o)]
    mn, mx = kitlib.bbox(pts)
    rot = Matrix.Identity(4)
    if (mx.y - mn.y) > (mx.x - mn.x):
        rot = Matrix.Rotation(math.radians(90), 4, "Z")
    if not upright and (mx.z - mn.z) > max(mx.x - mn.x, mx.y - mn.y):
        rot = Matrix.Rotation(math.radians(90), 4, "Y") @ rot
    rot = Matrix.Rotation(math.radians(tilt), 4, "X") @ Matrix.Rotation(math.radians(turn), 4, "Z") @ rot
    for r in roots:
        r.matrix_world = rot @ r.matrix_world
    bpy.context.view_layer.update()
    return kitlib.bbox([p for o in body for p in kitlib.world_verts(o)])


def move(objs, off):
    for r in (o for o in objs if o.parent is None):
        r.matrix_world = Matrix.Translation(off) @ r.matrix_world
    bpy.context.view_layer.update()


def flat_material(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    return m


def quad(x0, x1, z0, z1, mat):
    me = bpy.data.meshes.new("quad")
    y = 2.0
    me.from_pydata([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new("quad", me)
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(o)


def text(body, x, z, size, mat, align="LEFT"):
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = align
    o = bpy.data.objects.new("label", cu)
    o.location = (x, -1.0, z)
    o.rotation_euler = (math.radians(90), 0, 0)
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(o)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", action="append", required=True, help="Title=path.glb")
    ap.add_argument("--turns", default="0,45,90,135,180", help="degrees about the vertical axis, one column each")
    ap.add_argument("--upright", action="store_true", help="keep models standing (grenades, props)")
    ap.add_argument("--tilt", type=float, default=20.0, help="degrees the top tips toward the camera")
    ap.add_argument("--px-per-m", type=int, default=300)
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)
    turns = [float(t) for t in args.turns.split(",")]

    kitlib.reset()
    ink = flat_material("Ink", (0.02, 0.02, 0.02))

    # First pass: import every model once per turn and measure, so all cells share one size.
    rows = []
    for spec in args.model:
        title, path = spec.split("=", 1)
        cells = []
        for t in turns:
            objs, body = load(path)
            mn, mx = orient(objs, body, t, args.tilt, args.upright)
            cells.append((objs, mn, mx))
        objs0, mn0, mx0 = cells[0]
        tris = sum(kitlib.tris(o) for o in objs0 if o.type == "MESH")
        rows.append((title, tris, cells, mx0.x - mn0.x))
    cell_w = max(mx.x - mn.x for _t, _n, cells, _l in rows for _o, mn, mx in cells) + 0.15
    row_h = max(mx.z - mn.z for _t, _n, cells, _l in rows for _o, mn, mx in cells) + 0.12

    top = 0.0
    for r, (title, tris, cells, length) in enumerate(rows):
        base = top - (r + 1) * row_h
        for c, (objs, mn, mx) in enumerate(cells):
            cx = LABEL_W + c * cell_w + cell_w / 2
            move(objs, Vector((cx - (mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, base + 0.06 - mn.z)))
        text(f"{title}\n{tris} tris\n{length:.2f} m long", 0.05, base + row_h * 0.62, 0.05, ink)
        quad(0.0, LABEL_W + len(turns) * cell_w, base - 0.002, base + 0.002, ink)
    for c, t in enumerate(turns):
        text(f"{t:g} deg", LABEL_W + c * cell_w + cell_w / 2, top + 0.03, 0.045, ink, "CENTER")
    # 1 m ruler along the top-left.
    quad(LABEL_W, LABEL_W + 1.0, top + 0.11, top + 0.125, ink)
    for i in range(11):
        h = 0.035 if i % 5 == 0 else 0.018
        quad(LABEL_W + i / 10 - 0.002, LABEL_W + i / 10 + 0.002, top + 0.125, top + 0.125 + h, ink)
    text("1 m", LABEL_W + 1.04, top + 0.105, 0.045, ink)

    width = LABEL_W + len(turns) * cell_w
    height = len(rows) * row_h + 0.2
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(width, height)
    cam.location = (width / 2, -20, top + 0.2 - height / 2)
    cam.rotation_euler = (math.radians(90), 0, 0)
    cam.data.clip_end = 100
    scene.collection.objects.link(cam)
    scene.camera = cam

    r = scene.render
    r.engine = "BLENDER_WORKBENCH"
    r.resolution_x = round(width * args.px_per_m)
    r.resolution_y = round(height * args.px_per_m)
    r.image_settings.file_format = "PNG"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_object_outline = True
    sh.object_outline_color = (0.1, 0.1, 0.1)
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.82, 0.82, 0.8)
    scene.view_settings.view_transform = "Standard"
    r.filepath = str(args.out)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print(f"wrote {args.out} ({r.resolution_x}x{r.resolution_y})")


main()
