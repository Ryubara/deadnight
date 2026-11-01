"""Write game/world/drive_in_greybox.tscn: the CSG greybox of the drive-in lot (docs/design/map.md).

Plain Python, no dependencies; run it from the repository root and commit the scene it writes:

    python tools/world/build_greybox.py

Metres, Y up, x east, z south (the screen is at the north, z -48). Every area is a named Node3D with its own colours.
Cars are placed from a fixed seed so the scene does not change from one run to the next.
"""

import math
import random
from pathlib import Path

OUT = Path("game/world/drive_in_greybox.tscn")

# Materials per area: id -> (albedo, emission or None). Colours read in the top-down capture, not in the style bible.
MATS = {
    "outskirts": ("#14161c", None),
    "field_ground": ("#46563a", None),
    "field_struct": ("#b9c1b0", None),
    "field_fence": ("#5d6068", None),
    "screen_face": ("#dfe8f5", "#8fa4c8"),
    "concession_ground": ("#9c6a3a", None),
    "concession_wall": ("#d98a3d", None),
    "concession_prop": ("#f0c27a", None),
    "midway_ground": ("#8a7f6a", None),
    "midway_wall": ("#b0a48a", None),
    "booth_ground": ("#5d4a7a", None),
    "booth_wall": ("#8d6fc0", None),
    "booth_prop": ("#c4a8f0", None),
    "yard_ground": ("#7a6a26", None),
    "yard_wall": ("#d1ab46", None),
    "yard_prop": ("#a8321f", None),
    "yard_gen": ("#f0e26a", "#c8b030"),
    "backlot_ground": ("#2c5252", None),
    "backlot_wall": ("#4f8f8f", None),
    "backlot_prop": ("#6b6f58", None),
    "neon": ("#ff4a5a", "#ff2a40"),
    "road_ground": ("#474b57", None),
    "road_wall": ("#7a86b8", None),
    "road_line": ("#d1ab46", None),
    "door": ("#d0302c", "#6a1210"),
}

lines: list[str] = []
node_names: set[str] = set()


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
    props = {"transform": xform(pos, rot_y)}
    if collide:
        props["use_collision"] = "true"
    props["size"] = vec(size)
    props["material"] = f'SubResource("{mat}")'
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


def omni(parent: str, name: str, pos, energy: float, rng: float, col: str, powered: bool = True) -> None:
    props = {
        "transform": xform(pos),
        "light_color": color(col),
        "light_energy": f"{energy:g}",
        "omni_range": f"{rng:g}",
    }
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


def marker(parent: str, name: str, pos) -> None:
    node(name, "Marker3D", parent, {"transform": xform(pos)})


def instance(parent: str, name: str, res: str, pos, rot_y: float = 0.0) -> None:
    lines.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{res}")]')
    lines.append(f"transform = {xform(pos, rot_y)}")
    lines.append("")
    node_names.add(f"{parent}/{name}")


def door(name: str, cost: int, centre, width: float, height: float, axis: str) -> None:
    size = (width, height, 0.3) if axis == "x" else (0.3, height, width)
    box("Doors", name, size, (centre[0], height / 2, centre[1]), "door")
    node_meta[name] = cost


node_meta: dict[str, int] = {}


# ---------------------------------------------------------------------------------------------------------------
def build() -> None:
    lines.append("[gd_scene format=3]")
    lines.append("")
    lines.append('[ext_resource type="PackedScene" path="res://world/drive_in/car.tscn" id="car"]')
    lines.append('[ext_resource type="PackedScene" path="res://world/drive_in/lamp_post.tscn" id="lamp"]')
    lines.append("")
    for mid, (albedo, emis) in MATS.items():
        lines.append(f'[sub_resource type="StandardMaterial3D" id="{mid}"]')
        lines.append(f"albedo_color = {color(albedo)}")
        lines.append("roughness = 1.0")
        if emis:
            lines.append("emission_enabled = true")
            lines.append(f"emission = {color(emis)}")
        lines.append("")
    lines.append('[sub_resource type="Environment" id="night"]')
    lines.append("background_mode = 1")
    lines.append("background_color = Color(0.015, 0.02, 0.05, 1)")
    lines.append("ambient_light_source = 2")
    lines.append("ambient_light_color = Color(0.3, 0.36, 0.55, 1)")
    lines.append("ambient_light_energy = 0.35")
    lines.append("tonemap_mode = 2")
    lines.append("")

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
            "transform": "Transform3D(0.866, -0.2165, 0.4495, 0, 0.9, 0.4334, -0.5, -0.375, 0.7785, 0, 20, 0)",
            "light_color": color("#9db4e8"),
            "light_energy": "0.35",
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
    # Perimeter fence (2.4 m) with the breach panels where the dead come in.
    fence_h = 2.4
    wall(field, "FenceN", "x", -52, -62, 62, fence_h, "field_fence")
    wall(field, "FenceW", "z", -62, -52, -4, fence_h, "field_fence")
    wall(field, "FenceE", "z", 62, -52, -4, fence_h, "field_fence")
    breaches = [("NW", -62, -46), ("NE", 62, -46), ("W", -62, -22), ("E", 62, -22), ("N", -36, -52), ("N2", 36, -52)]
    for tag, bx, bz in breaches:
        if abs(bx) == 62:
            box(field, f"Breach{tag}", (0.6, 2.4, 4.0), (bx, 1.2, bz), "door")
        else:
            box(field, f"Breach{tag}", (4.0, 2.4, 0.6), (bx, 1.2, bz), "door")
    # Fence between the field and the yard / back lot, with the two purchase gates (doors listed below).
    wall(field, "FenceS_W", "x", -4, -62, -10, fence_h, "field_fence", [(-40, 4, 0, 2.6)])
    wall(field, "FenceS_E", "x", -4, 10, 62, fence_h, "field_fence", [(40, 4, 0, 2.6)])

    rows = group("Rows", field)
    rng = random.Random(1958)
    n_cars = 0
    for ri, radius in enumerate((14.0, 21.0, 28.0, 35.0, 42.0), start=1):
        row = group(f"Row{ri}", rows)
        step = math.degrees(3.3 / radius)
        a = -80.0
        while a <= 80.0:
            x = screen_c[0] + radius * math.sin(math.radians(a))
            z = screen_c[1] + radius * math.cos(math.radians(a))
            aisle = abs(x) < 3.6 or 20.0 < abs(x) < 25.0
            if not aisle and abs(x) < 56 and z < -9 and rng.random() > 0.12:
                n_cars += 1
                instance(row, f"Car{n_cars:02d}", "car", (x, 0, z), a)
            a += step
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
        instance(props, f"Wreck{i}", "car", (px, 0, pz), ry)
    lamps = group("Lamps", field)
    for i, (lx, lz) in enumerate(
        [(-4.6, -34), (4.6, -34), (-4.6, -22), (4.6, -22), (-4.6, -10), (4.6, -10), (-22.5, -28), (22.5, -28)], start=1
    ):
        instance(lamps, f"Lamp{i}", "lamp", (lx, 0, lz))
    omni(lamps, "ScreenGlow", (0, 7, -44), 1.4, 34, "#aebfe8")
    spawns = group("PlayerSpawns", field)
    for i, sx in enumerate((-6, -2, 2, 6), start=1):
        marker(spawns, f"Player{i}", (sx, 0, -43))
    zs = group("ZombieSpawns", field)
    for tag, bx, bz in breaches:
        marker(zs, f"Spawn{tag}", (bx * 0.97 if abs(bx) == 62 else bx, 0, bz if abs(bx) == 62 else bz + 2))
    label(field, "Label", "1  SCREEN FIELD  (start)", (-26, 0.6, -13), 130)
    label(field, "LabelScreen", "SCREEN", (0, 0.6, -50), 110)

    # --- Concession stand ----------------------------------------------------------------------------------------
    con = group("Concession", ".")
    floor_tiles(con, "Floor", -10, 10, -4, 8, "concession_ground", 24)
    wall(
        con, "WallN", "x", -4, -10, 10, 4.0, "concession_wall",
        [(0, 3, 0, 2.6), (-6, 2.2, 1.0, 2.4), (6, 2.2, 1.0, 2.4)],
    )  # fmt: skip
    wall(con, "WallS", "x", 8, -10, 10, 4.0, "concession_wall", [(-5, 1.8, 0, 2.4), (5, 1.8, 0, 2.4)])
    wall(con, "WallW", "z", -10, -4, 8, 4.0, "concession_wall")
    wall(con, "WallE", "z", 10, -4, 8, 4.0, "concession_wall")
    box(con, "Roof", (20.8, 0.3, 12.8), (0, 4.15, 2), "concession_wall")
    block(con, "Counter", -5, 5, 1, 3, 1.0, "concession_prop")
    block(con, "PrizeCrane", -9.4, -7.4, 4, 6, 2.4, "concession_prop")
    block(con, "SodaFountain", 7.0, 9.4, 4.4, 5.4, 1.6, "concession_prop")
    cl = group("Lamps", con)
    omni(cl, "InteriorW", (-5, 3.3, 3), 1.6, 9, "#ffb866")
    omni(cl, "InteriorE", (5, 3.3, 3), 1.6, 9, "#ffb866")
    omni(cl, "InteriorN", (0, 3.3, -2), 1.4, 8, "#ffb866")
    label(con, "Label", "2 CONCESSION", (0, 4.6, 2), 80)

    # --- Midway: the courtyard behind the stand, the hub the other areas hang off ------------------------------
    mid = group("Midway", ".")
    floor_tiles(mid, "Ground", -16, 16, 8, 38, "midway_ground")
    floor_tiles(mid, "AlleyW", -16, -10, -4, 8, "midway_ground")
    floor_tiles(mid, "AlleyE", 10, 16, -4, 8, "midway_ground")
    wall(mid, "FenceW", "z", -16, -4, 38, 2.6, "midway_wall", [(20, 4.5, 0, 2.6)])
    wall(mid, "FenceE", "z", 16, -4, 38, 2.6, "midway_wall", [(20, 4.5, 0, 2.6)])
    wall(mid, "AlleyEndW", "x", -4, -16, -10, 2.6, "midway_wall")
    wall(mid, "AlleyEndE", "x", -4, 10, 16, 2.6, "midway_wall")
    block(mid, "DumpsterW", -15.2, -12.4, -3.2, -1.4, 1.5, "midway_wall")
    block(mid, "DumpsterE", 12.4, 15.2, -3.2, -1.4, 1.5, "midway_wall")
    block(mid, "CrateStackA", -12, -9.4, 14, 16.4, 1.8, "midway_wall")
    block(mid, "CrateStackB", 9.4, 12, 28, 30.4, 1.8, "midway_wall")
    ml = group("Lamps", mid)
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
    box(booth, "Landing", (2.0, 0.3, 1.4), (-5.0, 3.75, 22.7), "booth_wall")
    box(booth, "Roof", (12.8, 0.3, 10.8), (0, 7.55, 27), "booth_wall")
    # The ramp up: 1.6 m wide along the west wall, rising 3.6 m over 7.6 m.
    ramp_len = math.hypot(7.6, 3.6)
    ramp_pitch = math.degrees(math.atan2(3.6, 7.6))
    cp, sp = math.cos(math.radians(ramp_pitch)), math.sin(math.radians(ramp_pitch))
    ramp = f"Transform3D(1, 0, 0, 0, {cp:.4f}, {sp:.4f}, 0, {-sp:.4f}, {cp:.4f}, -4.8, 1.75, 27)"
    node(
        "Ramp", "CSGBox3D", booth,
        {"transform": ramp, "use_collision": "true", "size": vec((1.6, 0.3, ramp_len)), "material": 'SubResource("booth_prop")'},
    )  # fmt: skip
    block(booth, "ReCutMachine", 2, 5, 27, 29.4, 1.8, "booth_prop")
    block(booth, "FilmRacks", -3.4, -1, 30, 31.6, 2.2, "booth_prop")
    block(booth, "Projector", -1.0, 1.0, 24.5, 26.0, 1.3, "booth_prop", 4.05)
    bl = group("Lamps", booth)
    spot(bl, "ProjectorBeam", (0, 5.4, 22.3), 180, -5.0, 6.0, 100, 7, "#e8f0ff")
    omni(bl, "Lower", (0, 3.0, 27), 1.0, 8, "#c9a8ff")
    omni(bl, "Upper", (0, 6.6, 27), 0.9, 7, "#c9a8ff")
    label(booth, "Label", "4 BOOTH", (0, 7.9, 27), 100)

    # --- Generator yard (east) ----------------------------------------------------------------------------------------
    yard = group("GeneratorYard", ".")
    floor_tiles(yard, "Ground", 16, 62, -4, 38, "yard_ground")
    wall(yard, "FenceE", "z", 62, -4, 38, 2.4, "yard_wall")
    wall(yard, "FenceS", "x", 38, 16, 62, 2.4, "yard_wall")
    # The generator cage: 8 x 6 m, open on the west and east sides, roofless.
    wall(yard, "CageN", "x", 15, 36, 44, 3.0, "yard_wall")
    wall(yard, "CageS", "x", 21, 36, 44, 3.0, "yard_wall")
    wall(yard, "CageW", "z", 36, 15, 21, 3.0, "yard_wall", [(18, 1.8, 0, 2.4)])
    wall(yard, "CageE", "z", 44, 15, 21, 3.0, "yard_wall", [(18, 1.8, 0, 2.4)])
    box(yard, "Generator", (3.2, 1.8, 1.6), (40, 0.9, 18), "yard_gen")
    for i, ty in enumerate((6, 12)):
        node(
            f"FuelTank{i + 1}", "CSGCylinder3D", yard,
            {"transform": xform((55, 1.7, ty)), "use_collision": "true", "radius": "1.4", "height": "3.4",
             "sides": "16", "material": 'SubResource("yard_prop")'},
        )  # fmt: skip
    block(yard, "ContainerA", 24, 30, 6, 8.6, 2.6, "yard_prop")
    block(yard, "ContainerB", 50, 56, 26, 28.6, 2.6, "yard_prop")
    block(yard, "Pallets", 26, 29, 28, 31, 1.2, "yard_wall")
    block(yard, "DrumRow", 20, 22, 2, 9, 1.0, "yard_prop")
    yl = group("Lamps", yard)
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
    wall(back, "FenceW", "z", -62, -4, 38, 2.4, "backlot_wall")
    wall(back, "FenceS", "x", 38, -62, -16, 2.4, "backlot_wall")
    wrecks = group("Wrecks", back)
    n = 0
    for row_z in (6, 14, 30):
        x = -58.0
        while x < -22:
            if rng.random() > 0.35:
                n += 1
                instance(
                    wrecks, f"Wreck{n:02d}", "car", (x + rng.uniform(-0.4, 0.4), 0, row_z), 90 + rng.choice((-6, 0, 6))
                )
            x += 5.6
    block(back, "Bus", -44, -32, 20.5, 23.3, 3.0, "backlot_prop")
    block(back, "ScrapStackA", -58, -52, 20, 26, 2.6, "backlot_prop")
    block(back, "ScrapStackB", -26, -20, 22, 28, 2.6, "backlot_prop")
    block(back, "SignBoard", -50, -44, 35.2, 35.8, 4.2, "neon", 0.0)
    bk = group("Lamps", back)
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
    box(road, "RoadblockTown", (8, 2.6, 3), (58, 1.3, 58), "door")
    for sx in (-1, 1):
        tag = "W" if sx < 0 else "E"
        block(road, f"Kiosk{tag}", sx * 6 - 1.2, sx * 6 + 1.2, 44, 46.4, 2.4, "road_wall")
    box(road, "Canopy", (18, 0.3, 5), (0, 3.6, 45.2), "road_wall")
    for i, px in enumerate((-9, 9)):
        box(road, f"CanopyPost{i}", (0.4, 3.6, 0.4), (px, 1.8, 47.8), "road_wall")
    box(road, "CentreLine", (0.3, 0.02, 12), (0, 0.01, 46), "road_line", collide=False)
    block(road, "Wreck", -34, -29.4, 56.4, 58.4, 1.6, "road_wall")
    block(road, "WreckB", 20, 24.6, 59, 61, 1.6, "road_wall")
    rl = group("Lamps", road)
    omni(rl, "Kiosk", (0, 3.0, 44), 1.0, 8, "#a8c4ff")
    spot(rl, "WreckHeadlightL", (-31, 1.0, 55.8), 0, 0, 2.5, 18, 28, "#fff2cc")
    spot(rl, "WreckHeadlightR", (-33, 1.0, 55.8), 0, 0, 2.5, 18, 28, "#fff2cc")
    rz = group("ZombieSpawns", road)
    marker(rz, "SpawnW", (-56, 0, 58))
    marker(rz, "SpawnE", (50, 0, 62))
    marker(rz, "SpawnPlaza", (-14, 0, 50))
    label(road, "Label", "7  THE ROAD", (0, 0.6, 58), 150)
    label(road, "LabelPlaza", "TICKET PLAZA", (0, 0.6, 41), 90)

    # --- Purchase doors: a coloured slab per door; the cost is metadata ------------------------------------------
    group("Doors", ".")
    door("Door_Concession_750", 750, (0, -3.6), 3.0, 2.6, "x")
    door("Gate_GeneratorYard_1000", 1000, (40, -4), 4.0, 2.6, "x")
    door("Door_ProjectionBooth_1250", 1250, (0, 22.2), 3.0, 2.6, "x")
    door("Gate_BackLot_1750", 1750, (-40, -4), 4.0, 2.6, "x")
    door("Gate_Road_2500", 2500, (0, 38), 4.0, 2.6, "x")
    for name, cost in node_meta.items():
        label("Doors", f"Label_{name}", f"{cost}", (0, 3.2, 0), 100)
    # Door labels need the door positions: patch their transforms.
    patch = {
        "Door_Concession_750": (0, 3.3, -6.0),
        "Gate_GeneratorYard_1000": (40, 3.3, -6.5),
        "Door_ProjectionBooth_1250": (0, 3.3, 19.5),
        "Gate_BackLot_1750": (-40, 3.3, -6.5),
        "Gate_Road_2500": (0, 3.3, 35.5),
    }
    for i, ln in enumerate(lines):
        if ln.startswith('[node name="Label_'):
            door_name = ln.split('"')[1][len("Label_") :]
            px, py, pz = patch[door_name]
            lines[i + 1] = f"transform = Transform3D(1, 0, 0, 0, 0, 1, 0, -1, 0, {px:g}, {py:g}, {pz:g})"
    # Metadata on the door slabs.
    out: list[str] = []
    current = None
    for ln in lines:
        if ln.startswith("[node name="):
            current = ln.split('"')[1]
        out.append(ln)
        if current in node_meta and ln.startswith("material = "):
            out.append(f"metadata/cost = {node_meta[current]}")
            current = None
    lines[:] = out

    OUT.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {OUT}: {len(node_names)} nodes, {n_cars} field cars")


if __name__ == "__main__":
    build()
