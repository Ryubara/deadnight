"""Deadnight title art: five compositions made for the title, from the game's own models.

Run with the pinned Blender, headless only (never a window on the person's desktop):

    blender -b --factory-startup -P title_shots.py -- --shot feature --aspect land --width 3840 --samples 160 \
        --out <png> [--blend <blend>]

Shots: feature, headlights, marquee, headliner, backtoback. Aspects: `land` (16:9) and `port` (2:3, for the
vertical and library capsules), the same scene with the camera reframed. Every shot keeps a clean dark area for the
title (the wordmark is laid over afterwards by `post.py`, so one render serves every target and the library hero
gets the same art with no text).

`--frames N --video-dir <dir>` renders an N-frame camera push (and walking dead) for the Discord video preview.
"""

import argparse
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import functools
import operator

import bpy
import keyart as K
import lotset as S
from mathutils import Matrix, Vector

# The Soldier: the kit Soldier's look on the player's parts (helmet, field vest), olive.
SOLDIER = {
    "head": "stubble",
    "hair": "crew",
    "headwear": "helmet",
    "torso": "vest",
    "legs": "trousers",
    "feet": "boots",
    "eyewear": "none",
    "neck": "none",
    "arm": "none",
}
SOLDIER_COL = {"skin": 2, "hair": 1, "primary": 4, "secondary": 3, "accent": 12}
# A second player: the Greaser preset (the first default look).
GREASER = {
    "head": "plain",
    "hair": "pompadour",
    "headwear": "none",
    "torso": "jacket",
    "legs": "cuffed",
    "feet": "boots",
    "eyewear": "none",
    "neck": "none",
    "arm": "none",
}
GREASER_COL = {"skin": 1, "hair": 0, "primary": 0, "secondary": 9, "accent": 0}

SODIUM = "#ffb866"
KINDS = ["walker", "greaser", "usher", "farmhand", "runner", "brute"]

# Animated dead for the video: (armature, clip, start frame, ground speed m/s, heading unit vector, start location).
WALKERS = []


def yaw_towards(src, dst):
    """The character yaw (0 faces -Y) that faces from src to dst on the ground."""
    d = Vector((dst[0] - src[0], dst[1] - src[1]))
    return math.degrees(math.atan2(d.x, -d.y))


def soldier(
    look=SOLDIER,
    col=SOLDIER_COL,
    at=(0, 0, 0),
    facing=0.0,
    clip="Aim_Shotgun",
    frame=0,
    cls="Shotgun",
    aim_yaw=0.0,
    aim_pitch=0.0,
    tag="p1",
):
    arm, _meshes = K.load_soldier(look, col, clip=clip, frame=frame, tag=tag, location=at, yaw_deg=facing)
    gun = None
    if cls:
        gun, _sup, _muzzle = K.shoulder_weapon(arm, cls, facing, aim_yaw_deg=aim_yaw, aim_pitch_deg=aim_pitch, tag=tag)
    return arm, K.char_objects(arm, [gun] if gun else [])


def zombie(variant, at, facing, clip="Walk", frame=0, scale=K.ZOMBIE_SCALE, walk=None, reach=99.0):
    arm = K.load_zombie(
        variant, clip, frame, location=at, yaw_deg=facing, scale=scale, tag=f"{variant}_{at[0]:.1f}_{at[1]:.1f}"
    )[0]
    if walk is not None:
        a = math.radians(facing)
        WALKERS.append(
            (arm, clip, frame, walk, Vector((math.sin(a), -math.cos(a), 0)), Vector(at), facing, scale, reach)
        )
    return arm


def boss(at, facing, clip="Boss_Roar", frame=30):
    before = set(bpy.data.actions)
    objs = K.import_gltf(K.ASSETS / "characters/zombie_boss/zombie_boss.glb")
    arm = next(o for o in objs if o.type == "ARMATURE")
    arm.name = "Headliner"
    K.take_actions(arm, before)
    for o in [o for o in objs if o.type == "MESH" and "Far" in o.name]:
        bpy.data.objects.remove(o)
    K.set_pose(arm, clip, frame)
    K.place(arm, at, facing, K.ZOMBIE_SCALE)
    return arm


def horde(
    n,
    centre,
    spread,
    target,
    seed,
    clips=("Walk", "Walk", "Idle_Attack"),
    walk=True,
    avoid=(),
    walk_scale=1.0,
    stop=1.8,
):
    rnd = random.Random(seed)
    arms = []
    placed = []
    tries = 0
    while len(arms) < n and tries < n * 30:
        tries += 1
        x = centre[0] + rnd.uniform(-spread[0], spread[0])
        y = centre[1] + rnd.uniform(-spread[1], spread[1])
        if any((Vector((x, y)) - Vector(p)).length < 1.3 for p in placed):
            continue
        if any((Vector((x, y)) - Vector(c)).length < r for c, r in avoid):
            continue
        kind = KINDS[len(arms) % len(KINDS)]
        clip = "Run_Arms" if kind == "runner" else clips[len(arms) % len(clips)]
        face = yaw_towards((x, y), target) + rnd.uniform(-14, 14)
        # Video speeds: the walk at its ground speed, runners held back, and each stops `stop` short of the target
        # so none reaches a player (or hides the subject) in the clip.
        speed = {"Walk": 0.8, "Run_Arms": 1.4}.get(clip, 0.0) * walk_scale if walk else None
        reach = max((Vector((x, y)) - Vector(target[:2])).length - stop, 0.0)
        arms.append(zombie(kind, (x, y, 0), face, clip, rnd.uniform(0, 20), walk=speed, reach=reach))
        placed.append((x, y))
    return arms


def lot_rows(rows, cols, origin, row_step, col_step, face_yaw, skip=lambda x, y: False, seed=0, speakers=True):
    """Parked cars in rows facing the screen, a speaker post between every second pair."""
    rnd = random.Random(seed)
    paints = ["blue", "cream", "red", "green", "yellow"]
    ox, oy = origin
    for r in range(rows):
        for c in range(cols):
            x = ox + row_step[0] * r + col_step[0] * c + rnd.uniform(-0.4, 0.4)
            y = oy + row_step[1] * r + col_step[1] * c + rnd.uniform(-0.4, 0.4)
            if skip(x, y) or rnd.random() < 0.18:
                continue
            K.load_prop(f"props/car_{rnd.choice(paints)}.gltf", (x, y, 0), face_yaw + rnd.uniform(-6, 6), 1.0)
            if speakers and c % 2 == 0:
                K.load_prop(
                    "drivein/speaker_post.gltf", (x + col_step[0] * 0.5, y + col_step[1] * 0.5, 0), face_yaw, 1.0
                )


def projection_booth(at, screen, beam_watts, angle=7.0):
    """The projection booth: a block building with a flat roof, a lit port toward the screen, and the beam."""
    to = (Vector((screen.x, screen.y, 0)) - Vector((at.x, at.y, 0))).normalized()
    yaw = math.atan2(to.y, to.x)
    S.box("Booth", (5.0, 5.0, 4.2), (at.x, at.y, 2.1), "#9a9ca6", rot=(0, 0, yaw), bevel=0.08)
    S.box("BoothRoof", (5.6, 5.6, 0.3), (at.x, at.y, 4.35), "#5f5f5f", rot=(0, 0, yaw), bevel=0.05)
    port = Vector((at.x, at.y, 3.2)) + to * 2.52
    m = S.mat_cached(("port",), lambda: K.emissive_material("Port", K.hexrgb("#fff1d6"), 25.0))
    bpy.ops.mesh.primitive_plane_add(size=1, location=port, rotation=(math.radians(90), 0, yaw + math.pi / 2))
    p = bpy.context.active_object
    p.scale = (0.7, 0.45, 1)
    p.data.materials.append(m)
    return K.spot_light(
        "Projector",
        tuple(port + to * 0.1),
        (screen.x, screen.y, screen.z or 10),
        K.hexrgb("#e6eeff"),
        beam_watts,
        angle_deg=angle,
        blend=0.3,
        radius=0.2,
    )


def glow_swatch(roots, hex_col, strength, tol=0.06):
    """Light the faces of a palette-textured prop whose swatch is `hex_col` (the marquee's Amber bulbs and arrow):
    emission = the texture colour where it is near that swatch."""
    target = K.hexrgb(hex_col)
    seen = set()
    for r in roots:
        for o in [r] + list(r.children_recursive):
            if o.type != "MESH":
                continue
            for slot in o.material_slots:
                m = slot.material
                if not m or m.name in seen:
                    continue
                m = m.copy()
                slot.material = m
                seen.add(m.name)
                nt = m.node_tree
                b = nt.nodes.get("Principled BSDF")
                tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None)
                if not b or not tex:
                    continue
                dist = nt.nodes.new("ShaderNodeVectorMath")
                dist.operation = "DISTANCE"
                dist.inputs[1].default_value = target
                mr = nt.nodes.new("ShaderNodeMapRange")
                mr.inputs["From Min"].default_value = tol * 0.5
                mr.inputs["From Max"].default_value = tol
                mr.inputs["To Min"].default_value = strength
                mr.inputs["To Max"].default_value = 0.0
                nt.links.new(tex.outputs["Color"], dist.inputs[0])
                nt.links.new(dist.outputs["Value"], mr.inputs["Value"])
                nt.links.new(tex.outputs["Color"], b.inputs["Emission Color"])
                nt.links.new(mr.outputs["Result"], b.inputs["Emission Strength"])


def car(paint, at, yaw):
    roots = K.load_prop(f"props/car_{paint}.gltf", at, yaw, 1.0)
    mn, mx = K.world_bbox([o for r in roots for o in [r] + list(r.children_recursive) if o.type == "MESH"])
    return roots, mn, mx


def headlights(at, yaw_deg, watts, length=4.4, half_track=0.62, z=0.62, emit=40.0):
    """Two headlamps at the front of a car (front is +Y at yaw 0, the cars' facing in the game's rows): spots
    down the road and glowing lenses."""
    rot = Matrix.Rotation(math.radians(yaw_deg), 3, "Z")
    fwd = rot @ Vector((0, 1, 0))
    side = rot @ Vector((1, 0, 0))
    m = S.mat_cached(("headlamp",), lambda: K.emissive_material("Headlamp", K.hexrgb("#fff2d8"), emit))
    lights = []
    for s in (-1, 1):
        p = Vector(at) + fwd * (length / 2 + 0.02) + side * (s * half_track) + Vector((0, 0, z))
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, location=p, segments=12, ring_count=8)
        o = bpy.context.active_object
        o.scale = (1, 0.35, 1)
        o.rotation_euler = (0, 0, math.radians(yaw_deg))
        o.data.materials.append(m)
        o.visible_shadow = False
        lights.append(
            K.spot_light(
                f"Headlamp{s}",
                tuple(p + fwd * 0.15),
                tuple(p + fwd * 20 + Vector((0, 0, -0.6))),
                K.hexrgb("#ffe8c4"),
                watts,
                angle_deg=34,
                blend=0.5,
                radius=0.08,
            )
        )
    return lights


def night(wet=0.7, horizon="#18244e"):
    K.ground(size=600, color="#34363f", wet=wet)
    S.stars_world(top="#05081a", horizon=horizon, strength=1.0)
    S.moon_light(elev_deg=30, az_deg=20, strength=0.1)


def key_rim(objs, at, key_off, rim_off, key=120.0, rim=500.0, key_col="#ffd2a0", rim_col="#a9c4ff", tag=""):
    at = Vector(at)
    k = K.area_light(
        f"Key{tag}", tuple(at + Vector(key_off)), tuple(at + Vector((0, 0, 1.2))), K.hexrgb(key_col), key, size=1.5
    )
    K.link_light(k, objs)
    r = K.area_light(
        f"Rim{tag}", tuple(at + Vector(rim_off)), tuple(at + Vector((0, 0, 1.2))), K.hexrgb(rim_col), rim, size=2.0
    )
    K.link_light(r, objs)


def dead_rim(arms, at, target, watts, size=12.0, size_y=4.0, col="#b5ccff"):
    zr = K.area_light("ZRim", at, target, K.hexrgb(col), watts, size=size, size_y=size_y)
    K.link_light(zr, functools.reduce(operator.iadd, (K.char_objects(a) for a in arms), []))
    return zr


def cam_for(args, land, port):
    """Camera (location, target point, frame x, frame y, lens) for the aspect. The portrait frame is the
    landscape's camera with a longer lens (Blender fits the 36 mm sensor to the long side, so the same lens in a
    tall frame shows far more sky) and the subject a little lower, leaving the top for the title."""
    port_fx = land[5] if len(land) > 5 else 0.5
    if args.aspect == "land":
        return land[:5]
    loc, tgt, _fx, fy, lens = land[:5]
    return loc, tgt, port_fx, min(fy + args.port_drop, 0.8), lens * args.port_lens


# ---------------------------------------------------------------- A: feature presentation


def feature(args):
    """Tonight's feature: from among the parked cars, the two players hold an aisle against the dead pouring
    down it from under the glowing screen; the screen and the sky above it are where the title goes."""
    night()
    scr = Vector((0.0, 36.0, 0))
    S.drive_in_screen(tuple(scr), 0.0, strength=args.screen, seed=1.3)
    _roots, _mn, mx = car("cream", (-2.2, -2.5, 0), 4.0)
    roof = mx.z
    p1 = Vector((-2.2, -2.7, roof - 0.05))
    _a1, o1 = soldier(at=tuple(p1), facing=yaw_towards(p1, (1.0, 14.0)), aim_pitch=-6, tag="p1")
    p2 = Vector((1.4, -1.2, 0))
    _a2, o2 = soldier(
        GREASER, GREASER_COL, at=tuple(p2), facing=yaw_towards(p2, (4.5, 12.0)), cls="Rifle", aim_pitch=2, tag="p2"
    )
    arms = horde(args.horde, (0.5, 11.0), (5.0, 6.0), (0.0, -2.0), seed=21)
    lot_rows(5, 7, (-30, 2), (0, 8), (6.5, 0), 0.0, skip=lambda x, y: -7 < x < 7, seed=31)
    for x, y in ((-10, 6), (10, 9), (-14, 26), (15, 30)):
        S.lamp_post((x, y, 0), yaw_deg=90 if x < 0 else -90, watts=args.lamp, name=f"Lamp{x}_{y}")
    S.flare((0.2, 3.0, 0), strength=args.flare)
    dead_rim(arms, (0, 26, 7), (0, 10, 0.8), args.zrim, size=20, size_y=6)
    key_rim(o1, p1, (-2.0, -3.0, 2.5), (1.0, 4.0, 2.6), key=args.key, rim=args.rim, tag="1")
    key_rim(o2, p2, (2.0, -3.0, 2.2), (-1.0, 4.0, 2.6), key=args.key, rim=args.rim, tag="2")
    K.fog_box((0, 30, 12), (200, 140, 24), density=args.fog, color="#8fa3d6", ground_boost=2.5, ground_height=2.5)
    projection_booth(Vector((-9.0, -40.0, 0)), Vector((0, 36, 10)), args.beam)
    loc, tgt, fx, fy, lens = cam_for(
        args,
        ((0.6, -7.8, 0.7), (-0.6, -1.0, 2.0), 0.46, 0.66, 24, 0.62),
        ((0.4, -8.8, 0.7), (-0.4, -1.0, 2.0), 0.5, 0.7, 20),
    )
    c = K.camera(loc, tgt, lens=lens)
    K.frame_camera(c, Vector(tgt), fx, fy)
    return c


# ---------------------------------------------------------------- B: headlights


def headlights_shot(args):
    """Into the headlights: from behind the dead, a parked car's lamps glare through the fog and cut the dead into
    silhouettes; the Soldier fires from the roof and the Greaser from the wing, facing us."""
    night(wet=0.9)
    S.drive_in_screen((18.0, -40.0, 0), 200.0, strength=args.screen * 0.7, seed=2.4)
    yaw = 180.0  # the car's front (+Y at yaw 0) points at the camera (-Y)
    car_at = Vector((0.0, 6.0, 0))
    roots, _mn, mx = car("red", tuple(car_at), yaw + 12)
    headlights(car_at, yaw + 12, args.beam)
    p1 = car_at + Vector((0.3, 0.6, mx.z - 0.04))
    _a1, o1 = soldier(at=tuple(p1), facing=yaw_towards(p1, (-1.0, -2.0)), aim_pitch=-12, tag="p1")
    p2 = car_at + Vector((-2.9, -1.6, 0))
    _a2, o2 = soldier(
        GREASER, GREASER_COL, at=tuple(p2), facing=yaw_towards(p2, (-1.0, -3.0)), cls="Rifle", aim_pitch=0, tag="p2"
    )
    arms = horde(
        min(args.horde, 9),
        (0.4, 1.6),
        (4.4, 1.2),
        tuple(car_at),
        seed=7,
        clips=("Walk", "Idle_Attack", "Walk"),
        avoid=(((0.3, 1.6), 1.6), ((-2.9, 2.6), 1.4)),
        walk_scale=0.4,
        stop=3.4,
    )
    lot_rows(3, 9, (-30, 14), (0, 9), (6.5, 0), 180.0, seed=41, skip=lambda x, y: -5 < x < 5 and y < 18)
    for x, y in ((-9.0, 11.0), (10.0, 12.0)):
        S.lamp_post((x, y, 0), yaw_deg=90 if x < 0 else -90, watts=args.lamp, name=f"Lamp{x}_{y}")
    both = o1 + o2
    key_rim(both, car_at, (-2.5, -8.0, 3.0), (1.5, 4.0, 3.5), key=args.key, rim=args.rim * 1.5, key_col="#ffc48a")
    body = [o for r in roots for o in [r] + list(r.children_recursive)]
    kc = K.area_light(
        "CarKey",
        tuple(car_at + Vector((-3.0, -6.0, 4.0))),
        tuple(car_at),
        K.hexrgb("#ffb866"),
        args.key * 2.5,
        size=3.0,
    )
    K.link_light(kc, body)
    dead_rim(arms, (0.0, 8.0, 3.0), (0.2, 2.0, 1.0), args.zrim * 0.6, size=6, size_y=3, col="#ffe8c4")
    K.fog_box(
        (0, 10, 10), (120, 120, 20), density=args.fog * 0.45, color="#8fa3d6", ground_boost=2.0, ground_height=2.0
    )
    aim = car_at + Vector((-0.4, -0.5, 1.7))
    loc, tgt, fx, fy, lens = cam_for(
        args, ((0.5, -4.6, 1.0), tuple(aim), 0.5, 0.58, 24), ((0.5, -5.6, 1.0), tuple(aim), 0.5, 0.62, 22)
    )
    c = K.camera(loc, tgt, lens=lens)
    K.frame_camera(c, Vector(tgt), fx, fy)
    return c


# ---------------------------------------------------------------- C: the marquee


def marquee_shot(args):
    """The way in: under the lit marquee at the entrance, the dead shamble in past the ticket booth toward the
    Soldier and the Greaser; the lot and the screen glow beyond."""
    night()
    mq = K.load_prop("drivein/marquee.gltf", (-0.6, 9.0, 0), 0.0, 1.0, "Marquee")
    glow_swatch(mq, "#e8a33a", args.bulbs)
    for i, x in enumerate((-3.6, 2.4)):
        K.point_light(f"MarqueeGlow{i}", (x, 7.6, 4.2), K.hexrgb("#ffb866"), args.lamp * 0.35, radius=0.5)
    bt = K.load_prop("drivein/ticket_booth.gltf", (4.6, 8.0, 0), -15.0, 1.0, "TicketBooth")
    glow_swatch(bt, "#e8a33a", args.bulbs * 0.6)
    S.drive_in_screen((-16.0, 80.0, 0), 10.0, strength=args.screen, seed=0.6)
    lot_rows(4, 8, (-30, 26), (0, 9), (6.5, 0), 0.0, seed=51)
    p2 = Vector((-2.4, 1.6, 0))
    _a2, o2 = soldier(
        GREASER, GREASER_COL, at=tuple(p2), facing=yaw_towards(p2, (-1.2, 9.0)), cls="Rifle", aim_pitch=1, tag="p2"
    )
    p1 = Vector((1.9, 1.0, 0))
    _a1, o1 = soldier(at=tuple(p1), facing=yaw_towards(p1, (0.0, 8.0)), aim_pitch=0, tag="p1")
    arms = horde(args.horde, (-0.6, 11.5), (3.4, 4.0), (0.0, 1.0), seed=13)
    for x, y in ((-10, 13), (9, 15)):
        S.lamp_post((x, y, 0), yaw_deg=90 if x < 0 else -90, watts=args.lamp, name=f"Lamp{x}_{y}")
    S.flare((-0.4, 4.0, 0), strength=args.flare)
    key_rim(o1 + o2, (0, 1.2, 0), (-1.0, -3.5, 2.6), (0.0, 4.0, 2.8), key=args.key, rim=args.rim)
    dead_rim(arms, (-0.6, 24, 6), (-0.6, 11, 0.8), args.zrim, size=14, size_y=5)
    K.fog_box((0, 30, 10), (160, 140, 20), density=args.fog, color="#8fa3d6", ground_boost=2.5, ground_height=2.5)
    loc, tgt, fx, fy, lens = cam_for(
        args, ((0.6, -4.6, 0.6), (-0.4, 6.0, 2.6), 0.5, 0.56, 22), ((0.4, -6.0, 0.6), (-0.4, 6.0, 2.4), 0.5, 0.6, 20)
    )
    c = K.camera(loc, tgt, lens=lens)
    K.frame_camera(c, Vector(tgt), fx, fy)
    return c


# ---------------------------------------------------------------- D: the headliner


def headliner(args):
    """The headliner: the projectionist, grown huge, roars over two players, the projector's beam blazing
    through the fog behind him and the arc lamp burning in his gut."""
    night(wet=0.8, horizon="#1a2550")
    b_at = Vector((0.3, 5.0, 0))
    bz = boss(tuple(b_at), -10.0, "Boss_Roar", args.boss_frame)
    booth = Vector((-2.0, 24.0, 0))
    # The beam comes from behind him toward us (the screen is behind the camera).
    projection_booth(booth, Vector((1.5, -40.0, 9.0)), args.beam, angle=9)
    S.drive_in_screen((0.0, -70.0, 0), 180.0, strength=1.0, seed=0.2)
    side = horde(args.horde, (0.0, 11.0), (9.0, 4.0), (0.0, 0.0), seed=17, avoid=((b_at.xy, 2.5),))
    p1 = Vector((-1.5, 0.8, 0))
    _a1, o1 = soldier(at=tuple(p1), facing=yaw_towards(p1, tuple(b_at)) - 4, aim_pitch=14, tag="p1")
    p2 = Vector((1.9, 1.4, 0))
    _a2, o2 = soldier(
        GREASER, GREASER_COL, at=tuple(p2), facing=yaw_towards(p2, tuple(b_at)) + 6, cls="Rifle", aim_pitch=16, tag="p2"
    )
    for x, y in ((-9, 10), (9, 12)):
        S.lamp_post((x, y, 0), yaw_deg=90 if x < 0 else -90, watts=args.lamp * 0.8, name=f"Lamp{x}_{y}")
    lot_rows(3, 9, (-30, 18), (0, 9), (6.5, 0), 180.0, seed=61, skip=lambda x, y: -6 < x < 6)
    bobj = K.char_objects(bz)
    k = K.area_light(
        "BossKey",
        (b_at.x + 3.0, b_at.y - 5.0, 1.0),
        (b_at.x, b_at.y, 2.0),
        K.hexrgb("#ff8a50"),
        args.key * 3.0,
        size=2.0,
    )
    K.link_light(k, bobj)
    r = K.area_light(
        "BossRim", (b_at.x, b_at.y + 4.0, 5.0), (b_at.x, b_at.y, 2.0), K.hexrgb("#cfe0ff"), args.rim * 4, size=3.0
    )
    K.link_light(r, bobj)
    K.point_light("Gut", (b_at.x, b_at.y - 0.9, 1.55), K.hexrgb("#ffd27a"), args.gut, radius=0.15)
    key_rim(o1 + o2, (0.2, 1.0, 0), (0.0, -3.5, 2.0), (0.0, 3.0, 3.0), key=args.key, rim=args.rim)
    dead_rim(side, (0, 22, 6), (0, 12, 0.8), args.zrim, size=18, size_y=5)
    S.flare((0.3, 2.8, 0), strength=args.flare)
    K.fog_box((0, 10, 10), (120, 120, 20), density=args.fog, color="#8fa3d6", ground_boost=2.5, ground_height=2.5)
    loc, tgt, fx, fy, lens = cam_for(
        args, ((0.6, -3.6, 0.45), (0.3, 5.0, 2.0), 0.5, 0.6, 24), ((0.6, -4.4, 0.45), (0.3, 5.0, 2.0), 0.5, 0.64, 22)
    )
    c = K.camera(loc, tgt, lens=lens)
    K.frame_camera(c, Vector(tgt), fx, fy)
    return c


# ---------------------------------------------------------------- E: back to back, close


def backtoback(args):
    """Back to back, close: the Soldier and the Greaser cover each other over a burning flare, the dead closing
    in out of the fog on both sides; above them, the sky for the title."""
    night(wet=0.9)
    S.drive_in_screen((6.0, 60.0, 0), -8.0, strength=args.screen, seed=3.7)
    p1 = Vector((0.45, 0.0, 0))
    p2 = Vector((-0.45, 0.3, 0))
    _a1, o1 = soldier(at=tuple(p1), facing=yaw_towards(p1, (5.0, -2.5)), aim_pitch=3, tag="p1")
    _a2, o2 = soldier(
        GREASER, GREASER_COL, at=tuple(p2), facing=yaw_towards(p2, (-5.0, 1.5)), cls="Rifle", aim_pitch=3, tag="p2"
    )
    right = horde(max(args.horde // 2, 1), (5.0, 3.0), (2.0, 3.5), (0.45, 0.0), seed=3)
    left = horde(max(args.horde // 2, 1), (-5.5, 3.5), (2.0, 3.5), (-0.45, 0.3), seed=5)
    for x, paint in ((-8, "blue"), (-2.5, "cream"), (3.0, "green"), (9.0, "yellow")):
        K.load_prop(f"props/car_{paint}.gltf", (x, 8.0, 0), 180.0, 1.0)
    lot_rows(3, 10, (-32, 20), (0, 9), (6.5, 0), 180.0, seed=71)
    for x, y in ((-7, 11), (8, 12)):
        S.lamp_post((x, y, 0), yaw_deg=0, watts=args.lamp, name=f"Lamp{x}_{y}")
    S.flare((0.1, -0.7, 0), strength=args.flare)
    both = o1 + o2
    k = K.point_light("FlareKey", (0.1, -0.9, 0.35), K.hexrgb("#ff5a24"), args.key, radius=0.15)
    K.link_light(k, both)
    key_rim(both, (0, 0.1, 0), (-2.0, -3.0, 3.0), (0.5, 3.5, 2.8), key=args.key * 0.6, rim=args.rim, key_col="#ffd2a0")
    dead_rim(right + left, (0, 10, 4.5), (0, 3, 0.8), args.zrim, size=14, size_y=4)
    K.fog_box((0, 20, 10), (120, 120, 20), density=args.fog, color="#8fa3d6", ground_boost=2.5, ground_height=2.5)
    loc, tgt, fx, fy, lens = cam_for(
        args,
        ((0.2, -6.2, 0.9), (0.0, 0.1, 1.0), 0.5, 0.7, 30, 0.56),
        ((0.2, -6.0, 0.8), (0.0, 0.1, 1.0), 0.5, 0.72, 30),
    )
    c = K.camera(loc, tgt, lens=lens)
    K.frame_camera(c, Vector(tgt), fx, fy)
    return c


SHOTS = {
    "feature": feature,
    "headlights": headlights_shot,
    "marquee": marquee_shot,
    "headliner": headliner,
    "backtoback": backtoback,
}


def animate(cam, frames, push):
    """A slow camera push toward the subject and the dead walking, for the Discord video preview: the dead's
    clips are baked frame by frame as pose keys and they move at their clips' ground speed."""
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, frames
    sc.render.fps = 24
    fwd = cam.matrix_world.to_3x3() @ Vector((0, 0, -1))
    start = cam.location.copy()
    for f in (1, frames):
        cam.location = start + fwd * (push * (f - 1) / max(frames - 1, 1))
        cam.keyframe_insert("location", frame=f)
    for fc in cam.animation_data.action.fcurves if hasattr(cam.animation_data.action, "fcurves") else []:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    for arm, clip, f0, speed, heading, at, facing, scale, reach in WALKERS:
        action = K.ACTIONS[arm.name][clip]
        length = action.frame_range[1] - action.frame_range[0]
        keyed = bpy.data.actions.new(f"Video_{arm.name}")
        for f in range(1, frames + 1):
            # set_pose plays the clip's action and leaves the pose on the bones with no action; put the video's
            # own action back only now, with no depsgraph update in between, so the keys take the clip's pose.
            K.set_pose(arm, clip, (f0 + f - 1) % max(length, 1))
            K.place(arm, tuple(at + heading * min(speed * (f - 1) / 24.0, reach)), facing, scale)
            arm.animation_data.action = keyed
            if hasattr(arm.animation_data, "action_slot") and keyed.slots:
                arm.animation_data.action_slot = keyed.slots[0]
            for pb in arm.pose.bones:
                pb.keyframe_insert("location", frame=f)
                pb.keyframe_insert("rotation_quaternion", frame=f)
            arm.keyframe_insert("location", frame=f)
        arm.animation_data.action = keyed
        if hasattr(arm.animation_data, "action_slot") and keyed.slots:
            arm.animation_data.action_slot = keyed.slots[0]
    sc.frame_set(1)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot", required=True, choices=sorted(SHOTS))
    ap.add_argument("--aspect", default="land", choices=["land", "port"])
    ap.add_argument("--width", type=int, default=1920)
    ap.add_argument("--samples", type=int, default=128)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--blend", type=Path)
    ap.add_argument("--frames", type=int, default=0)
    ap.add_argument("--video-dir", type=Path)
    ap.add_argument("--push", type=float, default=1.2)
    ap.add_argument("--port-lens", type=float, default=1.35)
    ap.add_argument("--port-drop", type=float, default=0.06)
    ap.add_argument("--screen", type=float, default=3.0)
    ap.add_argument("--lamp", type=float, default=700.0)
    ap.add_argument("--flare", type=float, default=80.0)
    ap.add_argument("--fog", type=float, default=0.013)
    ap.add_argument("--key", type=float, default=120.0)
    ap.add_argument("--rim", type=float, default=500.0)
    ap.add_argument("--zrim", type=float, default=2500.0)
    ap.add_argument("--beam", type=float, default=500000.0)
    ap.add_argument("--bulbs", type=float, default=30.0)
    ap.add_argument("--gut", type=float, default=60.0)
    ap.add_argument("--boss-frame", type=float, default=30.0)
    ap.add_argument("--horde", type=int, default=14)
    ap.add_argument("--bloom", type=float, default=0.3)
    ap.add_argument("--bloom-threshold", type=float, default=1.5)
    ap.add_argument("--exposure", type=float, default=0.0)
    ap.add_argument("--dof", type=float, default=0.0)
    args = ap.parse_args(argv)
    if args.shot == "headlights" and args.beam == 500000.0:
        args.beam = 6000.0
    w = args.width
    h = round(w * 9 / 16) if args.aspect == "land" else round(w * 3 / 2)
    K.reset()
    bpy.context.scene.render.resolution_x = w
    bpy.context.scene.render.resolution_y = h
    cam = SHOTS[args.shot](args)
    if args.dof:
        cam.data.dof.use_dof = True
        cam.data.dof.focus_distance = 8.0
        cam.data.dof.aperture_fstop = args.dof
    K.cycles(samples=args.samples, width=w, height=h, exposure=args.exposure)
    K.glare_compositor(threshold=args.bloom_threshold, strength=args.bloom)
    if args.blend:
        K.save_blend(args.blend.resolve())
    if args.frames:
        animate(cam, args.frames, args.push)
        sc = bpy.context.scene
        args.video_dir.mkdir(parents=True, exist_ok=True)
        sc.render.filepath = str(args.video_dir.resolve()) + "/f_"
        bpy.ops.render.render(animation=True)
        print(f"wrote {args.video_dir}")
    else:
        K.render(args.out.resolve())


main()
