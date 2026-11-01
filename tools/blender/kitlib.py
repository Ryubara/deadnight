"""Shared helpers for the headless Blender kit scripts (imported by measure_kit.py and render_sheet.py).

Not run on its own. The scripts that use it put this folder on sys.path first.
"""

import bpy
from mathutils import Vector

# Bones whose children are part of the body (hats, helmets, shoulder pads); meshes parented to any other bone are
# held items (the kit's character files carry every kit weapon in the hand).
BODY_BONES = {"Head", "Neck", "Torso", "Abdomen", "Hips", "Body", "Shoulder.L", "Shoulder.R"}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    """Import a glTF file into an empty scene and return the objects it created."""
    reset()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


def armature_of(objs):
    return next((o for o in objs if o.type == "ARMATURE"), None)


def rest_pose(objs):
    """Put every armature in its rest pose so measurements do not depend on the imported clip."""
    for o in objs:
        if o.type == "ARMATURE":
            o.data.pose_position = "REST"
            if o.animation_data:
                o.animation_data.action = None
    bpy.context.view_layer.update()


def is_stray(o, arm):
    """An unparented helper mesh left in a rigged file (the kit's characters carry an 80-tri Icosphere)."""
    return arm is not None and o.type == "MESH" and o.parent is None


def split_parts(objs):
    """Split the meshes of one file into body, held items and strays."""
    arm = armature_of(objs)
    body, held, stray = [], [], []
    for o in objs:
        if o.type != "MESH":
            continue
        if is_stray(o, arm):
            stray.append(o)
        elif arm is None:
            body.append(o)
        elif any(m.type == "ARMATURE" for m in o.modifiers) or o.parent_type != "BONE" or o.parent_bone in BODY_BONES:
            body.append(o)
        else:
            held.append(o)
    return body, held, stray


def world_verts(o):
    """World-space vertex positions of the evaluated mesh (modifiers and pose applied)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    mw = o.matrix_world
    pts = [mw @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def bbox(points):
    mn = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    mx = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return mn, mx


def tris(o):
    me = o.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)
