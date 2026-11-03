"""Render a contact sheet of exported small-map kit pieces beside the game's Soldier, a zombie and drive-in props.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/render_smallmap_sheet.py -- --out <scratch>/sheet.png \
        --names wall_door_narrow,door_purchase,... [--dir game/assets/smallmap] [--view front|back] [--boards]

It imports the written glTF files (so the sheet shows what the game gets), stands them left to right on the kit's
0.5 m grid (a brighter line every 2 m) after the Soldier (1.8 m), a zombie (1.63 m in its Idle) and the drive-in
`--compare` props at their own scale, and renders a three-quarter orthographic Workbench view in the atlas colours.
`--boards` puts five window boards across every zombie window, where the window fixture's markers put them. A
name `a+b` stands b at a's origin (a door leaf in its doorway). Kit pieces stand at their own origin's height (a beam
hangs at 2.4-2.8 m); `name@3` lifts one by 3 m (an upper floor's edge, one storey up).
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib
from build_kit_blockout import bounds, character, grid_floor, place
from smallmap_kit import SILL, WALL_T, WIN_H, atlas_material

GAP = 0.6


def imported(path):
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    return [o for o in bpy.data.objects if o not in before]


def boards_for(folder, thick):
    """Five boards on the zombie window's room face (build_smallmap_walls.board_slots)."""
    out = []
    for i in range(5):
        z = SILL + 0.17 + i * (WIN_H - 0.34) / 4
        tilt = (-4, 3, -2, 5, -3)[i]
        b = imported(folder / "window_board.gltf")
        for o in b:
            if o.parent is None:
                o.matrix_world = (
                    Matrix.Translation((0.03 * (-1) ** i, -(thick / 2 + 0.04 + 0.025), z))
                    @ Matrix.Rotation(math.radians(tilt), 4, "Y")
                    @ o.matrix_world
                )
        out += b
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="game/assets/smallmap")
    ap.add_argument("--names", required=True)
    ap.add_argument("--soldier", default="game/assets/characters/soldier/soldier.glb")
    ap.add_argument("--zombie", default="game/assets/characters/zombies/zombie_farmhand.glb")
    ap.add_argument("--compare", default="game/assets/drivein/trash_can.gltf,game/assets/drivein/ticket_booth.gltf")
    ap.add_argument("--view", default="front", choices=("front", "back"))
    ap.add_argument("--boards", action="store_true")
    ap.add_argument("--px", type=int, default=3000)
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    folder = Path(a.dir)
    groups = []
    if a.soldier:
        groups.append(character(a.soldier, 1.8))
    if a.zombie:
        groups.append(character(a.zombie, 1.63))
    for path in filter(None, a.compare.split(",")):
        groups.append(imported(path))
    lifts = {}
    for entry in a.names.split(","):
        entry, _, lift = entry.partition("@")
        objs = []
        for name in entry.split("+"):
            objs += imported(folder / f"{name}.gltf")
            if a.boards and name.startswith("wall_window_zombie"):
                objs += boards_for(folder, 0.2 if name.endswith("_upper") else WALL_T)
        groups.append(objs)
        lifts[id(objs)] = float(lift or 0.0)
    x = 0.0
    for objs in groups:
        mn, mx = bounds(objs)
        z = lifts.get(id(objs), -mn.z)  # characters and props stand on the grid
        place(objs, (x - mn.x, 0.0, z))
        x += (mx.x - mn.x) + GAP
    allobjs = [o for g in groups for o in g]
    mn, mx = bounds(allobjs)
    img = bpy.data.images.load(str((folder / "smallmap_palette.png").resolve()))
    grid_floor(
        atlas_material(img, "Grid"), Vector((math.floor(mn.x) - 0.5, -3.0, 0)), Vector((math.ceil(mx.x) + 0.5, 3.0, 0))
    )
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    ang = math.radians(24 if a.view == "front" else 180 + 24)
    d = Vector((math.sin(ang), -math.cos(ang), 0.3)).normalized()
    centre = (mn + mx) / 2
    cam.location = centre + d * 60
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    span = mx - mn
    cam.data.ortho_scale = max(span.x * 1.02, span.z * 3.0)
    cam.data.clip_end = 200
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_cavity = True
    sc.display.shading.show_object_outline = True
    sc.render.resolution_x = a.px
    sc.render.resolution_y = int(a.px * 0.36)
    sc.world = bpy.data.worlds.new("W")
    sc.world.color = (0.03, 0.035, 0.06)
    sc.render.filepath = str(Path(a.out).resolve())
    bpy.ops.render.render(write_still=True)
    print("SHEET", sc.render.filepath)


main()
