"""Render Soldier looks front, side and back on a 0.5 m grid, at the game's size, in one clip frame (#678).

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/render_soldier_views.py -- \
        --model "He=<previews>/greaser.glb" --model "She=<previews>/greaser_female.glb" \
        [--pose Idle | --pose Sprint_Rifle@6] [--clips game/assets/characters/soldier/sprint/soldier_sprint.glb] \
        --out <workspace>/scratch/deadnight/<branch>/views.png

Each `--model` is Title=path.glb (build_soldier_parts.py --preview writes one per preset, `<id>.glb` as built and
`<id>_<other body>.glb` worn by the other character). The models stand side by side in three groups (front, side
seen from their right, back), scaled to the game's 0.8, in front of a wall with a line every 0.5 m (a darker one
every metre) and on a floor line, orthographic, Workbench in the atlas colours. `--pose` names a clip and an optional
frame (the clip's first frame by default); `--clips` imports the clips of another file of the Soldier's (same bones),
for the sprint, strike, downed and revive clips that the parts file does not carry.
"""

import argparse
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

GAME_SCALE = 0.8  # the player scene's scale on the Soldier (style bible)
GAP = 0.25  # metres between two models of a group
GROUP_GAP = 0.9  # metres between the front, side and back groups
WALL_Y = 1.2  # the grid wall behind the models
VIEWS = (("front", 0.0), ("side", 90.0), ("back", 180.0))


def clean(name):
    return re.sub(r"\.\d+$", "", name.split("|")[-1])


def import_clips(path):
    """The actions of another Soldier file, by clean name; its objects are removed."""
    before_objs, before_acts = set(bpy.data.objects), set(bpy.data.actions)
    kitlib.gltf_import(path)
    for o in [o for o in bpy.data.objects if o not in before_objs]:
        bpy.data.objects.remove(o)
    return {clean(a.name): a for a in bpy.data.actions if a not in before_acts}


def load(path, clip, frame, extra):
    before_objs, before_acts = set(bpy.data.objects), set(bpy.data.actions)
    kitlib.gltf_import(path)
    objs = [o for o in bpy.data.objects if o not in before_objs]
    kitlib.apply_base_colours(objs, path)
    kitlib.base_colour_active()
    own = {clean(a.name): a for a in bpy.data.actions if a not in before_acts}
    arm = kitlib.armature_of(objs)
    action = own.get(clip) or extra.get(clip)
    assert action is not None, f"no clip {clip} in {path}"
    arm.animation_data_create()
    arm.animation_data.action = action
    if action.slots:  # Blender 5: an action plays only through a slot
        arm.animation_data.action_slot = action.slots[0]
    arm.data.pose_position = "POSE"
    bpy.context.scene.frame_set(int(action.frame_range[0]) + frame)
    for r in (o for o in objs if o.parent is None):
        r.matrix_world = Matrix.Scale(GAME_SCALE, 4) @ r.matrix_world
    bpy.context.view_layer.update()
    body = [o for o in objs if o.type == "MESH"]
    return objs, body


def bounds(body):
    pts = [p for o in body for p in kitlib.world_verts(o)]
    return kitlib.bbox(pts)


def stand(objs, body, yaw, x0):
    """Turn the model by `yaw` degrees about its feet, put its left edge at x0 and its feet on z 0."""
    roots = [o for o in objs if o.parent is None]
    mn, mx = bounds(body)
    c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, 0))
    turn = Matrix.Translation(c) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Translation(-c)
    for r in roots:
        r.matrix_world = turn @ r.matrix_world
    bpy.context.view_layer.update()
    mn, mx = bounds(body)
    off = Vector((x0 - mn.x, -(mn.y + mx.y) / 2, -mn.z))
    for r in roots:
        r.matrix_world = Matrix.Translation(off) @ r.matrix_world
    bpy.context.view_layer.update()
    return mx.x - mn.x, mx.z - mn.z


def flat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
    return m


def quad(name, x0, x1, z0, z1, y, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new(name, me)
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(o)


def text(body, x, z, size, mat):
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = "CENTER"
    o = bpy.data.objects.new("label", cu)
    o.location = (x, WALL_Y - 0.05, z)
    o.rotation_euler = (math.radians(90), 0, 0)
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(o)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", action="append", required=True, help="Title=path.glb")
    ap.add_argument("--pose", default="Idle", help="Clip or Clip@frame")
    ap.add_argument("--clips", action="append", default=[], help="another Soldier file whose clips --pose may name")
    ap.add_argument("--title", default="")
    ap.add_argument("--px-per-m", type=int, default=420)
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)

    kitlib.reset()
    clip, _, frame = args.pose.partition("@")
    extra = {}
    for path in args.clips:
        extra.update(import_clips(path))
    ink = flat("Ink", (0.03, 0.03, 0.03))
    wall = flat("Wall", (0.80, 0.80, 0.78))
    line = flat("Line", (0.62, 0.62, 0.60))
    metre = flat("Metre", (0.38, 0.38, 0.37))

    cursor, tallest, labels = 0.4, 0.0, []
    for view, yaw in VIEWS:
        start = cursor
        for spec in args.model:
            title, path = spec.split("=", 1)
            objs, body = load(path, clip, int(frame or 0), extra)
            w, h = stand(objs, body, yaw, cursor)
            labels.append((cursor + w / 2, title))
            tallest = max(tallest, h)
            cursor += w + GAP
        labels.append(((start + cursor - GAP) / 2, None, view))
        cursor += GROUP_GAP - GAP
    width = cursor - GROUP_GAP + 0.6
    top = math.ceil((tallest + 0.1) * 2) / 2

    quad("wall", -0.2, width + 0.2, -0.6, top + 0.2, WALL_Y, wall)
    for i in range(int(top / 0.5) + 1):  # rows every 0.5 m, a darker line every metre
        z = i * 0.5
        quad(f"row{i}", -0.2, width + 0.2, z - 0.006, z + 0.006, WALL_Y - 0.01, metre if i % 2 == 0 else line)
        text(f"{z:g} m", 0.15, z + 0.03, 0.07, ink)
    for j in range(int(width / 0.5) + 1):
        x = 0.3 + j * 0.5
        quad(f"col{j}", x - 0.006, x + 0.006, 0.0, top, WALL_Y - 0.01, line)
    quad("floor", -0.2, width + 0.2, -0.02, 0.0, -1.5, ink)
    for entry in labels:
        if entry[1] is None:
            text(entry[2], entry[0], -0.42, 0.11, ink)
        else:
            text(entry[1], entry[0], -0.2, 0.08, ink)
    if args.title:
        text(args.title, width / 2, top + 0.05, 0.1, ink)

    bottom, ceiling = -0.55, top + 0.25
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(width, ceiling - bottom)
    cam.location = (width / 2, -20, (ceiling + bottom) / 2)
    cam.rotation_euler = (math.radians(90), 0, 0)
    cam.data.clip_end = 100
    scene = bpy.context.scene
    scene.collection.objects.link(cam)
    scene.camera = cam
    r = scene.render
    r.engine = "BLENDER_WORKBENCH"
    r.resolution_x = round(width * args.px_per_m)
    r.resolution_y = round((ceiling - bottom) * args.px_per_m)
    r.resolution_percentage = 100
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
