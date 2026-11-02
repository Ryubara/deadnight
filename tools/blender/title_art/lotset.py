"""The lot's set pieces for the marketing renders: the plank fence with a breach and its boards, lamp posts,
the screen with its glowing face, parked cars, speaker posts, a flare, bulbs, the night sky and the moon.

Everything is the game's own models (props, drive-in props) or built here from the game's numbers (the fence's
3 m plank wall, the board's 4.1 x 0.45 x 0.14 box, the sodium lamp colour)."""

import math

import bpy
import keyart as K
import numpy as np
from mathutils import Matrix, Vector

WOOD = ["#6e573b", "#5f4a32", "#76603f", "#654f35"]
_MATS = {}


def mat_cached(key, maker):
    if key not in _MATS:
        _MATS[key] = maker()
    return _MATS[key]


def box(name, size, location, rgb_hex, rot=(0, 0, 0), bevel=0.02, roughness=0.65, mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        m = o.modifiers.new("Chamfer", "BEVEL")
        m.width = bevel
        m.segments = 1
        m.limit_method = "NONE"
    if mat is None:
        mat = mat_cached(
            ("flat", rgb_hex, roughness), lambda: K.flat_material(f"Flat_{rgb_hex}", K.hexrgb(rgb_hex), roughness)
        )
    o.data.materials.append(mat)
    return o


def fence_line(p0, p1, height=3.0, breach=None, seed=1, name="Fence"):
    """A plank fence from p0 to p1 (x, y on the ground): boards 0.25 m wide standing on end, posts every 2.4 m
    and two rails on the outside (the side left of p0 -> p1 seen from above is the inside). `breach` =
    (fraction along, width): a gap there with a post each side. Returns the objects and the line's frame."""
    rng = np.random.default_rng(seed)
    a, b = Vector((*p0, 0)), Vector((*p1, 0))
    d = b - a
    L = d.length
    u = d.normalized()
    n = Vector((u.y, -u.x, 0))  # the outside
    yaw = math.atan2(u.y, u.x)
    objs = []
    gap = None
    if breach:
        gap = (breach[0] * L - breach[1] / 2, breach[0] * L + breach[1] / 2)
    t = 0.0
    i = 0
    while t < L:
        if gap and gap[0] <= t + 0.125 <= gap[1]:
            t += 0.25
            continue
        h = height + rng.uniform(-0.08, 0.06)
        c = a + u * (t + 0.125)
        col = WOOD[int(rng.integers(0, len(WOOD)))]
        objs.append(box(f"{name}_plank{i}", (0.235, 0.06, h), (c.x, c.y, h / 2), col, rot=(0, 0, yaw), bevel=0.012))
        t += 0.25
        i += 1
    posts = []
    t = 0.0
    while t <= L:
        posts.append(t)
        t += 2.4
    if gap:
        posts = [p for p in posts if not (gap[0] - 0.3 < p < gap[1] + 0.3)] + [gap[0] - 0.12, gap[1] + 0.12]
    for k, t in enumerate(posts):
        c = a + u * t + n * 0.1
        objs.append(
            box(
                f"{name}_post{k}",
                (0.2, 0.2, height + 0.1),
                (c.x, c.y, (height + 0.1) / 2),
                "#5a4630",
                rot=(0, 0, yaw),
                bevel=0.02,
            )
        )
    for z in (0.6, height - 0.5):
        segs = [(0, L)] if not gap else [(0, gap[0]), (gap[1], L)]
        for s0, s1 in segs:
            if s1 - s0 < 0.1:
                continue
            c = a + u * ((s0 + s1) / 2) + n * 0.075
            objs.append(
                box(f"{name}_rail", (s1 - s0, 0.09, 0.14), (c.x, c.y, z), "#5f4a32", rot=(0, 0, yaw), bevel=0.015)
            )
    return objs, {"a": a, "u": u, "n": n, "L": L, "yaw": yaw, "gap": gap}


def point_on(frame, t, out=0.0, z=0.0):
    p = frame["a"] + frame["u"] * t + frame["n"] * out
    return Vector((p.x, p.y, z))


def board(name, centre, yaw, roll=0.0, pitch=0.0, color="#8a5a2b"):
    """A barricade board (the game's Board: 4.1 x 0.45 x 0.14 m) at a centre, along yaw, turned."""
    o = box(name, (4.1, 0.14, 0.45), (0, 0, 0), color, bevel=0.02)
    o.rotation_mode = "XYZ"
    o.matrix_world = (
        Matrix.Translation(centre)
        @ Matrix.Rotation(yaw, 4, "Z")
        @ Matrix.Rotation(math.radians(pitch), 4, "Y")
        @ Matrix.Rotation(math.radians(roll), 4, "X")
    )
    return o


def barricade(frame, boards_up=(0, 2, 4), hanging=None, torn_on_ground=(), out=0.03):
    """The breach's five boards, from the bottom (0) to the top (4), at 0.45 m spacing from 0.5 m up.
    `hanging` = (index, degrees): one board torn at one end, swung down. Torn boards lie on the field side."""
    g0, g1 = frame["gap"]
    mid = (g0 + g1) / 2
    objs = []
    for i in range(5):
        z = 0.55 + i * 0.5
        c = point_on(frame, mid, out + 0.12, z)
        if i in boards_up:
            objs.append(board(f"Board{i}", c, frame["yaw"], color=["#6a4626", "#5e3f22", "#73502c"][i % 3]))
        elif hanging and hanging[0] == i:
            # Nailed at the far end, the near end swung down.
            pivot = point_on(frame, g1 - 0.05, out + 0.12, z)
            o = board(f"Board{i}", Vector((0, 0, 0)), 0, color="#5e3f22")
            o.matrix_world = (
                Matrix.Translation(pivot)
                @ Matrix.Rotation(frame["yaw"], 4, "Z")
                @ Matrix.Rotation(math.radians(hanging[1]), 4, "Y")
                @ Matrix.Translation((-2.0, 0, 0))
            )
            objs.append(o)
    for k, (t_off, inward, turn) in enumerate(torn_on_ground):
        c = point_on(frame, mid + t_off, -inward, 0.08)
        objs.append(board(f"Torn{k}", c, frame["yaw"] + math.radians(turn), roll=90, color="#5e3f22"))
    return objs


def lamp_post(location, yaw_deg=0.0, watts=900.0, color="#ffb866", lens_strength=40.0, name="Lamp"):
    """The kit street light with a sodium lamp in its head: a point light and an emissive lens."""
    roots = K.load_prop("props/street_light.gltf", location, yaw_deg, 1.0, name)
    mn, mx = K.world_bbox([r for r in roots if r.type == "MESH"])
    # The head is the far end of the arm from the pole: the corner of the bounding box away from the base.
    base = Vector(location)
    cands = [Vector((x, y, mx.z)) for x in (mn.x, mx.x) for y in (mn.y, mx.y)]
    far = max(cands, key=lambda p: (Vector((p.x, p.y, 0)) - Vector((base.x, base.y, 0))).length)
    centre_xy = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, 0))
    head = Vector((far.x, far.y, 0)) * 0.55 + centre_xy * 0.45
    # Snap the head to the arm's axis: along the longest horizontal side of the box.
    if (mx.x - mn.x) > (mx.y - mn.y):
        head = Vector((far.x - math.copysign(0.25, far.x - base.x), (mn.y + mx.y) / 2, mx.z - 0.3))
    else:
        head = Vector(((mn.x + mx.x) / 2, far.y - math.copysign(0.25, far.y - base.y), mx.z - 0.3))
    lamp = K.point_light(f"{name}_light", head + Vector((0, 0, -0.15)), K.hexrgb(color), watts, radius=0.2)
    lens_mat = mat_cached(
        ("lens", color, lens_strength), lambda: K.emissive_material("SodiumLens", K.hexrgb(color), lens_strength)
    )
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=head + Vector((0, 0, -0.1)), segments=12, ring_count=8)
    lens = bpy.context.active_object
    lens.name = f"{name}_lens"
    lens.scale = (1.0, 1.0, 0.4)
    lens.data.materials.append(lens_mat)
    lens.visible_shadow = False
    return roots, lamp, head


def bulb(location, radius=0.07, strength=30.0, color="#ffc66b", name="Bulb"):
    m = mat_cached(("bulb", color, strength), lambda: K.emissive_material(f"Bulb_{color}", K.hexrgb(color), strength))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location, segments=10, ring_count=6)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(m)
    o.visible_shadow = False
    return o


def flare(location, strength=150.0, color="#ff5a24", yaw=0.6):
    """A road flare burning on the ground: a red stick, a hot tip, an orange light."""
    x, y = location[0], location[1]
    box("Flare", (0.32, 0.045, 0.045), (x, y, 0.03), "#b8322e", rot=(0, 0, yaw), bevel=0.0)
    tip = Vector((x + 0.16 * math.cos(yaw), y + 0.16 * math.sin(yaw), 0.05))
    m = mat_cached(("flaretip", color), lambda: K.emissive_material("FlareTip", K.hexrgb("#ffd2a0"), 120.0))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=tip, segments=8, ring_count=6)
    t = bpy.context.active_object
    t.data.materials.append(m)
    t.visible_shadow = False
    return K.point_light("FlareLight", tip + Vector((0, 0, 0.2)), K.hexrgb(color), strength, radius=0.1)


def drive_in_screen(location, yaw_deg, strength=5.0, seed=0.0):
    """The screen frame (our prop) and a 32 x 12 m glowing face in it, its middle 10 m up, facing the frame's -Y."""
    roots = K.load_prop("drivein/screen_frame.gltf", location, yaw_deg, 1.0, "ScreenFrame")
    rot = Matrix.Rotation(math.radians(yaw_deg), 3, "Z")
    c = Vector(location) + rot @ Vector((0, -0.05, 10.0))
    bpy.ops.mesh.primitive_plane_add(size=1, location=c, rotation=(math.radians(90), 0, math.radians(yaw_deg)))
    face = bpy.context.active_object
    face.name = "ScreenFace"
    face.scale = (32.0, 12.0, 1)
    face.data.materials.append(K.screen_material(strength, seed))
    return roots, face


def stars_world(top="#070b1e", horizon="#1a2550", strength=1.0, density=0.06):
    """The night sky: a gradient and small stars that fade out toward the horizon."""
    w = K.world_night(top, horizon, strength)
    nt = w.node_tree
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    ramp = next(n for n in nt.nodes if n.type == "VALTORGB")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 220.0
    star = nt.nodes.new("ShaderNodeMapRange")
    star.inputs["From Min"].default_value = 0.0
    star.inputs["From Max"].default_value = 0.07
    star.inputs["To Min"].default_value = 1.0
    star.inputs["To Max"].default_value = 0.0
    sel = nt.nodes.new("ShaderNodeMath")
    sel.operation = "GREATER_THAN"
    sel.inputs[1].default_value = 1.0 - density
    sep_c = nt.nodes.new("ShaderNodeSeparateColor")
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    hz = nt.nodes.new("ShaderNodeMapRange")
    hz.inputs["From Min"].default_value = 0.04
    hz.inputs["From Max"].default_value = 0.3
    mul2 = nt.nodes.new("ShaderNodeMath")
    mul2.operation = "MULTIPLY"
    sc = nt.nodes.new("ShaderNodeMath")
    sc.operation = "MULTIPLY"
    sc.inputs[1].default_value = 1.2
    add = nt.nodes.new("ShaderNodeMix")
    add.data_type = "RGBA"
    add.blend_type = "ADD"
    add.inputs["Factor"].default_value = 1.0
    # Normalised direction so stars do not stretch: the Generated coordinate of a world is the view direction.
    nt.links.new(tc.outputs["Generated"], vor.inputs["Vector"])
    nt.links.new(vor.outputs["Distance"], star.inputs["Value"])
    nt.links.new(vor.outputs["Color"], sep_c.inputs["Color"])
    nt.links.new(sep_c.outputs[0], sel.inputs[0])
    nt.links.new(star.outputs["Result"], mul.inputs[0])
    nt.links.new(sel.outputs[0], mul.inputs[1])
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], hz.inputs["Value"])
    nt.links.new(mul.outputs[0], mul2.inputs[0])
    nt.links.new(hz.outputs["Result"], mul2.inputs[1])
    nt.links.new(mul2.outputs[0], sc.inputs[0])
    nt.links.new(ramp.outputs["Color"], add.inputs["A"])
    nt.links.new(sc.outputs[0], add.inputs["B"])
    nt.links.new(add.outputs["Result"], bg.inputs["Color"])
    return w


def moon_light(elev_deg=38.0, az_deg=0.0, strength=0.08, color="#9fb4ff"):
    """A weak cool sun from the moon's direction (az 0 = from +Y)."""
    d = bpy.data.lights.new("Moon", "SUN")
    d.color = K.hexrgb(color)
    d.energy = strength
    d.angle = math.radians(1.5)
    o = bpy.data.objects.new("Moon", d)
    bpy.context.scene.collection.objects.link(o)
    direction = Vector(
        (
            math.sin(math.radians(az_deg)) * math.cos(math.radians(elev_deg)),
            math.cos(math.radians(az_deg)) * math.cos(math.radians(elev_deg)),
            math.sin(math.radians(elev_deg)),
        )
    )
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = (-direction).to_track_quat("-Z", "Y")
    return o


def moon_disc(location, radius=2.5, strength=6.0):
    m = K.emissive_material("MoonDisc", K.hexrgb("#e8ecff"), strength)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location, segments=24, ring_count=12)
    o = bpy.context.active_object
    o.data.materials.append(m)
    o.visible_shadow = False
    return o
