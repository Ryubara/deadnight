"""Build Deadnight's boss zombie, the Projectionist, from the Quaternius Zombie (CC0): model, two LODs, five clips.

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/build_boss.py -- \
        --zombie <workspace>/refs/polypizza/VlXjG0N8Eg/model.glb --out game/assets/characters/zombie_boss

Writes `zombie_boss.glb` (the kit zombie's 50-bone skeleton, the kit's 16 clips plus the boss's five, the meshes
`Zombie_Mesh` and `Zombie_Far`, and a `WeakSpot` node on the `Torso` bone), `clips.json` (the boss clips: length, loop
and the event frames the behaviour code times its hits on) and `boss.json` (triangle counts). The design is in
docs/design/zombies.md (Boss).

It is a variant on the shared rig, made the way build_zombies.py makes the brute (it imports that file's helpers):
the kit rig-sharing clean-up, a bigger build pushed along the normals, a painted coat, a taller armature scale. On
top: two accessories skinned 100 % to `Torso` and joined into the body (the arc lamp burning in its chest, the weak
spot, and a film reel on its back), and one emissive swatch, so the lamp lens glows at night.

The five clips are authored here from the kit zombie's own poses (Idle, Walk, Death), never from a blank rig. Every
clip keys every bone (rotation and location), so no bone falls back to the rest pose on export, and each quaternion
key keeps the sign of the one before (soldier_clips.write does both). Offsets are local Euler degrees in each bone's
own axes; the axes were read off a probe sheet (`--probe` adds a `Probe` clip that turns one bone per frame).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_zombies as bz
import kitlib
import soldier_clips as sc

HEIGHT = 1.45  # armature scale over the walker: 1.97 m at kit scale, 2.56 m at game scale (x1.3)
PALETTE = {"skin": "#6f7f5c", "trousers": "#2b2f36", "belt": "#252525"}
COAT = ("#bdb39a", bz.TOP_LONG)  # the projection booth's dust coat, pale so it catches any light
LAMP_BODY, LAMP_RIM, LENS = "#414141", "#818491", "#ffd27a"
REEL, REEL_HUB, FILM = "#818491", "#252525", "#3a2c22"
LAMP_HEIGHT = 0.5  # of the way from the Abdomen bone to the Neck: the belly; the chin hides the upper chest
GLOW = {LENS: 6.0}  # emissive swatches and their strength (glTF KHR_materials_emissive_strength)
PUSH = {
    r"^(Torso|Neck|Shoulder\.[LR])$": 0.075,
    r"^(UpperArm|LowerArm)\.[LR]$": 0.06,
    r"^(Abdomen|Hips)$": 0.06,
    r"^(UpperLeg|LowerLeg)\.[LR]$": 0.025,
}
TARGET_TRIS = (8000, 3000)  # boss budget: two walkers' worth (docs/design/zombies.md)
CLIP_NAMES = ("Boss_Walk", "Boss_Attack", "Boss_Roar", "Boss_Stagger", "Boss_Death")


# ---- Model ------------------------------------------------------------------------------------------------------
def torso_frame(body, arm, height=0.5):
    """Chest point (front surface), back point and shoulder width, from the bones and the body's surface.

    The point is `height` of the way from the Abdomen bone's head to the Neck's; the surface is the body vertex
    nearest the midline at that height on the front (the zombie faces -Y) and on the back.
    """
    mw = arm.matrix_world
    t = mw @ arm.data.bones["Abdomen"].head_local
    n = mw @ arm.data.bones["Neck"].head_local
    zc = t.z + height * (n.z - t.z)
    width = abs((mw @ arm.data.bones["UpperArm.L"].head_local).x - (mw @ arm.data.bones["UpperArm.R"].head_local).x)
    # The trunk only: not the jaw and tongue hanging over the chest, nor the arms and hands in front of it.
    w = bz.group_weights(body, r"^(Head|Neck|Tongue\d|Eyelid|UpperArm|LowerArm|Index|Middle|Pinky|Thumb)")
    pts = [body.matrix_world @ v.co for v, wi in zip(body.data.vertices, w) if wi < 0.5]
    band = [p for p in pts if abs(p.x) < 0.3 * width and abs(p.z - zc) < 0.06]
    front = min(p.y for p in band)
    back = max(p.y for p in band)
    return Vector((0, front, zc)), Vector((0, back, zc)), width


def cylinder(bm, radius, depth, segments, centre, axis_y=True):
    """A capped cylinder along Y (or Z) at `centre`; returns its faces."""
    before = set(bm.faces)
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=depth)
    verts = res["verts"]
    if axis_y:
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, verts=verts, vec=centre)
    faces = [f for f in bm.faces if f not in before]
    edges = {e for f in faces for e in f.edges if len(e.link_faces) == 2 and e.calc_face_angle() > 1.0}
    bmesh.ops.bevel(bm, geom=list(edges), offset=radius * 0.06, segments=1, affect="EDGES")
    return [f for f in bm.faces if f not in before]


def add_accessories(body, arm, atlas):
    """The arc lamp in the chest (housing, rim, glowing lens) and the film reel on the back, skinned to Torso."""
    front, back, width = torso_frame(body, arm, LAMP_HEIGHT)
    print("LAMP", tuple(round(c, 3) for c in front), "back", round(back.y, 3), "shoulders", round(width, 3))
    uvname = body.data.uv_layers.active.name
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new(uvname)  # same name as the body's, or the join drops it

    def paint(faces, hexcol, test=None):
        uv = atlas.swatch(hexcol)
        for f in faces:
            if test is None or test(f):
                for loop in f.loops:
                    loop[uvl].uv = uv

    # Arc lamp: a squat housing sunk into the chest, a lighter rim, the lens proud of it, facing -Y.
    r = width * 0.4
    housing = cylinder(bm, r, r * 0.9, 12, front + Vector((0, r * 0.15, 0)))
    paint(housing, LAMP_BODY)
    paint(housing, LAMP_RIM, lambda f: f.normal.y < -0.9)
    lens = cylinder(bm, r * 0.72, r * 0.5, 12, front + Vector((0, -r * 0.42, 0)))
    paint(lens, LAMP_RIM)
    paint(lens, LENS, lambda f: f.normal.y < -0.9)
    # Film reel on the back, standing upright like a shield: flange, a coil of film, and the hub.
    rr = width * 0.95
    centre = back + Vector((0, rr * 0.12, rr * 0.55))
    flange = cylinder(bm, rr, rr * 0.08, 16, centre)
    paint(flange, REEL)
    coil = cylinder(bm, rr * 0.82, rr * 0.2, 16, centre + Vector((0, rr * 0.02, 0)))
    paint(coil, FILM)
    hub = cylinder(bm, rr * 0.22, rr * 0.34, 8, centre + Vector((0, rr * 0.06, 0)))
    paint(hub, REEL_HUB)
    me = bpy.data.meshes.new("accessories")
    bm.to_mesh(me)
    bm.free()
    acc = bpy.data.objects.new("accessories", me)
    bpy.context.collection.objects.link(acc)
    vg = acc.vertex_groups.new(name="Torso")
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    acc.data.materials.append(body.data.materials[0])
    tris = kitlib.tris(acc)
    bpy.ops.object.select_all(action="DESELECT")
    acc.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    return front + Vector((0, -r * 0.7, 0)), tris


def emission_map(atlas, path):
    """Black everywhere but the glowing swatches: the lens is the only lit thing on the body."""
    w, h = atlas.w, atlas.h
    px = [0.0, 0.0, 0.0, 1.0] * (w * h)
    for hexcol in GLOW:
        u, v = atlas.swatch(hexcol)
        cx, cy = round(u * w), round(v * h)
        r, g, b = bz.hex_rgb(hexcol)
        for y in range(cy - bz.SWATCH_PX // 2, cy + bz.SWATCH_PX // 2):
            for x in range(cx - bz.SWATCH_PX // 2, cx + bz.SWATCH_PX // 2):
                i = (y * w + x) * 4
                px[i : i + 4] = [r, g, b, 1.0]
    img = bpy.data.images.new("zombie_boss_emission", w, h, alpha=False)
    img.pixels = px
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    return img


def set_material(body, atlas_img, glow_img):
    mat = body.data.materials[0]
    mat.name = "Boss_Atlas"
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    base = next(n for n in nodes if n.type == "TEX_IMAGE")
    base.image = atlas_img
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = glow_img
    tex.interpolation = "Closest"
    links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = max(GLOW.values())
    nodes.active = base  # Workbench's texture colour shows the active image node


def add_weak_spot(arm, point):
    """An empty on the Torso bone at the lens: the hitbox and the light hang from it in Godot."""
    e = bpy.data.objects.new("WeakSpot", None)
    e.empty_display_size = 0.05
    bpy.context.collection.objects.link(e)
    e.parent = arm
    e.parent_type = "BONE"
    e.parent_bone = "Torso"
    bpy.context.view_layer.update()
    e.matrix_world = Matrix.Translation(point)
    return e


# ---- Clips ------------------------------------------------------------------------------------------------------
def filled(arm, pose):
    """Every bone: the pose's value, or the rest pose for bones the kit clip does not key (as the kit clips export)."""
    out = {b.name: {"rot": Euler((0, 0, 0)).to_quaternion(), "loc": Vector()} for b in arm.pose.bones}
    for b, v in pose.items():
        out[b] = {"rot": v["rot"].copy(), "loc": v["loc"].copy()}
    return out


def off(pose, **bones):
    return sc.offset(pose, **bones)


def arms(raise_=0, spread=0, elbow=0):
    """Both upper arms raised (up from the zombie's arms-forward pose, hands closing in) and spread (up and out to
    the sides), and both elbows bent, in degrees. Measured by moving each axis 50 degrees and reading where the hand
    went: X swings the hand up and in across the chest on both arms, Z up and out on the left and -Z on the right
    (mirrored), LowerArm X bends the elbow. Straight overhead is X and Z together (raise and spread equal)."""
    return {"UpperArm_L": (raise_, 0, spread), "UpperArm_R": (raise_, 0, -spread),
            "LowerArm_L": (elbow, 0, 0), "LowerArm_R": (elbow, 0, 0)}  # fmt: skip


def build_clips(arm, probe=False):
    sc.CLIPS.clear()
    acts = {a.name: a for a in bpy.data.actions}
    every = [b.name for b in arm.pose.bones]
    idle = filled(arm, sc.sample(acts["Idle"], 0))

    def write(name, keys, loop, events=None):
        sc.write(arm, name, keys, every, "full", loop, events=events)

    # Heavy walk: the kit Walk stretched from 32 to 40 frames, hunched, the head held up to look ahead, the arms
    # hanging lower and the chest rolling over the planted foot.
    walk = acts["Walk"]
    n = 40
    keys = []
    for i in range(n + 1):
        t = i * walk.frame_range[1] / n
        roll = 7 * math.sin(2 * math.pi * i / n)
        p = filled(arm, sc.sample(walk, t))
        p = off(p, Abdomen=(10, 0, 0), Torso=(6, roll, 0), Neck=(-8, 0, 0), Head=(-6, -roll * 0.5, 0),
                **arms(-18))  # fmt: skip
        keys.append((i, p))
    write("Boss_Walk", keys, True)

    # Attack: a two-handed overhead smash. A long, readable wind-up (arms climb overhead, the body leans back and
    # holds) so players can see it coming and step out, then a fast slam and a slow recovery.
    gather = off(idle, Abdomen=(8, 0, 0), Torso=(10, 0, 0), **arms(-20))
    raised = off(idle, Abdomen=(-10, 0, 0), Torso=(-18, 0, 0), Neck=(-10, 0, 0), Head=(-14, 0, 0),
                 **arms(55, 55, 15))  # fmt: skip
    peak = off(raised, Torso=(-4, 0, 0), **arms(8))
    slam = off(idle, Abdomen=(18, 0, 0), Torso=(34, 0, 0), Neck=(-12, 0, 0), Head=(4, 0, 0),
               **arms(-5))  # fmt: skip
    follow = off(slam, Torso=(6, 0, 0), Abdomen=(4, 0, 0))
    keys = [(0, idle), (8, gather), (22, raised), (28, peak), (32, slam), (35, follow), (44, follow), (60, idle)]
    write("Boss_Attack", keys, False, {"windup": 0, "telegraph": 22, "hit": 32, "recover": 44, "end": 60})

    # Entrance roar: gather, rear up with the chest out and the arms flung wide, shake, settle.
    crouch = off(idle, Abdomen=(14, 0, 0), Torso=(14, 0, 0), Neck=(6, 0, 0), **arms(-30))
    roar = off(idle, Abdomen=(-12, 0, 0), Torso=(-20, 0, 0), Neck=(-16, 0, 0), Head=(-22, 0, 0),
               **arms(25, 55, 20))  # fmt: skip
    keys = [(0, idle), (12, crouch), (22, roar)]
    for k, f in enumerate(range(25, 50, 3)):
        s = 1 if k % 2 == 0 else -1
        keys.append((f, off(roar, Head=(0, 0, 6 * s), Torso=(0, 2 * s, 0))))
    keys += [(52, roar), (66, idle)]
    write("Boss_Roar", keys, False, {"roar": 22, "end": 66})

    # Weak-spot stagger: thrown back by the hit on the lamp, then folded over it, hands at the chest, and back.
    thrown = off(idle, Abdomen=(-14, 0, 0), Torso=(-24, 0, 0), Neck=(-10, 0, 0), Head=(-18, 0, 0),
                 **arms(35, 35))  # fmt: skip
    fold = off(idle, Abdomen=(16, 0, 0), Torso=(26, 0, 0), Neck=(-6, 0, 0), Head=(8, 0, 0),
               **arms(-20, -10, 70))  # fmt: skip
    keys = [(0, idle), (4, thrown), (12, fold), (24, fold), (34, idle)]
    write("Boss_Stagger", keys, False, {"hit": 0, "end": 34})

    # Death: the stagger's recoil and fold, then the kit Death slowed 2.5x: a heavy fall that ends on its back.
    death = acts["Death"]
    keys = [(0, idle), (5, thrown), (14, fold)]
    d0, skip = 20, 5  # the kit Death's first frames stand back up straight: start where it already falls
    nd = int(death.frame_range[1])
    for i in range(skip, nd + 1):
        keys.append((d0 + round((i - skip) * 2.5), filled(arm, sc.sample(death, i))))
    write("Boss_Death", keys, False, {"fall": d0, "end": d0 + round((nd - skip) * 2.5)})

    if probe:  # one bone turned per frame, for reading the axes off a sheet
        keys, f = [(0, idle)], 1
        for bone in ("Torso", "UpperArm_L", "UpperArm_R", "LowerArm_L", "LowerArm_R"):
            for ax in range(3):
                deg = [0, 0, 0]
                deg[ax] = 50
                keys.append((f, off(idle, **{bone: tuple(deg)})))
                f += 1
        write("Probe", keys, False)
        sc.CLIPS.pop("Probe")  # built and exported, never listed in clips.json
    return [*sc.CLIPS, *(["Probe"] if probe else [])]


def add_tracks(arm, names):
    ad = arm.animation_data
    ad.action = None
    for name in names:
        a = bpy.data.actions[name]
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 0, a)
        if hasattr(strip, "action_slot") and a.slots:
            strip.action_slot = a.slots[0]
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zombie", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--textures", type=Path, help="where to save the atlas PNGs (default: --out); the .glb embeds them")
    ap.add_argument("--probe", action="store_true", help="add a Probe clip (one bone turned per frame)")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    args.out.mkdir(parents=True, exist_ok=True)
    tex = args.textures or args.out
    tex.mkdir(parents=True, exist_ok=True)

    arm, body, kit_clips = bz.clean(args.zombie)
    atlas = bz.Atlas(next(i for i in bpy.data.images if i.name.startswith("Zombie_Atlas")))
    for col in (*PALETTE.values(), bz.darker(PALETTE["skin"]), COAT[0], LAMP_BODY, LAMP_RIM, LENS, REEL, REEL_HUB,
                FILM):  # fmt: skip
        atlas.swatch(col)
    info = {"kit_tris": kitlib.tris(body)}
    bz.push(body, PUSH)
    lens_point, info["accessory_tris"] = add_accessories(body, arm, atlas)
    bz.recolour(body, atlas, PALETTE, COAT)
    atlas_img = atlas.save(tex / "zombie_boss_atlas.png")
    glow_img = emission_map(atlas, tex / "zombie_boss_emission.png")
    set_material(body, atlas_img, glow_img)
    weak = add_weak_spot(arm, lens_point)

    new = build_clips(arm, args.probe)
    add_tracks(arm, new)
    arm.scale = (HEIGHT,) * 3
    body.name = body.data.name = "Zombie_Full"
    lod0 = bz.decimate(body, TARGET_TRIS[0])
    lod0.name = lod0.data.name = "Zombie_Mesh"
    lod1 = bz.decimate(body, TARGET_TRIS[1])
    lod1.name = lod1.data.name = "Zombie_Far"
    info.update(full_tris=kitlib.tris(body), tris=kitlib.tris(lod0), far_tris=kitlib.tris(lod1), height=HEIGHT)
    info.update(bones=len(arm.data.bones), kit_clips=kit_clips, boss_clips=new)
    weak.select_set(True)
    bz.export(args.out / "zombie_boss.glb", arm, [lod0, lod1, weak], True)
    spec = {
        "fps": sc.FPS,
        "height": HEIGHT,
        "weak_spot": {"node": "WeakSpot", "bone": "Torso"},
        "clips": {n: {k: c[k] for k in ("loop", "frames", "seconds", "events")} for n, c in sc.CLIPS.items()},
    }
    (args.out / "clips.json").write_text(json.dumps(spec, indent=1) + "\n", newline="\n")
    (args.out / "boss.json").write_text(json.dumps(info, indent=1) + "\n", newline="\n")
    print("BOSS", {k: v for k, v in info.items() if "clips" not in k}, new)


main()
