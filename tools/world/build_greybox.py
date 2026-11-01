"""Write game/world/drive_in_greybox.tscn: the CSG greybox of the drive-in lot (docs/design/map.md).

Plain Python, no dependencies; run it from the repository root and commit the scene it writes:

    python tools/world/build_greybox.py

Metres, Y up, x east, z south (the screen is at the north, z -48). Every area is a named Node3D with its own colours.
Cars are placed from a fixed seed so the scene does not change from one run to the next.
"""

import math
import random
import re
from pathlib import Path

import drivein_props
import lot_props

OUT = Path("game/world/drive_in_greybox.tscn")
TUNING = Path("game/gameplay/rules/default_tuning.tres")

# The map's purchase doors and the shop items (the rules' tuning) that price them. The price and the prerequisite
# are read from the tuning, so the economy has one source and the map follows it.
DOOR_ITEMS = {
    "Door_Concession": "door_concession",
    "Door_GeneratorYard": "door_yard",
    "Door_ProjectionBooth": "door_booth",
    "Door_BackLot": "door_back_lot",
    "Door_Road": "door_road",
}

# Bodies and the camera rig, mirrored from the player (PlayerTuning: pivot 1.55, shoulder 0.75, arm 2.8, margin 0.25).
# A passage is sized for the camera, not the capsule: the shoulder offset is applied after the spring arm, so the
# camera sits SHOULDER m to one side of the player and needs CAMERA_CLEAR m of air beyond that.
BODY_RADIUS = 0.35  # the player and a zombie
SHOULDER = 0.75
CAMERA_CLEAR = 0.1
MIN_PASSAGE = 2 * (SHOULDER + CAMERA_CLEAR)  # 1.7 m: a centred player keeps both shoulder views free

# Widths of the places the camera has to get through (metres). The first draft had 1.4 / 1.6 / 1.8.
CAR_LENGTH = 4.5
CAR_WIDTH = 1.9
CAR_GAP = 1.8  # between the cars of a row
REAR_EXIT = 2.0  # the stand's rear exits, the generator cage's openings
RAMP_WIDTH = 2.0
RAMP_X = -4.8  # the ramp's centre line, along the booth's west wall (x -6)
MIDWAY_LINK = 4.5  # the midway's links to the yard and the back lot
MIDWAY_LINK_Z = 20.0
# The lot's outer walls are higher than the tallest platform beside them (a car roof, 1.65 m) plus a full jump (the
# player's 1.1 m, PlayerTuning.jump_height) plus a margin, so nobody leaves the map from a roof (docs/design/map.md).
PERIMETER_H = 3.0
# The breaches in the field's fence: a gap of BREACH_WIDTH closed by BOARDS boards, each BOARD_PITCH above the last (from
# the ground to the fence's top, so nobody jumps out over the boards), and
# an apron outside (APRON_DEPTH deep, APRON_WIDTH wide, walled in) where the dead stand before they tear the boards off.
# The ids are the rules' (`BarricadeTuning.ids`); the number of boards is `BarricadeTuning.boards`.
BREACH_WIDTH = 4.0
BOARDS = 5
BOARD_FIRST = 0.3  # the middle of the lowest board; the boards are 0.45 m tall, so five fill the gap to its top
BOARD_PITCH = 0.6
APRON_DEPTH = 8.0
APRON_WIDTH = 12.0
SPAWN_OUTSIDE = 4.0  # the dead appear this far outside the fence line
# The breaker posts: (circuit, the shop door of the area it lights, where, the way its front faces as (x, z)).
SWITCHES = [
    ("screen_lot", "", (0.0, 0.0, -46.2), (0.0, 1.0)),  # behind the players' spawns, in the avenue below the screen
    ("concession", "door_concession", (8.5, 0.0, -4.6), (0.0, -1.0)),  # on the stand's front wall, field side
    ("booth", "door_booth", (4.6, 0.0, 21.5), (0.0, -1.0)),  # on the booth's north wall, midway side
    ("back_lot", "door_back_lot", (-35.5, 0.0, -4.6), (0.0, -1.0)),  # on the field's south fence, by the gate
]
SCREEN_AFTERGLOW = 0.3  # the screen still glows when the generator is dead (docs/design/map.md, Light and dark)

# The night look (docs/research/night-environment.md). Compatibility renderer only: a sky shader, exponential fog,
# a flat ambient colour and one moon light with no shadows (the web build is WebGL2).
MOON_TOWARDS = (0.30, 0.62, -0.72)  # the direction to the moon: over the screen, so the player faces it at the start
MOON_LIGHT = "#9db4e8"
MOON_ENERGY = 0.36
SKY_ZENITH = "#050a1f"
SKY_MID = "#0b1636"
SKY_HORIZON = "#1a2a5a"
SKY_GROUND = "#0a1330"
AMBIENT = "#4d5c8c"
AMBIENT_ENERGY = 0.24
TONEMAP_EXPOSURE = 1.0
FOG = "#16224a"
FOG_DENSITY = 0.013

# Materials per surface: game/assets/lot/materials/<id>.tres, written by tools/world/build_lot_textures.py (the
# style bible's palette tinting a flat-toned pattern, projected in world space). Every id used below is listed here.
MATS = [
    "outskirts", "field_ground", "field_struct", "field_fence", "screen_face",
    "concession_ground", "concession_wall", "concession_roof", "concession_prop",
    "midway_ground", "midway_wall", "booth_ground", "booth_wall", "booth_prop",
    "yard_ground", "yard_wall", "yard_prop", "yard_gen", "backlot_ground", "backlot_wall", "backlot_prop", "neon",
    "road_ground", "road_wall", "road_kiosk", "road_line", "door", "roadblock", "breach_ground", "line_paint",
    "plaque", "ammo_crate", "ammo_band",
]  # fmt: skip
# Parking lines: a painted stripe between neighbouring stalls of a row, as long as a stall (one MultiMesh, one draw).
LINE_WIDTH = 0.12
LINE_LENGTH = 5.0

lines: list[str] = []
resources: list[str] = []  # sub-resources made while the nodes are written, put before the first node
node_names: set[str] = set()


def shop_doors() -> dict[str, tuple[int, str]]:
    """Shop id -> (price, the door it requires or "") for every item in the rules' tuning that has a price."""
    found: dict[str, tuple[int, str]] = {}
    for block_text in re.split(r"\n\n", TUNING.read_text(encoding="utf-8")):
        item = re.search(r'^id = &"(door_\w+)"$', block_text, re.MULTILINE)
        price = re.search(r"^price = (\d+)$", block_text, re.MULTILINE)
        needs = re.search(r'^requires = &"(\w+)"$', block_text, re.MULTILINE)
        if item and price:
            found[item.group(1)] = (int(price.group(1)), needs.group(1) if needs else "")
    return found


def moon_transform() -> str:
    """The Moon light's transform: it shines along -Z, so its Z axis points at the moon."""
    z = tuple(c / math.sqrt(sum(d * d for d in MOON_TOWARDS)) for c in MOON_TOWARDS)
    x = (z[2], 0.0, -z[0])  # up x z, then normalised
    xl = math.hypot(x[0], x[2])
    x = (x[0] / xl, 0.0, x[2] / xl)
    y = (z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0])
    rows = (x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2])
    return "Transform3D({}, 0, 20, 0)".format(", ".join(f"{v:.4f}" for v in rows))


def night_environment_resources() -> list[str]:
    """The sky material, the sky and the environment (docs/research/night-environment.md): one place for the look."""
    moon = tuple(round(c / math.sqrt(sum(d * d for d in MOON_TOWARDS)), 4) for c in MOON_TOWARDS)
    out = [
        '[sub_resource type="ShaderMaterial" id="night_sky_material"]',
        'shader = ExtResource("night_sky")',
        f"shader_parameter/moon_direction = {vec(moon)}",
        f"shader_parameter/zenith_color = {color(SKY_ZENITH)}",
        f"shader_parameter/mid_color = {color(SKY_MID)}",
        f"shader_parameter/horizon_color = {color(SKY_HORIZON)}",
        f"shader_parameter/ground_color = {color(SKY_GROUND)}",
        "",
        '[sub_resource type="Sky" id="night_sky_resource"]',
        'sky_material = SubResource("night_sky_material")',
        "radiance_size = 0",
        "",
        '[sub_resource type="Environment" id="night"]',
        "background_mode = 2",
        'sky = SubResource("night_sky_resource")',
        "ambient_light_source = 2",
        f"ambient_light_color = {color(AMBIENT)}",
        f"ambient_light_energy = {AMBIENT_ENERGY:g}",
        "tonemap_mode = 2",
        f"tonemap_exposure = {TONEMAP_EXPOSURE:g}",
        "fog_enabled = true",
        f"fog_light_color = {color(FOG)}",
        f"fog_density = {FOG_DENSITY:g}",
        "fog_sky_affect = 0",
        "",
    ]
    return out


def vec(v: tuple[float, float, float]) -> str:
    return "Vector3({:g}, {:g}, {:g})".format(*v)


def color(hexstr: str) -> str:
    h = hexstr.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return f"Color({r:.3f}, {g:.3f}, {b:.3f}, 1)"


def xform(pos: tuple[float, float, float], rot_y_deg: float = 0.0) -> str:
    c, s = math.cos(math.radians(rot_y_deg)), math.sin(math.radians(rot_y_deg))
    basis = f"{c:.4f}, 0, {s:.4f}, 0, 1, 0, {-s:.4f}, 0, {c:.4f}"
    return f"Transform3D({basis}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})"


def node(name: str, kind: str, parent: str | None, props: dict[str, str] | None = None, extra: str = "") -> str:
    key = name if parent in (None, ".") else f"{parent}/{name}"
    full = f"{parent}/{name}" if parent not in (None, ".") else name
    assert full not in node_names, f"duplicate node {full}"
    node_names.add(full)
    head = f'[node name="{name}" type="{kind}"'
    if parent is not None:
        head += f' parent="{parent}"'
    lines.append(head + extra + "]")
    for k, v in (props or {}).items():
        lines.append(f"{k} = {v}")
    lines.append("")
    return key


def group(name: str, parent: str) -> str:
    node(name, "Node3D", parent)
    return name if parent == "." else f"{parent}/{name}"


def lamps(parent: str, circuit: str, name: str = "Lamps") -> str:
    """A group of lamps on one circuit. Every light below it takes the circuit id from this node's metadata
    (`LotLamps`): a generator circuit, `mains` (wired to the generator, no switch) or `battery` (not the generator's)."""
    node(name, "Node3D", parent, {"metadata/circuit": f'"{circuit}"'})
    return f"{parent}/{name}"


counter = {"n": 0}


def box(
    parent: str,
    name: str,
    size: tuple[float, float, float],
    pos: tuple[float, float, float],
    mat: str,
    rot_y: float = 0.0,
    collide: bool = True,
) -> None:
    if name in drivein_props.REPLACED:  # a drive-in prop stands here, with this block's collision
        return
    props = {"transform": xform(pos, rot_y)}
    if collide:
        props["use_collision"] = "true"
    props["size"] = vec(size)
    props["material"] = f'ExtResource("{mat}")'
    node(name, "CSGBox3D", parent, props)


def block(parent: str, name: str, x0: float, x1: float, z0: float, z1: float, h: float, mat: str, y0: float = 0.0):
    """A solid axis-aligned box from corner coordinates."""
    box(parent, name, (x1 - x0, h, z1 - z0), ((x0 + x1) / 2, y0 + h / 2, (z0 + z1) / 2), mat)


def floor_tiles(parent: str, prefix: str, x0: float, x1: float, z0: float, z1: float, mat: str, tile: float = 24.0):
    """Ground in tiles of at most `tile` metres: Compatibility caps the lights per mesh, so one big floor goes dark."""
    nx, nz = math.ceil((x1 - x0) / tile), math.ceil((z1 - z0) / tile)
    for i in range(nx):
        for j in range(nz):
            xa, xb = x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx
            za, zb = z0 + (z1 - z0) * j / nz, z0 + (z1 - z0) * (j + 1) / nz
            box(parent, f"{prefix}{i}_{j}", (xb - xa, 0.4, zb - za), ((xa + xb) / 2, -0.2, (za + zb) / 2), mat)


def wall(
    parent: str,
    name: str,
    axis: str,
    fixed: float,
    a0: float,
    a1: float,
    height: float,
    mat: str,
    gaps: list[tuple[float, float, float, float]] | None = None,
    thick: float = 0.4,
    y0: float = 0.0,
) -> None:
    """A wall along `axis` ('x' or 'z') at the other coordinate `fixed`, from a0 to a1, with doorways and windows.

    A gap is (centre, width, bottom, top) in metres above the wall's base. Everything is plain boxes.
    """
    pieces: list[tuple[float, float, float, float]] = []  # (from, to, bottom, top)
    cursor = a0
    for centre, width, bottom, top in sorted(gaps or []):
        lo, hi = centre - width / 2, centre + width / 2
        if lo > cursor:
            pieces.append((cursor, lo, 0.0, height))
        if bottom > 0:
            pieces.append((lo, hi, 0.0, bottom))
        if top < height:
            pieces.append((lo, hi, top, height))
        cursor = hi
    if cursor < a1:
        pieces.append((cursor, a1, 0.0, height))
    for i, (p0, p1, b, t) in enumerate(pieces):
        if axis == "x":
            block(parent, f"{name}{i}", p0, p1, fixed - thick / 2, fixed + thick / 2, t - b, mat, y0 + b)
        else:
            block(parent, f"{name}{i}", fixed - thick / 2, fixed + thick / 2, p0, p1, t - b, mat, y0 + b)


def omni(
    parent: str, name: str, pos, energy: float, rng: float, col: str, powered: bool = True, afterglow: float = 0.0
) -> None:
    """An omni light in the `powered_light` group. `afterglow` is the fraction of its energy it keeps when its circuit
    is dark (the screen's glow); it lights nothing for the dead, it is only seen."""
    props = {
        "transform": xform(pos),
        "light_color": color(col),
        "light_energy": f"{energy:g}",
        "omni_range": f"{rng:g}",
    }
    if afterglow:
        props["metadata/afterglow"] = f"{afterglow:g}"
    node(name, "OmniLight3D", parent, props, ' groups=["powered_light"]' if powered else "")


def spot(parent: str, name: str, pos, yaw: float, pitch: float, energy: float, rng: float, angle: float, col: str):
    # Pitch is applied by rotating the basis about the local X axis after yaw: write it as an explicit basis.
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    # R = Ry(yaw) * Rx(pitch); rows of the matrix
    rows = [
        (cy, sy * sp, sy * cp),
        (0, cp, -sp),
        (-sy, cy * sp, cy * cp),
    ]
    flat = ", ".join(f"{v:.4f}" for r in rows for v in r)
    t = f"Transform3D({flat}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})"
    props = {
        "transform": t,
        "light_color": color(col),
        "light_energy": f"{energy:g}",
        "spot_range": f"{rng:g}",
        "spot_angle": f"{angle:g}",
    }
    node(name, "SpotLight3D", parent, props, ' groups=["powered_light"]')


def label(parent: str, name: str, text: str, pos, size: int = 220, pixel: float = 0.04) -> None:
    props = {
        "transform": f"Transform3D(1, 0, 0, 0, 0, 1, 0, -1, 0, {pos[0]:g}, {pos[1]:g}, {pos[2]:g})",
        "visible": "false",
        "pixel_size": f"{pixel:g}",
        "no_depth_test": "true",
        "modulate": "Color(1, 1, 1, 1)",
        "outline_modulate": "Color(0, 0, 0, 1)",
        "outline_size": "48",
        "text": f'"{text}"',
        "font_size": str(size),
    }
    node(name, "Label3D", parent, props, ' groups=["area_labels"]')


def marker(parent: str, name: str, pos, yaw: float = 0.0) -> None:
    node(name, "Marker3D", parent, {"transform": xform(pos, yaw)})


def heading(dx: float, dz: float) -> float:
    """The yaw in degrees that makes a node face (dx, dz) with its -Z axis, as Godot does."""
    return math.degrees(math.atan2(-dx, -dz))


def probe(name: str, pos, dx: float, dz: float) -> None:
    """A place the camera must get through: a marker facing the way a player walks through it."""
    marker("CameraProbes", name, pos, heading(dx, dz))


def painted_lines(parent: str, name: str, mat: str, size: tuple[float, float], at: list[tuple[float, float, float]]):
    """Stripes of paint on the ground, (x, z, yaw) each, drawn as one MultiMesh: one draw call, no collision."""
    mesh_id, multi_id = f"{name}_mesh", f"{name}_multi"
    floats: list[str] = []
    for x, z, yaw in at:
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        floats += [
            f"{c:.4f}",
            "0",
            f"{s:.4f}",
            f"{x:.3f}",
            "0",
            "1",
            "0",
            "0.012",
            f"{-s:.4f}",
            "0",
            f"{c:.4f}",
            f"{z:.3f}",
        ]
    resources.append(f'[sub_resource type="BoxMesh" id="{mesh_id}"]')
    resources.append(f'material = ExtResource("{mat}")')
    resources.append(f"size = Vector3({size[0]:g}, 0.02, {size[1]:g})")
    resources.append("")
    resources.append(f'[sub_resource type="MultiMesh" id="{multi_id}"]')
    resources.append("transform_format = 1")
    resources.append(f"instance_count = {len(at)}")
    resources.append(f'mesh = SubResource("{mesh_id}")')
    resources.append(f"buffer = PackedFloat32Array({', '.join(floats)})")
    resources.append("")
    node(name, "MultiMeshInstance3D", parent, {"multimesh": f'SubResource("{multi_id}")'})


def instance(parent: str, name: str, res: str, pos, rot_y: float = 0.0) -> None:
    lines.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{res}")]')
    lines.append(f"transform = {xform(pos, rot_y)}")
    lines.append("")
    node_names.add(f"{parent}/{name}")


def breach(field: str, tag: str, bx: float, bz: float) -> None:
    """The boards across one gap of the fence, and the walled apron outside it where the dead gather.

    The Barricade node stands in the gap on the fence line with its +Z pointing into the field (`Field/Breach*`); the
    boards are its children. The apron is ground the navigation mesh needs (the dead walk in over it), closed on three
    sides so nobody walks off the map through a torn fence.
    """
    ix, iz = (1.0, 0.0) if bx == -62 else (-1.0, 0.0) if bx == 62 else (0.0, 1.0)
    rot = math.degrees(math.atan2(ix, iz))
    props = {
        "transform": xform((bx, 0, bz), rot),
        "script": 'ExtResource("barricade")',
        "metadata/barricade_id": f'"{tag.lower()}"',
    }
    node(f"Breach{tag}", "Node3D", field, props)
    for i in range(BOARDS):
        instance(
            f"{field}/Breach{tag}", f"Board{i + 1}", "board", (0.0, BOARD_FIRST + i * BOARD_PITCH, 0.03 * (-1) ** i)
        )
    # The apron: out from the fence line along -inward.
    ox, oz = -ix, -iz
    half = APRON_WIDTH / 2
    cx, cz = bx + ox * APRON_DEPTH / 2, bz + oz * APRON_DEPTH / 2
    if ox != 0:
        size = (APRON_DEPTH, 0.4, APRON_WIDTH)
        box(field, f"Apron{tag}", size, (cx, -0.2, cz), "breach_ground")
        end = bx + ox * APRON_DEPTH
        block(
            field,
            f"Apron{tag}End",
            min(end, end + ox * 0.4),
            max(end, end + ox * 0.4),
            bz - half,
            bz + half,
            PERIMETER_H,
            "field_fence",
        )
        for side, dz in (("A", -half), ("B", half)):
            block(
                field,
                f"Apron{tag}Side{side}",
                min(bx, end),
                max(bx, end),
                bz + dz - 0.2,
                bz + dz + 0.2,
                PERIMETER_H,
                "field_fence",
            )
    else:
        size = (APRON_WIDTH, 0.4, APRON_DEPTH)
        box(field, f"Apron{tag}", size, (cx, -0.2, cz), "breach_ground")
        end = bz + oz * APRON_DEPTH
        block(
            field,
            f"Apron{tag}End",
            bx - half,
            bx + half,
            min(end, end + oz * 0.4),
            max(end, end + oz * 0.4),
            PERIMETER_H,
            "field_fence",
        )
        for side, dx in (("A", -half), ("B", half)):
            block(
                field,
                f"Apron{tag}Side{side}",
                bx + dx - 0.2,
                bx + dx + 0.2,
                min(bz, end),
                max(bz, end),
                PERIMETER_H,
                "field_fence",
            )


def door(name: str, label_at) -> None:
    """A purchase door: a group that holds its slabs; the shop item, its price and the item it needs are metadata.

    One purchase removes every slab of the group, so an area with two ways in (a gate in the field's fence and a
    link from the midway) still has exactly one door.
    """
    item = DOOR_ITEMS[name]
    cost, requires = shop_doors()[item]
    props = {"metadata/cost": str(cost), "metadata/shop_id": f'"{item}"', "metadata/requires": f'"{requires}"'}
    node(name, "Node3D", "Doors", props)
    label(f"Doors/{name}", "Label", f"{cost}", label_at, 100)


def shop_spot(name: str, kind: str, shop_id: str, pos, yaw: float = 0.0, crane_spot: int | None = None) -> None:
    """Where a player stands to buy: a marker in `ShopSpots`. `kind` is wall, crane or ammo; `shop_id` is the shop item
    (empty for ammunition: the lot sells the rounds of the weapon in hand). A crane marker names its place in the
    rules' list of crane spots (`crane_spot`, an index into `spot_doors` of the tuning's crane)."""
    props = {"transform": xform(pos, yaw), "metadata/kind": f'"{kind}"', "metadata/shop_id": f'"{shop_id}"'}
    if crane_spot is not None:
        props["metadata/crane_spot"] = str(crane_spot)
    node(name, "Marker3D", "ShopSpots", props)


def sign(parent: str, name: str, text: str, pos, yaw: float, size: int = 72) -> None:
    """Text that is always on: the name and price on a plaque or a locker. The prices are the shop's, read at run time
    by the HUD; this is only the name."""
    props = {
        "transform": xform(pos, yaw),
        "pixel_size": "0.006",
        "text": f'"{text}"',
        "font_size": str(size),
        "outline_size": "24",
        "modulate": "Color(0.1, 0.07, 0.02, 1)",
        "outline_modulate": "Color(1, 0.9, 0.6, 1)",
    }
    node(name, "Label3D", parent, props)


def ammo_locker(name: str, centre: tuple[float, float], yaw: float = 0.0) -> None:
    """A green crate with a yellow band: the lot's ammunition. The spot is half a metre in front of it."""
    x, z = centre
    rad = math.radians(yaw)
    fx, fz = math.sin(rad), math.cos(rad)  # the crate's front (+Z at yaw 0)
    box("ShopProps", name, (1.2, 1.0, 0.7), (x, 0.5, z), "ammo_crate", yaw)
    box("ShopProps", f"{name}Band", (1.24, 0.18, 0.74), (x, 0.82, z), "ammo_band", yaw, collide=False)
    sign("ShopProps", f"{name}Sign", "AMMO", (x + fx * 0.37, 0.5, z + fz * 0.37), yaw, 60)
    shop_spot(f"Spot{name}", "ammo", "", (x + fx * 1.1, 0, z + fz * 1.1), yaw)


def slab(door_name: str, tag: str, centre, width: float, height: float, axis: str) -> None:
    size = (width, height, 0.3) if axis == "x" else (0.3, height, width)
    box(f"Doors/{door_name}", tag, size, (centre[0], height / 2, centre[1]), "door")


# ---------------------------------------------------------------------------------------------------------------
def build() -> None:
    lines.append("[gd_scene format=3]")
    lines.append("")
    lines.append('[ext_resource type="PackedScene" path="res://world/drive_in/car.tscn" id="car"]')
    lines.append('[ext_resource type="PackedScene" path="res://world/drive_in/lamp_post.tscn" id="lamp"]')
    lines.append('[ext_resource type="Script" path="res://world/drive_in/lot_doors.gd" id="doors"]')
    lines.append('[ext_resource type="Shader" path="res://world/drive_in/night_sky.gdshader" id="night_sky"]')
    lines.append('[ext_resource type="Script" path="res://world/drive_in/barricade.gd" id="barricade"]')
    lines.append('[ext_resource type="PackedScene" path="res://world/drive_in/board.tscn" id="board"]')
    lines.append('[ext_resource type="PackedScene" path="res://world/drive_in/circuit_switch.tscn" id="switch"]')
    lines.append(f'[ext_resource type="PackedScene" path="{lot_props.WRECK}" id="wreck"]')
    lines.extend(lot_props.ext_resources())
    lines.extend(drivein_props.ext_resources())
    lines.append("")
    for mid in MATS:
        lines.append(f'[ext_resource type="Material" path="res://assets/lot/materials/{mid}.tres" id="{mid}"]')
    lines.append("")
    lines.extend(night_environment_resources())
    node("DriveInGreybox", "Node3D", None)
    lines.pop()  # drop the blank line so the root gets its metadata below
    lines.append("")

    lighting = group("Lighting", ".")
    node("WorldEnvironment", "WorldEnvironment", lighting, {"environment": 'SubResource("night")'})
    node(
        "Moon",
        "DirectionalLight3D",
        lighting,
        {
            "transform": moon_transform(),
            "light_color": color(MOON_LIGHT),
            "light_energy": f"{MOON_ENERGY:g}",
        },
    )

    box(".", "Outskirts", (320, 0.4, 320), (0, -0.7, 0), "outskirts")

    # --- Field: the screen, the car rows, the first lit ground --------------------------------------------------
    field = group("Field", ".")
    floor_tiles(field, "Ground", -62, 62, -52, -4, "field_ground")
    screen_c = (0.0, -52.0)
    box(field, "ScreenPanel", (32, 12, 1.2), (0, 10, -48), "screen_face")
    box(field, "ScreenFrame", (33.6, 13.6, 0.8), (0, 10, -48.7), "field_struct")
    for sx in (-10, 10):
        box(field, f"ScreenLeg{sx}".replace("-", "N"), (1.4, 4.2, 1.6), (sx, 2.1, -48), "field_struct")
    for sx in (-14, 14):
        box(field, f"ScreenStay{sx}".replace("-", "N"), (0.8, 0.8, 7), (sx, 3.0, -52.8), "field_struct")
    # Perimeter fence (PERIMETER_H) with a gap at each breach, where the dead come in. Boards (a Barricade) close
    # each gap, and a walled apron outside it is where they stand before they tear the boards off. The fence between
    # the field and the yard and back lot is 2.4 m.
    fence_h = 2.4
    breaches = [("NW", -62, -46), ("NE", 62, -46), ("W", -62, -22), ("E", 62, -22), ("N", -36, -52), ("N2", 36, -52)]
    fence_w = [(bz, BREACH_WIDTH, 0, PERIMETER_H) for (_, bx, bz) in breaches if bx == -62]
    fence_e = [(bz, BREACH_WIDTH, 0, PERIMETER_H) for (_, bx, bz) in breaches if bx == 62]
    fence_n = [(bx, BREACH_WIDTH, 0, PERIMETER_H) for (_, bx, bz) in breaches if bz == -52]
    wall(field, "FenceN", "x", -52, -62, 62, PERIMETER_H, "field_fence", fence_n)
    wall(field, "FenceW", "z", -62, -52, -4, PERIMETER_H, "field_fence", fence_w)
    wall(field, "FenceE", "z", 62, -52, -4, PERIMETER_H, "field_fence", fence_e)
    for tag, bx, bz in breaches:
        breach(field, tag, bx, bz)
    # Fence between the field and the yard / back lot, with the two purchase gates (doors listed below).
    wall(field, "FenceS_W", "x", -4, -62, -10, fence_h, "field_fence", [(-40, 4, 0, 2.6)])
    wall(field, "FenceS_E", "x", -4, 10, 62, fence_h, "field_fence", [(40, 4, 0, 2.6)])

    rows = group("Rows", field)
    rng = random.Random(1958)
    n_cars = 0
    car_slots: list[tuple[int, float, float]] = []  # (row, radius, angle) of every parked car, for the speaker posts
    gaps: dict[int, list[tuple[float, float]]] = {}  # row -> (x, z) midpoints of two neighbouring cars' gap
    stall_lines: set[tuple[float, float]] = set()  # (row radius, angle) of a painted line beside a stall
    for ri, radius in enumerate((14.0, 21.0, 28.0, 35.0, 42.0), start=1):
        row = group(f"Row{ri}", rows)
        step = math.degrees((CAR_WIDTH + CAR_GAP) / radius)
        a = -80.0
        last_placed = None
        while a <= 80.0:
            x = screen_c[0] + radius * math.sin(math.radians(a))
            z = screen_c[1] + radius * math.cos(math.radians(a))
            aisle = abs(x) < 3.6 or 20.0 < abs(x) < 25.0
            if not aisle and abs(x) < 56 and z < -9:
                for edge in (a - step / 2, a + step / 2):
                    stall_lines.add((round(radius, 3), round(edge, 6)))
            if not aisle and abs(x) < 56 and z < -9 and rng.random() > 0.12:
                n_cars += 1
                instance(row, f"Car{n_cars:02d}", "car", (x, 0, z), a)
                car_slots.append((ri, radius, a))
                if last_placed is not None and abs(a - last_placed - step) < 1e-6:
                    am = math.radians(a - step / 2)
                    gaps.setdefault(ri, []).append(
                        (screen_c[0] + radius * math.sin(am), screen_c[1] + radius * math.cos(am))
                    )
                last_placed = a
            a += step
    painted_lines(
        field,
        "ParkingLines",
        "line_paint",
        (LINE_WIDTH, LINE_LENGTH),
        [
            (screen_c[0] + r * math.sin(math.radians(ang)), screen_c[1] + r * math.cos(math.radians(ang)), ang)
            for r, ang in sorted(stall_lines)
        ],
    )
    # Cover on the open flanks: a playground to the west, a picnic shelter to the east, a few wrecks.
    props = group("Props", field)
    block(props, "JungleGymA", -53, -47, -40, -36, 2.4, "field_struct")
    block(props, "JungleGymB", -46, -43, -34, -31, 1.4, "field_struct")
    block(props, "SwingFrame", -52, -44, -28, -27.6, 2.6, "field_struct")
    block(props, "ShelterRoof", 44, 52, -34, -28, 0.3, "field_struct", 3.2)
    for i, (px, pz) in enumerate([(44, -34), (52, -34), (44, -28), (52, -28)], start=1):
        block(props, f"ShelterPost{i}", px - 0.2, px + 0.2, pz - 0.2, pz + 0.2, 3.2, "field_struct")
    block(props, "PicnicTable", 46, 50, -32, -30, 0.9, "field_struct")
    for i, (px, pz, ry) in enumerate([(-52, -14, 70), (54, -14, 100), (40, -44, 20), (-38, -12, 95)], start=1):
        instance(props, f"Wreck{i}", "wreck", (px, 0, pz), ry)
    lamps_f = lamps(field, "screen_lot")
    field_lamps = [(-4.6, -34), (4.6, -34), (-4.6, -22), (4.6, -22), (-4.6, -10), (4.6, -10), (-22.5, -28), (22.5, -28)]
    for i, (lx, lz) in enumerate(field_lamps, start=1):
        instance(lamps_f, f"Lamp{i}", "lamp", (lx, 0, lz))
    omni(lamps_f, "ScreenGlow", (0, 7, -44), 1.4, 34, "#aebfe8", afterglow=SCREEN_AFTERGLOW)
    spawns = group("PlayerSpawns", field)
    for i, sx in enumerate((-6, -2, 2, 6), start=1):
        marker(spawns, f"Player{i}", (sx, 0, -43))
    zs = group("ZombieSpawns", field)
    for tag, bx, bz in breaches:
        # Outside the fence, on the apron: the dead come to the boards from the dark.
        at = (bx + math.copysign(SPAWN_OUTSIDE, bx), 0, bz) if abs(bx) == 62 else (bx, 0, bz - SPAWN_OUTSIDE)
        node(
            f"Spawn{tag}",
            "Marker3D",
            zs,
            {"transform": xform(at), "metadata/barricade_id": f'"{tag.lower()}"'},
        )
    label(field, "Label", "1  SCREEN FIELD  (start)", (-26, 0.6, -13), 130)
    label(field, "LabelScreen", "SCREEN", (0, 0.6, -50), 110)

    # --- Concession stand ----------------------------------------------------------------------------------------
    con = group("Concession", ".")
    floor_tiles(con, "Floor", -10, 10, -4, 8, "concession_ground", 24)
    wall(
        con, "WallN", "x", -4, -10, 10, 4.0, "concession_wall",
        [(0, 3, 0, 2.6), (-6, 2.2, 1.0, 2.4), (6, 2.2, 1.0, 2.4)],
    )  # fmt: skip
    wall(con, "WallS", "x", 8, -10, 10, 4.0, "concession_wall", [(-5, REAR_EXIT, 0, 2.4), (5, REAR_EXIT, 0, 2.4)])
    wall(con, "WallW", "z", -10, -4, 8, 4.0, "concession_wall")
    wall(con, "WallE", "z", 10, -4, 8, 4.0, "concession_wall")
    box(con, "Roof", (20.8, 0.3, 12.8), (0, 4.15, 2), "concession_roof")
    block(con, "Counter", -5, 5, 1, 3, 1.0, "concession_prop")
    block(con, "PrizeCrane", -9.4, -7.4, 4, 6, 2.4, "concession_prop")
    block(con, "SodaFountain", 7.0, 9.4, 4.4, 5.4, 1.6, "concession_prop")
    cl = lamps(con, "concession")
    omni(cl, "InteriorW", (-5, 3.3, 3), 1.6, 9, "#ffb866")
    omni(cl, "InteriorE", (5, 3.3, 3), 1.6, 9, "#ffb866")
    omni(cl, "InteriorN", (0, 3.3, -2), 1.4, 8, "#ffb866")
    label(con, "Label", "2 CONCESSION", (0, 4.6, 2), 80)

    # --- Midway: the courtyard behind the stand, the hub the other areas hang off ------------------------------
    mid = group("Midway", ".")
    floor_tiles(mid, "Ground", -16, 16, 8, 38, "midway_ground")
    floor_tiles(mid, "AlleyW", -16, -10, -4, 8, "midway_ground")
    floor_tiles(mid, "AlleyE", 10, 16, -4, 8, "midway_ground")
    wall(mid, "FenceW", "z", -16, -4, 38, 2.6, "midway_wall", [(MIDWAY_LINK_Z, MIDWAY_LINK, 0, 2.6)])
    wall(mid, "FenceE", "z", 16, -4, 38, 2.6, "midway_wall", [(MIDWAY_LINK_Z, MIDWAY_LINK, 0, 2.6)])
    wall(mid, "AlleyEndW", "x", -4, -16, -10, 2.6, "midway_wall")
    wall(mid, "AlleyEndE", "x", -4, 10, 16, 2.6, "midway_wall")
    # Dumpsters, crate stacks: the kit's props (lot_props.DRESSING).
    ml = lamps(mid, "concession")
    omni(ml, "Court", (-10, 3.6, 14), 1.2, 9, "#ffd9a0")
    omni(ml, "Court2", (11, 3.6, 36), 1.0, 9, "#ffd9a0")
    mz = group("ZombieSpawns", mid)
    marker(mz, "SpawnSW", (-14, 0, 36))
    marker(mz, "SpawnSE", (14, 0, 36))
    label(mid, "Label", "3  MIDWAY", (0, 0.6, 14), 130)

    # --- Projection booth ------------------------------------------------------------------------------------------
    booth = group("ProjectionBooth", ".")
    floor_tiles(booth, "Floor", -6, 6, 22, 32, "booth_ground", 24)
    wall(booth, "WallS", "x", 32, -6, 6, 7.4, "booth_wall")
    wall(booth, "WallW", "z", -6, 22, 32, 7.4, "booth_wall")
    wall(booth, "WallE", "z", 6, 22, 32, 7.4, "booth_wall")
    # North wall: the purchase door below, the projector port above the upper floor.
    wall(booth, "WallN", "x", 22, -6, 6, 3.6, "booth_wall", [(0, 3, 0, 2.6)])
    wall(booth, "WallNUpper", "x", 22, -6, 6, 3.8, "booth_wall", [(0, 5, 1.0, 2.6)], y0=3.6)
    box(booth, "UpperFloor", (9.8, 0.3, 10), (1.1, 3.75, 27), "booth_wall")
    # The ramp climbs to the south and ends at its top beside the upper floor; the landing joins the two.
    box(booth, "Landing", (2.4, 0.3, 1.4), (RAMP_X, 3.65, 31.2), "booth_wall")
    box(booth, "Roof", (12.8, 0.3, 10.8), (0, 7.55, 27), "booth_wall")
    # The ramp up: RAMP_WIDTH wide along the west wall, rising 3.6 m over 7.6 m.
    ramp_len = math.hypot(7.6, 3.6)
    ramp_pitch = math.degrees(math.atan2(3.6, 7.6))
    cp, sp = math.cos(math.radians(ramp_pitch)), math.sin(math.radians(ramp_pitch))
    ramp = f"Transform3D(1, 0, 0, 0, {cp:.4f}, {sp:.4f}, 0, {-sp:.4f}, {cp:.4f}, {RAMP_X}, 1.75, 27)"
    node(
        "Ramp", "CSGBox3D", booth,
        {"transform": ramp, "use_collision": "true", "size": vec((RAMP_WIDTH, 0.3, ramp_len)), "material": 'ExtResource("booth_prop")'},
    )  # fmt: skip
    block(booth, "ReCutMachine", 2, 5, 27, 29.4, 1.8, "booth_prop")
    block(booth, "FilmRacks", -3.4, -1, 30, 31.6, 2.2, "booth_prop")
    block(booth, "Projector", -1.0, 1.0, 24.5, 26.0, 1.3, "booth_prop", 4.05)
    bl = lamps(booth, "booth")
    spot(bl, "ProjectorBeam", (0, 5.4, 22.3), 180, -5.0, 6.0, 100, 7, "#e8f0ff")
    omni(bl, "Lower", (0, 3.0, 27), 1.0, 8, "#c9a8ff")
    omni(bl, "Upper", (0, 6.6, 27), 0.9, 7, "#c9a8ff")
    label(booth, "Label", "4 BOOTH", (0, 7.9, 27), 100)

    # --- Generator yard (east) ----------------------------------------------------------------------------------------
    yard = group("GeneratorYard", ".")
    floor_tiles(yard, "Ground", 16, 62, -4, 38, "yard_ground")
    wall(yard, "FenceE", "z", 62, -4, 38, PERIMETER_H, "yard_wall")
    wall(yard, "FenceS", "x", 38, 16, 62, 2.4, "yard_wall")
    # The generator cage: 8 x 6 m, open on the west and east sides, roofless.
    wall(yard, "CageN", "x", 15, 36, 44, 3.0, "yard_wall")
    wall(yard, "CageS", "x", 21, 36, 44, 3.0, "yard_wall")
    wall(yard, "CageW", "z", 36, 15, 21, 3.0, "yard_wall", [(18, REAR_EXIT, 0, 2.4)])
    wall(yard, "CageE", "z", 44, 15, 21, 3.0, "yard_wall", [(18, REAR_EXIT, 0, 2.4)])
    box(yard, "Generator", (3.2, 1.8, 1.6), (40, 0.9, 18), "yard_gen")
    for i, ty in enumerate((6, 12)):
        node(
            f"FuelTank{i + 1}", "CSGCylinder3D", yard,
            {"transform": xform((55, 1.7, ty)), "use_collision": "true", "radius": "1.4", "height": "3.4",
             "sides": "16", "material": 'ExtResource("yard_prop")'},
        )  # fmt: skip
    # Containers, pallets, the drum row: the kit's props (lot_props.DRESSING).
    yl = lamps(yard, "mains")
    for i, (lx, lz) in enumerate([(35, 12), (45, 12), (35, 24), (45, 24)], start=1):
        instance(yl, f"WorkLamp{i}", "lamp", (lx, 0, lz))
    omni(yl, "GeneratorGlow", (40, 2.4, 18), 1.4, 8, "#f0e26a")
    yz = group("ZombieSpawns", yard)
    marker(yz, "SpawnNE", (60, 0, -2))
    marker(yz, "SpawnSE", (60, 0, 36))
    marker(yz, "SpawnS", (28, 0, 36))
    label(yard, "Label", "5  GENERATOR YARD", (39, 0.6, 31), 110)

    # --- Back lot (west) --------------------------------------------------------------------------------------------
    back = group("BackLot", ".")
    floor_tiles(back, "Ground", -62, -16, -4, 38, "backlot_ground")
    wall(back, "FenceW", "z", -62, -4, 38, PERIMETER_H, "backlot_wall")
    wall(back, "FenceS", "x", 38, -62, -16, 2.4, "backlot_wall")
    wrecks = group("Wrecks", back)
    n = 0
    for row_z in (6, 14, 30):
        x = -58.0
        while x < -22:
            if rng.random() > 0.35:
                n += 1
                instance(
                    wrecks,
                    f"Wreck{n:02d}",
                    "wreck",
                    (x + rng.uniform(-0.4, 0.4), 0, row_z),
                    90 + rng.choice((-6, 0, 6)),
                )
            x += 5.6
    block(back, "Bus", -44, -32, 20.5, 23.3, 3.0, "backlot_prop")
    block(back, "ScrapStackA", -58, -52, 20, 26, 2.6, "backlot_prop")
    block(back, "ScrapStackB", -26, -20, 22, 28, 2.6, "backlot_prop")
    block(back, "SignBoard", -50, -44, 35.2, 35.8, 4.2, "neon", 0.0)
    bk = lamps(back, "back_lot")
    omni(bk, "NeonSign", (-47, 3.5, 33.5), 1.8, 12, "#ff3a4a")
    bz = group("ZombieSpawns", back)
    marker(bz, "SpawnNW", (-60, 0, -2))
    marker(bz, "SpawnSW", (-60, 0, 36))
    marker(bz, "SpawnS", (-30, 0, 36))
    label(back, "Label", "6  BACK LOT  (dark)", (-39, 0.6, 12), 110)

    # --- Road: ticket plaza, the gate, the way into town -------------------------------------------------------------
    road = group("Road", ".")
    floor_tiles(road, "Plaza", -16, 16, 38, 52, "road_ground")
    floor_tiles(road, "Asphalt", -62, 62, 52, 64, "road_ground")
    wall(road, "FenceS", "x", 38, -16, 16, 2.6, "road_wall", [(0, 4, 0, 2.6)])
    wall(road, "SideW", "z", -16, 38, 52, 2.6, "road_wall")
    wall(road, "SideE", "z", 16, 38, 52, 2.6, "road_wall")
    wall(road, "BarrierS", "x", 64, -62, 62, 1.6, "road_wall")
    wall(road, "EndW", "z", -62, 52, 64, 1.6, "road_wall")
    wall(road, "EndE", "z", 62, 52, 64, 1.6, "road_wall")
    box(road, "RoadblockTown", (8, 2.6, 3), (58, 1.3, 58), "roadblock")
    for sx in (-1, 1):
        tag = "W" if sx < 0 else "E"
        block(road, f"Kiosk{tag}", sx * 6 - 1.2, sx * 6 + 1.2, 44, 46.4, 2.4, "road_kiosk")
    box(road, "Canopy", (18, 0.3, 5), (0, 3.6, 45.2), "concession_roof")
    for i, px in enumerate((-9, 9)):
        box(road, f"CanopyPost{i}", (0.4, 3.6, 0.4), (px, 1.8, 47.8), "road_wall")
    box(road, "CentreLine", (0.3, 0.02, 12), (0, 0.01, 46), "road_line", collide=False)
    # The road's broken centre line: 3 m dashes every 6 m.
    painted_lines(road, "RoadDashes", "road_line", (0.15, 3.0), [(x + 1.5, 58.0, 90.0) for x in range(-60, 60, 6)])
    instance(road, "Wreck", "wreck", (-32.0, 0, 58.0), 0)  # its headlights (below) are at its front, z 55.8
    instance(road, "WreckB", "wreck", (22.3, 0, 60.0), 90)
    rl = lamps(road, "back_lot")
    omni(rl, "Kiosk", (0, 3.0, 44), 1.0, 8, "#a8c4ff")
    hl = lamps(road, "battery", "Headlights")
    spot(hl, "WreckHeadlightL", (-31, 1.0, 55.8), 0, 0, 2.5, 18, 28, "#fff2cc")
    spot(hl, "WreckHeadlightR", (-33, 1.0, 55.8), 0, 0, 2.5, 18, 28, "#fff2cc")
    rz = group("ZombieSpawns", road)
    marker(rz, "SpawnW", (-56, 0, 58))
    marker(rz, "SpawnE", (50, 0, 62))
    marker(rz, "SpawnPlaza", (-14, 0, 50))
    label(road, "Label", "7  THE ROAD", (0, 0.6, 58), 150)
    label(road, "LabelPlaza", "TICKET PLAZA", (0, 0.6, 41), 90)

    # --- The drive-in's own props (tools/world/drivein_props.py): speaker posts, the counter, booths, the marquee ---
    drivein_props.write_scenes()
    n_posts = drivein_props.place(instance, group, node, lines, car_slots, gaps, screen_c, field_lamps)

    # --- Shop spots: wall weapons, the prize crane and the ammunition lockers ---------------------------------------
    # The weapons on the walls sell what the rules' tuning prices (weapon_shotgun, weapon_rifle); the crane is
    # crane_play inside the stand; a locker sells the rounds of the weapon in hand. Each spot is a marker with the
    # kind and the shop id as metadata (NightWorld.shop_spots), and the plaque beside it only names it.
    group("ShopSpots", ".")
    group("ShopProps", ".")
    # The shotgun, on the stand's front wall, field side: the first weapon a player can afford, in the open.
    box("ShopProps", "ShotgunPlaque", (1.7, 0.9, 0.12), (-8.2, 1.6, -4.26), "plaque", collide=False)
    sign("ShopProps", "ShotgunSign", "SHOTGUN", (-8.2, 1.6, -4.34), 180)
    shop_spot("SpotShotgun", "wall", "weapon_shotgun", (-8.2, 0, -5.6), 180)
    # The rifle, on the booth's front wall, midway side.
    box("ShopProps", "RiflePlaque", (1.7, 0.9, 0.12), (-4.0, 1.6, 21.74), "plaque", collide=False)
    sign("ShopProps", "RifleSign", "RIFLE", (-4.0, 1.6, 21.66), 180)
    shop_spot("SpotRifle", "wall", "weapon_rifle", (-4.0, 0, 20.4), 180)
    # The prize crane, inside the stand, beside the cabinet that was already there.
    sign("ShopProps", "CraneSign", "PRIZE CRANE", (-7.3, 2.0, 5.0), 90, 60)
    shop_spot("SpotCrane", "crane", "crane_play", (-6.4, 0, 5.0), 270, crane_spot=0)
    # The crane's other places (rules: `crane.spot_doors`): the midway, the open field and the yard. A breakdown moves
    # the crane to one of the spots whose door is open; the prize crane stands on only one at a time.
    shop_spot("SpotCraneMidway", "crane", "crane_play", (6.0, 0, 14.0), 90, crane_spot=1)
    shop_spot("SpotCraneField", "crane", "crane_play", (-24.0, 0, -14.0), 0, crane_spot=2)
    shop_spot("SpotCraneYard", "crane", "crane_play", (40.0, 0, 10.0), 270, crane_spot=3)
    # Lockers: the avenue (the first one, in the open), the stand, the midway, the yard and the back lot.
    ammo_locker("LockerField", (3.1, -31.0), 270)
    ammo_locker("LockerStand", (9.2, 1.8), 270)
    ammo_locker("LockerMidway", (14.6, 12.0), 270)
    ammo_locker("LockerYard", (31.0, 20.0), 0)
    ammo_locker("LockerBackLot", (-24.0, 18.0), 0)

    # --- Dressing: the kit's props, from tools/world/lot_props.py ------------------------------------------------
    lot_props.write_scenes()
    for area in ("Field", "Concession", "Midway", "ProjectionBooth", "GeneratorYard", "BackLot", "Road"):
        lot_props.dress(area, group, instance)

    # --- Purchase doors: a group per door, a coloured slab per way in; the cost and the prerequisite are metadata ---
    # The lot opens outward from the stand: every other door needs the concession, so the midway is open before any
    # of them can be bought. An area with two ways in (the yard and the back lot, from the field and from the midway)
    # has one door with a slab in each, so there is no way in that is not the door.
    node("Doors", "Node3D", ".", {"script": 'ExtResource("doors")'})
    door("Door_Concession", (0, 3.3, -6.0))
    slab("Door_Concession", "Front", (0, -3.6), 3.0, 2.6, "x")
    door("Door_GeneratorYard", (40, 3.3, -6.5))
    slab("Door_GeneratorYard", "Field", (40, -4), 4.0, 2.6, "x")
    slab("Door_GeneratorYard", "Midway", (16, MIDWAY_LINK_Z), MIDWAY_LINK, 2.6, "z")
    door("Door_ProjectionBooth", (0, 3.3, 19.5))
    slab("Door_ProjectionBooth", "Front", (0, 22.2), 3.0, 2.6, "x")
    door("Door_BackLot", (-40, 3.3, -6.5))
    slab("Door_BackLot", "Field", (-40, -4), 4.0, 2.6, "x")
    slab("Door_BackLot", "Midway", (-16, MIDWAY_LINK_Z), MIDWAY_LINK, 2.6, "z")
    door("Door_Road", (0, 3.3, 35.5))
    slab("Door_Road", "Front", (0, 38), 4.0, 2.6, "x")

    # --- Circuit switches: a breaker post for each circuit a player can switch ------------------------------------------
    # Each stands where the area's door is bought from, well clear of the door's slabs (a door's prompt is the first
    # to win), and faces the way the player arrives. The yard's `mains` has none: it is wired to the generator.
    group("Switches", ".")
    for circuit, door_id, at, front in SWITCHES:
        instance("Switches", f"Switch_{circuit}", "switch", at, math.degrees(math.atan2(front[0], front[1])))
        lines.pop()  # the metadata joins the instance's node, so the blank line goes after it
        lines.append(f'metadata/circuit = "{circuit}"')
        lines.append(f'metadata/door = "{door_id}"')
        lines.append("")

    # --- Camera probes: every narrow place the over-the-shoulder camera has to get through -----------------------
    # Each marker faces the way a player walks through; the tests sweep the spring arm from it, both ways round.
    group("CameraProbes", ".")
    for ri, found in sorted(gaps.items()):
        for tag, (gx, gz) in zip(
            "abc", (found[len(found) // 4], found[len(found) // 2], found[3 * len(found) // 4]), strict=True
        ):
            probe(f"CarGap_R{ri}{tag}", (gx, 0, gz), gx - screen_c[0], gz - screen_c[1])
    probe("Ramp", (RAMP_X, 1.8, 27), 0, 1)
    probe("ConcessionFront", (0, 0, -4), 0, 1)
    probe("ConcessionRearW", (-5, 0, 8), 0, 1)
    probe("ConcessionRearE", (5, 0, 8), 0, 1)
    probe("LinkYard", (16, 0, MIDWAY_LINK_Z), 1, 0)
    probe("LinkBackLot", (-16, 0, MIDWAY_LINK_Z), -1, 0)
    probe("GateYard", (40, 0, -4), 0, 1)
    probe("GateBackLot", (-40, 0, -4), 0, 1)
    probe("BoothDoor", (0, 0, 22), 0, 1)
    probe("RoadGate", (0, 0, 38), 0, 1)
    probe("CageW", (36, 0, 18), 1, 0)
    probe("CageE", (44, 0, 18), 1, 0)

    root = lines.index('[node name="DriveInGreybox" type="Node3D"]')
    lines[root:root] = resources
    OUT.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {OUT}: {len(node_names)} nodes, {n_cars} field cars, {n_posts} speaker posts")


if __name__ == "__main__":
    build()
