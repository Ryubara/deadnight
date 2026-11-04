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
import soldier_arms
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
    "lips": "#b4504c",  # the female Soldier's mouth until #895 (kept: a swatch's cell never moves)
    "blush": "#e08c7c",  # her cheeks on the "Rosy" face
    "mouth": "#2a1414",  # #895: the mouth, dark like the eyes so it reads on every skin tone at night
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
            "bob": "Bob",  # #678: appended, never reordered (the wire sends a part's index)
            "curls": "Pin curls",
            "bun": "Bun",
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
    # The character (#678): the last slot, so the wire's slot order only grows. No mesh of its own: `female` shows
    # the `<slot>__<part>__female` variant of every part that has one (BODY_VARIANTS), so every outfit fits both.
    "body": {"default": "male", "parts": {"male": "Male", "female": "Female"}},
}
HIDES_HAIR = {"helmet", "ballcap", "ranger"}
BODY_SLOT = "body"
FEMALE = "female"
# The slots whose every part has a female variant: her face, and the torso and legs shaped by female_shape.
BODY_VARIANTS = ("head", "torso", "legs")
# What the face choices are called on her: no beard; freckles and rosy cheeks instead.
FEMALE_LABELS = {("head", "plain"): "Natural", ("head", "stubble"): "Freckles", ("head", "beard"): "Rosy"}
# The hair each character starts from, so switching the character in the loadout swaps one for the other.
BODY_HAIR = {"male": "crew", "female": "bob"}
# Hair cut for one character: switching to the other puts that one's BODY_HAIR on. Untagged hair (the ponytail)
# stays whichever character wears it.
HAIR_BODY = {"none": "male", "crew": "male", "pompadour": "male", "flattop": "male", "bob": FEMALE,
             "curls": FEMALE, "bun": FEMALE}  # fmt: skip

# The clips this file carries: the set it shipped with (#130, #342). Later clips (sprint, strike, downed, revive,
# aim-move) ship in their own files under characters/soldier/, finger channels stripped, and the controller adds
# them by name only when the library lacks them: exporting them here too would shadow those files.
FILE_CLIPS = (
    "Aim_Melee", "Aim_Pistol", "Aim_Rifle", "Aim_Shotgun", "Death", "Downed", "Duck", "Equip_Melee", "Equip_Pistol",
    "Equip_Rifle", "Equip_Shotgun", "Fire_Pistol", "Fire_Rifle", "Fire_Shotgun", "Grenade_Cook", "Grenade_Throw",
    "Grenade_Toss", "HitReact", "Idle", "Idle_Shoot", "Jump", "Jump_Idle", "Jump_Land", "No", "Punch",
    "Reload_Pistol", "Reload_Rifle", "Reload_Shotgun", "Repair_Board", "Run", "Run_Gun", "Swing_Melee",
    "Unequip_Melee", "Unequip_Pistol", "Unequip_Rifle", "Unequip_Shotgun", "Walk", "Wave", "Yes",
)  # fmt: skip


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
    # Her starting looks (#678), after his eight so a preset's index never moves.
    (
        "carhop",
        "Carhop",
        look(
            {"skin": 1, "hair": 3, "primary": 15, "secondary": 1, "accent": 6},
            body=FEMALE,
            hair="bob",
            headwear="papercap",
            torso="shirt",
            legs="cuffed",
            feet="sneakers",
            neck="bowtie",
        ),
    ),
    (
        "usherette",
        "Usherette",
        look(
            {"skin": 4, "hair": 4, "primary": 8, "secondary": 0, "accent": 11},
            body=FEMALE,
            hair="curls",
            headwear="pillbox",
            torso="jacket",
            legs="striped",
            feet="shoes",
        ),
    ),
    (
        "pit_crew",
        "Pit crew",
        look(
            {"skin": 0, "hair": 2, "primary": 5, "secondary": 3, "accent": 10},
            body=FEMALE,
            head="stubble",
            hair="bun",
            torso="rolled",
            legs="trousers",
            feet="boots",
            eyewear="goggles",
        ),
    ),
    (
        "pep_squad",
        "Pep squad",
        look(
            {"skin": 5, "hair": 0, "primary": 7, "secondary": 1, "accent": 1},
            body=FEMALE,
            head="beard",
            hair="ponytail",
            torso="letterman",
            legs="cuffed",
            feet="sneakers",
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
    soldier_arms.shorten_forearms(arm)  # #978: before any clip is solved by reach
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
    for a in [a for a in bpy.data.actions if a.name not in FILE_CLIPS]:
        bpy.data.actions.remove(a)
    clips = sorted(bpy.data.actions, key=lambda a: a.name)
    assert [a.name for a in clips] == sorted(FILE_CLIPS), "a clip of this file is missing"
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


def torso_rule(kind):
    """Swatch per face, or None to delete it. Sleeve x is along the arm in the rest T-pose (elbow at |x| 0.54)."""

    def rule(t):
        ax = abs(t.centre.x)
        sleeve = t.mat == "Black" and t.size >= 150
        cuff = t.mat == "Black" and t.size < 150 and ax > soldier_arms.along(0.8)
        pouch = t.mat == "DarkGrey" and t.centre.y < -0.09 and 1.09 < t.centre.z < 1.35 and ax < 0.2
        collar = t.mat == "Character_Main" and t.bone in ("Head", "Neck")
        if t.mat == "Skin":
            return "skin"
        if collar and t.size < 100 and kind in LOW_COLLAR:
            return None  # the tall collar's lip and front flap: laid on the neck they turned inside out (#895)
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
                return None  # bare wrists: the rings go, a band of skin joins the sleeve to the hand (bridge_wrist)
            if sleeve:
                return "primary" if upper else "skin"
            return "primary"
        if kind == "tank":
            if cuff:
                return None  # as the shirts' (bridge_wrist)
            if sleeve or collar:
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

# The hand's vertices (main bone a finger's, as the grip test reads them) never move: the weapon grips (#507) were
# solved on the kit's hand. Pushed in with the bare arm, every hand of a short-sleeved top floated 15-20 mm off its
# grips; with only its faces spared, the wrist's border vertices and the cuff ring still moved and the palm sank
# 3-13 mm into the rifle and shotgun (#678).
HAND_BONES = ("Index", "Middle", "Pinky", "Thumb")


def hand_vertices(o):
    """Indices of the vertices whose main bone is a hand bone."""
    names = [g.name for g in o.vertex_groups]
    out = set()
    for v in o.data.vertices:
        if v.groups and names[max(v.groups, key=lambda g: g.weight).group].startswith(HAND_BONES):
            out.add(v.index)
    return out


PUSH = {  # (slot, part): [(swatch the push applies to, metres along the normal)]: bare skin hugs the limb
    ("torso", "shirt"): [("skin", -0.025)],
    ("torso", "rolled"): [("skin", -0.025)],
    ("torso", "tank"): [("skin", -0.025)],
    ("legs", "shorts"): [("skin", -0.03)],
}


def weld_key(co):
    return (round(co.x * 1e5), round(co.y * 1e5), round(co.z * 1e5))


def push_taper(co):
    """How much of the bare-skin push a rest-pose vertex takes: none at the wrist (the hand is never pushed: its
    grips, #678) and at the ankle (the shoe's top is not), all of it a few centimetres away."""
    if abs(co.x) > 0.5:  # an arm, along X at rest: the wrist seam is at |x| 0.83-0.89 on the kit's arm (#978: along)
        return 1.0 - ramp(abs(co.x), soldier_arms.along(0.74), soldier_arms.along(0.83))
    if co.z < 0.6:  # a shin: the ankle seam is at z 0.19-0.26
        return ramp(co.z, 0.27, 0.36)
    return 1.0


def push_skin(me, keys, push, hands):
    """Push the faces of a swatch along the normals by an amount, every copy of a vertex alike (#895)."""
    amounts = {}
    for p, key in zip(me.polygons, keys):
        for swatch, amount in push:
            if key == swatch:
                amounts[p.index] = amount
    push_faces(me, amounts, hands)


# The long sleeves' forearms (#895): in the menu's carried holds of the long guns the right forearm crosses the
# chest, and the kit sleeve's girth sank it up to 46 mm into the jacket; 20 mm slimmer it is 33-39 mm (the bare
# forearms are pushed 25 mm), none of it at the elbow or in the cuff (drawn in, the cuffs bared the wrist's
# openings).
FOREARM_SLIM = -0.02


def slim_forearms(me, tags, hands):
    amounts = {
        p.index: FOREARM_SLIM
        for p, t in zip(me.polygons, tags)
        if t.mat == "Black" and t.size >= 150 and t.bone.startswith("LowerArm")
    }
    push_faces(me, amounts, hands, elbow=True)


def push_faces(me, amounts, hands, elbow=False):
    """Push faces ({polygon index: metres}) along the normals, every copy of a vertex alike (#895).

    The kit body is split at every material and normal seam, so a vertex is several vertices in one place: pushed
    one by one along their own normals they parted and the arms and shins showed cracks all along. `elbow` also
    tapers the push to nothing at the elbow (|x| 0.54 at rest)."""
    copies = collections.defaultdict(list)
    for v in me.vertices:
        copies[weld_key(v.co)].append(v.index)
    amount_at = {}
    for pi, amount in amounts.items():
        for vi in me.polygons[pi].vertices:
            amount_at[weld_key(me.vertices[vi].co)] = amount
    for k, amount in amount_at.items():
        ids = copies[k]
        if any(vi in hands for vi in ids):
            continue
        n = sum((me.vertices[vi].normal for vi in ids), Vector())
        if n.length < 1e-9:
            continue
        co = me.vertices[ids[0]].co
        taper = push_taper(co) * (ramp(abs(co.x), soldier_arms.along(0.56), soldier_arms.along(0.64)) if elbow else 1.0)
        d = n.normalized() * amount * taper
        for vi in ids:
            me.vertices[vi].co += d


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
    hands = hand_vertices(o)
    if push:
        push_skin(me, keys, push, hands)
    if region == "torso" and not low_collar:
        slim_forearms(me, tags, hands)
    if region == "torso":
        sink_collar_foot(o, tags)
    if low_collar:
        fit_low_collar(o, tags)
    me.materials.clear()
    me.materials.append(mat)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    collar = [
        bm.faces[i]
        for i, (k, t) in enumerate(zip(keys, tags))
        if k is not None and region == "torso" and t.mat == "Character_Main" and t.bone in ("Head", "Neck")
    ]
    lining = "skin" if collar and keys[collar[0].index] == "skin" else "primary_shade"  # the tank's is bare skin
    gone = [bm.faces[i] for i, k in enumerate(keys) if k is None]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    if collar:
        line_collar(bm, collar, lining)
    if low_collar:
        for side in (-1, 1):
            bridge_wrist(bm, side)
    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(me)
    bm.free()
    for m in o.modifiers:
        if m.type == "ARMATURE":
            m.object = arm
    return o


# --- the bare wrist (#895) -------------------------------------------------------------------------------------------
#
# The kit hides the open end of the sleeve tube (|x| ~0.81) and the hand's open wrist (|x| ~0.89) under three cuff
# rings. The bare-armed tops used to pull those rings in to the arm, which bared both openings: from the side the eye
# looked into the hand and the forearm and out through them. They now drop the rings and join the two openings with
# one band of skin.
WRIST_X = (soldier_arms.along(0.74), soldier_arms.along(0.95))  # |x| of the openings a bare wrist joins, at rest


def open_loops(bm, keep):
    """The open edge loops of a mesh whose copies of a vertex are welded by place: each a list of positions in
    order, for the loops whose every vertex passes `keep(co)`."""
    tmp = bm.copy()
    bmesh.ops.remove_doubles(tmp, verts=tmp.verts[:], dist=1e-5)
    seen, out = set(), []
    for e in tmp.edges:
        if not e.is_boundary or e in seen:
            continue
        loop, v, edge = [], e.verts[0], e
        while edge not in seen:
            seen.add(edge)
            loop.append(v.co.copy())
            v = edge.other_vert(v)
            edge = next((x for x in v.link_edges if x.is_boundary and x not in seen), edge)
        if all(keep(co) for co in loop):
            out.append(loop)
    tmp.free()
    return out


ARMHOLE_X, ARMHOLE_Z = (0.11, 0.22), (1.28, 1.50)  # the sleeve tubes' inner ends, inside the shoulders at rest


def cap_armholes(o):
    """Close the inner open end of each sleeve tube (|x| 0.135): inside the shoulder, but the front of the armpit
    let a ray in under the collar and out through the tube (#895)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    loops = open_loops(bm, lambda co: ARMHOLE_X[0] < abs(co.x) < ARMHOLE_X[1] and ARMHOLE_Z[0] < co.z < ARMHOLE_Z[1])
    by_place = {}
    for v in bm.verts:
        by_place.setdefault(weld_key(v.co), v)
    uv = bm.loops.layers.uv.active
    for lp in loops:
        f = bm.faces.new([by_place[weld_key(p)] for p in lp])
        f.normal_update()
        side = 1 if sum(p.x for p in lp) > 0 else -1
        if f.normal.x * side > 0:  # the cap faces the trunk's middle, out of the tube
            f.normal_flip()
        u = uv_of("primary_shade")
        for loop in f.loops:
            loop[uv].uv = u
        bmesh.ops.triangulate(bm, faces=[f])
    bm.to_mesh(o.data)
    bm.free()
    return len(loops)


def bridge_wrist(bm, side):
    """Join the sleeve tube's open end to the hand's open wrist on one side with a band of triangles."""
    loops = open_loops(bm, lambda co: WRIST_X[0] < co.x * side < WRIST_X[1])
    assert len(loops) == 2, f"wrist {side}: {len(loops)} open loops, expected the sleeve's end and the hand's"
    loops.sort(key=lambda lp: sum(abs(c.x) for c in lp) / len(lp))
    by_place = {}
    for v in bm.verts:
        by_place.setdefault(weld_key(v.co), v)
    rings = []
    for lp in loops:
        c = sum(lp, Vector()) / len(lp)
        ring = sorted(((math.atan2(p.z - c.z, p.y - c.y), by_place[weld_key(p)]) for p in lp), key=lambda a: a[0])
        rings.append((c, ring))
    (ca, a), (cb, b) = rings
    uv = bm.loops.layers.uv.active
    skin_uv = uv_of("skin")
    i = j = 0
    na, nb = len(a), len(b)
    while i < na or j < nb:
        va, vb = a[i % na][1], b[j % nb][1]
        next_a = a[(i + 1) % na][0] + (2 * math.pi if i + 1 >= na else 0)
        next_b = b[(j + 1) % nb][0] + (2 * math.pi if j + 1 >= nb else 0)
        if j >= nb or (i < na and next_a <= next_b):
            tri = (va, a[(i + 1) % na][1], vb)
            i += 1
        else:
            tri = (va, b[(j + 1) % nb][1], vb)
            j += 1
        f = bm.faces.new(tri)
        f.normal_update()
        mid = f.calc_center_median()
        axis = ca + (cb - ca) * ((mid.x - ca.x) / (cb.x - ca.x))
        if f.normal.dot(mid - axis) < 0:
            f.normal_flip()
        for loop in f.loops:
            loop[uv].uv = skin_uv


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

    def add(self, make, swatch, at=(0, 0, 0), rot=None, scale=None, bevel=BEVEL, taper=None, under=None, smooth=False):
        """`under`: a second swatch for the faces that point down (a shade underneath); `smooth`: smooth-shaded
        (a rounded mass of hair, where flat faces showed every facet)."""
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
            f.smooth = smooth
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
    for pid, o in her_hair(arm, mat, crown).items():
        P["hair", pid] = o
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
    # Neck: on the Neck bone, which carries the open collars' band (#895; on Head, a strike's nod sank the bow tie
    # 57 mm into the chest).
    P["neck", "scarf"] = (
        Piece()
        .add(cyl(0.39, 0.37, 0.12, 14), "accent", at=(0, 0.0, 1.47))
        .add(cube((0.14, 0.06, 0.26)), "accent_shade", at=(0.16, -0.37, 1.34), rot=ry(-12))
        .build("neck__scarf", "Neck", arm, mat)
    )
    bow = Piece()
    for sx in (-1, 1):
        bow.add(
            cyl(0.085, 0.0, 0.14, 3), "accent", at=(sx * 0.075, -0.30, 1.43), rot=ry(-sx * 90) @ rx(90), bevel=0.008
        )
    bow.add(cube((0.06, 0.06, 0.06)), "accent_shade", at=(0, -0.31, 1.43), bevel=0.01)
    P["neck", "bowtie"] = bow.build("neck__bowtie", "Neck", arm, mat)  # #895: on Head it sank into the chest
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


# --- the female Soldier (#678) ---------------------------------------------------------------------------------------
#
# One smooth field moves the kit body's vertices at rest, so the torso and the legs, and every outfit cut from them,
# change the same way and still meet at the waist. The bones, the weights' bones and every clip stay his. Kit metres,
# front -Y (the Soldier is 0.8 of this in the game).
CHEST_X, CHEST_Z = 0.105, 1.145  # each side's centre: below the shoulder line (1.30), above the waist
CHEST_SX, CHEST_SZ = 0.085, 0.068  # its spread across and up (a Gaussian's sigma); kept off z 1.28, where the
# sprint carries lay the left forearm across the chest (#678: higher, the forearm sank 14 mm deeper than in his)
CHEST_DEPTH = 0.09  # how far forward each side comes at its centre (7 cm in the game)
CHEST_FRONT = (-0.04, -0.14)  # a vertex is pushed in full from y -0.14 forward, not at all behind y -0.04
CHEST_TO_TORSO = 0.6  # share of the pushed vertices' weights moved to Torso, so the shoulders do not pull them
WAIST_Z, WAIST_S, WAIST_IN = 1.04, 0.07, 0.13  # the waist: 13 % narrower at z 1.04
HIPS_Z, HIPS_S, HIPS_OUT = 0.86, 0.05, 0.03  # the hips: 3 % wider at z 0.86 (5 % put the swinging hands into them)
SHAPE_Z = (0.74, 1.34)  # nothing outside this band moves (the arms at rest are at z 1.39, the knees at 0.56)


def gauss(d, s):
    return math.exp(-(d * d) / (2 * s * s))


def ramp(v, a, b):
    t = min(max((v - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def female_shape(co):
    """(moved position, chest push 0-1) for one rest-pose vertex."""
    x, y, z = co
    if not SHAPE_Z[0] < z < SHAPE_Z[1] or abs(x) > 0.5:
        return Vector(co), 0.0
    scale = 1.0 - WAIST_IN * gauss(z - WAIST_Z, WAIST_S) + HIPS_OUT * gauss(z - HIPS_Z, HIPS_S)
    depth = 1.0 - 0.5 * WAIST_IN * gauss(z - WAIST_Z, WAIST_S)
    push = gauss(abs(x) - CHEST_X, CHEST_SX) * gauss(z - CHEST_Z, CHEST_SZ) * ramp(y, CHEST_FRONT[0], CHEST_FRONT[1])
    return Vector((x * scale, 0.01 + (y - 0.01) * depth - CHEST_DEPTH * push, z)), push


def female_copy(o, arm):
    """Her variant of a torso or legs part: a copy moved by female_shape, the chest weighted toward Torso."""
    f = o.copy()
    f.data = o.data.copy()
    f.name = f.data.name = o.name + "__" + FEMALE
    bpy.context.collection.objects.link(f)
    groups = {g.name: g for g in f.vertex_groups}
    torso = groups.get("Torso") or f.vertex_groups.new(name="Torso")
    for v in f.data.vertices:
        v.co, push = female_shape(v.co)
        k = CHEST_TO_TORSO * min(push * 1.5, 1.0)
        if k <= 0.0:
            continue
        for g in v.groups:
            g.weight *= 1.0 - k
        torso.add([v.index], k, "ADD")
    for m in f.modifiers:
        if m.type == "ARMATURE":
            m.object = arm
    return f


def thin_brows(features):
    """Her brows: the kit's block brows, half as tall, lifted 12 mm and arched (higher in the middle of each)."""
    me = features.data
    brow = {vi for p in me.polygons if p.center.z >= 1.89 for vi in p.vertices}
    for side in (-1, 1):
        verts = [me.vertices[i] for i in brow if me.vertices[i].co.x * side > 0]
        if not verts:
            continue
        cx = sum(v.co.x for v in verts) / len(verts)
        cz = sum(v.co.z for v in verts) / len(verts)
        hw = max(abs(v.co.x - cx) for v in verts) or 1.0
        for v in verts:
            t = (v.co.x - cx) / hw
            v.co.z = cz + (v.co.z - cz) * 0.5 + 0.012 + 0.014 * (1 - t * t) - 0.006 * t * side
    return features


def face_surface(head, x, z):
    """The y of the head's front surface at (x, z), from a ray along +Y (the face at rest)."""
    from mathutils.bvhtree import BVHTree

    me = head.data
    tree = BVHTree.FromPolygons([v.co for v in me.vertices], [p.vertices for p in me.polygons])
    hit, _n, _i, _d = tree.ray_cast(Vector((x, -2.0, z)), Vector((0, 1, 0)))
    return hit.y if hit else FRONT


def eye_bounds(features, side):
    """(inner x, outer x, top z, y at the top) of one eye of the face features (|x| grows outward)."""
    me = features.data
    pts = [v.co for v in me.vertices if v.co.z < 1.89 and v.co.x * side > 0]
    xs = [abs(p.x) for p in pts]
    top = max(p.z for p in pts)
    y_top = min(p.y for p in pts if p.z > top - 0.02)
    return min(xs), max(xs), top, y_top


def shell(r, centre, scale, keep_y=None, keep_z=None, segs=16, rings=10):
    """A sphere scaled about `centre`, cut open where y < keep_y (the face) and below keep_z, the cuts closed:
    in world terms, so Piece.add gets it at the origin with no further scale."""

    def make(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
        bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector(centre), verts=bm.verts)
        for co, no, wanted in (((0, keep_y, 0), (0, -1, 0), keep_y), ((0, 0, keep_z), (0, 0, -1), keep_z)):
            if wanted is None:
                continue
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True)
            bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)

    return make


def her_hair(arm, mat, crown):
    """Three cuts kept above the shoulders (the hair is skinned to Head; the collar's top is z 1.68 at r 0.36)."""
    hair = {}
    hair["bob"] = (
        Piece()
        # Its ends flare (r 0.40 at z 1.72) past the collar's top (r 0.36 at z 1.68), so a tilted head never sinks the
        # rim into the collar (it did at z 1.66, r 0.32, in the grenade throw).
        .add(shell(0.40, (0, 0.0, 1.86), (1.06, 1.06, 1.0), keep_y=-0.19, keep_z=1.72), "hair", bevel=0,
             under="hair_shade", smooth=True)
        .add(sphere(0.36, 16, 8), "hair", at=(0, -0.10, 2.07), scale=(1.06, 0.8, 0.36), bevel=0, under="hair_shade",
             smooth=True)
        .build("hair__bob", "Head", arm, mat)
    )  # fmt: skip
    curls = crown().add(
        shell(0.40, (0, 0.02, 1.88), (1.03, 1.0, 0.9), keep_y=-0.06, keep_z=1.70),
        "hair",
        bevel=0,
        under="hair_shade",
        smooth=True,
    )
    for side in (-1, 1):
        curls.add(cyl(0.105, 0.105, 0.34, 12), "hair", at=(side * 0.165, -0.12, TOP + 0.0), rot=rx(90), bevel=0.02,
                  under="hair_shade")  # fmt: skip
    hair["curls"] = curls.build("hair__curls", "Head", arm, mat)
    hair["bun"] = (
        crown()
        .add(sphere(0.16, 12, 8), "hair", at=(0, BACK - 0.04, TOP - 0.02), scale=(1.0, 0.95, 0.9), bevel=0,
             under="hair_shade", smooth=True)
        .add(cyl(0.13, 0.13, 0.045, 12), "accent", at=(0, BACK - 0.09, TOP - 0.06), rot=rx(-35), bevel=0.01)
        .build("hair__bun", "Head", arm, mat)
    )  # fmt: skip
    return hair


# --- the head (#895) -------------------------------------------------------------------------------------------------
#
# The kit head is a soldier's balaclava: a skin panel set back in a hood, a raised rim round the opening, and nothing
# under the hood (its vest's tall collar closed it). Recoloured, the rim read as a mask from the chin up both cheeks,
# and with an open-necked top the hood's open ring showed the inside of the head (#895). Each head is now one closed
# shape: the hood's outside (the convex hull of the kit's hood, face panel and rim, so every hat, hair and pair of
# glasses sits where it did), a quad sphere pushed out onto it, smooth, with a buzz of hair painted above a cut
# hairline, and a neck down into the shoulders. The eyes and brows are the kit's; the mouth is new (MOUTH_STYLE).
HEAD_SEGS = 6  # quads per cube edge of the head's quad sphere (216 quads; smooth-shaded, no facets show)
HEAD_RELAX = 2  # smoothing passes over the head's shape
HEAD_ON_HULL_Z = 1.72  # below this the head stays on the hull (the collar's top ring is on it)
HEAD_INTO_COLLAR = 0.008
NECK_R = 0.125  # the neck's radius: the kit trunk's own neck hole (r 0.12-0.13 at z 1.59) closes round it
NECK_Z = (1.40, 1.66)  # from inside the shoulders to inside the head
NECK_AXIS_Y = 0.003  # the Neck and Head bones' line
HAIR_FRONT_Z = 2.03  # the buzz's line across the forehead (the brows' top is z 1.94)
HAIR_TEMPLE_Y = -0.06  # behind this the hairline steps down at the temple
HAIR_SIDE_Z, HAIR_SLOPE = 1.95, 0.5  # from the temple the line falls 0.5 m a metre towards the nape
BEARD_Z, BEARD_BACK_Y, BEARD_SIDE_X = 1.74, 0.02, 0.27  # the jaw below the cheeks, and the sideburns up to the hair
EYE_PROUD = 0.006  # how far the eyes' front stands out of the new face
# The mouth (#895). The design and the two set aside are on docs/research/character-faces.md.
MOUTH_STYLE = "smile"
MOUTH_Z = 1.672  # its middle: between the eyes' bottom (1.748) and the chin
MOUTH_W = {"male": 0.135, FEMALE: 0.115}  # wide enough to read as a mouth past 10 m on a phone
MOUTH_DEPTH, MOUTH_PROUD = 0.012, 0.004  # into the head, and standing out of it


def head_hull(body, tags):
    """A bmesh of the convex hull of the kit head's faces (hood, face panel and rim) at rest."""
    me = body.data
    pts = {vi for p, t in zip(me.polygons, tags) if region_of(t) == "head" for vi in p.vertices}
    bm = bmesh.new()
    for vi in pts:
        bm.verts.new(me.vertices[vi].co)
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    return bm


def head_shape(hull):
    """The head: a quad sphere pushed out from the hull's middle onto the hull. Returns a bmesh (no UVs yet)."""
    from mathutils.bvhtree import BVHTree

    tree = BVHTree.FromBMesh(hull)
    lo = Vector([min(v.co[i] for v in hull.verts) for i in range(3)])
    hi = Vector([max(v.co[i] for v in hull.verts) for i in range(3)])
    centre = (lo + hi) / 2
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=HEAD_SEGS - 1, use_grid_fill=True)
    for v in bm.verts:
        d = v.co.normalized()
        hit, _n, _i, _dist = tree.ray_cast(centre, d)
        v.co = hit if hit is not None else centre + d * 0.3
    # The hull is faceted where the kit rim's corners stood out (a kink on each cheek caught the light): relax it.
    for _ in range(HEAD_RELAX):
        bmesh.ops.smooth_vert(bm, verts=bm.verts[:], factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # ...but not under the jaw: there the head stays on the hull, which passes through the hood's own bottom ring,
    # the ring the tall collars' tops were built to meet (relaxed, the head left a gap inside the collar).
    # The quad sphere's chords run a few millimetres inside the ring, so the jaw also stands HEAD_INTO_COLLAR out of
    # the hull: inside a tall collar, past the top of its ring (a ray between them looked into the collar).
    for v in bm.verts:
        if v.co.z < HEAD_ON_HULL_Z:
            d = (v.co - centre).normalized()
            hit, _n, _i, _dist = tree.ray_cast(centre, d)
            if hit is not None:
                v.co = hit + d * HEAD_INTO_COLLAR * ramp(HEAD_ON_HULL_Z - v.co.z, 0.0, 0.06)
    for f in bm.faces:
        f.smooth = True
    return bm


def cut(bm, co, no, where=None):
    """Bisect `bm` by a plane, only through the faces `where(face)` keeps (a cut through the whole head costs a
    ring of triangles where no colour changes)."""
    faces = [f for f in bm.faces if where is None or where(f)]
    geom = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges}) + faces
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)


def spans(f, axis, lo, hi):
    """Whether a face reaches into lo..hi along an axis (0 x, 1 y, 2 z)."""
    vals = [v.co[axis] for v in f.verts]
    return max(vals) >= lo and min(vals) <= hi


def head_swatches(bm, kind):
    """Cut the hairline (and the beard's edges) into the head and give each face its swatch: straight colour edges at
    every angle (whole faces painted by their centre left teeth: #140)."""
    cut(bm, (0, 0, HAIR_FRONT_Z), (0, 0, 1), lambda f: spans(f, 1, -1, HAIR_TEMPLE_Y))
    cut(bm, (0, HAIR_TEMPLE_Y, 0), (0, 1, 0), lambda f: spans(f, 2, HAIR_SIDE_Z - 0.02, HAIR_FRONT_Z + 0.02))
    side = Vector((0, HAIR_SLOPE, 1)).normalized()
    cut(bm, (0, HAIR_TEMPLE_Y, HAIR_SIDE_Z), side, lambda f: spans(f, 1, HAIR_TEMPLE_Y, 1))
    beard = {"plain": None, "stubble": "skin_shade", "beard": "hair"}.get(kind)
    if beard:
        cut(bm, (0, 0, BEARD_Z), (0, 0, 1), lambda f: spans(f, 1, -1, BEARD_BACK_Y))
        cut(bm, (0, BEARD_BACK_Y, 0), (0, 1, 0), lambda f: spans(f, 2, 0, HAIR_SIDE_Z + 0.05))
        for sx in (-1, 1):
            cut(bm, (sx * BEARD_SIDE_X, 0, 0), (1, 0, 0),
                lambda f: spans(f, 2, BEARD_Z, HAIR_SIDE_Z + 0.05) and spans(f, 1, -1, BEARD_BACK_Y))  # fmt: skip
    out = {}
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z > HAIR_FRONT_Z or (c.y > HAIR_TEMPLE_Y and (c.z - HAIR_SIDE_Z) + HAIR_SLOPE * (c.y - HAIR_TEMPLE_Y) > 0):
            out[f] = "hair"
        elif beard and c.y < BEARD_BACK_Y and (c.z < BEARD_Z or abs(c.x) > BEARD_SIDE_X):
            out[f] = beard
        else:
            out[f] = "skin"
    return out


def neck_shape(bm):
    """The neck: an open tube (both ends are inside other shapes) added to `bm`; returns its new faces."""
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=False, segments=12, radius1=NECK_R, radius2=NECK_R,
                          depth=NECK_Z[1] - NECK_Z[0])  # fmt: skip
    bmesh.ops.translate(tmp, verts=tmp.verts, vec=Vector((0, NECK_AXIS_Y, sum(NECK_Z) / 2)))
    me = bpy.data.meshes.new("tmp")
    tmp.to_mesh(me)
    tmp.free()
    start = len(bm.faces)
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bm.faces.ensure_lookup_table()
    faces = list(bm.faces)[start:]
    for f in faces:
        f.smooth = True
    return faces


def build_head(name, hull, kind, arm, mat):
    """One head part (no eyes yet): the shape, its swatches, the neck; skinned to Head, the neck's foot to Neck."""
    bm = head_shape(hull)
    swatch = head_swatches(bm, kind)
    for f in neck_shape(bm):
        swatch[f] = "skin"
    uv = bm.loops.layers.uv.new("UVMap")
    for f, key in swatch.items():
        u = uv_of(key)
        for loop in f.loops:
            loop[uv].uv = u
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.parent = arm
    o.matrix_parent_inverse = arm.matrix_world.inverted()
    me.materials.append(mat)
    head, neck = o.vertex_groups.new(name="Head"), o.vertex_groups.new(name="Neck")
    lo, hi = 1.46, 1.57  # the Neck bone's length: below it the neck follows Neck, above it Head
    for v in me.vertices:
        w = min(max((v.co.z - lo) / (hi - lo), 0.0), 1.0)
        if w > 0:
            head.add([v.index], w, "REPLACE")
        if w < 1:
            neck.add([v.index], 1 - w, "REPLACE")
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    return o


def seat_features(features, head):
    """Move the kit's eyes and brows straight forward so each eye's front stands EYE_PROUD out of the new face."""
    me = features.data
    shift = 0.0
    for side in (-1, 1):
        eye = [v.co for v in me.vertices if v.co.z < 1.89 and v.co.x * side > 0]
        front = min(eye, key=lambda c: c.y)
        surface = face_surface(head, front.x, front.z)
        shift = min(shift, surface - EYE_PROUD - front.y)
    for v in me.vertices:
        v.co.y += shift
    return shift


def decal(p, outline, swatch, head, proud=MOUTH_PROUD, depth=MOUTH_DEPTH):
    """A flat shape on the face: `outline` is (x, z) points round it (front view, counter-clockwise seen from the
    front); its front stands `proud` out of the face at each point and its back is `depth` inside."""
    bm = bmesh.new()
    front, back = [], []
    for x, z in outline:
        y = face_surface(head, x, z)
        front.append(bm.verts.new((x, y - proud, z)))
        back.append(bm.verts.new((x, y + depth, z)))
    n = len(outline)
    bm.faces.new(list(reversed(front)))
    bm.faces.new(back)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    # Outward by hand: recalc_face_normals turned this thin a shape inside out (the front culled away).
    middle = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median() - middle) < 0:
            f.normal_flip()
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    me = bpy.data.meshes.new("tmp")
    bm.to_mesh(me)
    bm.free()
    u = uv_of(swatch)
    start = len(p.bm.faces)
    p.bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    p.bm.faces.ensure_lookup_table()
    for f in list(p.bm.faces)[start:]:
        for loop in f.loops:
            loop[p.uv].uv = u
    return p


def mouth_outline(style, width, z=MOUTH_Z):
    """The mouth seen from the front, (x, z) counter-clockwise. `smile`: an open half-moon, flat on top, round below;
    `line`: a closed mouth, a bar whose corners turn up; `grin`: the half-moon, wider and shallower."""
    hw = width / 2
    if style in ("smile", "grin"):
        deep = 0.056 if style == "smile" else 0.04
        top = z + deep * 0.45
        # From the right corner round the bottom to the left corner, then back along the top: the top line has
        # points of its own so it follows the face's curve (a straight chord between the corners sank into it).
        arc = [(hw * math.cos(a), top - deep * math.sin(a)) for a in (math.pi * i / 10 for i in range(11))]
        return arc + [(-hw + width * i / 6, top) for i in range(1, 6)]
    if style == "line":
        n, thick, lift = 6, 0.026, 0.012
        xs = [-hw + width * i / n for i in range(n + 1)]
        lower = [(x, z - thick / 2 + lift * (2 * x / width) ** 2) for x in xs]
        upper = [(x, z + thick / 2 + lift * (2 * x / width) ** 2) for x in reversed(xs)]
        return lower + upper
    raise ValueError(style)


def face_extras(kind, female, features, head, arm, mat, style=MOUTH_STYLE):
    """The parts of a face kept whole in the far level of detail: the mouth, and for her the lashes and the
    freckles (stubble's place) or rosy cheeks (beard's)."""
    p = Piece()
    pts = mouth_outline(style, MOUTH_W[FEMALE if female else "male"])
    decal(p, pts, "mouth", head)
    if female:
        add_lashes(p, features, head)
        if kind == "stubble":  # freckles: three dots under each eye
            for side in (-1, 1):
                for dx, dz in ((0.14, 1.732), (0.175, 1.718), (0.21, 1.734)):
                    y = face_surface(head, side * dx, dz)
                    p.add(cube((0.016, 0.012, 0.016)), "skin_shade", at=(side * dx, y + 0.001, dz), bevel=0.0)
        if kind == "beard":  # rosy cheeks
            for side in (-1, 1):
                y = face_surface(head, side * 0.2, 1.715)
                p.add(cyl(0.04, 0.04, 0.012, 10), "blush", at=(side * 0.2, y + 0.002, 1.715), rot=rx(90),
                      scale=(1.0, 0.62, 1.0), bevel=0.0)  # fmt: skip
    return p.build("face_extras", "Head", arm, mat)


def add_lashes(p, features, head):
    """Her lashes: a lid line over each eye and two strokes out from its outer corner."""
    for side in (-1, 1):
        x0, x1, top, y_top = eye_bounds(features, side)
        cx, w = (x0 + x1) / 2, x1 - x0
        p.add(cube((w * 0.92, 0.022, 0.024)), "eye", at=(side * cx, y_top - 0.004, top + 0.004), bevel=0)
        for i, (length, angle) in enumerate(((0.062, 30), (0.045, 58))):
            a = math.radians(angle)
            along = Vector((side * math.cos(a), 0, math.sin(a)))
            bx, bz = side * (x1 - 0.004 - 0.022 * i), top - 0.002 + 0.012 * i
            base = Vector((bx, face_surface(head, bx, bz) - 0.006, bz))
            p.add(cube((length, 0.02, 0.02)), "eye", at=base + along * (length / 2), rot=ry(-side * angle), bevel=0)


# --- the open-necked tops' collar (#895) -------------------------------------------------------------------------------
#
# The kit's tall collar folded down (verts above z 1.50 squashed to 45 %) stood off the shoulders as a thin ring with
# the head's open ring above it, and moved with the head. Now its verts above COLLAR_FOOT are laid on a slope from the
# shoulders up to a band that hugs the neck, and follow the Neck bone.
COLLAR_FOOT = 1.45
COLLAR_TOP_Z = 1.585
COLLAR_HUG = NECK_R - 0.006  # the band's top edge: just inside the neck, so no gap shows between them


def collar_verts(me, tags):
    return {
        vi
        for p, t in zip(me.polygons, tags)
        if t.mat == "Character_Main" and t.bone in ("Head", "Neck")
        for vi in p.vertices
    }


def fit_low_collar(o, tags):
    me = o.data
    groups = {g.name: g for g in o.vertex_groups}
    neck = groups.get("Neck") or o.vertex_groups.new(name="Neck")
    names = [g.name for g in o.vertex_groups]
    top = max(me.vertices[vi].co.z for vi in collar_verts(me, tags))
    for vi in collar_verts(me, tags):
        v = me.vertices[vi]
        co = v.co
        if co.z <= COLLAR_FOOT:
            continue
        t = ramp(co.z, COLLAR_FOOT, top)
        d = Vector((co.x, co.y - NECK_AXIS_Y, 0))
        r = d.length
        if r > 1e-6:
            r_new = r + (COLLAR_HUG - r) * t
            d = d / r * r_new
        co.x, co.y = d.x, NECK_AXIS_Y + d.y
        co.z = COLLAR_FOOT + (COLLAR_TOP_Z - COLLAR_FOOT) * t
        # The band follows the neck's foot, not the head (a head turn swung the old ring through the shoulders).
        moved = 0.0
        for g in v.groups:
            if names[g.group] == "Head":
                moved += g.weight
                g.weight = 0.0
        if moved:
            neck.add([vi], moved, "ADD")


def line_collar(bm, faces, swatch):
    """Give the collar an inside: a copy of its faces turned round, in `swatch`. Single-sided, its inside was
    culled, and a look down between the collar and the head saw out through it (#895)."""
    res = bmesh.ops.duplicate(bm, geom=list(faces))
    lining = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)]
    bmesh.ops.reverse_faces(bm, faces=lining)
    uv = bm.loops.layers.uv.active
    u = uv_of(swatch)
    for f in lining:
        for loop in f.loops:
            loop[uv].uv = u


COLLAR_SKIRT_Z = 1.43  # the kit collar's foot (z 1.406) stands off the shoulders: below this it sinks in
COLLAR_SINK = 0.0


def sink_collar_foot(o, tags):
    """Pull the foot of the collar in towards the neck's line, into the shoulders (a ray under its edge looked into
    the collar from below)."""
    me = o.data
    for vi in collar_verts(me, tags):
        co = me.vertices[vi].co
        if co.z < COLLAR_SKIRT_Z:
            d = Vector((co.x, co.y - NECK_AXIS_Y, 0))
            if d.length > COLLAR_SINK:
                k = (d.length - COLLAR_SINK * ramp(COLLAR_SKIRT_Z - co.z, 0.0, 0.02)) / d.length
                co.x, co.y = d.x * k, NECK_AXIS_Y + d.y * k


def cap_neck_hole(o):
    """Close the trunk's own neck hole (an open ring of r ~0.12 round the neck's foot, z ~1.54-1.59)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    edges = [
        e
        for e in bm.edges
        if e.is_boundary and all(v.co.z > 1.5 and Vector((v.co.x, v.co.y - NECK_AXIS_Y)).length < 0.16 for v in e.verts)
    ]
    if edges:
        res = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        uv = bm.loops.layers.uv.active
        u = uv_of("skin")
        for f in res["faces"]:
            f.normal_update()
            if f.normal.z < 0:  # holes_fill faced it down, into the trunk
                f.normal_flip()
            for loop in f.loops:
                loop[uv].uv = u
    bm.to_mesh(o.data)
    bm.free()
    return len(edges)


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
        # (#895: a triangle with two corners 0.01 mm apart counted here and was welded away by the export)
        bad, seen = [], set()
        for f in bm.faces:
            corners = tuple(sorted(weld_key(v.co) for v in f.verts))
            if f.calc_area() < 1e-8 or min(e.calc_length() for e in f.edges) < 1e-5 or corners in seen:
                bad.append(f)
            seen.add(corners)
        bmesh.ops.delete(bm, geom=bad, context="FACES_ONLY")
        bm.to_mesh(far.data)
        bm.free()
    return far


def far_parts(parts, presets_of):
    """A far copy of every part ({mesh name: object}), with one decimation ratio for every part bigger than
    FAR_KEEP, solved so the heaviest preset's far parts come to FAR_AIM (`presets_of(tris)` gives each preset's sum
    for a {mesh: tris})."""
    near = {k: kitlib.tris(o) for k, o in parts.items()}
    big = {k: v for k, v in near.items() if v > FAR_KEEP}
    ratio = 1.0
    for _ in range(6):
        guess = {k: (v * ratio if k in big else v) for k, v in near.items()}
        worst = max(presets_of(guess).values())
        if worst <= FAR_AIM:
            break
        small = max(presets_of({k: (0 if k in big else v) for k, v in near.items()}).values())
        ratio = min(ratio, max((FAR_AIM - small) / max(worst - small, 1) * ratio, FAR_MIN_RATIO)) * 0.99
    far = {key: far_copy(o, ratio if key in big else 1.0) for key, o in parts.items()}
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


def part_entry(s, p, label, tris, tris_far, female):
    """One part in parts.json; `female` holds her variant's meshes, `label_female` what she calls it, `body` the
    character a hair cut belongs to."""
    empty = p == "none" or s == BODY_SLOT
    near = f"{s}__{p}"
    entry = {
        "label": label,
        "mesh": None if empty else near,
        "tris": tris.get(near, 0),
        "mesh_far": None if empty else near + "__far",
        "tris_far": tris_far.get(near, 0),
    }
    if s == "headwear" and p in HIDES_HAIR:
        entry["hides_hair"] = True
    if s == "hair" and p in HAIR_BODY:
        entry["body"] = HAIR_BODY[p]
    if (s, p) in female:
        her = f"{near}__{FEMALE}"
        entry[FEMALE] = {"mesh": her, "tris": tris[her], "mesh_far": her + "__far", "tris_far": tris_far[her]}
    if (s, p) in FEMALE_LABELS:
        entry["label_" + FEMALE] = FEMALE_LABELS[s, p]
    return entry


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--soldier", required=True)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--preview", type=Path, help="also write one .glb per preset here (for render_sheet.py)")
    ap.add_argument("--preview-only", default="", help="comma-separated preset ids: write only these previews")
    ap.add_argument("--mouth", default=MOUTH_STYLE, help="a mouth design to try (smile, line, grin); ships smile")
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
    rules = {"torso": torso_rule, "legs": legs_rule, "feet": feet_rule}
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
            if slot == "torso":
                cap_neck_hole(parts[slot, pid])
                assert cap_armholes(parts[slot, pid]) == 2, f"{pid}: the two sleeve ends were not found"
    features = split_features(helmet)
    features.data.materials.append(mat)
    her_features = features.copy()
    her_features.data = features.data.copy()
    bpy.context.collection.objects.link(her_features)
    thin_brows(her_features)
    hull = head_hull(body, tags)
    female = {}  # (slot, part) -> her variant
    # The far heads decimate the head and its eyes and brows only and take the face's small pieces whole (the
    # mouth, her lashes and freckles): a collapse turned them into slivers that the glTF round trip dropped (Godot
    # counted fewer triangles).
    far_base, extras_of = {}, {}
    for pid in SLOTS["head"]["parts"]:
        for her in (False, True):
            name = f"head__{pid}__{FEMALE}" if her else f"head__{pid}"
            head = build_head(name, hull, "plain" if her else pid, arm, mat)
            f = (her_features if her else features).copy()
            f.data = (her_features if her else features).data.copy()
            bpy.context.collection.objects.link(f)
            seat_features(f, head)
            extras = face_extras(pid, her, f, head, arm, mat, args.mouth)
            join(head, f)
            base = head.copy()
            base.data = head.data.copy()
            base.name = base.data.name = name  # far_copy names its copy after this
            bpy.context.collection.objects.link(base)
            far_base[name], extras_of[name] = base, extras
            f = extras.copy()
            f.data = extras.data.copy()
            bpy.context.collection.objects.link(f)
            join(head, f)
            head.name = head.data.name = name
            if her:
                female["head", pid] = head
            else:
                parts["head", pid] = head
    bpy.data.objects.remove(features)
    bpy.data.objects.remove(her_features)
    hull.free()
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
    for slot in ("torso", "legs"):
        for pid in SLOTS[slot]["parts"]:
            female[slot, pid] = female_copy(parts[slot, pid], arm)

    missing = [
        (s, p)
        for s, spec in SLOTS.items()
        for p in spec["parts"]
        if p != "none" and s != BODY_SLOT and (s, p) not in parts
    ]
    assert not missing, f"parts with no mesh: {missing}"
    assert set(female) == {(s, p) for s in BODY_VARIANTS for p in SLOTS[s]["parts"]}, "a part has no female variant"
    # Every mesh by its node name: `<slot>__<part>`, and hers `<slot>__<part>__female`.
    by_name = {f"{s}__{p}": o for (s, p), o in parts.items()}
    by_name.update({f"{s}__{p}__{FEMALE}": o for (s, p), o in female.items()})
    tris = {k: kitlib.tris(o) for k, o in by_name.items()}

    def shown(lk):
        """The mesh names a look shows (SoldierLook.visible_meshes)."""
        hide_hair = lk["parts"]["headwear"] in HIDES_HAIR
        her = lk["parts"].get(BODY_SLOT) == FEMALE
        out = []
        for s, p in lk["parts"].items():
            if s == BODY_SLOT or p == "none" or (s == "hair" and hide_hair):
                continue
            out.append(f"{s}__{p}__{FEMALE}" if her and (s, p) in female else f"{s}__{p}")
        return out

    def look_sum(lk, counts):
        return sum(counts.get(k, 0) for k in shown(lk))

    # Every preset, and each of them worn by the other character, must fit the budgets.
    def worn_both(lk):
        other = {**lk, "parts": {**lk["parts"], BODY_SLOT: "male" if lk["parts"][BODY_SLOT] == FEMALE else FEMALE}}
        return (lk, other)

    looks_checked = {f"{pid}/{i}": lk2 for pid, _n, lk in PRESETS for i, lk2 in enumerate(worn_both(lk))}
    # The far ratio is solved over every look as built and as worn by the other character (#895: the heads' mouths
    # are kept whole like her face pieces, so they count as they are).
    extra_tris = {name: kitlib.tris(o) for name, o in extras_of.items()}

    def with_extras(counts):
        return {k: v + extra_tris.get(k, 0) for k, v in counts.items()}

    far_sources = {**by_name, **far_base}
    far_by_name, far_ratio = far_parts(
        far_sources, lambda counts: {k: look_sum(lk, with_extras(counts)) for k, lk in looks_checked.items()}
    )
    for name, extras in extras_of.items():
        far = join(far_by_name[name], extras)
        far.name = far.data.name = f"{name}__far"
        bpy.data.objects.remove(far_base[name])
    tris_far = {k: kitlib.tris(o) for k, o in far_by_name.items()}

    presets = []
    for pid, name, lk in PRESETS:
        for lk2 in worn_both(lk):
            t, t_far = look_sum(lk2, tris), look_sum(lk2, tris_far)
            assert t <= BUDGET, f"{pid} ({lk2['parts'][BODY_SLOT]}): {t} tris over the {BUDGET} budget"
            assert t_far <= FAR_BUDGET, f"{pid} ({lk2['parts'][BODY_SLOT]}): {t_far} far tris over {FAR_BUDGET}"
        presets.append({"id": pid, "name": name, **lk, "tris": look_sum(lk, tris), "tris_far": look_sum(lk, tris_far)})

    finish_pose(arm, factor)
    meshes = list(by_name.values()) + list(far_by_name.values())
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
                "parts": {p: part_entry(s, p, label, tris, tris_far, female) for p, label in spec["parts"].items()},
            }
            for s, spec in SLOTS.items()
        },
        # The character choice (#678): which slot holds it, and the hair each character starts from.
        "body": {"slot": BODY_SLOT, "variant": FEMALE, "hair": BODY_HAIR},
        "presets": presets,
    }
    (out / "parts.json").write_text(json.dumps(catalog, indent=1) + "\n", encoding="utf-8", newline="\n")
    print("PARTS", json.dumps({"clips": n_clips, "bones": len(arm.data.bones), "tris": tris}))
    print("PRESETS", json.dumps({p["id"]: p["tris"] for p in presets}))
    print("BOTH", json.dumps({k: [look_sum(lk, tris), look_sum(lk, tris_far)] for k, lk in looks_checked.items()}))
    print("FAR", json.dumps({"ratio": round(far_ratio, 3), "presets": {p["id"]: p["tris_far"] for p in presets},
                             "parts": tris_far}))  # fmt: skip

    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
        only = set(filter(None, args.preview_only.split(",")))
        for p in presets:
            if only and p["id"] not in only:
                continue
            img = paint_atlas("atlas_" + p["id"], p["colours"])
            mat.node_tree.nodes["Image Texture"].image = img
            for lk2 in worn_both(p):
                suffix = "" if lk2["parts"][BODY_SLOT] == p["parts"][BODY_SLOT] else "_" + lk2["parts"][BODY_SLOT]
                export(args.preview / f"{p['id']}{suffix}.glb", arm, [by_name[k] for k in shown(lk2)], images=True)
                keep_far = [far_by_name[k] for k in shown(lk2)]
                export(args.preview / f"{p['id']}{suffix}_far.glb", arm, keep_far, images=True)
        mat.node_tree.nodes["Image Texture"].image = atlas


if __name__ == "__main__":
    main()
