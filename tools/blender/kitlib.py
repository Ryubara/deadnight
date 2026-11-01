"""Shared helpers for the headless Blender kit scripts (imported by measure_kit.py and render_sheet.py).

Not run on its own. The scripts that use it put this folder on sys.path first.
"""

import json
import re
import struct
from pathlib import Path

import bpy
from mathutils import Vector

# Meshes parented to a hand bone are held items (the kit's character files carry every kit weapon in the right hand);
# meshes parented to any other bone (helmets, shoulder pads) are part of the body.
HAND_BONE_PREFIXES = ("LowerArm", "Hand", "Wrist", "Palm", "Index", "Middle", "Ring", "Pinky", "Thumb")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def gltf_import(path, merge=False):
    """The one glTF import call every script uses.

    `bone_heuristic="TEMPERANCE"`: with the default ("BLENDER") Blender re-orients the bones and the meshes parented
    to a bone (the kit's helmets, vests, shoulder pads and held weapons) land in the wrong place: the Soldier's
    shoulder pads float by his helmet on the wrong side. TEMPERANCE keeps them where the file puts them.
    """
    bpy.ops.import_scene.gltf(filepath=str(path), merge_vertices=merge, bone_heuristic="TEMPERANCE")


def import_glb(path, merge=False):
    """Import a glTF file into an empty scene and return the objects it created.

    `merge` welds the vertices glTF splits at every normal seam, so faces share edges again (bevel and part counts
    need it; it does not change the triangle count).
    """
    reset()
    before = set(bpy.data.objects)
    gltf_import(path, merge)
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
        elif o.parent_type == "BONE" and o.parent_bone.startswith(HAND_BONE_PREFIXES):
            held.append(o)
        else:
            body.append(o)
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


def gltf_base_colours(path):
    """Material name -> linear baseColorFactor, read from the .glb's JSON chunk.

    Read from the file, not the Blender material: where a mesh carries a COLOR_0 attribute the importer feeds Base
    Color through a vertex-colour node and leaves the socket at its 0.8 default.
    """
    data = Path(path).read_bytes()
    n = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20 : 20 + n])
    return {
        m.get("name", ""): m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
        for m in doc.get("materials", [])
    }


def base_colour_active():
    """Make each material's Base Color image node the active node: Workbench's texture colour shows the active one,
    and a material with an emission map (the boss zombie) otherwise renders its black emission map."""
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        for link in m.node_tree.links:
            if link.to_socket.name == "Base Color" and link.from_node.type == "TEX_IMAGE":
                m.node_tree.nodes.active = link.from_node


def apply_base_colours(objs, path):
    """Set each material's viewport colour (what Workbench draws) to its glTF base colour."""
    factors = gltf_base_colours(path)
    for o in objs:
        for slot in getattr(o, "material_slots", []):
            mat = slot.material
            if mat:
                f = factors.get(mat.name) or factors.get(re.sub(r"\.\d{3}$", "", mat.name))
                if f:
                    mat.diffuse_color = f
