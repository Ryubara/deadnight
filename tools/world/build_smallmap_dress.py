"""The second map's dressing: the kit's pieces, lights, machines and backdrop on the greybox's sockets (#792).

Not run by itself: `build_smallmap_greybox.py` calls `apply` after it has written every box, so the scene stays one file
written by one script and a rerun leaves it unchanged. Every piece here is drawn only, or it sits on collision the
greybox already has, or it is a solid thing that is part of the walking mesh (the saved meshes are baked again after
the greybox changes, `docs/design/smallmap.md#sockets-for-the-kit-and-for-the-night`).

The kit is `game/world/smallmap/fixtures/` (the scenes, with their hidden collision), `game/assets/smallmap/` (the
models alone) and `game/world/smallmap/lights/` (the lamps and the light cards). Notes: docs/research/maps/small-map-art.md.
"""

import math
import re
from pathlib import Path

import build_greybox as bg

FIXTURES = Path("game/world/smallmap/fixtures")
LIGHTS = "res://world/smallmap/lights"

_ext: dict[str, tuple[str, str]] = {}  # id -> (resource type, path), written at the head of the scene


def ext(kind: str, path: str, rid: str) -> str:
    """Declares an external resource once; returns its id."""
    _ext[rid] = (kind, path)
    return rid


def fixture(name: str) -> str:
    return ext("PackedScene", f"res://world/smallmap/fixtures/{name}.tscn", f"fx_{name}")


def model(name: str) -> str:
    """A kit model on its own (no collision): the greybox's boxes are the collision."""
    return ext("PackedScene", f"res://assets/smallmap/{name}.gltf", f"md_{name}")


def light_scene(name: str) -> str:
    return ext("PackedScene", f"{LIGHTS}/{name}.tscn", f"lt_{name}")


def machine(name: str) -> str:
    return ext("PackedScene", f"res://world/machines/{name}.tscn", f"mc_{name}")


def ext_lines() -> list[str]:
    return [f'[ext_resource type="{kind}" path="{path}" id="{rid}"]' for rid, (kind, path) in sorted(_ext.items())]


def xf(pos, yaw: float = 0.0, scale=(1.0, 1.0, 1.0), roll: float = 0.0) -> str:
    """A transform: yaw about Y (so +Z turns to (sin, cos)), `scale` in the piece's own axes, an optional roll about Z."""
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    sx, sy, sz = scale
    if roll:
        cr, sr = math.cos(math.radians(roll)), math.sin(math.radians(roll))
        # local rows after the roll about Z: x' = (cr, -sr, 0), y' = (sr, cr, 0), z' = (0, 0, 1)
        rows = [(cr, -sr, 0.0), (sr, cr, 0.0), (0.0, 0.0, 1.0)]
    else:
        rows = [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]
    # M = Ry(yaw) * Rz(roll) * S, written as the rows Godot reads (xx, xy, xz, yx, ...)
    ry = [(c, 0.0, s), (0.0, 1.0, 0.0), (-s, 0.0, c)]
    m = [[sum(ry[i][k] * rows[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    m = [[m[i][j] * (sx, sy, sz)[j] for j in range(3)] for i in range(3)]
    flat = ", ".join(f"{m[i][j]:.4f}" for i in range(3) for j in range(3))
    return f"Transform3D({flat}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})"


def place(parent, name, rid, pos, yaw=0.0, scale=(1.0, 1.0, 1.0), props=None, hide=(), roll: float = 0.0) -> str:
    """An instance of a scene; `hide` names children (below the instance) to switch off. Returns its path."""
    bg.lines.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{rid}")]')
    bg.lines.append(f"transform = {xf(pos, yaw, scale, roll)}")
    for key, value in (props or {}).items():
        bg.lines.append(f"{key} = {value}")
    bg.lines.append("")
    path = f"{parent}/{name}" if parent != "." else name
    bg.node_names.add(path)
    for child in hide:
        bg.lines.append(f'[node name="{child}" parent="{path}"]')
        bg.lines.append("visible = false")
        bg.lines.append("")
    return path


def override(path: str, props: dict[str, str], groups: tuple[str, ...] = ()) -> None:
    """Properties (and groups) of a node inside an instanced scene (`path` is the node's own path from the root)."""
    parent, _, name = path.rpartition("/")
    extra = " groups=[" + ", ".join(f'"{g}"' for g in groups) + "]" if groups else ""
    bg.lines.append(f'[node name="{name}" parent="{parent}"{extra}]')
    for key, value in props.items():
        bg.lines.append(f"{key} = {value}")
    bg.lines.append("")


def hidden_box(parent, name, size, pos, layers: int = bg.GROUND_LAYER, yaw: float = 0.0) -> None:
    """A solid box that is not drawn: collision and walking mesh only (the dressing is drawn over it)."""
    bg.box(parent, name, size, pos, "smallmap_wall_ground", yaw, True, False, layers)


def slots_of(fixture_name: str) -> list[str]:
    """The `BoardSlot` transforms of a kit window fixture, as written in its scene."""
    text = (FIXTURES / f"{fixture_name}.tscn").read_text(encoding="utf-8")
    found = re.findall(
        r'\[node name="BoardSlot\d" type="Marker3D" parent="\."\]\ntransform = (Transform3D\([^)]*\))', text
    )
    assert found, fixture_name
    return found


# --- The shell ---------------------------------------------------------------------------------------------------------

BAND = 0.4  # the kit's 2.8 m modules leave this much of a 3.2 m storey above them


def breach_dressing(window_key: str, thick: float) -> None:
    """The broken wall's hole: a post of the kit on each side of the gap, a beam across its top, rubble on the floor.
    Drawn over the wall beside the gap and in it above the dead's heads; the hole stays as wide as the greybox made it."""
    trim = model("trim_end")
    for side, name in ((-1, "PostL"), (1, "PostR")):
        place(window_key, name, trim, (side * 1.18, 0, 0))
    place(window_key, "Beam", model("beam_2"), (0, 0, 0))
    # Rubble that is walked over (no collision): chunks in the opening and on the room side.
    place(window_key, "RubbleA", model("rubble_a"), (0.35, 0, 0.55), 20)
    place(window_key, "RubbleB", model("rubble_b"), (-0.5, 0, 0.9), 75)
    place(window_key, "RubbleC", model("rubble_b"), (0.1, 0, -0.45), 140)


def opening(room: str, name: str, at) -> None:
    """The kit's wide opening drawn in a link's gap (its own hidden jambs and lintel leave 2.0 x 2.4 m clear); a wall
    runs along X, so the module needs no turn."""
    place(room, name, fixture("wall_opening_wide"), at)


def link_doors(stair_a, stair_b, door_x: float, door_width: float, door_height: float, stair_width: float) -> None:
    """The purchase leaf and the debris blocker on the paid links: they go with the slab when the link is bought."""
    leaf = model("door_purchase")
    # The plank door across the side door, 2.0 m of leaf where the kit's is 1.35 (the planks stretch with it).
    place("Doors/Door_Side", "Leaf", leaf, (door_x, 0, -0.15), 0.0, (door_width / 1.348, door_height / 2.36, 1.0))
    blocker = model("debris_blocker")
    for name, (x0, x1, z0, z1) in (("Stairs_Start", stair_a), ("Stairs_Side", stair_b)):
        # A pile of furniture at the foot of the flight, its room side the foot's (west).
        place(f"Doors/{name}", "Pile", blocker, (x0, 0, (z0 + z1) / 2), -90.0, (stair_width / 1.4, 1.0, 1.0))


def stair_model(
    parent: str, name: str, foot_x: float, mid_z: float, floor: float, run: float, width: float, rise: float
):
    """The kit's straight flight over a greybox ramp: its foot at `foot_x`, climbing east, the rails off (the flight has
    a wall on both sides), stretched from the kit's 1.4 x 4.5 x 3.0 m to this flight."""
    scale = (width / 1.4, rise / 3.0, run / 4.5)
    place(parent, f"{name}Flight", model("stair_straight"), (foot_x + run / 2, floor, mid_z), -90.0, scale,
          hide=("RailLeft", "RailRight"))  # fmt: skip


def pillar(parent: str, name: str, rect, ceiling: float, wall_mat: str) -> None:
    """A square pillar to the ceiling: hidden collision (the walking mesh), the kit's pillar up to 2.8 m and a band of the
    wall's own block above it."""
    x0, x1, z0, z1 = rect
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    hidden_box(parent, name, (x1 - x0, ceiling, z1 - z0), (cx, ceiling / 2, cz), bg.WALL_LAYERS)
    place(parent, f"{name}Model", model("pillar"), (cx, 0, cz))
    bg.box(
        parent, f"{name}Band", (x1 - x0, ceiling - 2.8, z1 - z0), (cx, (ceiling + 2.8) / 2, cz), wall_mat, collide=False
    )


def rack(parent: str, name: str, rect, height: float, mat: str) -> None:
    """A film rack between two pillars: hidden collision at a jump's height, two of the kit's shelf racks drawn over it."""
    x0, x1, z0, z1 = rect
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    hidden_box(parent, name, (x1 - x0, height, z1 - z0), (cx, height / 2, cz))
    width = x1 - x0
    for i, share in enumerate((0.25, 0.75)):
        # Squat as the hidden collision, so the view over the racks stays open (the kit's rack is 2.0 m).
        place(
            parent,
            f"{name}Shelf{i + 1}",
            model("shelf_rack"),
            (x0 + width * share, 0, cz),
            0.0,
            (1.0, height / 2.0, 1.0),
        )


# --- Light ---------------------------------------------------------------------------------------------------------------

HANG = 0.4  # the kit's pendant hangs from 2.8 m; this map's ceiling is 3.2 m
BULB_NAME = "Light"


def pendants(lamps, storey: float) -> None:
    """The map's lamps as the kit's pendant lamps: each is one of the map's real lights (the `powered_light` group: the
    dead's lit pace asks about it) with the lamp, the halo, the pool on the floor and the cone of haze round it."""
    scene = light_scene("pendant_light")
    for i, (room, (x, y, z)) in enumerate(lamps, start=1):
        floor = storey if y > storey else 0.0
        path = place(room, f"Lamp{i}", scene, (x, floor, z), props={"hang": f"{HANG:g}"})
        mask = bg.LIGHT_MASKS.get(f"{path}/{BULB_NAME}")
        override(
            f"{path}/{BULB_NAME}", {} if mask is None else {"light_cull_mask": str(mask)}, groups=("powered_light",)
        )


def decor_pendant(room: str, name: str, at, follows: str) -> None:
    """A pendant lamp that is only seen (no light slot): it burns with the real lamp `follows` (a sibling in `room`)."""
    place(room, name, light_scene("pendant_light"), at,
          props={"hang": f"{HANG:g}", "own_light": "false", "light_path": f'NodePath("../{follows}/{BULB_NAME}")'})  # fmt: skip


def lantern(room: str, name: str, at, yaw: float, follows: str) -> None:
    """A wall lantern (its foot at 1.8 m, its back on the wall, +Z into the room) with its cards, following `follows`."""
    place(room, name, light_scene("lantern_light"), at, yaw,
          props={"own_light": "false", "light_path": f'NodePath("../{follows}/{BULB_NAME}")'})  # fmt: skip


def door_glow(door: str, at, yaw: float, follows_path: str, opening=(2.0, 2.4)) -> None:
    """The light of the far room behind a purchase door or a blocker, on the door's own group (it goes when the link is
    bought). `follows_path` is the lamp's light, from the door group's own node."""
    place(f"Doors/{door}", "Glow", light_scene("door_glow"), at, yaw,
          props={"opening": f"Vector2({opening[0]:g}, {opening[1]:g})", "light_path": f'NodePath("{follows_path}")'})  # fmt: skip


MOON = (0.30, 0.62, -0.72)  # towards the moon, as the lot's `MOON_TOWARDS`


def moon_shaft(window_key: str, inward, upper: bool, bars: int = 0, rails: int = 5) -> None:
    """Cool moonlight through a window, as an additive card in the opening, two sheets of haze and its patch on the floor
    (`MoonShaft`). The moon is the lot's, from the north; a window that does not face it still gets a shaft, leaning
    the way the light travels in its own frame (the stylised moon is everywhere)."""
    travel = (-MOON[0], -MOON[2])  # the moon's light travels away from it, along the ground
    ix, iz = inward
    side = travel[0] * iz - travel[1] * ix  # across the window's frame (local +X is (iz, -ix))
    ahead = abs(travel[0] * ix + travel[1] * iz)
    yaw = max(-50.0, min(50.0, math.degrees(math.atan2(side, ahead + 0.35))))
    place(window_key, "Shaft", light_scene("moon_shaft"), (0, 0, 0),
          props={"yaw": f"{yaw:.1f}", "wall_face": "0.1" if upper else "0.15", "rails": str(rails), "bars": str(bars),
                 "light_path": 'NodePath("../../../Lighting/Moon")'})  # fmt: skip


CHALK = (
    "KEEP THE LIGHTS ON",
    "STAY IN THE LIGHT",
    "THEY COME AT DARK",
    "NOT THIS WAY",
    "HOLD THE WINDOWS",
    "UP THERE ->",
)


def chalk(room: str, name: str, message: str, at, yaw: float, width: float, follows: str) -> None:
    """A chalk message on a wall, 1 cm off it, burning with the lamp `follows`."""
    place(room, name, light_scene("chalk_message"), at, yaw,
          props={"message": str(CHALK.index(message)), "width": f"{width:g}",
                 "light_path": f'NodePath("../{follows}/{BULB_NAME}")'})  # fmt: skip


# --- Outside -------------------------------------------------------------------------------------------------------------


def outside() -> None:
    """The backdrop (the yard's wire fence, bare trees, the pole lines and the drive-in in the distance): never walked and
    never collided with, so it is one instance at the building's origin. It is turned half a circle, so the drive-in
    (north in the backdrop's own frame) lies south of the building, in front of the hall's south window (#917)."""
    place("Outside", "Backdrop", ext("PackedScene", "res://world/smallmap/backdrop.tscn", "backdrop"), (0, 0, 0), 180.0)


def outside_stair_model(centre, run: float, width: float, rise: float) -> None:
    """The kit's straight flight drawn over the outside stair's hidden ramp, climbing north, its rails on (one side is
    open to the yard)."""
    scale = (width / 1.4, rise / 3.0, run / 4.5)
    place("Outside", "OutStairFlight", model("stair_straight"), centre, 0.0, scale)


# --- The machines the lot has ----------------------------------------------------------------------------------------------

PERK_SCALE = (
    0.85  # a perk cooler is 2.1 m with its emblem to 3.55 m: at 0.85 the emblem clears this map's 3.2 m ceiling
)
# name, the machine's scene, its look (perks), the shop item and kind of its spot, room, floor, where it stands (its middle),
# yaw (its front is +Z before the turn), the hidden block (its size along x and z in the world, and its height) and how far in front of its middle the
# spot is. The soda against the hall's west wall; each perk cooler at the back of its own alcove (#917: never two side by
# side), two in the side room and three upstairs (the dearest, farthest from the start); the re-cut bench upstairs.
MACHINES = [
    ("Soda", "soda_fountain", None, "tonic_hearty", "perk", "start", 0.0, (0.5, 9.6), 90, (1.0, 2.4, 1.6), 1.2),
    (
        "PerkLoad",
        "perk_machine",
        "quick_load",
        "tonic_quick_load",
        "perk",
        "side",
        0.0,
        (6.9, -8.6),
        0,
        (1.28, 0.77, 1.8),
        1.1,
    ),
    (
        "PerkRescue",
        "perk_machine",
        "swift_rescue",
        "tonic_swift_rescue",
        "perk",
        "side",
        0.0,
        (-1.45, 0.7),
        180,
        (1.28, 0.77, 1.8),
        1.1,
    ),
    (
        "ReCut",
        "recut_machine",
        None,
        "upgrade_weapon",
        "upgrade",
        "upstairs",
        3.4,
        (-0.3, -1.45),
        180,
        (3.0, 2.4, 2.0),
        2.3,
    ),
    (
        "PerkHolster",
        "perk_machine",
        "third_holster",
        "tonic_third_holster",
        "perk",
        "upstairs",
        3.4,
        (-4.6, -8.6),
        0,
        (1.28, 0.77, 1.8),
        1.1,
    ),
    (
        "PerkShot",
        "perk_machine",
        "double_shot",
        "tonic_double_shot",
        "perk",
        "upstairs",
        3.4,
        (6.9, -8.6),
        0,
        (1.28, 0.77, 1.8),
        1.1,
    ),
    (
        "PerkShock",
        "perk_machine",
        "reload_shock",
        "tonic_reload_shock",
        "perk",
        "upstairs",
        3.4,
        (17.0, -4.0),
        -90,
        (0.77, 1.28, 1.8),
        1.1,
    ),
]


def machines() -> None:
    """Every machine of the lot, placed: the machine (drawn by its own script), a hidden block that holds its place in the
    walking mesh and the spot a player buys from (`ShopSpots`, the lot's kinds `perk` and `upgrade`)."""
    for name, kind, perk, item, spot_kind, room, floor, (mx, mz), yaw, (bx, bz, bh), dist in MACHINES:
        props = {}
        scale = (1.0, 1.0, 1.0)
        if perk is not None:
            props["perk"] = f'&"{perk}"'
            scale = (PERK_SCALE,) * 3
        props.update(bg.light_layers(f"ShopProps/{name}"))
        place("ShopProps", name, machine(kind), (mx, floor, mz), yaw, scale, props)
        hidden_box("ShopProps", f"{name}Block", (bx, bh, bz), (mx, floor + bh / 2, mz))
        sx, sz = mx + math.sin(math.radians(yaw)) * dist, mz + math.cos(math.radians(yaw)) * dist
        bg.node(f"Spot{name}", "Marker3D", "ShopSpots",
                {"transform": bg.xform((sx, floor, sz), yaw), "metadata/kind": f'"{spot_kind}"',
                 "metadata/shop_id": f'"{item}"', "metadata/room": f'"{room}"'})  # fmt: skip


# --- The cabinet and the clutter -------------------------------------------------------------------------------------------


def cabinet(name: str, shop_id: str, face, into, floor: float, yaw: float, plaque_mat: str) -> None:
    """The rifle's wall buy: the kit's tall cabinet against the wall with the lot's plaque on end in its recess, the
    silhouette on the plaque. Its hidden collision is the cabinet's."""
    x, z = face
    dx, dz = into
    depth = 0.53
    path = place(
        "ShopProps", f"{name}Case", fixture("tall_cabinet"), (x + dx * depth / 2, floor, z + dz * depth / 2), yaw
    )
    # The fixture's `PlaqueSlot` (turned a quarter about Z, so the 1.7 x 0.9 plaque stands upright in the 0.92 x 1.72 m
    # recess); the silhouette inside it is turned back.
    slot = "Transform3D(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, 1.02, -0.13)"
    bg.node("Slot", "Node3D", path, {"transform": slot})
    bg.node(
        "Plaque",
        "CSGBox3D",
        f"{path}/Slot",
        {"size": "Vector3(1.7, 0.9, 0.12)", "material": f'ExtResource("{plaque_mat}")'},
    )
    bg.node("Silhouette", "Node3D", f"{path}/Slot",
            {"transform": "Transform3D(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0.07)", "script": 'ExtResource("silhouette")',
             "shop_id": f'&"{shop_id}"', "upright": "true"})  # fmt: skip


# The hall's counter: its top, where the radio and the lantern stand (the greybox builds the counter to this height).
# Above what the body climbs from a standing start (1.25 m, `tools/world/ledge_probe.gd`) and above the dead's reach, so
# nobody can stand on it where they cannot be struck (#847).
COUNTER_TOP = 1.5

# What lies about, by room: (kind, piece, where, yaw, floor). `solid` pieces carry the fixture's hidden collision and sit
# against a wall or in a corner (the walking mesh goes round them); the rest are walked over and have none.
CLUTTER = [
    # the hall: filing cabinets on the south wall by the shop wall's corner (the pistol's plaque is above that corner of
    # the west wall, #994), a tipped table between two windows, chunks under the windows
    ("solid", "filing_cabinet", (2.2, 0.0, 14.2), 180),
    ("solid", "filing_cabinet", (2.8, 0.0, 14.2), 180),
    ("solid", "table_tipped", (15.6, 0.0, 6.0), 270),
    ("solid", "chair", (14.9, 0.0, 6.6), 235),
    ("walk", "rubble_a", (4.0, 0.0, 13.8), 30),
    ("walk", "rubble_b", (4.7, 0.0, 13.4), 120),
    ("walk", "rubble_a", (12.0, 0.0, 13.7), 200),
    ("walk", "rubble_b", (15.2, 0.0, 4.0), 75),
    ("walk", "rubble_a", (15.1, 0.0, 12.0), 250),
    ("walk", "helmet", (5.2, 0.0, 12.9), 40),
    ("walk", "radio", (7.0, COUNTER_TOP, 5.6), 20),
    ("walk", "lantern", (9.3, COUNTER_TOP, 6.6), 0),
    # the side room: cabinets and a chair on the south wall, rubble in the breach's pocket
    ("solid", "filing_cabinet", (1.0, 0.0, -0.6), 180),
    ("solid", "filing_cabinet", (1.6, 0.0, -0.6), 180),
    ("solid", "chair", (3.0, 0.0, -0.9), 160),
    ("solid", "rubble_cone", (-9.0, 0.0, -4.3), 0),
    ("walk", "rubble_a", (-5.4, 0.0, -4.2), 90),
    ("walk", "rubble_b", (-5.0, 0.0, -3.9), 10),
    ("walk", "rubble_a", (14.8, 0.0, -2.6), 300),
    ("walk", "helmet", (12.4, 0.0, -2.3), 120),
    # upstairs: a tipped table by the locker, cabinets, a rack by the cabinet, chunks inside the windows
    ("solid", "table_tipped", (15.3, 3.4, 3.9), 270),
    ("solid", "filing_cabinet", (14.4, 3.4, 0.25), 0),
    ("solid", "filing_cabinet", (15.0, 3.4, 0.25), 0),
    ("solid", "shelf_rack", (-5.8, 3.4, -1.3), 90),
    ("walk", "rubble_a", (1.0, 3.4, 1.6), 15),
    ("walk", "rubble_b", (10.2, 3.4, 3.8), 160),
    ("walk", "rubble_a", (-3.0, 3.4, -2.6), 70),
    ("walk", "rubble_b", (9.0, 3.4, -7.4), 220),
    ("walk", "helmet", (14.0, 3.4, -3.0), 80),
    ("walk", "radio", (2.9, 3.4, -0.5), 200),
]


def clutter() -> None:
    bg.node("Dressing", "Node3D", ".")
    counts: dict[str, int] = {}
    for kind, piece, at, yaw in CLUTTER:
        counts[piece] = counts.get(piece, 0) + 1
        rid = fixture(piece) if kind == "solid" else model(piece)
        place("Dressing", f"{piece.title().replace('_', '')}{counts[piece]}", rid, at, yaw)
