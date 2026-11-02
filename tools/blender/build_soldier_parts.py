"""Build the modular Soldier: swappable parts on the Soldier's rig, one palette atlas and the eight starting looks.

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/build_soldier_parts.py -- \
        --soldier <bundle>/models/PpLF4rt4ah.glb --out game/assets/characters/soldier_parts \
        [--preview <scratch>/previews]

Writes `soldier_parts.glb` (CharacterArmature, every Soldier clip, one skinned mesh per part named `<slot>__<part>`),
`soldier_parts_atlas.png` and `parts.json` (the catalog the game and the customization screen read). `--preview`
also writes one `<preset>.glb` per starting look (only its parts, its colours baked into the atlas) for
render_sheet.py. The look schema and the part list are in docs/design/characters.md.

Additive to build_soldier.py: the same clean-up and the same clips (soldier_clips.py, imported, never changed), so
the skeleton and the clips match soldier.glb bone for bone. The parts come from the kit Soldier's own meshes, split
by bone weight and material into head, torso, legs and feet and recoloured per part (the variants recipe of the kit
docs/blender/variants.md), plus small original pieces (hair, hats, glasses, scarf, bow tie, armband) built from
primitives with a one-segment chamfer and skinned 100 % to one bone.
"""

import argparse
import collections
import json
import math
import re
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib
import soldier_clips as sc
from palette_import import ensure_import

BUDGET = 6000  # style bible: player character, gameplay LOD
FAR_BUDGET = 2000  # style bible: player character, far LOD (#139); the build fails if a preset is over it
FAR_AIM = 1950  # what the far ratio is solved for, under the budget (a collapse lands within a few triangles)
FAR_KEEP = 260  # parts this small keep every triangle in the far LOD (caps, glasses, a bow tie): little to save, and a
# collapse turns them to slivers (the ball cap at 0.36 lost its peak)
FAR_MIN_RATIO = 0.2  # no part is cut below this share of its triangles (it would lose its shape)
SWATCH_PX = 16
ATLAS_W, ATLAS_H = 256, 64
SHADE = 0.75

# Row 0 of the atlas: colour channels, repainted per look. `<c>_shade` is `<c>` times SHADE.
CHANNELS = ["skin", "hair", "primary", "secondary", "accent"]
CHANNEL_PALETTE = {"skin": "skin", "hair": "hair", "primary": "cloth", "secondary": "cloth", "accent": "cloth"}
# Row 1: fixed colours (kit palette where one fits: style bible).
FIXED = {
    "black": "#252525",
    "darkgrey": "#414141",
    "grey": "#818491",
    "grey2": "#5f5f5f",
    "white": "#e9e2cf",
    "leather": "#664531",
    "lens": "#2b3a42",
    "glass": "#a9c4cc",
    "metal": "#8f92a0",
    "eye": "#161616",
    "amber": "#d1ab46",
}
PALETTES = {
    "skin": ["#f1c9a5", "#d9a77a", "#b89359", "#a68450", "#8a5a3b", "#5e3b26"],
    "hair": ["#252525", "#4a3221", "#7a4b2a", "#c9a25a", "#9c3d22", "#8f8f8f"],
    "cloth": [
        "#252525",
        "#e9e2cf",
        "#818491",
        "#5f5f5f",
        "#5c6d37",
        "#496321",
        "#8c3735",
        "#991c22",
        "#3b4b8c",
        "#2e4466",
        "#d1ab46",
        "#c79b17",
        "#9b7048",
        "#664531",
        "#4f8a8b",
        "#d98a9b",
    ],
}
PALETTE_NAMES = {
    "skin": ["porcelain", "peach", "sand", "olive", "umber", "cocoa"],
    "hair": ["black", "dark brown", "brown", "blond", "auburn", "grey"],
    "cloth": [
        "black",
        "cream",
        "grey",
        "charcoal",
        "olive",
        "green",
        "red",
        "cherry",
        "blue",
        "denim",
        "mustard",
        "gold",
        "tan",
        "brown",
        "teal",
        "pink",
    ],
}
# The atlas file's own channel colours: the kit Soldier's (olive vest, sand skin), so the png reads on its own.
BASE_COLOURS = {"skin": 2, "hair": 0, "primary": 4, "secondary": 3, "accent": 0}


def swatch_cells():
    cells = {}
    for i, c in enumerate(CHANNELS):
        cells[c] = (2 * i, 0)
        cells[c + "_shade"] = (2 * i + 1, 0)
    for i, name in enumerate(FIXED):
        cells[name] = (i, 1)
    return cells


CELLS = swatch_cells()

# Slots in display order: (slot, default part, may be empty). Parts: id -> label (and flags).
SLOTS = {
    "head": {"default": "plain", "parts": {"plain": "Clean-shaven", "stubble": "Stubble", "beard": "Beard"}},
    "hair": {
        "default": "crew",
        "parts": {
            "none": "Buzzed",
            "crew": "Crew cut",
            "pompadour": "Pompadour",
            "flattop": "Flat top",
            "ponytail": "Ponytail",
        },
    },
    "headwear": {
        "default": "none",
        "parts": {
            "none": "None",
            "helmet": "Helmet",
            "pillbox": "Usher's cap",
            "ballcap": "Ball cap",
            "papercap": "Paper cap",
            "ranger": "Ranger hat",
        },
    },
    "torso": {
        "default": "jacket",
        "parts": {
            "vest": "Field vest",
            "jacket": "Jacket",
            "shirt": "Short sleeves",
            "rolled": "Rolled sleeves",
            "tank": "Tank top",
            "letterman": "Letter jacket",
        },
    },
    "legs": {
        "default": "trousers",
        "parts": {"trousers": "Trousers", "cuffed": "Cuffed jeans", "shorts": "Shorts", "striped": "Striped"},
    },
    "feet": {"default": "boots", "parts": {"boots": "Boots", "sneakers": "Sneakers", "shoes": "Shoes"}},
    "eyewear": {
        "default": "none",
        "parts": {"none": "None", "sunglasses": "Sunglasses", "glasses": "Glasses", "goggles": "Goggles"},
    },
    "neck": {"default": "none", "parts": {"none": "None", "scarf": "Scarf", "bowtie": "Bow tie"}},
    "arm": {"default": "none", "parts": {"none": "None", "armband": "Armband"}},
}
HIDES_HAIR = {"helmet", "ballcap", "ranger"}


def look(colours, **parts):
    full = {s: spec["default"] for s, spec in SLOTS.items()}
    full.update(parts)
    return {"parts": full, "colours": colours}


# The eight starting looks (docs/design/characters.md). Colours are palette indices (PALETTES above).
PRESETS = [
    (
        "greaser",
        "Greaser",
        look(
            {"skin": 1, "hair": 0, "primary": 0, "secondary": 9, "accent": 0},
            hair="pompadour",
            torso="jacket",
            legs="cuffed",
            feet="boots",
        ),
    ),
    (
        "usher",
        "Usher",
        look(
            {"skin": 4, "hair": 1, "primary": 7, "secondary": 0, "accent": 11},
            hair="crew",
            headwear="pillbox",
            torso="jacket",
            legs="striped",
            feet="shoes",
            neck="bowtie",
        ),
    ),
    (
        "mechanic",
        "Mechanic",
        look(
            {"skin": 2, "hair": 2, "primary": 14, "secondary": 3, "accent": 6},
            head="stubble",
            hair="crew",
            torso="rolled",
            legs="trousers",
            feet="boots",
            eyewear="goggles",
        ),
    ),
    (
        "lifeguard",
        "Lifeguard",
        look(
            {"skin": 0, "hair": 3, "primary": 6, "secondary": 6, "accent": 1},
            hair="flattop",
            torso="tank",
            legs="shorts",
            feet="sneakers",
            eyewear="sunglasses",
        ),
    ),
    (
        "soda_jerk",
        "Soda jerk",
        look(
            {"skin": 3, "hair": 4, "primary": 1, "secondary": 3, "accent": 15},
            hair="ponytail",
            headwear="papercap",
            torso="shirt",
            legs="trousers",
            feet="shoes",
            neck="bowtie",
        ),
    ),
    (
        "ranger",
        "Ranger",
        look(
            {"skin": 2, "hair": 1, "primary": 4, "secondary": 12, "accent": 10},
            head="beard",
            hair="crew",
            headwear="ranger",
            torso="shirt",
            legs="trousers",
            feet="boots",
            neck="scarf",
        ),
    ),
    (
        "letterman",
        "Letterman",
        look(
            {"skin": 5, "hair": 0, "primary": 8, "secondary": 9, "accent": 1},
            hair="crew",
            headwear="ballcap",
            torso="letterman",
            legs="cuffed",
            feet="sneakers",
        ),
    ),
    (
        "projectionist",
        "Projectionist",
        look(
            {"skin": 1, "hair": 5, "primary": 1, "secondary": 13, "accent": 6},
            head="stubble",
            hair="crew",
            torso="rolled",
            legs="trousers",
            feet="shoes",
            eyewear="glasses",
            arm="armband",
        ),
    ),
]


# --- atlas ---------------------------------------------------------------------------------------------------------


def hex_rgb(h):
    h = h.lstrip("#")
    return [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]


def uv_of(key):
    col, row = CELLS[key]
    return ((col * SWATCH_PX + SWATCH_PX / 2) / ATLAS_W, 1 - (row * SWATCH_PX + SWATCH_PX / 2) / ATLAS_H)


def channel_rgb(colours):
    out = {}
    for c in CHANNELS:
        pal = PALETTES[CHANNEL_PALETTE[c]]
        rgb = hex_rgb(pal[colours[c] % len(pal)])
        out[c] = rgb
        out[c + "_shade"] = [v * SHADE for v in rgb]
    return out


def paint_atlas(name, colours):
    px = [0.0] * (ATLAS_W * ATLAS_H * 4)
    fills = {k: hex_rgb(v) for k, v in FIXED.items()}
    fills.update(channel_rgb(colours))
    for key, rgb in fills.items():
        col, row = CELLS[key]
        for y in range(ATLAS_H - (row + 1) * SWATCH_PX, ATLAS_H - row * SWATCH_PX):
            for x in range(col * SWATCH_PX, (col + 1) * SWATCH_PX):
                i = (y * ATLAS_W + x) * 4
                px[i : i + 4] = [*rgb, 1.0]
    img = bpy.data.images.new(name, ATLAS_W, ATLAS_H, alpha=True)
    img.pixels = px
    return img


def atlas_material(img):
    mat = bpy.data.materials.new("SoldierParts")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.8
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


# --- the Soldier, cleaned as build_soldier.py does -----------------------------------------------------------------


def clean_soldier(path):
    """build_soldier.py steps 1-6 (kit rig-sharing recipe); returns (armature, body, helmet, pads, scale factor)."""
    objs = kitlib.import_glb(path)
    arm = kitlib.armature_of(objs)
    sc.capture_static(arm)
    ad = arm.animation_data
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    ad.action = None
    sc.build(arm)
    kit_actions = [a for a in bpy.data.actions if "|" in a.name]
    for a in kit_actions:
        sc.bake_static(arm, a)
    _body, held, stray = kitlib.split_parts(objs)
    for o in held + stray:
        bpy.data.objects.remove(o)
    for o in [o for o in bpy.data.objects if o.type == "EMPTY" and o.name.endswith("_end")]:
        bpy.data.objects.remove(o)
    root = arm.parent
    mw = arm.matrix_world.copy()
    arm.parent = None
    arm.matrix_world = mw
    if root is not None and root.type == "EMPTY":
        bpy.data.objects.remove(root)
    factor = arm.scale[0]
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    pinned = {c: c.matrix_world.copy() for c in arm.children if c.parent_type == "BONE"}
    select(arm)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True, properties=False)
    bpy.context.view_layer.update()
    for c, m in pinned.items():
        c.matrix_world = m
    for c in arm.children:
        if c.type == "MESH" and c.parent_type != "BONE":
            select(c)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for a in kit_actions:
        a.name = re.sub(r"^.*\|", "", a.name)
    clips = sorted(bpy.data.actions, key=lambda a: a.name)
    for a in clips:
        a.use_fake_user = True
        for fc in sc.fcurves(a):
            if fc.data_path.endswith(".location"):
                for k in fc.keyframe_points:
                    k.co[1] *= factor
                    k.handle_left[1] *= factor
                    k.handle_right[1] *= factor
    for a in clips:
        track = ad.nla_tracks.new()
        track.name = a.name
        strip = track.strips.new(a.name, int(a.frame_range[0]), a)
        if hasattr(strip, "action_slot") and a.slots:
            strip.action_slot = a.slots[0]
    bpy.context.view_layer.update()  # still at REST: parts are built in the rest pose
    body = bpy.data.objects["Body"]
    helmet = bpy.data.objects["Head"]
    pads = [bpy.data.objects["ShoulderPad.L"], bpy.data.objects["ShoulderPad.R"]]
    for o in [helmet, *pads]:
        to_skinned(o, arm, o.parent_bone)
    return arm, body, helmet, pads, factor, len(clips)


def select(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def to_skinned(o, arm, bone):
    """A bone-parented mesh becomes a mesh skinned 100 % to that bone (same place at rest)."""
    mw = o.matrix_world.copy()
    o.parent = None
    o.data.transform(mw)
    o.matrix_world = Matrix.Identity(4)
    o.parent = arm
    o.matrix_parent_inverse = arm.matrix_world.inverted()
    skin(o, arm, bone)


def skin(o, arm, bone):
    vg = o.vertex_groups.new(name=bone)
    vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


# --- tagging the kit body ------------------------------------------------------------------------------------------


Face = collections.namedtuple("Face", "mat bone island size centre normal")


def tag_body(body):
    """Per face: kit material, dominant bone, island id (same-material neighbours) and its size, centre, normal."""
    me = body.data
    names = [g.name for g in body.vertex_groups]
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    island = [-1] * len(bm.faces)
    sizes = []
    for f in bm.faces:
        if island[f.index] >= 0:
            continue
        n = len(sizes)
        stack, count = [f], 0
        island[f.index] = n
        while stack:
            g = stack.pop()
            count += 1
            for e in g.edges:
                for h in e.link_faces:
                    if island[h.index] < 0 and h.material_index == g.material_index:
                        island[h.index] = n
                        stack.append(h)
        sizes.append(count)
    bm.free()
    tags = []
    for p in me.polygons:
        acc = collections.Counter()
        for vi in p.vertices:
            for g in me.vertices[vi].groups:
                acc[names[g.group]] += g.weight
        mat = re.sub(r"\.\d+$", "", body.material_slots[p.material_index].material.name)
        isl = island[p.index]
        tags.append(Face(mat, acc.most_common(1)[0][0], isl, sizes[isl], p.center.copy(), p.normal.copy()))
    return tags


def region_of(t):
    """head, torso, legs or feet for one kit body face (bounds measured on the kit Soldier at rest, kit metres)."""
    if t.bone in ("Head", "Neck") and t.mat != "Character_Main":
        return "head"
    if t.mat in ("Black", "DarkGrey") and t.bone.startswith(("Foot", "LowerLeg")):
        return "feet"
    if t.mat == "Pants" or (t.mat == "DarkGrey" and t.centre.z < 1.0 and abs(t.centre.x) < 0.31):
        return "legs"
    return "torso"


# --- kit-body parts: which faces, which swatch -----------------------------------------------------------------------


def head_rule(kind):
    def rule(t):
        if t.mat == "Skin":
            return "skin"
        if t.mat == "Black":
            beard = {"plain": "skin", "stubble": "skin_shade", "beard": "hair"}[kind]
            if t.size >= 300:  # the hood over the skull reads as short hair; its front below the eyes is the beard
                return beard if (t.centre.y < -0.15 and t.centre.z < 1.80) else "hair"
            if t.size >= 40:  # the ring in front: brows above the eyes, the beard below
                if t.centre.z > 2.0:
                    return "hair"
                return beard
            return "eye"
        return "grey"

    return rule


def torso_rule(kind):
    """Swatch per face, or None to delete it. Sleeve x is along the arm in the rest T-pose (elbow at |x| 0.54)."""

    def rule(t):
        ax = abs(t.centre.x)
        sleeve = t.mat == "Black" and t.size >= 150
        cuff = t.mat == "Black" and t.size < 150 and ax > 0.8
        pouch = t.mat == "DarkGrey" and t.centre.y < -0.09 and 1.09 < t.centre.z < 1.35 and ax < 0.2
        collar = t.mat == "Character_Main" and t.bone in ("Head", "Neck")
        if t.mat == "Skin":
            return "skin"
        if kind == "vest":
            return {"Character_Main": "primary", "DarkGrey": "darkgrey", "Black": "secondary"}.get(t.mat, "grey")
        if pouch:
            return None  # closed boxes on the vest: the vest is whole underneath
        if t.mat == "DarkGrey":
            return "primary_shade"
        if kind == "jacket":
            if cuff or collar:
                return "accent"
            return "primary"
        if kind == "letterman":
            if cuff or collar:
                return "primary_shade"
            return "accent" if sleeve else "primary"
        upper = t.bone.startswith("UpperArm")  # the sleeve tube has one long face per side from shoulder to elbow
        if kind in ("shirt", "rolled"):
            if cuff:
                return "skin"  # the cuff rings join the sleeve to the hand: deleting them leaves a gap
            if sleeve:
                return "primary" if upper else "skin"
            return "primary"
        if kind == "tank":
            if cuff or sleeve or collar:
                return "skin"
            return "primary"
        raise ValueError(kind)

    return rule


def legs_rule(kind):
    def rule(t):
        if t.mat == "DarkGrey":
            return "leather"  # the belt
        cuff = t.size < 40
        if kind == "trousers":
            return "secondary"
        if kind == "cuffed":
            return "secondary_shade" if cuff else "secondary"
        if kind == "striped":
            return "secondary"  # the stripe is cut in afterwards (cut_stripe): faces by centre zigzag
        if kind == "shorts":
            return "skin" if (cuff or t.centre.z < 0.56) else "secondary"
        raise ValueError(kind)

    return rule


def feet_rule(kind):
    def rule(t):
        sole = t.mat == "Black" and t.size < 100
        top = t.mat == "DarkGrey"
        if kind == "boots":
            return "darkgrey" if (sole or top) else "black"
        if kind == "sneakers":
            return "white" if (sole or top) else "accent"
        if kind == "shoes":
            if top or (not sole and t.centre.z > 0.13):
                return "secondary"  # the trousers come down over a low shoe
            return "black" if sole else "leather"
        raise ValueError(kind)

    return rule


# Open-necked torsos fold the kit's tall collar down: its verts above the chin line drop and pull in.
LOW_COLLAR = {"shirt", "rolled", "tank"}

PUSH = {  # (slot, part): [(swatch the push applies to, metres along the normal)]: bare skin hugs the limb
    ("torso", "shirt"): [("skin", -0.025)],
    ("torso", "rolled"): [("skin", -0.025)],
    ("torso", "tank"): [("skin", -0.025)],
    ("legs", "shorts"): [("skin", -0.03)],
}


def body_part(body, tags, region, rule, name, mat, arm, push=(), low_collar=False):
    o = body.copy()
    o.data = body.data.copy()
    o.name = o.data.name = name
    bpy.context.collection.objects.link(o)
    me = o.data
    uv = me.uv_layers.active.data
    keys = [rule(t) if region_of(t) == region else None for t in tags]
    for p, key in zip(me.polygons, keys):
        if key:
            u = uv_of(key)
            for li in p.loop_indices:
                uv[li].uv = u
    if push:
        offs = collections.defaultdict(Vector)
        for p, key in zip(me.polygons, keys):
            for swatch, amount in push:
                if key == swatch:
                    for vi in p.vertices:
                        offs[vi] = me.vertices[vi].normal * amount
        for vi, d in offs.items():
            me.vertices[vi].co += d
    if low_collar:  # bare forearms: the kit's wrist cuffs pull in to the arm (arm axis along X at y 0.017, z 1.393)
        cuffs = {
            vi
            for p, t in zip(me.polygons, tags)
            if t.mat == "Black" and t.size < 150 and abs(t.centre.x) > 0.8
            for vi in p.vertices
        }
        for vi in cuffs:
            co = me.vertices[vi].co
            co.y = 0.017 + (co.y - 0.017) * 0.72
            co.z = 1.393 + (co.z - 1.393) * 0.72
        verts = {
            vi
            for p, t in zip(me.polygons, tags)
            if t.mat == "Character_Main" and t.bone in ("Head", "Neck")
            for vi in p.vertices
        }
        for vi in verts:
            co = me.vertices[vi].co
            if co.z > 1.50:
                co.z = 1.50 + (co.z - 1.50) * 0.45
                co.x *= 0.95
                co.y = 0.02 + (co.y - 0.02) * 0.95
    me.materials.clear()
    me.materials.append(mat)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    gone = [bm.faces[i] for i, k in enumerate(keys) if k is None]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(me)
    bm.free()
    for m in o.modifiers:
        if m.type == "ARMATURE":
            m.object = arm
    return o


# The Usher's trouser stripe (Deadnight #140): a band down the outer side of each leg, between two vertical planes
# STRIPE_HALF either side of the leg's outer face, cut into the mesh so its edges are straight (painting whole faces
# by their centre left sawtooth teeth along the edges). Kit metres at rest; front is -Y.
STRIPE_HALF = 0.045
STRIPE_OUTER = 0.55  # a face is on the leg's outer side when its normal's X, away from the body, is at least this


def cut_stripe(o):
    """Cut the stripe into a `legs__striped` part and paint it `accent`."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    trouser = Vector(uv_of("secondary"))
    accent = uv_of("accent")

    def outer(f, side):
        return f.normal.x * side >= STRIPE_OUTER and f.calc_center_median().x * side > 0.05

    def is_trouser(f):
        return (Vector(f.loops[0][uv].uv) - trouser).length < 1e-4

    for side in (-1, 1):
        faces = [f for f in bm.faces if outer(f, side) and is_trouser(f)]
        area = sum(f.calc_area() for f in faces)
        centre_y = sum(f.calc_center_median().y * f.calc_area() for f in faces) / area
        for y in (centre_y - STRIPE_HALF, centre_y + STRIPE_HALF):
            faces = [f for f in bm.faces if outer(f, side) and is_trouser(f)]
            geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, y, 0), plane_no=(0, 1, 0))
        for f in bm.faces:
            if outer(f, side) and is_trouser(f) and abs(f.calc_center_median().y - centre_y) < STRIPE_HALF:
                for loop in f.loops:
                    loop[uv].uv = accent
    bm.to_mesh(me)
    bm.free()


def split_features(helmet):
    """The kit keeps the eyes and brows in the helmet mesh (Head): move them to their own mesh for the head parts.

    Eyes: two 96-face black islands at x +-0.12..0.23, z 1.75..1.89; brows: small black blocks at z 1.89..1.94.
    """
    me = helmet.data
    feat = helmet.copy()
    feat.data = me.copy()
    feat.name = feat.data.name = "face_features"
    bpy.context.collection.objects.link(feat)
    keep_feat = []
    for p in me.polygons:
        kit = re.sub(r"\.\d+$", "", helmet.material_slots[p.material_index].material.name)
        c = p.center
        keep_feat.append(kit == "Black" and abs(c.x) < 0.26 and c.y < -0.24 and c.z < 1.95)
    for o, want in ((feat, True), (helmet, False)):
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f, k in zip(bm.faces, keep_feat) if k != want], context="FACES_ONLY")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
    uv = feat.data.uv_layers.active.data
    for p in feat.data.polygons:
        u = uv_of("eye" if p.center.z < 1.89 else "hair")
        for li in p.loop_indices:
            uv[li].uv = u
    feat.data.materials.clear()
    return feat


def recolour(o, by_material, mat):
    """Move a kit mesh (the helmet, the pads) onto the atlas: kit material name -> swatch."""
    me = o.data
    uv = me.uv_layers.active.data
    for p in me.polygons:
        kit = re.sub(r"\.\d+$", "", o.material_slots[p.material_index].material.name)
        u = uv_of(by_material.get(kit, "grey"))
        for li in p.loop_indices:
            uv[li].uv = u
    me.materials.clear()
    me.materials.append(mat)
    for p in me.polygons:
        p.material_index = 0


# --- original pieces from primitives -----------------------------------------------------------------------------------

BEVEL = 0.02  # style bible: 15-25 mm one-segment chamfer at kit scale


UNDER_Z = -0.3  # a face whose normal's Z is below this points down (Piece.add's `under`)


class Piece:
    """Collects primitive shapes, each with a swatch, into one mesh skinned to one bone."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def add(self, make, swatch, at=(0, 0, 0), rot=None, scale=None, bevel=BEVEL, taper=None, under=None):
        """`under`: a second swatch for the faces that point down (a shade underneath)."""
        tmp = bmesh.new()
        make(tmp)
        if taper:  # (factor_x, factor_y) for the verts above the centre: a narrower top
            for v in tmp.verts:
                if v.co.z > 0:
                    v.co.x *= taper[0]
                    v.co.y *= taper[1]
        if scale:
            bmesh.ops.scale(tmp, vec=scale, verts=tmp.verts)
        if bevel:
            edges = [e for e in tmp.edges if len(e.link_faces) == 2 and e.calc_face_angle() > 0.6]
            bmesh.ops.bevel(tmp, geom=edges, offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
        if rot:
            bmesh.ops.rotate(tmp, verts=tmp.verts, matrix=rot)
        bmesh.ops.translate(tmp, verts=tmp.verts, vec=Vector(at))
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        u = uv_of(swatch)
        start = len(self.bm.faces)
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        self.bm.faces.ensure_lookup_table()
        for f in list(self.bm.faces)[start:]:
            colour = uv_of(under) if under and f.normal.z < UNDER_Z else u
            for loop in f.loops:
                loop[self.uv].uv = colour
        return self

    def build(self, name, bone, arm, mat):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        o = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(o)
        o.parent = arm
        o.matrix_parent_inverse = arm.matrix_world.inverted()  # the armature keeps the import's 90 degree X turn
        me.materials.append(mat)
        skin(o, arm, bone)
        return o


def cube(size):
    return lambda bm: bmesh.ops.create_cube(bm, size=1.0) and bmesh.ops.scale(bm, vec=size, verts=bm.verts)


def cyl(r1, r2, depth, segs=12):
    return lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)


def sphere(r, segs=12, rings=8):
    return lambda bm: bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)


def dome(r, segs=12, rings=8):
    """The top half of a sphere, closed at the bottom."""

    def make(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
        bmesh.ops.bisect_plane(
            bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True
        )
        edges = [e for e in bm.edges if e.is_boundary]
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)

    return make


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ry(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rz(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


# Head landmarks on the kit Soldier at rest (kit metres; front is -Y): the hood spans x +-0.35, y -0.36..0.32,
# z 1.53..2.20; the face panel z 1.68..2.10, eyes z 1.75..1.89 at x +-0.12..0.23 (in the kit's helmet mesh); the collar ring z 1.40..1.68, r 0.36.
TOP, FRONT, BACK, EYE_Z = 2.20, -0.37, 0.32, 1.82


def build_pieces(arm, mat):
    P = {}

    # Hair (Head): all sit on the hood, which stays as the short hair underneath.
    def crown():  # a low rounded cap of hair over the hood
        return Piece().add(dome(0.36, 12, 6), "hair", at=(0, -0.01, TOP - 0.19), scale=(1.0, 0.97, 0.62), bevel=0)

    P["hair", "crew"] = crown().build("hair__crew", "Head", arm, mat)
    P["hair", "flattop"] = (
        Piece()
        .add(cube((0.62, 0.58, 0.17)), "hair", at=(0, 0.0, TOP - 0.03), taper=(0.92, 0.92))
        .build("hair__flattop", "Head", arm, mat)
    )
    # The pompadour (#140): a rounded mass swept up from the hairline into the crown, and a rolled quiff in front of
    # it over the forehead, in the crown's own `hair`; `hair_shade` only where they turn underneath. (A box on the
    # crown, darker than the hair, read as a cap.)
    P["hair", "pompadour"] = (
        crown()
        .add(
            sphere(0.3, 12, 8),
            "hair",
            at=(0, FRONT + 0.25, TOP - 0.05),
            rot=rx(-14),
            scale=(1.0, 1.05, 0.52),
            bevel=0,
            under="hair_shade",
        )
        .add(
            sphere(0.22, 12, 7),
            "hair",
            at=(0, FRONT + 0.1, TOP - 0.02),
            rot=rx(-28),
            scale=(1.12, 0.78, 0.66),
            bevel=0,
            under="hair_shade",
        )
        .build("hair__pompadour", "Head", arm, mat)
    )
    P["hair", "ponytail"] = (
        crown()
        .add(cyl(0.10, 0.05, 0.42, 8), "hair", at=(0, BACK + 0.12, TOP - 0.36), rot=rx(-25))
        .add(cyl(0.085, 0.085, 0.06, 8), "accent", at=(0, BACK + 0.04, TOP - 0.17), rot=rx(-25), bevel=0.01)
        .build("hair__ponytail", "Head", arm, mat)
    )
    # Headwear (Head).
    P["headwear", "pillbox"] = (
        Piece()
        .add(cyl(0.27, 0.25, 0.20, 12), "primary", at=(0.05, -0.02, TOP + 0.06), rot=ry(8))
        .add(cyl(0.28, 0.28, 0.05, 12), "accent", at=(0.05, -0.02, TOP - 0.02), rot=ry(8), bevel=0.01)
        .build("headwear__pillbox", "Head", arm, mat)
    )
    P["headwear", "ballcap"] = (
        Piece()
        .add(dome(0.40, 12, 8), "primary", at=(0, 0.0, TOP - 0.17), scale=(0.98, 1.0, 0.78), bevel=0)
        .add(cube((0.52, 0.34, 0.04)), "primary_shade", at=(0, FRONT - 0.12, TOP - 0.13), rot=rx(-8))
        .add(cyl(0.04, 0.04, 0.04, 8), "accent", at=(0, 0.0, TOP + 0.15), bevel=0.008)
        .build("headwear__ballcap", "Head", arm, mat)
    )
    P["headwear", "papercap"] = (
        Piece()
        .add(cube((0.30, 0.74, 0.17)), "white", at=(0, 0.0, TOP + 0.05), taper=(0.35, 0.9))
        .add(cube((0.31, 0.76, 0.05)), "accent", at=(0, 0.0, TOP - 0.01), bevel=0.01)
        .build("headwear__papercap", "Head", arm, mat)
    )
    P["headwear", "ranger"] = (
        Piece()
        .add(cyl(0.66, 0.64, 0.05, 16), "primary_shade", at=(0, 0, TOP - 0.06), bevel=0.012)
        .add(cyl(0.36, 0.10, 0.36, 4), "primary_shade", at=(0, 0, TOP + 0.13), rot=rz(45))
        .add(cyl(0.375, 0.36, 0.07, 16), "accent", at=(0, 0, TOP - 0.01), bevel=0.01)
        .build("headwear__ranger", "Head", arm, mat)
    )
    # Eyewear (Head), in front of the face.
    sun = Piece()
    for sx in (-1, 1):
        sun.add(cube((0.22, 0.05, 0.14)), "lens", at=(sx * 0.14, FRONT - 0.03, EYE_Z), bevel=0.015)
    sun.add(cube((0.10, 0.04, 0.04)), "black", at=(0, FRONT - 0.03, EYE_Z + 0.03), bevel=0.008)
    for sx in (-1, 1):
        sun.add(cube((0.04, 0.30, 0.04)), "black", at=(sx * 0.27, FRONT + 0.11, EYE_Z + 0.03), bevel=0.008)
    P["eyewear", "sunglasses"] = sun.build("eyewear__sunglasses", "Head", arm, mat)
    gl = Piece()
    for sx in (-1, 1):
        gl.add(cyl(0.10, 0.10, 0.03, 10), "black", at=(sx * 0.14, FRONT - 0.035, EYE_Z), rot=rx(90), bevel=0.008)
        gl.add(cyl(0.08, 0.08, 0.035, 10), "glass", at=(sx * 0.14, FRONT - 0.04, EYE_Z), rot=rx(90), bevel=0)
        gl.add(cube((0.03, 0.30, 0.03)), "black", at=(sx * 0.255, FRONT + 0.11, EYE_Z + 0.03), bevel=0.006)
    gl.add(cube((0.08, 0.03, 0.03)), "black", at=(0, FRONT - 0.035, EYE_Z + 0.03), bevel=0.006)
    P["eyewear", "glasses"] = gl.build("eyewear__glasses", "Head", arm, mat)
    gg = Piece().add(cyl(0.375, 0.375, 0.07, 16), "black", at=(0, -0.02, 2.09), bevel=0.01)
    for sx in (-1, 1):
        gg.add(cyl(0.10, 0.09, 0.08, 10), "metal", at=(sx * 0.14, FRONT - 0.02, 2.11), rot=rx(90), bevel=0.012)
        gg.add(cyl(0.075, 0.075, 0.09, 10), "amber", at=(sx * 0.14, FRONT - 0.025, 2.11), rot=rx(90), bevel=0)
    P["eyewear", "goggles"] = gg.build("eyewear__goggles", "Head", arm, mat)
    # Neck (Head: the collar ring under the chin is weighted to the head).
    P["neck", "scarf"] = (
        Piece()
        .add(cyl(0.39, 0.37, 0.12, 14), "accent", at=(0, 0.0, 1.47))
        .add(cube((0.14, 0.06, 0.26)), "accent_shade", at=(0.16, -0.37, 1.34), rot=ry(-12))
        .build("neck__scarf", "Head", arm, mat)
    )
    bow = Piece()
    for sx in (-1, 1):
        bow.add(
            cyl(0.085, 0.0, 0.14, 3), "accent", at=(sx * 0.075, -0.30, 1.43), rot=ry(-sx * 90) @ rx(90), bevel=0.008
        )
    bow.add(cube((0.06, 0.06, 0.06)), "accent_shade", at=(0, -0.31, 1.43), bevel=0.01)
    P["neck", "bowtie"] = bow.build("neck__bowtie", "Head", arm, mat)
    # Arm: a band round the left upper arm (the arm points along +X at rest; the sleeve is r 0.12 about y 0.02 z 1.39).
    P["arm", "armband"] = (
        Piece()
        .add(cyl(0.135, 0.135, 0.09, 12), "accent", at=(0.36, 0.017, 1.393), rot=ry(90), bevel=0.012)
        .build("arm__armband", "UpperArm.L", arm, mat)
    )
    # Letter patch on the letter jacket's chest (Torso), added to that torso part below.
    return P


def sleeve_rolls(arm, mat):
    """A rolled band above each elbow (the arms point along +-X at rest; elbow at |x| 0.54, sleeve r 0.12)."""
    out = []
    for side, sx in (("L", 1), ("R", -1)):
        p = Piece().add(
            cyl(0.125, 0.125, 0.06, 10), "primary_shade", at=(sx * 0.50, 0.017, 1.393), rot=ry(90), bevel=0.015
        )
        out.append(p.build(f"roll_{side}", f"UpperArm.{side}", arm, mat))
    return out


def letter_patch(arm, mat):
    p = Piece()
    p.add(cube((0.15, 0.03, 0.17)), "accent", at=(0.13, -0.215, 1.30), bevel=0.012)
    p.add(cube((0.045, 0.02, 0.10)), "primary", at=(0.13, -0.235, 1.30), bevel=0.0)
    return p.build("letter_patch", "Torso", arm, mat)


def join(base, extra):
    bpy.ops.object.select_all(action="DESELECT")
    base.select_set(True)
    extra.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    return base


# --- export ----------------------------------------------------------------------------------------------------------


def far_copy(o, ratio):
    """The part's far level of detail: a copy (same skeleton, same atlas UVs, same skin) collapse-decimated to
    `ratio` of its triangles. The Armature modifier stays; the Decimate goes first in the stack and is applied, so
    the rest-pose mesh is what is cut, and the cut interpolates the skin weights."""
    far = o.copy()
    far.data = o.data.copy()
    far.name = far.data.name = o.name + "__far"
    bpy.context.collection.objects.link(far)
    if ratio < 1.0:
        mod = far.modifiers.new("far", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        select(far)
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        # A collapse can leave zero-area triangles and folded n-gons, which the glTF round trip drops or splits
        # its own way: triangulate here and drop the zero-area ones, so the catalog counts what Godot draws.
        bm = bmesh.new()
        bm.from_mesh(far.data)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_area() < 1e-10], context="FACES_ONLY")
        bm.to_mesh(far.data)
        bm.free()
    return far


def far_parts(parts, presets_of):
    """A far copy of every part, with one decimation ratio for every part bigger than FAR_KEEP, solved so the
    heaviest preset's far parts come to FAR_AIM (`presets_of(tris)` gives each preset's sum for a {mesh: tris})."""
    near = {f"{s}__{p}": kitlib.tris(o) for (s, p), o in parts.items()}
    big = {k: v for k, v in near.items() if v > FAR_KEEP}
    ratio = 1.0
    for _ in range(6):
        guess = {k: (v * ratio if k in big else v) for k, v in near.items()}
        worst = max(presets_of(guess).values())
        if worst <= FAR_AIM:
            break
        small = max(presets_of({k: (0 if k in big else v) for k, v in near.items()}).values())
        ratio = min(ratio, max((FAR_AIM - small) / max(worst - small, 1) * ratio, FAR_MIN_RATIO)) * 0.99
    far = {key: far_copy(o, ratio if f"{key[0]}__{key[1]}" in big else 1.0) for key, o in parts.items()}
    return far, ratio


def finish_pose(arm, factor):
    arm.data.pose_position = "POSE"
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = sc.STATIC[pb.name]["rot"]
        pb.location = sc.STATIC[pb.name]["loc"] * factor


def export(path, arm, meshes, images):
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_image_format="AUTO" if images else "NONE",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_reset_pose_bones=False,  # as build_soldier.py: unkeyed bones hold the static pose
        export_optimize_animation_size=False,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--soldier", required=True)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--preview", type=Path, help="also write one .glb per preset here (for render_sheet.py)")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)

    arm, body, helmet, pads, factor, n_clips = clean_soldier(args.soldier)
    atlas = paint_atlas("soldier_parts_atlas", BASE_COLOURS)
    atlas.filepath_raw = str(out / "soldier_parts_atlas.png")
    atlas.file_format = "PNG"
    atlas.save()
    ensure_import(out / "soldier_parts_atlas.png")  # lossless, no mipmaps, Detect 3D off
    mat = atlas_material(atlas)

    tags = tag_body(body)
    parts = {}
    rules = {"head": head_rule, "torso": torso_rule, "legs": legs_rule, "feet": feet_rule}
    for slot, make_rule in rules.items():
        for pid in SLOTS[slot]["parts"]:
            parts[slot, pid] = body_part(
                body,
                tags,
                slot,
                make_rule(pid),
                f"{slot}__{pid}",
                mat,
                arm,
                PUSH.get((slot, pid), ()),
                low_collar=slot == "torso" and pid in LOW_COLLAR,
            )
    features = split_features(helmet)
    features.data.materials.append(mat)
    for pid in SLOTS["head"]["parts"]:
        f = features.copy()
        f.data = features.data.copy()
        bpy.context.collection.objects.link(f)
        join(parts["head", pid], f)
    bpy.data.objects.remove(features)
    cut_stripe(parts["legs", "striped"])
    patch = letter_patch(arm, mat)
    join(parts["torso", "letterman"], patch)
    for roll in sleeve_rolls(arm, mat):
        join(parts["torso", "rolled"], roll)
    bpy.data.objects.remove(body)
    recolour(helmet, {"Character_Main": "secondary", "Black": "black", "Grey": "grey"}, mat)
    helmet.name = helmet.data.name = "headwear__helmet"
    parts["headwear", "helmet"] = helmet
    for pad in pads:
        recolour(pad, {}, mat)
    parts["torso", "vest"] = join(join(parts["torso", "vest"], pads[0]), pads[1])
    parts["torso", "vest"].name = parts["torso", "vest"].data.name = "torso__vest"
    parts.update(build_pieces(arm, mat))

    missing = [(s, p) for s, spec in SLOTS.items() for p in spec["parts"] if p != "none" and (s, p) not in parts]
    assert not missing, f"parts with no mesh: {missing}"
    tris = {f"{s}__{p}": kitlib.tris(o) for (s, p), o in parts.items()}

    def look_tris(lk):
        hide_hair = lk["parts"]["headwear"] in HIDES_HAIR
        return sum(tris.get(f"{s}__{p}", 0) for s, p in lk["parts"].items() if not (s == "hair" and hide_hair))

    def look_sum(lk, counts):
        hide_hair = lk["parts"]["headwear"] in HIDES_HAIR
        return sum(counts.get(f"{s}__{p}", 0) for s, p in lk["parts"].items() if not (s == "hair" and hide_hair))

    far, far_ratio = far_parts(parts, lambda counts: {pid: look_sum(lk, counts) for pid, _n, lk in PRESETS})
    tris_far = {f"{s}__{p}": kitlib.tris(o) for (s, p), o in far.items()}

    presets = []
    for pid, name, lk in PRESETS:
        t = look_tris(lk)
        assert t <= BUDGET, f"{pid}: {t} tris over the {BUDGET} budget"
        t_far = look_sum(lk, tris_far)
        assert t_far <= FAR_BUDGET, f"{pid}: {t_far} far tris over the {FAR_BUDGET} budget"
        presets.append({"id": pid, "name": name, **lk, "tris": t, "tris_far": t_far})

    finish_pose(arm, factor)
    meshes = list(parts.values()) + list(far.values())
    export(out / "soldier_parts.glb", arm, meshes, images=False)

    catalog = {
        "version": 1,
        "source": "tools/blender/build_soldier_parts.py from the Quaternius Toon Shooter Game Kit Soldier (CC0)",
        "model": "soldier_parts.glb",
        "atlas": {
            "image": "soldier_parts_atlas.png",
            "size": [ATLAS_W, ATLAS_H],
            "swatch_px": SWATCH_PX,
            "cells": {k: list(v) for k, v in CELLS.items()},
        },
        "shade": SHADE,
        "channels": CHANNEL_PALETTE,
        "palettes": PALETTES,
        "palette_names": PALETTE_NAMES,
        "budget": BUDGET,
        "far_budget": FAR_BUDGET,
        "far_ratio": round(far_ratio, 3),
        "clips": sorted(a.name for a in bpy.data.actions),
        "weapon_clips": {c: [n for n in sc.CLIPS if n.endswith("_" + c)] for c in sc.CLASSES},
        "slots": {
            s: {
                "default": spec["default"],
                "parts": {
                    p: {
                        "label": label,
                        "mesh": None if p == "none" else f"{s}__{p}",
                        "tris": tris.get(f"{s}__{p}", 0),
                        "mesh_far": None if p == "none" else f"{s}__{p}__far",
                        "tris_far": tris_far.get(f"{s}__{p}", 0),
                        **({"hides_hair": True} if s == "headwear" and p in HIDES_HAIR else {}),
                    }
                    for p, label in spec["parts"].items()
                },
            }
            for s, spec in SLOTS.items()
        },
        "presets": presets,
    }
    (out / "parts.json").write_text(json.dumps(catalog, indent=1) + "\n", encoding="utf-8", newline="\n")
    print("PARTS", json.dumps({"clips": n_clips, "bones": len(arm.data.bones), "tris": tris}))
    print("PRESETS", json.dumps({p["id"]: p["tris"] for p in presets}))
    print("FAR", json.dumps({"ratio": round(far_ratio, 3), "presets": {p["id"]: p["tris_far"] for p in presets},
                             "parts": tris_far}))  # fmt: skip

    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
        for p in presets:
            img = paint_atlas("atlas_" + p["id"], p["colours"])
            mat.node_tree.nodes["Image Texture"].image = img
            hide_hair = p["parts"]["headwear"] in HIDES_HAIR
            keep = [
                parts[s, pid] for s, pid in p["parts"].items() if (s, pid) in parts and not (s == "hair" and hide_hair)
            ]
            export(args.preview / f"{p['id']}.glb", arm, keep, images=True)
            keep_far = [
                far[s, pid] for s, pid in p["parts"].items() if (s, pid) in far and not (s == "hair" and hide_hair)
            ]
            export(args.preview / f"{p['id']}_far.glb", arm, keep_far, images=True)
        mat.node_tree.nodes["Image Texture"].image = atlas


main()
