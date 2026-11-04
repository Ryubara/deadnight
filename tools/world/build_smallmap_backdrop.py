"""Write game/world/smallmap/backdrop.tscn: the small map's outside, past the playable bounds (issue #638).

Plain Python, no dependencies; run it from the repository root and commit the scene it writes:

    python tools/world/build_smallmap_backdrop.py

The map is indoors (the maintainer's decision, 2026-11-02); through its windows, doors and broken walls the players
see Deadnight's own world in the distance: the yard's wire fence and bare trees, a pole line, and to the north the
drive-in itself, its screen lit, cars parked in rows, the marquee and a neon sign, a wreck burning. Nothing here is
walked or collides. Metres, Y up, x east, z south, the building's middle at the origin; the lot's screen is north in
this scene's own frame, as on the drive-in lot. The second map places the scene turned half a circle, so on that map
the drive-in lies south of the building, in front of the hall's window, and the yard is one level all round (#917). Every repeated model is one MultiMesh (one draw for all its copies);
`Backdrop` (game/world/smallmap/backdrop.gd) fills the glTF ones and keeps the haze in step with the fog. Placements
come from a fixed seed, so the scene does not change from one run to the next. Notes: docs/research/maps/small-map-art.md.
"""

import math
import random
from pathlib import Path

OUT = Path("game/world/smallmap/backdrop.tscn")

# The building (the formula's 29 x 21 m ground floor) and the fenced yard round it, where the dead come from. The yard
# is the level's (the greybox); the backdrop starts at its fence. Change these to the greybox's and run again.
BUILDING_HALF = (14.5, 10.5)
YARD_HALF = (31.0, 27.0)
GATE = 3.0  # a gap in the north fence, closed by barbed coils, where the road to the drive-in leaves

# The drive-in, north: the screen's middle at x 0 (its shader maps the panel from world x, so it stays on x 0).
SCREEN_Z = -120.0
SCREEN_W, SCREEN_H, SCREEN_MID = 32.0, 12.0, 10.0
CAR_ROWS = (-101.0, -92.0, -83.0)
CAR_PITCH = 4.4
CAR_FILL = 0.6  # a weeknight: about six stalls in ten taken
LOT_GROUND = (0.0, -92.0, 76.0, 64.0)  # x, z, width, depth of the lot's asphalt
MARQUEE = (34.0, -70.0)
BOOTH = (42.0, -62.0)
NEON = (-30.0, -74.0)
LOT_FENCE_Z = -60.0
LOT_LAMPS = ((-30.0, -88.0), (30.0, -88.0), (-12.0, -66.0), (12.0, -66.0), (-30.0, -106.0), (30.0, -106.0))

# A pole line along the road south of the yard and one up the east side to the drive-in.
POLE_SPAN = 12.0
SOUTH_LINE_Z = YARD_HALF[1] + 14.0
SOUTH_LINE_X = (-84.0, 84.0)
EAST_LINE_X = 48.0
NEAR = 70.0  # poles and wires nearer the middle than this are the near models, the rest the far ones

TREES_NEAR = 16
TREES_FAR = 70
SEED = 638

FIRES = {
    # name: (model, where, yaw, flame height)
    "Wreck": ("res://assets/props/broken_car.gltf", (38.0, -40.0), 30.0, 1.6),
    "Barrel": ("res://assets/props/barrel.gltf", (-40.0, 36.0), 0.0, 1.0),
}
CAR_COLOURS = ("red", "blue", "cream", "green", "yellow")


def num(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def xf(x, z, yaw=0.0, y=0.0, scale=1.0):
    """A MultiMesh transform: basis rows, each followed by its origin's coordinate."""
    c, s = math.cos(math.radians(yaw)) * scale, math.sin(math.radians(yaw)) * scale
    return [c, 0, s, x, 0, scale, 0, y, -s, 0, c, z]


def facing(x, z, tx=0.0, tz=0.0):
    """The yaw that turns a model's front (+Z) from (x, z) towards (tx, tz)."""
    return math.degrees(math.atan2(tx - x, tz - z))


def along(dx, dz):
    """The yaw that turns a piece's +X (a fence run, a wire span) along (dx, dz)."""
    return math.degrees(math.atan2(-dz, dx))


class Scene:
    def __init__(self):
        self.ext, self.sub, self.nodes = [], [], []

    def ext_res(self, kind, path, rid):
        self.ext.append(f'[ext_resource type="{kind}" path="{path}" id="{rid}"]')
        return rid

    def sub_res(self, kind, rid, props):
        lines = [f'[sub_resource type="{kind}" id="{rid}"]'] + [f"{k} = {v}" for k, v in props]
        self.sub.append("\n".join(lines))
        return rid

    def node(self, name, kind, parent, props=(), extra=""):
        head = (
            f'[node name="{name}" type="{kind}"' + (f' parent="{parent}"' if parent is not None else "") + extra + "]"
        )
        self.nodes.append("\n".join([head] + [f"{k} = {v}" for k, v in props]))

    def multi(self, name, parent, transforms, material, mesh=None, source=None, extra=(), mesh_sub=None):
        rid = f"mm_{parent.replace('/', '_')}_{name}"
        flat = ", ".join(num(v) for t in transforms for v in t)
        props = [("transform_format", 1), ("instance_count", len(transforms))]
        if mesh:
            props.append(("mesh", f'ExtResource("{mesh}")'))
        if mesh_sub:
            props.append(("mesh", f'SubResource("{mesh_sub}")'))
        props.append(("buffer", f"PackedFloat32Array({flat})"))
        self.sub_res("MultiMesh", rid, props)
        node_props = [("material_override", f'SubResource("{material}")'), ("cast_shadow", 0)]
        node_props += list(extra)
        node_props.append(("multimesh", f'SubResource("{rid}")'))
        if source:
            node_props.append(("metadata/source", f'"{source}"'))
        self.node(name, "MultiMeshInstance3D", parent, node_props)

    def text(self):
        head = "[gd_scene format=3]"
        return "\n\n".join([head, "\n".join(self.ext)] + self.sub + self.nodes) + "\n"


def colour(rgb, a=1.0):
    return f"Color({num(rgb[0])}, {num(rgb[1])}, {num(rgb[2])}, {num(a)})"


def glow(sc, rid, tint, energy, falloff, billboard=True):
    return sc.sub_res(
        "ShaderMaterial",
        rid,
        [
            ("render_priority", 1),
            ("shader", 'ExtResource("glow")'),
            ("shader_parameter/tint", colour(tint)),
            ("shader_parameter/energy", num(energy)),
            ("shader_parameter/falloff", num(falloff)),
            ("shader_parameter/billboard", "true" if billboard else "false"),
        ],
    )


def quad(sc, name, parent, size, at, material, mesh_id):
    sc.sub_res("QuadMesh", mesh_id, [("size", f"Vector2({num(size[0])}, {num(size[1])})")])
    sc.node(
        name,
        "MeshInstance3D",
        parent,
        [
            ("transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {num(at[0])}, {num(at[1])}, {num(at[2])})"),
            ("cast_shadow", 0),
            ("mesh", f'SubResource("{mesh_id}")'),
            ("material_override", f'SubResource("{material}")'),
        ],
    )


def ring_point(rng, inner, outer):
    """A point between two rectangles round the middle (half sizes `inner` and `outer`)."""
    while True:
        x, z = rng.uniform(-outer[0], outer[0]), rng.uniform(-outer[1], outer[1])
        if abs(x) > inner[0] or abs(z) > inner[1]:
            return x, z


def north_view(x, z, half_width):
    """Whether (x, z) stands in the view from the building to the drive-in, kept clear of trees."""
    return z < -YARD_HALF[1] and abs(x) < half_width + (-z - YARD_HALF[1]) * 0.25


def build():
    rng = random.Random(SEED)
    sc = Scene()
    sc.ext_res("Script", "res://world/smallmap/backdrop.gd", "script")
    sc.ext_res("Shader", "res://world/smallmap/backdrop_haze.gdshader", "haze")
    sc.ext_res("Shader", "res://world/drive_in/glow.gdshader", "glow")
    sc.ext_res("Shader", "res://world/drive_in/screen.gdshader", "screen")
    sc.ext_res("Texture2D", "res://assets/smallmap/smallmap_palette.png", "kit_palette")
    sc.ext_res("Texture2D", "res://assets/props/props_palette.png", "props_palette")
    sc.ext_res("Texture2D", "res://assets/drivein/drivein_palette.png", "drivein_palette")
    sc.ext_res("Material", "res://assets/smallmap/materials/frost_ground.tres", "frost")
    sc.ext_res("Material", "res://assets/lot/materials/field_ground.tres", "asphalt")
    objs = [
        "bare_tree_a",
        "bare_tree_b",
        "bare_tree_c",
        "bare_tree_a_far",
        "bare_tree_b_far",
        "bare_tree_c_far",
        "utility_pole",
        "utility_pole_far",
        "utility_wire",
        "utility_wire_far",
        "wire_fence_far",
        "fence_post",
        "barbed_coil",
        "neon_sign",
    ]
    for o in objs:
        sc.ext_res("Mesh", f"res://assets/smallmap/{o}.obj", o)
    for rid, tex, glow_cells in (
        ("haze_kit", "kit_palette", (6, 19)),
        ("haze_props", "props_palette", (-1, -1)),
        ("haze_drivein", "drivein_palette", (6, 19)),
    ):
        sc.sub_res(
            "ShaderMaterial",
            rid,
            [
                ("shader", 'ExtResource("haze")'),
                ("shader_parameter/atlas", f'ExtResource("{tex}")'),
                ("shader_parameter/glow_cell_a", glow_cells[0]),
                ("shader_parameter/glow_cell_b", glow_cells[1]),
            ],
        )
    screen_mat = sc.sub_res(
        "ShaderMaterial",
        "screen_face",
        [
            ("shader", 'ExtResource("screen")'),
            ("shader_parameter/energy", 0.75),
            ("shader_parameter/panel_size", f"Vector2({num(SCREEN_W)}, {num(SCREEN_H)})"),
            ("shader_parameter/panel_centre_y", num(SCREEN_MID)),
        ],
    )
    glow(sc, "screen_halo", (0.5, 0.62, 0.82), 0.16, 1.4)
    glow(sc, "amber_halo", (1.0, 0.66, 0.3), 0.3, 2.2)
    glow(sc, "neon_halo", (1.0, 0.25, 0.5), 0.42, 2.0)
    glow(sc, "lamp_halo", (1.0, 0.72, 0.4), 0.5, 2.6)

    sc.node(
        "Backdrop",
        "Node3D",
        None,
        extra=' node_paths=PackedStringArray("screen_face", "fires")',
        props=[
            ("script", 'ExtResource("script")'),
            ("screen_face", 'NodePath("Lot/ScreenFace")'),
            ("fires", "[" + ", ".join(f'NodePath("Fires/{n}/Flame")' for n in FIRES) + "]"),
            ("metadata/yard_half", f"Vector2({num(YARD_HALF[0])}, {num(YARD_HALF[1])})"),
        ],
    )
    sc.node(
        "Ground",
        "CSGBox3D",
        ".",
        [
            ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.22, 0)"),
            ("cast_shadow", 0),
            ("size", "Vector3(360, 0.4, 360)"),
            ("material", 'ExtResource("frost")'),
        ],
    )

    # The yard's fence: 2 m wire runs round the yard, a gate gap in the north side closed by coils.
    sc.node("Yard", "Node3D", ".")
    hx, hz = YARD_HALF
    runs, posts = [], []
    corners = [(-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)]
    for (x0, z0), (x1, z1) in zip(corners, corners[1:] + corners[:1]):
        length = math.hypot(x1 - x0, z1 - z0)
        dx, dz = (x1 - x0) / length, (z1 - z0) / length
        for i in range(int(length // 2)):
            x, z = x0 + dx * 2 * i, z0 + dz * 2 * i
            if z0 == z1 == -hz and abs(x + 1.0) < GATE:
                continue
            runs.append(xf(x, z, along(dx, dz), 0.0))
        posts.append(xf(x1, z1, 0.0, 0.0))
    for x in (-GATE - 1.0, GATE - 1.0):
        posts.append(xf(x, -hz, 0.0, 0.0))
    sc.multi("WireFence", "Yard", runs, "haze_kit", mesh="wire_fence_far")
    sc.multi("FencePosts", "Yard", posts, "haze_kit", mesh="fence_post")
    coils = [xf(-1.0, -hz - 0.6, 0.0, 0.0), xf(1.0, -hz - 0.6, 0.0, 0.0)]
    for x, z in ((-hx + 4, -hz - 0.7), (hx - 6, -hz - 0.7), (hx + 0.7, 6.0), (-hx - 0.7, -8.0), (8.0, hz + 0.7)):
        yaw = 90.0 if abs(abs(x) - hx) < 1.0 else 0.0
        coils.append(xf(x, z, yaw))
        coils.append(xf(x + (0 if yaw else 2.0), z + (2.0 if yaw else 0), yaw))
    sc.multi("Coils", "Yard", coils, "haze_kit", mesh="barbed_coil")

    # Bare trees: a near ring just outside the fence, the far ones in a belt round everything but the drive-in view.
    near = {"bare_tree_a": [], "bare_tree_b": [], "bare_tree_c": []}
    while sum(len(v) for v in near.values()) < TREES_NEAR:
        x, z = ring_point(rng, (hx + 3, hz + 3), (hx + 16, hz + 14))
        if north_view(x, z, 26.0):
            continue
        near[rng.choice(list(near))].append(xf(x, z, rng.uniform(0, 360), scale=rng.uniform(0.85, 1.15)))
    far = {"bare_tree_a_far": [], "bare_tree_b_far": [], "bare_tree_c_far": []}
    while sum(len(v) for v in far.values()) < TREES_FAR:
        a, r = rng.uniform(0, math.tau), rng.uniform(58, 150)
        x, z = math.sin(a) * r, math.cos(a) * r
        if north_view(x, z, 44.0) or abs(z - SOUTH_LINE_Z) < 4 or abs(x - EAST_LINE_X) < 4:
            continue
        far[rng.choice(list(far))].append(xf(x, z, rng.uniform(0, 360), scale=rng.uniform(0.9, 1.3)))
    for name, ts in near.items():
        sc.multi(name.title().replace("_", ""), "Yard", ts, "haze_kit", mesh=name)
    sc.node("Woods", "Node3D", ".")
    for name, ts in far.items():
        sc.multi(name.title().replace("_", ""), "Woods", ts, "haze_kit", mesh=name)

    # The pole lines. A wire piece runs from its pole's insulators 12 m along its own +X to the next pole.
    sc.node("Lines", "Node3D", ".")
    poles = {"near": [], "far": []}
    wires = {"near": [], "far": []}
    xs = [SOUTH_LINE_X[0] + i * POLE_SPAN for i in range(int((SOUTH_LINE_X[1] - SOUTH_LINE_X[0]) // POLE_SPAN) + 1)]
    line = [(x, SOUTH_LINE_Z, 0.0) for x in xs]
    east_x = min(xs, key=lambda x: abs(x - EAST_LINE_X))
    zs = [SOUTH_LINE_Z - POLE_SPAN * (i + 1) for i in range(int((SOUTH_LINE_Z - SCREEN_Z) // POLE_SPAN))]
    north = [(east_x, z, along(0, -1)) for z in zs]
    for pts in (line, [(east_x, SOUTH_LINE_Z, along(0, -1))] + north):
        for i, (x, z, yaw) in enumerate(pts):
            band = "near" if math.hypot(x, z) < NEAR else "far"
            if (x, z) != (east_x, SOUTH_LINE_Z) or pts is line:
                poles[band].append(xf(x, z, yaw))
            if i + 1 < len(pts):
                wires[band].append(xf(x, z, yaw))
    sc.multi("Poles", "Lines", poles["near"], "haze_kit", mesh="utility_pole")
    sc.multi("PolesFar", "Lines", poles["far"], "haze_kit", mesh="utility_pole_far")
    sc.multi("Wires", "Lines", wires["near"], "haze_kit", mesh="utility_wire")
    sc.multi("WiresFar", "Lines", wires["far"], "haze_kit", mesh="utility_wire_far")

    # The drive-in to the north: its asphalt, the screen lit, the cars in rows facing it, the lamps, the marquee and
    # booth at the entrance, a neon sign and a stretch of the lot's fence.
    sc.node("Lot", "Node3D", ".")
    gx, gz, gw, gd = LOT_GROUND
    sc.node(
        "Asphalt",
        "CSGBox3D",
        "Lot",
        [
            ("transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {num(gx)}, -0.05, {num(gz)})"),
            ("cast_shadow", 0),
            ("size", f"Vector3({num(gw)}, 0.1, {num(gd)})"),
            ("material", 'ExtResource("asphalt")'),
        ],
    )
    sc.multi("ScreenFrame", "Lot", [xf(0, SCREEN_Z)], "haze_drivein", source="res://assets/drivein/screen_frame.gltf")
    sc.sub_res("QuadMesh", "screen_quad", [("size", f"Vector2({num(SCREEN_W)}, {num(SCREEN_H)})")])
    sc.node(
        "ScreenFace",
        "MeshInstance3D",
        "Lot",
        [
            ("transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {num(SCREEN_MID)}, {num(SCREEN_Z + 0.8)})"),
            ("cast_shadow", 0),
            ("mesh", 'SubResource("screen_quad")'),
            ("material_override", f'SubResource("{screen_mat}")'),
        ],
    )
    quad(sc, "ScreenHalo", "Lot", (64, 34), (0, SCREEN_MID, SCREEN_Z + 3.0), "screen_halo", "screen_halo_quad")
    cars = {c: [] for c in CAR_COLOURS}
    for row in CAR_ROWS:
        n = 11
        for i in range(n):
            if rng.random() > CAR_FILL:
                continue
            x = (i - (n - 1) / 2) * CAR_PITCH
            # Rows curve a little towards the screen, as the lot's do; every car's nose to the screen.
            z = row + 0.012 * x * x
            yaw = facing(x, z, 0.0, SCREEN_Z) + 180.0 + rng.uniform(-4, 4)
            cars[rng.choice(CAR_COLOURS)].append(xf(x, z, yaw))
    for c, ts in cars.items():
        if ts:
            sc.multi(f"Cars{c.title()}", "Lot", ts, "haze_props", source=f"res://assets/props/car_{c}.gltf")
    sc.multi(
        "Lamps",
        "Lot",
        [xf(x, z, facing(x, z)) for x, z in LOT_LAMPS],
        "haze_props",
        source="res://assets/props/street_light.gltf",
    )
    # The lamps' halos: one multimesh of quads (the glow shader's billboard reads each copy's own origin).
    sc.sub_res("QuadMesh", "lamp_halo_quad", [("size", "Vector2(3.2, 3.2)")])
    sc.multi("LampHalos", "Lot", [xf(x, z, y=4.4) for x, z in LOT_LAMPS], "lamp_halo", mesh_sub="lamp_halo_quad")
    sc.multi(
        "Marquee", "Lot", [xf(*MARQUEE, facing(*MARQUEE))], "haze_drivein", source="res://assets/drivein/marquee.gltf"
    )
    quad(sc, "MarqueeHalo", "Lot", (11, 6), (MARQUEE[0], 4.4, MARQUEE[1] + 1.0), "amber_halo", "marquee_halo_quad")
    sc.multi(
        "Booth", "Lot", [xf(*BOOTH, facing(*BOOTH))], "haze_drivein", source="res://assets/drivein/ticket_booth.gltf"
    )
    sc.multi("NeonSign", "Lot", [xf(*NEON, facing(*NEON))], "haze_kit", mesh="neon_sign")
    quad(sc, "NeonHalo", "Lot", (13, 6), (NEON[0], 6.9, NEON[1] + 1.0), "neon_halo", "neon_halo_quad")
    fence = [xf(x, LOT_FENCE_Z) for x in [-34 + 2.13 * i for i in range(10)] + [13 + 2.13 * i for i in range(7)]]
    sc.multi("Fence", "Lot", fence, "haze_props", source="res://assets/props/fence_long.gltf")

    # Fires: a wreck burning past the yard's corner and a barrel fire to the south-west, flames and a halo each.
    sc.node("Fires", "Node3D", ".")
    for name, (model, (x, z), yaw, flame) in FIRES.items():
        sc.node(
            name, "Node3D", "Fires", [("transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {num(x)}, 0, {num(z)})")]
        )
        sc.multi("Model", f"Fires/{name}", [xf(0, 0, yaw)], "haze_props", source=model)
        glow(sc, f"flame_{name}", (1.0, 0.5, 0.16), 1.5, 1.3)
        glow(sc, f"fire_halo_{name}", (1.0, 0.45, 0.15), 0.35, 2.4)
        quad(
            sc,
            "Flame",
            f"Fires/{name}",
            (flame * 1.1, flame * 1.6),
            (0, flame + 0.5, 0),
            f"flame_{name}",
            f"flame_quad_{name}",
        )
        quad(
            sc,
            "Halo",
            f"Fires/{name}",
            (flame * 7, flame * 5),
            (0, flame + 0.3, 0),
            f"fire_halo_{name}",
            f"fire_halo_quad_{name}",
        )
    return sc


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build().text(), encoding="utf-8", newline="\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
