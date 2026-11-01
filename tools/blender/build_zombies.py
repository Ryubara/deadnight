"""Build Deadnight's zombie variants from the Quaternius Zombie (CC0), one glTF per variant and level of detail.

Run with the pinned Blender, headless (the outputs are CC0-derived and committed with their licence entry, issue #90):

    blender -b --factory-startup -P tools/blender/build_zombies.py -- \
        --zombie <workspace>/refs/polypizza/VlXjG0N8Eg/model.glb \
        --out game/assets/characters/zombies

Per variant it writes `zombie_<name>.glb`: one skeleton with all 16 clips and two skinned meshes, `Zombie_Mesh`
(gameplay LOD) and `Zombie_Far` (far LOD; the game switches them with visibility ranges), plus one shared `zombie_atlas.png` and `zombies.json` (triangle counts). The design is in
docs/design/zombies.md, the findings in docs/research/zombie-variants.md.

Every variant keeps the kit zombie's skeleton exactly (50 bones, same rest pose): the clean-up is the kit's
rig-sharing recipe (kit docs/blender/rig-sharing.md: TEMPERANCE import, armature as root, 100x scale applied with the
location keys scaled, one clip per name, pose bones cleared with pose_position left at POSE). Height is the armature
object's scale, which the glTF keeps as a node scale and never bakes into the bones, so one AnimationLibrary plays on
every variant with no rebasing of position keys. Build (brute, runner) moves vertices only, along their normals,
weighted by bone; missing parts delete the faces a bone carries and cap the hole with a wound colour. Colours stay
on the one atlas: the kit's 11 swatches plus new swatches painted into its empty corner, faces remapped by swatch.
"""

import argparse
import json
import re
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

# The kit atlas: every face sits on one 16 px swatch in a row at v 0.796 (style bible). Index = column.
SWATCHES = {
    "black": 0,  # eyes, brows
    "skin": 1,  # 71 % of the area
    "skin_dark": 2,  # ears, patches
    "mouth": 3,
    "wound_dark": 4,
    "wound": 5,
    "white": 6,  # sneaker soles
    "belt": 7,
    "bone": 8,  # teeth and the buckle
    "tongue": 9,  # tongue, nose
    "trousers": 10,
}
SWATCH_PX = 16
KIT_ROW_Y = 400  # pixel row (from the bottom) of the kit swatches
NEW_ROW_Y = 0  # new swatches go in the empty bottom-right corner of the atlas
NEW_COL0 = 16  # first free column there (x = 256 px)

# Bone groups as regular expressions on the vertex group (bone) names.
TOP_VEST = r"^(Torso|Abdomen|Shoulder\.[LR])$"
TOP_SHORT = r"^(Torso|Abdomen|Shoulder\.[LR]|UpperArm\.[LR])$"
TOP_LONG = r"^(Torso|Abdomen|Shoulder\.[LR]|UpperArm\.[LR]|LowerArm\.[LR])$"
WOUND = "#6b1e1e"

# Each variant: palette overrides (kit swatch -> sRGB hex); a painted top (the kit zombie is bare-chested: skin faces
# that follow the torso and arm bones are recoloured, so a shirt costs no triangles); height (the armature object's
# scale); vertex push along normals per bone group (metres at kit scale, times the skin weight); parts removed (faces
# that follow these bones go, the hole is capped in the wound colour); accessories. Clothes colours are the style
# bible's kit palette where one fits.
VARIANTS = {
    "walker": {"palette": {}, "height": 1.0},
    "greaser": {
        "palette": {"skin": "#8a9a6a", "trousers": "#2e4466", "belt": "#252525"},
        "top": ("#d6d0ba", TOP_SHORT),
        "height": 1.02,
    },
    "usher": {
        "palette": {"skin": "#6e8c4f", "trousers": "#252525", "belt": "#d1ab46"},
        "top": ("#8c3735", TOP_LONG),
        "height": 0.97,
        "accessories": [("cap", "#8c3735", "#d1ab46")],
    },
    "farmhand": {
        "palette": {"skin": "#7a9150", "trousers": "#5c6d37", "belt": "#664531"},
        "top": ("#9b7048", TOP_SHORT),
        "height": 1.0,
        "remove": r"^(LowerArm|Pinky\d|Middle\d|Index\d|Thumb\d)\.L$",
    },
    "runner": {
        "palette": {"skin": "#86a85a", "trousers": "#5f5f5f"},
        "top": ("#3b4b8c", TOP_VEST),
        "height": 1.07,
        "push": {r"^(UpperArm|LowerArm|UpperLeg|LowerLeg)\.[LR]$|^Abdomen$": -0.012},
    },
    "brute": {
        "palette": {"skin": "#5f7d45", "trousers": "#3f5363", "belt": "#252525"},
        "height": 1.18,
        "push": {
            r"^(Torso|Neck|Shoulder\.[LR])$": 0.05,
            r"^(UpperArm|LowerArm)\.[LR]$": 0.04,
            r"^(Abdomen|Hips)$": 0.03,
        },
    },
    "crawler": {
        "palette": {"skin": "#8d9a74", "trousers": "#4a3a2c"},
        "top": ("#7d6b55", TOP_VEST),
        "height": 1.0,
        "remove": r"^(LowerLeg|Foot)\.[LR]$",
    },
}
TARGET_TRIS = (4000, 1500)  # style bible budget: zombie gameplay LOD 4k, far LOD 1.5k


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))


def swatch_uv(col, row_y):
    return ((col * SWATCH_PX + SWATCH_PX / 2) / 512, (row_y + SWATCH_PX / 2) / 512)


class Atlas:
    """The kit atlas plus new swatches; hands out one UV per colour."""

    def __init__(self, image):
        self.img = image
        self.w, self.h = image.size
        self.px = list(image.pixels)
        self.uv = {}
        self.next = NEW_COL0

    def swatch(self, hexcol):
        if hexcol in self.uv:
            return self.uv[hexcol]
        n = self.next - NEW_COL0
        self.next += 1
        per_row = self.w // SWATCH_PX - NEW_COL0
        col, row_y = NEW_COL0 + n % per_row, NEW_ROW_Y + (n // per_row) * SWATCH_PX
        assert row_y < 64, "out of free swatches"
        r, g, b = hex_rgb(hexcol)
        for y in range(row_y, row_y + SWATCH_PX):
            for x in range(col * SWATCH_PX, (col + 1) * SWATCH_PX):
                i = (y * self.w + x) * 4
                self.px[i : i + 4] = [r, g, b, 1.0]
        self.uv[hexcol] = swatch_uv(col, row_y)
        return self.uv[hexcol]

    def save(self, path):
        img = bpy.data.images.new("zombie_atlas", self.w, self.h, alpha=True)
        img.pixels = self.px
        img.filepath_raw = str(path)
        img.file_format = "PNG"
        img.save()
        return img


def darker(hexcol, like=(0.388 / 0.463, 0.447 / 0.592, 0.247 / 0.318)):
    """The kit's skin_dark is its skin times these factors; keep that relation for a new skin."""
    r, g, b = hex_rgb(hexcol)
    return "#" + "".join(f"{round(min(1, c * f) * 255):02x}" for c, f in zip((r, g, b), like))


def clean(path):
    """The kit rig-sharing recipe; returns (armature, body mesh, clip names)."""
    objs = kitlib.import_glb(path)
    arm = kitlib.armature_of(objs)
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
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    arm.data.pose_position = "POSE"
    meshes = [c for c in arm.children if c.type == "MESH"]
    for c in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        c.select_set(True)
        bpy.context.view_layer.objects.active = c
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    seen = {}
    for a in list(bpy.data.actions):
        name = re.sub(r"^.*\|", "", a.name)
        if name in seen:
            bpy.data.actions.remove(a)
        else:
            seen[name] = a
    for a in seen.values():
        a.name = "tmp_" + a.name
    for name, a in seen.items():
        a.name = name
        a.use_fake_user = True
        for fc in kitlib_fcurves(a):
            if fc.data_path.endswith(".location"):
                for k in fc.keyframe_points:
                    k.co[1] *= factor
                    k.handle_left[1] *= factor
                    k.handle_right[1] *= factor
    fill_missing_rotations(arm, seen)
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    for name, a in sorted(seen.items()):
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, int(a.frame_range[0]), a)
        if hasattr(strip, "action_slot") and a.slots:
            strip.action_slot = a.slots[0]
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)
    # One mesh per zombie: the crowds spike measured the separate eyelid mesh at 30 % of the browser frame at 80.
    bpy.ops.object.select_all(action="DESELECT")
    body = next(c for c in meshes if c.name.startswith("Zombie"))
    for c in meshes:
        c.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = body.data.name = "Zombie_Mesh"
    return arm, body, sorted(seen)


def fill_missing_rotations(arm, clips, donor="Walk"):
    """Give every clip a rotation channel for each bone the donor clip turns, held at the donor's first frame.

    The kit's Idle, Yes and No have no channel at all for the shoulders and upper arms. Blender shows whatever pose
    the last clip left there; a sampled export writes the rest pose (arms straight out, a T-pose) and so does a Godot
    AnimationPlayer. Holding the Walk's arms-forward pose fills them with the zombie's own stance.
    """
    src = clips[donor]
    start = src.frame_range[0]
    donor = {
        (fc.data_path, fc.array_index): fc for fc in kitlib_fcurves(src) if fc.data_path.endswith("rotation_quaternion")
    }
    filled = {}
    for name, a in clips.items():
        if a is src:
            continue
        have = {(fc.data_path, fc.array_index) for fc in kitlib_fcurves(a)}
        for (path, index), fc in donor.items():
            if (path, index) in have:
                continue
            bone = re.search(r'bones\["([^"]+)"\]', path).group(1)
            bag = a.layers[0].strips[0].channelbags[0]
            new = bag.fcurves.new(path, index=index, group_name=bone)
            value = fc.evaluate(start)
            for f in a.frame_range:
                new.keyframe_points.insert(f, value)
            filled.setdefault(name, set()).add(bone)
    print("FILLED", {k: len(v) for k, v in filled.items()})


def kitlib_fcurves(action):
    if hasattr(action, "layers") and action.layers:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    else:
        yield from getattr(action, "fcurves", [])


def group_weights(obj, pattern):
    """Per vertex, the summed weight of the vertex groups (bones) whose name matches the regular expression."""
    rx = re.compile(pattern)
    idx = {g.index for g in obj.vertex_groups if rx.search(g.name)}
    return [sum(e.weight for e in v.groups if e.group in idx) for v in obj.data.vertices]


def swatch_of(u):
    return min(range(11), key=lambda c: abs(u - swatch_uv(c, KIT_ROW_Y)[0]))


def recolour(obj, atlas, palette, top=None):
    """Move faces to new swatches: kit swatches by the palette, then skin faces under a painted top."""
    pal = dict(palette)
    if "skin" in pal and "skin_dark" not in pal:
        pal["skin_dark"] = darker(pal["skin"])
    remap = {SWATCHES[k]: atlas.swatch(v) for k, v in pal.items()}
    if top:
        top_uv, top_w = atlas.swatch(top[0]), group_weights(obj, top[1])
    uv = obj.data.uv_layers.active.data
    for p in obj.data.polygons:
        u = sum(uv[i].uv[0] for i in p.loop_indices) / p.loop_total
        v = sum(uv[i].uv[1] for i in p.loop_indices) / p.loop_total
        if abs(v - swatch_uv(0, KIT_ROW_Y)[1]) > 0.02:
            continue  # already on a new swatch (caps, accessories)
        kit = swatch_of(u)
        new = remap.get(kit)
        on_skin = kit in (SWATCHES["skin"], SWATCHES["skin_dark"])
        if top and on_skin and sum(top_w[obj.data.loops[i].vertex_index] for i in p.loop_indices) / p.loop_total > 0.5:
            new = top_uv
        if new:
            for i in p.loop_indices:
                uv[i].uv = new


def push(obj, groups):
    me = obj.data
    normals = [v.normal.copy() for v in me.vertices]
    for prefixes, amount in groups.items():
        w = group_weights(obj, prefixes)
        for v, n, wi in zip(me.vertices, normals, w):
            if wi > 0:
                v.co += n * amount * min(1.0, wi)


def remove_parts(obj, bones, atlas):
    """Delete faces whose vertices mostly follow the given bones; cap each new hole with the wound colour."""
    w = group_weights(obj, bones)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    open_before = {e for e in bm.edges if e.is_boundary}
    gone = [f for f in bm.faces if sum(w[v.index] for v in f.verts) / len(f.verts) > 0.5]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # Fill only the holes the deletion made: the kit mesh has open edges of its own (sleeves, collar).
    edges = [e for e in bm.edges if e.is_boundary and e not in open_before]
    res = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    uvl = bm.loops.layers.uv.active
    wound = atlas.swatch(WOUND)
    for f in res["faces"]:
        for loop in f.loops:
            loop[uvl].uv = wound
    bm.to_mesh(obj.data)
    bm.free()
    return len(gone), len(res["faces"])


def add_cap(obj, arm, atlas, main, band):
    """A chunky pillbox cap on the head, skinned 100 % to Head, merged into the body mesh."""
    w = group_weights(obj, r"^Head$")
    pts = [obj.matrix_world @ v.co for v, wi in zip(obj.data.vertices, w) if wi > 0.9]
    xs, ys, zs = [p.x for p in pts], [p.y for p in pts], [p.z for p in pts]
    cx, cy, top = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, max(zs)
    width = max(xs) - min(xs)
    r, h = width * 0.33, width * 0.2
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=r * 0.92, depth=h)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(cx, cy, top - h * 0.15))
    bevel_edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle() > 1.0]
    bmesh.ops.bevel(bm, geom=bevel_edges, offset=width * 0.02, segments=1, affect="EDGES")
    uvl = bm.loops.layers.uv.new(obj.data.uv_layers.active.name)  # same name, or the join drops it
    m_uv, b_uv = atlas.swatch(main), atlas.swatch(band)
    zmid = top - h * 0.15
    for f in bm.faces:
        side_face = abs(f.normal.z) < 0.5
        lowband = side_face and f.calc_center_median().z < zmid
        for loop in f.loops:
            loop[uvl].uv = b_uv if lowband else m_uv
    me = bpy.data.meshes.new("cap")
    bm.to_mesh(me)
    bm.free()
    cap = bpy.data.objects.new("cap", me)
    bpy.context.collection.objects.link(cap)
    vg = cap.vertex_groups.new(name="Head")
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    cap.data.materials.append(obj.data.materials[0])
    bpy.ops.object.select_all(action="DESELECT")
    cap.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()


def decimate(obj, target):
    """A decimated copy; the armature modifier is lifted off while the decimate is applied."""
    lod = obj.copy()
    lod.data = obj.data.copy()
    bpy.context.collection.objects.link(lod)
    for m in list(lod.modifiers):
        lod.modifiers.remove(m)
    ratio = min(1.0, target / kitlib.tris(lod))
    mod = lod.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    bpy.ops.object.select_all(action="DESELECT")
    lod.select_set(True)
    bpy.context.view_layer.objects.active = lod
    bpy.ops.object.modifier_apply(modifier=mod.name)
    a = lod.modifiers.new("Armature", "ARMATURE")
    a.object = obj.parent
    return lod


def export(path, arm, meshes, animations):
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=animations,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_reset_pose_bones=True,
        export_optimize_animation_size=False,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zombie", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--only", action="append", help="build only these variants")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    args.out.mkdir(parents=True, exist_ok=True)

    # Pass 1: allocate every variant's swatches so all files share one atlas.
    kitlib.import_glb(args.zombie)
    atlas = Atlas(next(i for i in bpy.data.images))
    atlas.swatch(WOUND)
    for spec in VARIANTS.values():
        pal = dict(spec["palette"])
        if spec.get("top"):
            pal["top"] = spec["top"][0]
        if "skin" in pal:
            pal["skin_dark"] = darker(pal["skin"])
        for v in pal.values():
            atlas.swatch(v)
        for _, main_col, band in spec.get("accessories", []):
            atlas.swatch(main_col)
            atlas.swatch(band)
    atlas_path = args.out / "zombie_atlas.png"
    atlas.save(atlas_path)
    swatches = dict(atlas.uv)

    report = {}
    for name, spec in VARIANTS.items():
        if args.only and name not in args.only:
            continue
        arm, body, clips = clean(args.zombie)
        atlas = Atlas(next(i for i in bpy.data.images if i.name.startswith("Zombie_Atlas")))
        atlas.uv, atlas.next = dict(swatches), NEW_COL0 + len(swatches)
        img = bpy.data.images.load(str(atlas_path))
        for node in body.data.materials[0].node_tree.nodes:
            if node.type == "TEX_IMAGE":
                node.image = img
        info = {"kit_tris": kitlib.tris(body)}
        if spec.get("remove"):
            info["removed_faces"], info["caps"] = remove_parts(body, spec["remove"], atlas)
        if spec.get("push"):
            push(body, spec["push"])
        for acc, main_col, band in spec.get("accessories", []):
            if acc == "cap":
                add_cap(body, arm, atlas, main_col, band)
        recolour(body, atlas, spec["palette"], spec.get("top"))
        arm.scale = (spec["height"],) * 3
        body.name = body.data.name = "Zombie_Full"
        lod0 = decimate(body, TARGET_TRIS[0])
        lod0.name = lod0.data.name = "Zombie_Mesh"
        lod1 = decimate(body, TARGET_TRIS[1])
        lod1.name = lod1.data.name = "Zombie_Far"
        info.update(full_tris=kitlib.tris(body), tris=kitlib.tris(lod0), far_tris=kitlib.tris(lod1))
        info.update(height=spec["height"], bones=len(arm.data.bones), clips=clips)
        export(args.out / f"zombie_{name}.glb", arm, [lod0, lod1], True)
        report[name] = info
        print("ZOMBIE", name, {k: v for k, v in info.items() if k != "clips"})
    (args.out / "zombies.json").write_text(json.dumps(report, indent=1))


if __name__ == "__main__":  # build_boss.py imports this file for its helpers
    main()
