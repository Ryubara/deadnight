"""Side-on sheets of the climb clips at the sill (Deadnight #991): each tile puts the zombie's origin where the
simulation has it at that frame, beside a section of the thickest wall with its sill and its lintel.

    blender -b --factory-startup -P tools/blender/render_climb.py -- \
        --zombie <workspace>/refs/polypizza/VlXjG0N8Eg/model.glb --out <scratch folder>/climb
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_zombie_clips as zc
import build_zombies as bz

TILE_W, TILE_H = 420, 380
FRAMES = (0, 4, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35, 38, 41, 44)
COLUMNS = 5
LINTEL = 2.2


def box(name, depth, height, half_depth, half_height, colour):
    """A box of the wall's section in the file's world, at a game-metre place."""
    bpy.ops.mesh.primitive_cube_add(size=2, location=(0, -depth, height))
    ob = bpy.context.object
    ob.name = name
    ob.scale = (0.75, half_depth, half_height)
    ob.color = (*colour, 1)
    return ob


def camera():
    data = bpy.data.cameras.new("side")
    data.type = "ORTHO"
    data.ortho_scale = 3.6
    ob = bpy.data.objects.new("side", data)
    bpy.context.collection.objects.link(ob)
    ob.location = (-6.0, 0.0, 1.0)
    ob.rotation_euler = (math.pi / 2, 0, -math.pi / 2)
    return ob


def setup():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_object_outline = True
    scene.render.resolution_x, scene.render.resolution_y = TILE_W, TILE_H
    scene.render.image_settings.file_format = "PNG"


def clearance(arm, body, action):
    """How far the skinned mesh goes into the wall, frame by frame: the deepest vertex under the sill's top inside the
    wall (m), and the highest point over the lintel's underside, in game metres (printed, for tuning)."""
    worst = []
    for frame in range(zc.CLIMB_FRAMES + 1):
        bpy.context.scene.frame_set(frame)
        at, lift = zc.climb_origin(frame)
        arm.scale = (zc.GAIT_SCALE,) * 3
        arm.location = (0, -at, lift)
        graph = bpy.context.evaluated_depsgraph_get()
        evaluated = body.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        into, top, part = 0.0, 0.0, ""
        for v in mesh.vertices:
            p = evaluated.matrix_world @ v.co
            if abs(p.y) < zc.WALL / 2:
                deep = min(zc.SILL - p.z, zc.WALL / 2 - abs(p.y))
                top = max(top, p.z)
                if deep > into:
                    into = deep
                    held = body.data.vertices[v.index].groups
                    part = body.vertex_groups[max(held, key=lambda g: g.weight).group].name if len(held) else ""
        evaluated.to_mesh_clear()
        worst.append((frame, round(into, 3), part, round(top, 2)))
    print("CLIMB_WALL", action, [w for w in worst if w[1] > 0.0], "top", max(w[3] for w in worst))


def sheet(arm, clip, path):
    scene = bpy.context.scene
    ad = arm.animation_data
    for t in ad.nla_tracks:
        t.mute = True
    action = bpy.data.actions[clip]
    ad.action = action
    if hasattr(ad, "action_slot") and action.slots:
        ad.action_slot = action.slots[0]
    tiles = []
    tmp = path.with_suffix(".tile.png")
    for frame in FRAMES:
        scene.frame_set(frame)
        at, lift = zc.climb_origin(frame)
        arm.scale = (zc.GAIT_SCALE,) * 3
        arm.location = (0, -at, lift)
        bpy.context.view_layer.update()
        scene.render.filepath = str(tmp)
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(str(tmp))
        tiles.append(np.array(img.pixels[:], dtype=np.float32).reshape(TILE_H, TILE_W, 4))
        bpy.data.images.remove(img)
    tmp.unlink()
    rows = [np.hstack(tiles[i : i + COLUMNS]) for i in range(0, len(tiles), COLUMNS)]
    out = bpy.data.images.new("sheet", TILE_W * COLUMNS, TILE_H * len(rows))
    out.pixels[:] = np.vstack(rows[::-1]).ravel()
    out.filepath_raw = str(path)
    out.file_format = "PNG"
    out.save()
    ad.action = None
    arm.scale = (1, 1, 1)
    arm.location = (0, 0, 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zombie", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--clips", default=f"{zc.CLIMB},{zc.CRAWL_CLIMB}")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    arm, body, _kit = bz.clean(args.zombie)
    zc.build(arm)
    body.color = (0.45, 0.6, 0.3, 1)
    wall = zc.WALL / 2
    box("Sill", 0, zc.SILL / 2, wall, zc.SILL / 2, (0.5, 0.45, 0.4))
    box("Lintel", 0, LINTEL + 0.4, wall, 0.4, (0.5, 0.45, 0.4))
    box("Floor", 0, -0.05, 2.5, 0.05, (0.3, 0.3, 0.3))
    bpy.context.scene.camera = camera()
    setup()
    for clip in args.clips.split(","):
        if clip in bpy.data.actions:
            sheet(arm, clip, args.out.with_name(f"{args.out.name}-{clip}.png"))
            action = bpy.data.actions[clip]
            arm.animation_data.action = action
            if hasattr(arm.animation_data, "action_slot") and action.slots:
                arm.animation_data.action_slot = action.slots[0]
            clearance(arm, body, clip)
            arm.animation_data.action = None


if __name__ == "__main__":
    main()
