"""Shared helpers for Deadnight's marketing renders (app icon, key art): load the game's own models, pose them,
put the weapon in the hand the way the game does, and build the night look in Cycles.

Not run on its own: the shot scripts put this folder on sys.path first. Run with the pinned Blender, headless only.
"""

import json
import math
import re
import struct
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

GAME = Path(__file__).resolve().parents[3] / "game"
ASSETS = GAME / "assets"
SOLDIER_GLB = ASSETS / "characters/soldier_parts/soldier_parts.glb"
SOLDIER_ATLAS = ASSETS / "characters/soldier_parts/soldier_parts_atlas.png"
PARTS = json.loads((ASSETS / "characters/soldier_parts/parts.json").read_text())

# Game scales (docs/design/style.md, player_tuning.gd, zombie_models.gd).
SOLDIER_SCALE = 0.8
ZOMBIE_SCALE = 1.3
HAND_BONE = "Index1.R"
# The weapon scene's transform under a BoneAttachment3D on Index1.R (player_animation.gd), Godot axes.
HOLD_GUN = (
    (-0.062527, -0.997926, -0.015303),
    (0.118606, -0.022655, 0.992683),
    (-0.990971, 0.060254, 0.119776),
    (-0.039563, 0.197228, -0.070351),
)
HOLDS = {  # class: (glb, model_scale, support point in model units)
    "Rifle": ("weapons/lever_rifle/lever_rifle.glb", 0.71, (-0.45, -0.05, 0.0)),
    "Shotgun": ("weapons/double_shotgun/double_shotgun.glb", 0.82, (-0.45, -0.03, 0.0)),
    "Tommy": ("weapons/tommy_gun/tommy_gun.glb", 0.78, (-0.42, -0.06, 0.0)),
}

# glTF (Y up) to Blender (Z up).
M_GL = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def srgb_to_lin(c):
    c = c / 255.0 if c > 1 else c
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexrgb(h, linear=True):
    h = h.lstrip("#")
    rgb = [int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(srgb_to_lin(c) for c in rgb) if linear else tuple(rgb)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def gltf_doc(path):
    data = Path(path).read_bytes()
    if Path(path).suffix.lower() == ".gltf":
        return json.loads(data)
    n = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20 : 20 + n])


def import_gltf(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="TEMPERANCE")
    return [o for o in bpy.data.objects if o not in before]


def node_globals(doc):
    """Rest global matrix (glTF space) of every node, by name."""
    nodes = doc["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def local(n):
        t = Vector(n.get("translation", (0, 0, 0)))
        r = n.get("rotation", (0, 0, 0, 1))
        s = n.get("scale", (1, 1, 1))
        q = Quaternion((r[3], r[0], r[1], r[2]))
        return Matrix.Translation(t) @ q.to_matrix().to_4x4() @ Matrix.Diagonal((*s, 1))

    out = {}

    def glob(i):
        m = local(nodes[i])
        return glob(parent[i]) @ m if i in parent else m

    for i, n in enumerate(nodes):
        out[n.get("name", str(i))] = glob(i)
    return out


def mute_nla(arm):
    ad = arm.animation_data
    if ad:
        for t in ad.nla_tracks:
            t.mute = True


ACTIONS = {}


def take_actions(arm, before):
    """Remember the actions an import created, for this armature (a second import names them Idle.001...)."""
    ACTIONS[arm.name] = {re.sub(r"\.\d+$", "", a.name): a for a in bpy.data.actions if a not in before}


def set_pose(arm, clip, frame=0.0):
    """Put a clip's pose at a frame (from the clip's start) on the armature and bake it into the pose bones, so
    nothing else moves it. Mutes the NLA (lesson: a pose set by hand read back as the NLA track's)."""
    if arm.animation_data is None:
        arm.animation_data_create()
    mute_nla(arm)
    action = ACTIONS[arm.name].get(clip)
    if action is None:
        raise RuntimeError(f"no clip {clip}: {sorted(ACTIONS[arm.name])}")
    arm.animation_data.action = action
    if hasattr(arm.animation_data, "action_slot") and action.slots:
        arm.animation_data.action_slot = action.slots[0]
    f = action.frame_range[0] + frame
    bpy.context.scene.frame_set(int(f), subframe=f % 1.0)
    bpy.context.view_layer.update()
    mats = {pb.name: pb.matrix_basis.copy() for pb in arm.pose.bones}
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis = mats[pb.name]
    bpy.context.view_layer.update()
    return action


def place(obj, location, yaw_deg, scale):
    """Move an imported root: keep its import matrix (the Y-up to Z-up turn), then scale, yaw and move it."""
    base = obj.get("_base")
    if base is None:
        obj["_base"] = [v for row in obj.matrix_world for v in row]
        base = obj["_base"]
    m = Matrix([base[0:4], base[4:8], base[8:12], base[12:16]])
    obj.matrix_world = (
        Matrix.Translation(location) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z") @ Matrix.Scale(scale, 4) @ m
    )
    bpy.context.view_layer.update()


def flat_atlas_material(name, image, roughness=0.6, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    if emission is not None:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def soldier_atlas(colours, tag):
    """The parts atlas with row 0 painted for a look, as SoldierLook does (shade = colour x shade)."""
    src = bpy.data.images.load(str(SOLDIER_ATLAS))
    w, h = src.size
    px = np.array(src.pixels[:], dtype=np.float32).reshape(h, w, 4)
    sw = PARTS["atlas"]["swatch_px"]
    cells = PARTS["atlas"]["cells"]
    shade = PARTS["shade"]
    for ch, pal in PARTS["channels"].items():
        col = PARTS["palettes"][pal][colours[ch] % len(PARTS["palettes"][pal])]
        rgb = np.array(hexrgb(col, linear=False))
        for key, mul in ((ch, 1.0), (ch + "_shade", shade)):
            cx, cy = cells[key]
            # Blender pixel rows run bottom-up; atlas row 0 is the top.
            y0 = h - (cy + 1) * sw
            px[y0 : y0 + sw, cx * sw : (cx + 1) * sw, :3] = rgb * mul
    img = bpy.data.images.new(f"soldier_atlas_{tag}", w, h, alpha=True)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(px.ravel())
    img.update()
    bpy.data.images.remove(src)
    return img


def load_soldier(look, colours, clip="Idle", frame=0.0, tag="p1", location=(0, 0, 0), yaw_deg=0.0, scale=SOLDIER_SCALE):
    """The player model dressed in a look (parts per slot) and posed. Returns (armature, meshes)."""
    before = set(bpy.data.actions)
    objs = import_gltf(SOLDIER_GLB)
    arm = next(o for o in objs if o.type == "ARMATURE")
    arm.name = f"Soldier_{tag}"
    take_actions(arm, before)
    keep = set()
    hides_hair = False
    for slot, spec in PARTS["slots"].items():
        part = look.get(slot, spec["default"])
        p = spec["parts"][part]
        if p.get("hides_hair"):
            hides_hair = True
        if p["mesh"]:
            keep.add((slot, p["mesh"]))
    names = {m for s, m in keep if not (s == "hair" and hides_hair)}
    img = soldier_atlas(colours, tag)
    mat = flat_atlas_material(f"SoldierParts_{tag}", img)
    meshes = []
    for o in objs:
        if o.type != "MESH":
            continue
        if re.sub(r"\.\d+$", "", o.name) not in names:
            bpy.data.objects.remove(o)
            continue
        o.data.materials.clear()
        o.data.materials.append(mat)
        o.name = f"{tag}_{o.name}"
        meshes.append(o)
    set_pose(arm, clip, frame)
    place(arm, location, yaw_deg, scale)
    return arm, meshes


def godot_transform(rows):
    """Godot's Transform3D(Basis(x, y, z), origin) as a 4x4 (Basis columns are x, y, z)."""
    x, y, z, o = rows
    return Matrix(((x[0], y[0], z[0], o[0]), (x[1], y[1], z[1], o[1]), (x[2], y[2], z[2], o[2]), (0, 0, 0, 1)))


def attach_weapon(arm, cls, tag="w", extra=None):
    """The class's weapon in the right hand, where the game puts it (HOLD_GUN under Index1.R, the hold's scale).
    `C` is computed in armature space at rest, so it holds for any armature transform."""
    glb, scale, support = HOLDS[cls]
    doc = gltf_doc(SOLDIER_GLB)
    g = node_globals(doc)
    # Rest frame of the bone in glTF armature space; the armature node itself carries the root rotation, and the
    # Blender armature object stands for that node. So express everything relative to the armature node.
    arm_node = "CharacterArmature"
    rel = g[arm_node].inverted() @ g[HAND_BONE]
    # In Blender, the armature object's space corresponds to the armature node's glTF space mapped by M_GL, but the
    # importer folds the node's own rotation into the object; armature-space coordinates are glTF-armature-local
    # converted by M_GL.
    f_rest_arm = M_GL @ rel
    c = arm.data.bones[HAND_BONE].matrix_local.inverted() @ f_rest_arm
    objs = import_gltf(ASSETS / glb)
    root = next(o for o in objs if o.parent is None and o.type == "MESH")
    for o in objs:
        if o.parent is None and o is not root:
            o.parent = root
    h = godot_transform(HOLD_GUN) @ Matrix.Scale(scale, 4)
    pb = arm.pose.bones[HAND_BONE]
    w = arm.matrix_world @ pb.matrix @ c @ h @ M_GL.inverted()
    if extra is not None:
        w = w @ extra
    root.matrix_world = w
    root.name = f"{tag}_{cls}"
    # Parent to the bone, keeping the world transform.
    mw = root.matrix_world.copy()
    root.parent = arm
    root.parent_type = "BONE"
    root.parent_bone = HAND_BONE
    bpy.context.view_layer.update()
    root.matrix_world = mw
    bpy.context.view_layer.update()
    sup_world = root.matrix_world @ (M_GL @ Vector(support))
    return root, sup_world


def two_bone_reach(arm, upper, lower, end, target_world, pole_world):
    """Rotate `upper` and `lower` so the head of `end` reaches the target (lengths measured from the pose, not the
    importer's arbitrary bone tails; lesson: Blender IK cannot solve glTF-imported legs)."""
    mw = arm.matrix_world
    inv = mw.inverted()
    pu, pl, pe = (arm.pose.bones[n] for n in (upper, lower, end))
    a = pu.head.copy()
    b = pl.head.copy()
    e = pe.head.copy()
    l1 = (b - a).length
    l2 = (e - b).length
    t = inv @ target_world
    pole = inv @ pole_world
    d = t - a
    dist = min(d.length, (l1 + l2) * 0.999)
    dn = d.normalized()
    # Elbow position: law of cosines in the plane of (a, t, pole).
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    cos_a = max(-1, min(1, cos_a))
    pv = pole - a
    pv = (pv - dn * pv.dot(dn)).normalized()
    elbow = a + dn * (l1 * cos_a) + pv * (l1 * math.sqrt(1 - cos_a * cos_a))
    wrist = a + dn * dist

    def aim(pbone, cur_from, cur_to, new_to):
        q = (cur_to - cur_from).rotation_difference(new_to - cur_from)
        m = pbone.matrix.copy()
        loc = m.to_translation()
        r = q.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ m
        pbone.matrix = Matrix.Translation(loc) @ r
        bpy.context.view_layer.update()

    aim(pu, a, b, elbow)
    b2 = arm.pose.bones[lower].head.copy()
    e2 = arm.pose.bones[end].head.copy()
    aim(arm.pose.bones[lower], b2, e2, wrist)


def load_zombie(variant, clip="Walk", frame=0.0, location=(0, 0, 0), yaw_deg=0.0, scale=ZOMBIE_SCALE, tag=None):
    before = set(bpy.data.actions)
    objs = import_gltf(ASSETS / f"characters/zombies/zombie_{variant}.glb")
    arm = next(o for o in objs if o.type == "ARMATURE")
    tag = tag or variant
    arm.name = f"Zombie_{tag}"
    take_actions(arm, before)
    meshes = []
    for o in objs:
        if o.type == "MESH" and "Far" in o.name:
            bpy.data.objects.remove(o)
        elif o.type == "MESH":
            meshes.append(o)
    for o in meshes:
        for slot in o.material_slots:
            m = slot.material
            if m and m.use_nodes:
                b = m.node_tree.nodes.get("Principled BSDF")
                if b:
                    b.inputs["Metallic"].default_value = 0.0
                    b.inputs["Roughness"].default_value = 0.6
                for n in m.node_tree.nodes:
                    if n.type == "TEX_IMAGE":
                        n.interpolation = "Closest"
    set_pose(arm, clip, frame)
    place(arm, location, yaw_deg, scale)
    return arm, meshes


def load_prop(path, location=(0, 0, 0), yaw_deg=0.0, scale=1.0, name=None):
    objs = import_gltf(ASSETS / path)
    roots = [o for o in objs if o.parent is None]
    for o in objs:
        if o.type == "MESH":
            for slot in o.material_slots:
                m = slot.material
                if m and m.use_nodes:
                    b = m.node_tree.nodes.get("Principled BSDF")
                    if b:
                        b.inputs["Metallic"].default_value = 0.0
                        b.inputs["Roughness"].default_value = 0.6
                    for n in m.node_tree.nodes:
                        if n.type == "TEX_IMAGE":
                            n.interpolation = "Closest"
    for r in roots:
        place(r, location, yaw_deg, scale)
        if name:
            r.name = name
    bpy.context.view_layer.update()
    return roots


def world_bbox(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = o.matrix_world
        pts.extend(mw @ v.co for v in me.vertices)
        ev.to_mesh_clear()
    a = np.array([tuple(p) for p in pts])
    return Vector(a.min(0)), Vector(a.max(0))


# ---------------------------------------------------------------- look: lights, emissives, fog, camera


def emissive_material(name, rgb, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return mat


def flat_material(name, rgb, roughness=0.6):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = 0.0
    return mat


def screen_material(strength=6.0, seed=0.0):
    """The drive-in screen's face: drifting patches of cool and warm light with a vignette (the game's
    screen.gdshader look), as an emissive."""
    mat = bpy.data.materials.new("ScreenFace")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.6
    noise.inputs["Detail"].default_value = 2.0
    noise.noise_dimensions = "4D"
    w_in = noise.inputs.get("W")
    if w_in is not None:
        w_in.default_value = seed
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.35
    cr.elements[0].color = (*hexrgb("#7fa6d8"), 1)
    cr.elements[1].position = 0.7
    cr.elements[1].color = (*hexrgb("#e8f0ff"), 1)
    e = cr.elements.new(0.52)
    e.color = (*hexrgb("#c9b48a"), 1)
    # Vignette: distance from the UV centre.
    nt.nodes.new("ShaderNodeSeparateXYZ")
    sub = nt.nodes.new("ShaderNodeVectorMath")
    sub.operation = "SUBTRACT"
    sub.inputs[1].default_value = (0.5, 0.5, 0)
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = (1.0, 2.2, 0)
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    vr = nt.nodes.new("ShaderNodeMapRange")
    vr.inputs["From Min"].default_value = 0.25
    vr.inputs["From Max"].default_value = 0.75
    vr.inputs["To Min"].default_value = 1.0
    vr.inputs["To Max"].default_value = 0.45
    smul = nt.nodes.new("ShaderNodeMath")
    smul.operation = "MULTIPLY"
    smul.inputs[1].default_value = strength
    nt.links.new(tc.outputs["UV"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(tc.outputs["UV"], sub.inputs[0])
    nt.links.new(sub.outputs[0], mul.inputs[0])
    nt.links.new(mul.outputs[0], ln.inputs[0])
    nt.links.new(ln.outputs["Value"], vr.inputs["Value"])
    nt.links.new(vr.outputs["Result"], smul.inputs[0])
    nt.links.new(smul.outputs[0], em.inputs["Strength"])
    nt.links.new(em.outputs[0], out.inputs[0])
    return mat


def plane(name, size_x, size_y, location, rotation, mat):
    bpy.ops.mesh.primitive_plane_add(size=1, location=location, rotation=rotation)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size_x, size_y, 1)
    o.data.materials.append(mat)
    return o


def point_light(name, location, rgb, watts, radius=0.1):
    d = bpy.data.lights.new(name, "POINT")
    d.color = rgb
    d.energy = watts
    d.shadow_soft_size = radius
    o = bpy.data.objects.new(name, d)
    o.location = location
    bpy.context.scene.collection.objects.link(o)
    return o


def spot_light(name, location, target, rgb, watts, angle_deg=60, blend=0.6, radius=0.1):
    d = bpy.data.lights.new(name, "SPOT")
    d.color = rgb
    d.energy = watts
    d.spot_size = math.radians(angle_deg)
    d.spot_blend = blend
    d.shadow_soft_size = radius
    o = bpy.data.objects.new(name, d)
    o.location = location
    bpy.context.scene.collection.objects.link(o)
    look_at(o, target)
    return o


def area_light(name, location, target, rgb, watts, size=2.0, size_y=None):
    d = bpy.data.lights.new(name, "AREA")
    d.color = rgb
    d.energy = watts
    d.shape = "RECTANGLE"
    d.size = size
    d.size_y = size_y or size
    o = bpy.data.objects.new(name, d)
    o.location = location
    bpy.context.scene.collection.objects.link(o)
    look_at(o, target)
    return o


def look_at(o, target):
    d = Vector(target) - Vector(o.location)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("-Z", "Y")


def camera(location, target, lens=50.0, name="Camera", roll_deg=0.0):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.clip_start = 0.05
    cd.clip_end = 600
    o = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(o)
    o.location = location
    look_at(o, target)
    if roll_deg:
        o.rotation_quaternion = o.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(roll_deg))
    bpy.context.scene.camera = o
    return o


def world_night(top="#0b1230", horizon="#1c2a55", strength=1.0):
    w = bpy.data.worlds.new("Night")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (*hexrgb(horizon), 1)
    ramp.color_ramp.elements[1].position = 0.45
    ramp.color_ramp.elements[1].color = (*hexrgb(top), 1)
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    return w


def fog_box(center, size, density=0.02, color="#9fb0d8", anisotropy=0.35, ground_boost=2.5, ground_height=2.0):
    """A box of scattering haze, thicker near the ground."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    o = bpy.context.active_object
    o.name = "Fog"
    o.scale = size
    mat = bpy.data.materials.new("Fog")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (*hexrgb(color), 1)
    vol.inputs["Anisotropy"].default_value = anisotropy
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = ground_height
    mr.inputs["To Min"].default_value = density * ground_boost
    mr.inputs["To Max"].default_value = density
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.08
    noise.inputs["Detail"].default_value = 1.5
    nmr = nt.nodes.new("ShaderNodeMapRange")
    nmr.inputs["From Min"].default_value = 0.3
    nmr.inputs["From Max"].default_value = 0.7
    nmr.inputs["To Min"].default_value = 0.45
    nmr.inputs["To Max"].default_value = 1.4
    mulm = nt.nodes.new("ShaderNodeMath")
    mulm.operation = "MULTIPLY"
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(geo.outputs["Position"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], nmr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], mulm.inputs[0])
    nt.links.new(nmr.outputs["Result"], mulm.inputs[1])
    nt.links.new(mulm.outputs[0], vol.inputs["Density"])
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    o.data.materials.append(mat)
    o.visible_shadow = False
    return o


def ground(size=400, color="#2e3038", z=0.0, wet=0.5):
    """Asphalt: two flat tones in blotches (the lot's asphalt pattern), and damp patches that catch the lights
    (`wet` 0 dry, 1 puddles everywhere)."""
    mat = flat_material("Asphalt", hexrgb(color), roughness=0.75)
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.35
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (*hexrgb("#26282f"), 1)
    ramp.color_ramp.elements[1].position = 0.52
    ramp.color_ramp.elements[1].color = (*hexrgb(color), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    wn = nt.nodes.new("ShaderNodeTexNoise")
    wn.inputs["Scale"].default_value = 0.12
    wn.inputs["Detail"].default_value = 3.0
    wr = nt.nodes.new("ShaderNodeMapRange")
    wr.inputs["From Min"].default_value = 0.62 - 0.2 * wet
    wr.inputs["From Max"].default_value = 0.66 - 0.2 * wet
    wr.inputs["To Min"].default_value = 0.8
    wr.inputs["To Max"].default_value = 0.12
    nt.links.new(wn.outputs["Fac"], wr.inputs["Value"])
    nt.links.new(wr.outputs["Result"], b.inputs["Roughness"])
    return plane("Ground", size, size, (0, 0, z), (0, 0, 0), mat)


def cycles(
    samples=256,
    width=1024,
    height=1024,
    device="GPU",
    denoise=True,
    exposure=0.0,
    look="AgX - Medium High Contrast",
    max_bounces=6,
):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    picked = None
    for dev_type in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
        try:
            prefs.compute_device_type = dev_type
            prefs.get_devices()
            gpus = [d for d in prefs.devices if d.type == dev_type]
            if gpus:
                for d in prefs.devices:
                    d.use = d.type == dev_type
                picked = dev_type
                break
        except TypeError:
            continue
    sc.cycles.device = "GPU" if (device == "GPU" and picked) else "CPU"
    print(f"CYCLES device {sc.cycles.device} ({picked})")
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.01
    sc.cycles.use_denoising = denoise
    try:
        sc.cycles.denoiser = "OPTIX" if picked == "OPTIX" else "OPENIMAGEDENOISE"
    except TypeError:
        pass
    sc.cycles.max_bounces = max_bounces
    sc.cycles.volume_bounces = 1
    sc.cycles.volume_step_rate = 4.0
    sc.cycles.volume_max_steps = 256
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.blur_glossy = 1.0
    sc.render.resolution_x = width
    sc.render.resolution_y = height
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "AgX"
    try:
        sc.view_settings.look = look
    except TypeError:
        sc.view_settings.look = "None"
    sc.view_settings.exposure = exposure
    return sc


def glare_compositor(threshold=1.2, size=7, mix=-0.6, strength=1.0):
    """A bloom on the bright bits (lamps, bulbs, screen) in the compositor."""
    sc = bpy.context.scene
    try:
        sc.use_nodes = True
        tree = sc.node_tree
    except AttributeError:
        tree = None
    if tree is None:
        # Blender 5: the compositor is a node group assigned to the scene.
        tree = bpy.data.node_groups.new("KeyArtComp", "CompositorNodeTree")
        sc.compositing_node_group = tree
        tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        rl = tree.nodes.new("CompositorNodeRLayers")
        out = tree.nodes.new("NodeGroupOutput")
    else:
        tree.nodes.clear()
        rl = tree.nodes.new("CompositorNodeRLayers")
        out = tree.nodes.new("CompositorNodeComposite")
    gl = tree.nodes.new("CompositorNodeGlare")
    for attr, val in (
        ("glare_type", "BLOOM"),
        ("quality", "HIGH"),
        ("threshold", threshold),
        ("size", size),
        ("mix", mix),
    ):
        if hasattr(gl, attr):
            try:
                setattr(gl, attr, val)
            except (TypeError, AttributeError):
                pass
    # Blender 5 moved glare settings to input sockets.
    for name, val in (
        ("Type", "Bloom"),
        ("Quality", "High"),
        ("Threshold", threshold),
        ("Size", size / 9.0),
        ("Strength", strength),
        ("Saturation", 1.0),
    ):
        s = gl.inputs.get(name)
        if s is not None:
            try:
                s.default_value = val
            except (TypeError, AttributeError):
                pass
    tree.links.new(rl.outputs["Image"], gl.inputs["Image"])
    tree.links.new(gl.outputs["Image"], out.inputs[0])
    return gl


def render(path):
    sc = bpy.context.scene
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"wrote {path}")


def save_blend(path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)


# ---------------------------------------------------------------- the game's shouldered weapon (WeaponHandsIK)

GRIP_OFFSET = {"Rifle": (0.05, -0.09, -0.32), "Shotgun": (0.05, -0.09, -0.36), "Tommy": (0.05, -0.09, -0.32)}
ELBOW_OUT = 0.45
SUPPORT_HAND_BACK = 0.07


def _hand_correction(arm):
    g = node_globals(gltf_doc(SOLDIER_GLB))
    rel = g["CharacterArmature"].inverted() @ g[HAND_BONE]
    return arm.data.bones[HAND_BONE].matrix_local.inverted() @ (M_GL @ rel)


def shoulder_weapon(
    arm,
    cls,
    facing_deg,
    aim_yaw_deg=0.0,
    aim_pitch_deg=0.0,
    roll_deg=0.0,
    tag="w",
    grip_offset=None,
    left_hand=True,
    body_offset=None,
):
    """WeaponHandsIK in Blender: the weapon's grip at the right shoulder + the hold's grip offset in the aim frame,
    the barrel along the aim, the right hand on the grip through the kit hold, the left on the fore-end.

    `facing_deg` is the character's yaw (0 faces -Y); the aim turns from there."""
    glb, ms, support = HOLDS[cls]
    off = Vector(grip_offset or GRIP_OFFSET[cls])
    char_scale = arm.matrix_world.to_scale().x
    yaw = math.radians(facing_deg + aim_yaw_deg)
    fwd0 = Vector((math.sin(yaw), -math.cos(yaw), 0.0))
    right0 = Vector((-math.cos(yaw), -math.sin(yaw), 0.0))
    up0 = Vector((0, 0, 1))
    pr = Matrix.Rotation(math.radians(aim_pitch_deg), 3, right0)
    fwd = pr @ fwd0
    up = pr @ up0
    right = right0
    if roll_deg:
        rr = Matrix.Rotation(math.radians(roll_deg), 3, fwd)
        up = rr @ up
        right = rr @ right
    shoulder = arm.matrix_world @ arm.pose.bones["UpperArm.R"].head
    grip = shoulder + right * off.x + up * off.y + (-fwd) * off.z
    if body_offset is not None:
        # The grip placed in the body's frame (yaw only), for poses other than the aim (barrel up, low ready).
        bo = Vector(body_offset)
        grip = shoulder + right0 * bo.x + up0 * bo.y + fwd0 * bo.z
    s = char_scale * ms
    # glTF-local weapon axes to world: x -> back, y -> up, z -> left.
    back, left = -fwd, -right
    T = Matrix(
        (
            (back.x * s, up.x * s, left.x * s, grip.x),
            (back.y * s, up.y * s, left.y * s, grip.y),
            (back.z * s, up.z * s, left.z * s, grip.z),
            (0, 0, 0, 1),
        )
    )
    H = godot_transform(HOLD_GUN) @ Matrix.Scale(ms, 4)
    f_bone = T @ H.inverted()  # the hand bone's glTF frame in the world (carries the character's scale)
    c = _hand_correction(arm)
    # Right arm: reach the hand bone's head to its place, then set the bone exactly.
    hand_head = f_bone.to_translation()
    shoulders = [arm.matrix_world @ arm.pose.bones[n].head for n in ("UpperArm.R", "UpperArm.L")]
    side = (shoulders[0] - shoulders[1]).normalized()
    elbow_r = arm.matrix_world @ arm.pose.bones["LowerArm.R"].head
    two_bone_reach(
        arm, "UpperArm.R", "LowerArm.R", HAND_BONE, hand_head, elbow_r + side * ELBOW_OUT + Vector((0, 0, -1))
    )
    arm.pose.bones[HAND_BONE].matrix = arm.matrix_world.inverted() @ f_bone @ c.inverted()
    bpy.context.view_layer.update()
    # The weapon.
    objs = import_gltf(ASSETS / glb)
    root = next(o for o in objs if o.parent is None and o.type == "MESH")
    for o in objs:
        if o.parent is None and o is not root:
            o.parent = root
            o.matrix_parent_inverse = root.matrix_world.inverted()
    root.matrix_world = T @ M_GL.inverted()
    root.name = f"{tag}_{cls}"
    for o in objs:
        if o.type == "MESH":
            for slot in o.material_slots:
                m = slot.material
                if m and m.use_nodes:
                    b = m.node_tree.nodes.get("Principled BSDF")
                    if b:
                        b.inputs["Metallic"].default_value = 0.0
                        b.inputs["Roughness"].default_value = 0.5
                    for n in m.node_tree.nodes:
                        if n.type == "TEX_IMAGE":
                            n.interpolation = "Closest"
    bpy.context.view_layer.update()
    sup = T @ Vector(support)
    if left_hand:
        elbow_l = arm.matrix_world @ arm.pose.bones["LowerArm.L"].head
        wrist_l = arm.matrix_world @ arm.pose.bones["Index1.L"].head
        goal = sup - (wrist_l - elbow_l).normalized() * SUPPORT_HAND_BACK
        two_bone_reach(
            arm, "UpperArm.L", "LowerArm.L", "Index1.L", goal, elbow_l - side * ELBOW_OUT + Vector((0, 0, -1))
        )
    muzzle = next((o for o in objs if o.type == "EMPTY" and o.name.startswith("Muzzle")), None)
    bpy.context.view_layer.update()
    return root, sup, (muzzle.matrix_world.to_translation() if muzzle else None)


def link_light(light, receivers, name=None):
    """Light linking: the light lights only `receivers` (Cycles)."""
    coll = bpy.data.collections.new(name or f"{light.name}_receivers")
    for o in receivers:
        coll.objects.link(o)
    light.light_linking.receiver_collection = coll
    return coll


def char_objects(arm, extra=()):
    return [arm] + [o for o in bpy.data.objects if o.parent == arm] + list(extra)


def frame_camera(cam, point, fx, fy, iterations=12):
    """Turn the camera (no roll) so `point` lands at (fx, fy) of the frame: x from the left, y from the top."""
    from bpy_extras.object_utils import world_to_camera_view

    sc = bpy.context.scene
    look_at(cam, point)
    e = cam.rotation_quaternion.to_euler("XYZ")
    cam.rotation_mode = "XYZ"
    cam.rotation_euler = e
    for _ in range(iterations):
        bpy.context.view_layer.update()
        p = world_to_camera_view(sc, cam, Vector(point))
        dx = p.x - fx
        dy = (1.0 - p.y) - fy
        sw = cam.data.sensor_width
        aspect = sc.render.resolution_y / sc.render.resolution_x
        hx = math.atan(sw / 2 / cam.data.lens) * 2
        hy = math.atan(sw * aspect / 2 / cam.data.lens) * 2
        cam.rotation_euler.z -= dx * hx  # the subject too far right: turn right
        cam.rotation_euler.x -= dy * hy  # the subject too low: tilt down
    bpy.context.view_layer.update()
    p = world_to_camera_view(sc, cam, Vector(point))
    print(f"FRAME {point} -> ({p.x:.3f}, {1 - p.y:.3f}) wanted ({fx}, {fy})")
    return cam
