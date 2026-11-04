"""Render the helicopter (build_helicopter.py) from the exported glTF: the views the cutscene needs, on one sheet.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/render_helicopter.py -- --gltf game/assets/helicopter/helicopter.gltf \
        --ref <bundle>/models/PpLF4rt4ah.glb --out <scratch>/helicopter_sheet.png [--tile 330]

Workbench with the atlas colours and back faces culled, as the game draws them, so a face wound the wrong way shows
as a hole. The kit Soldier stands beside the door at the style bible's 0.8 for scale, the main rotor is turned off
the hull's axis, and `far` is the game camera's view at the size it has on a phone: the one that must read.
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

# view: (elevation degrees, azimuth degrees from +Y round Z, metres the frame spans, pixels of a tile it fills)
VIEWS = {
    "above_behind": (45, 200, 12.5, 1.0),
    "game_door_side": (50, 95, 12.5, 1.0),
    "door_side": (0, 90, 11.5, 1.0),
    "front": (0, 0, 9.5, 1.0),
    "top": (90, 0, 12.5, 1.0),
    "closed_side": (20, 285, 12.5, 1.0),
    "far": (50, 120, 12.5, 0.25),
}
GROUND = (0.035, 0.038, 0.05)


def imported(path):
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    return [o for o in bpy.data.objects if o not in before]


def render(cam, view, px, path):
    elev, azim, span, _fill = VIEWS[view]
    e, a = math.radians(elev), math.radians(azim)
    d = Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    centre = Vector((0, -1.3, 1.9))
    cam.location = centre + d * 60
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = span
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = px
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def load(path):
    img = bpy.data.images.load(str(path), check_existing=False)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return a


def sheet(tiles, tile, cols, path):
    rows = math.ceil(len(tiles) / cols)
    a = np.ones((rows * tile, cols * tile, 4), dtype=np.float32)
    a[..., :3] = tiles[0][0, 0, :3]  # the background as rendered, so a small tile sits on the same ground
    for i, t in enumerate(tiles):
        col, row = i % cols, rows - 1 - i // cols  # Blender's image rows start at the bottom
        h, w = t.shape[:2]
        oy, ox = row * tile + (tile - h) // 2, col * tile + (tile - w) // 2
        a[oy : oy + h, ox : ox + w] = t
    img = bpy.data.images.new("sheet", cols * tile, rows * tile, alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels = a.ravel().tolist()
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    ap = argparse.ArgumentParser()
    ap.add_argument("--gltf", default="game/assets/helicopter/helicopter.gltf")
    ap.add_argument("--ref", default="")
    ap.add_argument("--tile", type=int, default=330)
    ap.add_argument("--keep", action="store_true", help="keep each view's PNG beside the sheet")
    ap.add_argument("--light", default="STUDIO", help="FLAT shows the atlas colours with no shading")
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = imported(a.gltf)
    rotor = next(o for o in objs if o.name == "MainRotor")
    rotor.rotation_mode = "XYZ"
    rotor.rotation_euler.z = math.radians(32)
    if a.ref:
        ref = imported(a.ref)
        for o in ref:
            if o.type == "MESH" and (kitlib.is_stray(o, kitlib.armature_of(ref)) or "Gun" in o.name or o.parent_bone):
                o.hide_render = True
        for o in ref:
            if o.parent is None:
                o.scale = (0.8, 0.8, 0.8)
                o.location = (2.4, 0.0, 0.0)
                o.rotation_mode = "XYZ"
                o.rotation_euler = (0, 0, math.radians(90))
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.clip_end = 200
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = a.light
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_cavity = False
    sc.display.shading.show_object_outline = False
    sc.display.shading.show_backface_culling = True
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("W")
    sc.world.color = GROUND
    sc.render.image_settings.file_format = "PNG"
    out = Path(a.out).resolve()
    tiles = []
    for view, (*_rest, fill) in VIEWS.items():
        tmp = out.with_name(f"{out.stem}_{view}.png")
        render(cam, view, int(a.tile * fill), tmp)
        tiles.append(load(tmp))
        if not a.keep:
            tmp.unlink()
    sheet(tiles, a.tile, 3, out)
    print("SHEET", out)


main()
