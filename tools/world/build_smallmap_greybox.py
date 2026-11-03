"""Write game/world/smallmap/smallmap_greybox.tscn: the greybox of the second map, the small indoor one (#631).

Plain Python, no dependencies; run it from the repository root and commit the scene it writes:

    python tools/world/build_smallmap_greybox.py

The map is built to the hard targets of docs/research/maps/small-map-formula.md (its rows are named below where a
number comes from one) and measured against them by game/tests/world/smallmap/. The floorplan is our own (the design
page, docs/design/smallmap.md): a two-storey depot cut into a bank, a start room with a counter to run round, a long
side room with a row of racks, and an upper floor in two halves over them. Metres, Y up, x east, z south.

Everything is plain boxes: walls, floors and ceilings are CSG with collision (what the walking mesh is baked from),
and what opens or what only players bump into is a StaticBody3D the baker never reads (a window's frame and its
players-only blocker). The kit's modelled pieces replace the boxes later without moving a socket: each window is a
socket node (`Windows/<id>`, +Z into the room), each paid link a door group (`Doors/<id>`), and each room a group of
its own.
"""

import math
from pathlib import Path

import build_greybox as bg

OUT = Path("game/world/smallmap/smallmap_greybox.tscn")
ROOT = "SmallMapGreybox"

# --- Heights (formula rows 9 and 19; the kit's wall modules are 2.8 m and get a 0.4 m band on top) ----------------
CEILING = 3.2  # clear floor-to-ceiling of every room (row 9: 3.0 to 3.6)
SLAB = 0.2  # the floor between the storeys
STOREY = CEILING + SLAB  # 3.4: the stairs' rise (row 19: 3.3 to 4.0)
GROUND_WALL = 0.3  # thickness (the kit's ground-floor block walls)
UPPER_WALL = 0.2  # thickness (the kit's upper timber and plaster walls)

# --- Openings (row 27: every camera passage at least 1.8 m, doors 2.0 m) ----------------------------------------------
DOOR_WIDTH = 2.0  # the paid door and the upstairs opening: the kit's wide opening, 2.0 x 2.4
DOOR_HEIGHT = 2.4
STAIR_WIDTH = 2.0
RISER = 0.2  # the kit's riser and tread: 17 of them make the 3.4 m storey
TREAD = 0.3
STAIR_RUN = round(STOREY / RISER) * TREAD  # 5.1 m
STAIR_PITCH = math.degrees(math.atan2(STOREY, STAIR_RUN))  # 33.7 degrees, under the 45 degree floor limit
# A zombie window: the kit's 1.2 x 1.3 m opening with its sill at 0.9 m, in a 2 m gap of the wall. The gap is what the
# walking mesh sees (a 1.2 m gap would close under the dead's 0.5 m radius); the frame, the sill and the blocker that
# keeps players in are StaticBody3D pieces the baker never reads.
WINDOW_GAP = 2.0
WINDOW_WIDTH = 1.2
WINDOW_SILL = 0.9
WINDOW_TOP = 2.2
PARAPET = 1.2  # round a stairwell upstairs: higher than a jump (1.1 m)
BLOCKER_LAYER = 2  # the boards' layer: players collide with it, shots do not (Barricade.BOARD_LAYER)

# --- Rooms (interior faces): name, (x0, x1, z0, z1), floor height. Rows 4 to 7 ------------------------------------------
START = (0.0, 16.0, 0.0, 14.5)  # the loading hall: 232 m² of shell
SIDE = (-6.0, 16.0, -7.8, -0.3)  # the rewind room: 22 x 7.5 m along the hall's north side (row 7)
UPPER_A = (-0.05, 16.05, -0.05, 4.5)  # over the hall's north strip
UPPER_B = (-6.05, 16.05, -7.85, -0.25)  # over the rewind room
ROOMS = {
    "Start": ("start", START, 0.0),
    "Side": ("side", SIDE, 0.0),
    "UpperA": ("upstairs", UPPER_A, STOREY),
    "UpperB": ("upstairs", UPPER_B, STOREY),
}

# The start room's counter: four pillars and a counter between them, 5 x 3.5 m, the thing a train runs round (row 8:
# a 25 to 36 m loop). The counter is higher than a jump so nobody stands on it.
COUNTER = (5.5, 10.5, 4.5, 8.0)
COUNTER_H = 1.2
PILLAR = 0.5
# The side room's racks: four pillars in a row 3 m apart joined by film racks (row 14: a 25 to 36 m loop).
RACK_ROW = (4.6, 14.1, -4.3, -3.8)
RACK_H = 1.2

# The stairs (row 19): each along its room's north wall, rising east; the foot's landing is the room's corner.
STAIR_A = (3.0, -0.0, 0.0)  # (x of the foot, z of the north edge, floor) in the start room
STAIR_B = (-3.0, -7.8, 0.0)  # in the side room

# The paid links (row 11), with their placeholder price: #632 moves the price into the shop's tuning (formula row 20
# and 21: one price P for all three, 400 to 475, 450 the middle).
LINK_PRICE = 450
DOOR_X = 14.0  # the door between the hall and the rewind room, at the hall's north-east corner (row 10: short sights)
OPENING_X = 12.0  # the opening between the two halves upstairs
LINKS = {
    "Door_Side": "door_side",
    "Stairs_Start": "door_stairs_start",
    "Stairs_Side": "door_stairs_side",
}
STAND = bg.DOOR_STAND_DISTANCE

# The windows (row 15): id, room, the wall's axis and fixed coordinate, the centre along the wall, the inward direction
# (dx, dz), the floor height, the wall thickness. Start 5, side 3 (one a breach), upstairs 4 with each half one or more.
WINDOWS = [
    ("start_1", "start", "x", 14.65, 4.0, (0, -1), 0.0, GROUND_WALL),
    ("start_2", "start", "x", 14.65, 12.0, (0, -1), 0.0, GROUND_WALL),
    ("start_3", "start", "z", 16.15, 4.0, (-1, 0), 0.0, GROUND_WALL),
    ("start_4", "start", "z", 16.15, 8.0, (-1, 0), 0.0, GROUND_WALL),
    ("start_5", "start", "z", 16.15, 12.0, (-1, 0), 0.0, GROUND_WALL),
    ("side_1", "side", "x", -0.15, -4.6, (0, -1), 0.0, GROUND_WALL),
    ("side_2", "side", "x", -0.15, -1.6, (0, -1), 0.0, GROUND_WALL),
    ("upper_a1", "upstairs", "x", 4.6, 4.0, (0, -1), STOREY, UPPER_WALL),
    ("upper_a2", "upstairs", "x", 4.6, 12.0, (0, -1), STOREY, UPPER_WALL),
    ("upper_b1", "upstairs", "x", -7.95, -1.0, (0, 1), STOREY, UPPER_WALL),
    ("upper_b2", "upstairs", "x", -7.95, 9.0, (0, 1), STOREY, UPPER_WALL),
]
# The side room's third entry: a broken wall onto a dead-end pocket the dead come out of (row 15).
BREACH = ("side_breach", "side", "z", -6.15, -2.5, (1, 0), 0.0, GROUND_WALL)
BREACH_HEIGHT = 2.4
SPAWN_OUT = 7.0  # metres outside a window (row 18: 5 to 15)
BREACH_SPAWN_OUT = 6.0

# --- Outside: not playable. Each room's windows open onto ground of their own, so the dead never walk round from one
# room to another outside: the front yard (the hall's windows), the west yard (the rewind room's), the pocket behind
# the breach, the bank (the upper floor's north windows, at the upper floor's height) and the hall's roof (the upper
# floor's south windows). #638 builds the backdrop beyond them.
YARD = (-20.0, 30.0, -26.0, 30.0)
BANK_TOP = STOREY
FENCE_H = 3.0
POCKET = (-13.8, -6.3, -5.0, 0.0)

MIDDLES = {
    "Start": (8.0, 0.0, 11.0),
    "Side": (5.0, 0.0, -2.0),
    "UpperA": (11.0, STOREY, 2.3),
    "UpperB": (5.0, STOREY, -4.0),
}

# Lamps: plain warm lights, one or two a room, on no circuit (whether the generator comes to this map is the
# maintainer's call, formula row 30).
LAMPS = [
    ("Start", (4.0, 2.9, 10.5)),
    ("Start", (12.5, 2.9, 10.5)),
    ("Start", (8.0, 2.9, 2.6)),
    ("Side", (0.0, 2.9, -3.0)),
    ("Side", (10.0, 2.9, -2.0)),
    ("UpperA", (8.5, STOREY + 2.9, 2.5)),
    ("UpperB", (-2.0, STOREY + 2.9, -4.0)),
    ("UpperB", (10.0, STOREY + 2.9, -4.0)),
]
BULB = "#ffd9a0"

# The kit's shell materials (#633) on the walls, floors and ceilings; the lot's for the rest until the kit's pieces
# replace the boxes.
MATS = {
    "floor": "smallmap_floor_ground",
    "wall": "smallmap_wall_ground",
    "upper_wall": "smallmap_wall_upper",
    "upper_floor": "smallmap_floor_upper",
    "ceiling": "smallmap_ceiling",
    "stair": "booth_prop",
    "prop": "concession_prop",
    "rack": "yard_prop",
    "door": "door",
    "yard": "field_ground",
    "bank": "backlot_ground",
    "fence": "field_fence",
    "pocket": "breach_ground",
    "frame": "booth_wall",
}

_shapes: dict[tuple[float, float, float], str] = {}


def box_resources(size: tuple[float, float, float], mat: str | None) -> tuple[str, str | None]:
    """A BoxShape3D (and a BoxMesh in `mat`) of `size`, written once: the ids."""
    key = (round(size[0], 3), round(size[1], 3), round(size[2], 3))
    tag = "x".join(f"{v:g}" for v in key).replace(".", "p").replace("-", "m")
    shape = f"shape_{tag}"
    if key not in _shapes:
        _shapes[key] = shape
        bg.resources += [f'[sub_resource type="BoxShape3D" id="{shape}"]', f"size = {bg.vec(key)}", ""]
    mesh = None
    if mat is not None:
        mesh = f"mesh_{tag}_{mat}"
        if not any(line == f'[sub_resource type="BoxMesh" id="{mesh}"]' for line in bg.resources):
            bg.resources += [
                f'[sub_resource type="BoxMesh" id="{mesh}"]',
                f'material = ExtResource("{mat}")',
                f"size = {bg.vec(key)}",
                "",
            ]
    return shape, mesh


def body(parent: str, name: str, size, pos, layer: int, mat: str | None) -> None:
    """A StaticBody3D box the navigation baker never reads: drawn in `mat` (None: not drawn)."""
    shape, mesh = box_resources(size, mat)
    key = bg.node(name, "StaticBody3D", parent, {"transform": bg.xform(pos), "collision_layer": str(layer),
                                                  "collision_mask": "0"})  # fmt: skip
    bg.node("Shape", "CollisionShape3D", key, {"shape": f'SubResource("{shape}")'})
    if mesh is not None:
        bg.node("Mesh", "MeshInstance3D", key, {"mesh": f'SubResource("{mesh}")'})


def rect_box(parent: str, name: str, rect, y0: float, y1: float, mat: str, layers: int = bg.GROUND_LAYER) -> None:
    x0, x1, z0, z1 = rect
    bg.block(parent, name, x0, x1, z0, z1, y1 - y0, mat, y0, layers)


def slab_with_hole(parent: str, name: str, rect, hole, y0: float, mat: str) -> None:
    """A floor slab over `rect` with a rectangular stairwell `hole` cut out (four boxes round it)."""
    x0, x1, z0, z1 = rect
    hx0, hx1, hz0, hz1 = hole
    pieces = [
        ("N", (x0, x1, z0, hz0)),
        ("S", (x0, x1, hz1, z1)),
        ("W", (x0, hx0, hz0, hz1)),
        ("E", (hx1, x1, hz0, hz1)),
    ]
    for tag, (a0, a1, b0, b1) in pieces:
        if a1 - a0 > 0.01 and b1 - b0 > 0.01:
            rect_box(parent, f"{name}{tag}", (a0, a1, b0, b1), y0, y0 + SLAB, mat)


def stair(parent: str, name: str, foot_x: float, north_z: float, floor: float) -> tuple[float, float, float]:
    """A straight flight rising east from `foot_x` along a north wall at `north_z`: one hidden ramp as its collision
    (the kit's rule: fifteen step-ups bob the view), a wall on its open side up to the ceiling, a wall under its high
    end, and the parapets round its stairwell upstairs. Returns the stairwell (x0, x1, z0, z1)."""
    z0, z1 = north_z, north_z + STAIR_WIDTH
    x1 = foot_x + STAIR_RUN
    length = math.hypot(STAIR_RUN, STOREY)
    c, s = math.cos(math.radians(STAIR_PITCH)), math.sin(math.radians(STAIR_PITCH))
    thick = 0.3
    # The middle of the top face, moved down along the face's normal (-s, c) by half the thickness.
    mx, my = foot_x + STAIR_RUN / 2 - (-s) * thick / 2, floor + STOREY / 2 - c * thick / 2
    ramp = f"Transform3D({c:.4f}, {-s:.4f}, 0, {s:.4f}, {c:.4f}, 0, 0, 0, 1, {mx:.3f}, {my:.3f}, {(z0 + z1) / 2:.3f})"
    bg.node(
        f"{name}Ramp", "CSGBox3D", parent,
        {"transform": ramp, "use_collision": "true", "size": bg.vec((length, thick, STAIR_WIDTH)),
         "material": f'ExtResource("{MATS["stair"]}")'},
    )  # fmt: skip
    # The treads, drawn only (the ramp is what is walked on).
    steps = round(STOREY / RISER)
    for i in range(steps):
        bx = foot_x + (i + 0.5) * TREAD
        top = floor + (i + 1) * RISER
        bg.box(parent, f"{name}Tread{i + 1}", (TREAD, 0.06, STAIR_WIDTH), (bx, top - 0.03, (z0 + z1) / 2),
               MATS["stair"], collide=False)  # fmt: skip
    rect_box(
        parent, f"{name}Side", (foot_x, x1 + 0.2, z1, z1 + 0.2), floor, floor + CEILING, MATS["wall"], bg.WALL_LAYERS
    )
    rect_box(parent, f"{name}End", (x1, x1 + 0.2, z0, z1), floor, floor + CEILING, MATS["wall"], bg.WALL_LAYERS)
    up = floor + STOREY
    rect_box(parent, f"{name}ParapetS", (foot_x - 0.2, x1, z1, z1 + 0.2), up, up + PARAPET, MATS["upper_wall"],
             bg.WALL_LAYERS)  # fmt: skip
    rect_box(parent, f"{name}ParapetW", (foot_x - 0.2, foot_x, z0, z1), up, up + PARAPET, MATS["upper_wall"],
             bg.WALL_LAYERS)  # fmt: skip
    return (foot_x, x1, z0, z1)


def link(name: str, slab_size, slab_at, stands: list[tuple[str, tuple[float, float, float]]]) -> None:
    """A paid link: a door group in `Doors` with its shop id, price and prerequisite (none: every link can be bought
    first, as Nacht's can), one slab the walking mesh is baked around, and a stand on each side a player buys from."""
    props = {
        "metadata/cost": str(LINK_PRICE),
        "metadata/shop_id": f'"{LINKS[name]}"',
        "metadata/requires": '""',
    }
    key = bg.node(name, "Node3D", "Doors", props)
    bg.box(key, "Slab", slab_size, slab_at, MATS["door"])
    for tag, at in stands:
        bg.marker(key, f"Stand{tag}", at)


def window(spec, breach: bool = False) -> tuple[float, float, float]:
    """A window socket in `Windows`: a Node3D on the wall's centre line at floor height, +Z into the room, with the
    frame, the sill and the players-only blocker as its children. Returns where it is."""
    wid, room, axis, fixed, along, inward, floor, thick = spec
    pos = (along, floor, fixed) if axis == "x" else (fixed, floor, along)
    rot = math.degrees(math.atan2(inward[0], inward[1]))
    props = {
        "transform": bg.xform(pos, rot),
        "metadata/barricade_id": f'"{wid}"',
        "metadata/room": f'"{room}"',
        "metadata/kind": '"breach"' if breach else '"window"',
        # The gap in the wall the walking mesh sees: width, height, the wall's thickness.
        "metadata/gap": bg.vec((WINDOW_GAP, BREACH_HEIGHT if breach else WINDOW_TOP, thick)),
    }
    key = bg.node(f"Window_{wid}", "Node3D", "Windows", props)
    jamb = (WINDOW_GAP - WINDOW_WIDTH) / 2
    top = BREACH_HEIGHT if breach else WINDOW_TOP
    if breach:
        opening = WINDOW_GAP - 0.4
        for side in (-1, 1):  # broken edges of the hole, 0.2 m a side
            body(key, f"Edge{'L' if side < 0 else 'R'}", (0.2, top, thick), (side * (WINDOW_GAP / 2 - 0.1), top / 2, 0),
                 bg.WALL_LAYERS, MATS["wall"])  # fmt: skip
        body(key, "Blocker", (opening, top, thick), (0, top / 2, 0), BLOCKER_LAYER, None)
    else:
        for side in (-1, 1):
            body(key, f"Jamb{'L' if side < 0 else 'R'}", (jamb, top, thick + 0.04),
                 (side * (WINDOW_WIDTH / 2 + jamb / 2), top / 2, 0), bg.WALL_LAYERS, MATS["frame"])  # fmt: skip
        body(key, "Sill", (WINDOW_WIDTH, WINDOW_SILL, thick + 0.04), (0, WINDOW_SILL / 2, 0), bg.WALL_LAYERS,
             MATS["frame"])  # fmt: skip
        body(key, "Blocker", (WINDOW_WIDTH, top - WINDOW_SILL, thick), (0, (WINDOW_SILL + top) / 2, 0),
             BLOCKER_LAYER, None)  # fmt: skip
    return pos


def build() -> None:
    lines = bg.lines
    lines.append("[gd_scene format=3]")
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://world/drive_in/lot_doors.gd" id="doors"]')
    lines.append('[ext_resource type="Shader" path="res://world/drive_in/night_sky.gdshader" id="night_sky"]')
    for mid in sorted(set(MATS.values())):
        lines.append(f'[ext_resource type="Material" path="res://assets/lot/materials/{mid}.tres" id="{mid}"]')
    lines.append("")
    lines.extend(bg.night_environment_resources())
    bg.node(ROOT, "Node3D", None, {"metadata/map_id": '"smallmap"', "metadata/storey": f"{STOREY:g}",
                                   "metadata/ceiling": f"{CEILING:g}"})  # fmt: skip

    bg.node("Lighting", "Node3D", ".")
    bg.node("WorldEnvironment", "WorldEnvironment", "Lighting", {"environment": 'SubResource("night")'})
    bg.node(
        "Moon", "DirectionalLight3D", "Lighting",
        {"transform": bg.moon_transform(), "light_color": bg.color(bg.MOON_LIGHT), "light_energy": f"{bg.MOON_ENERGY:g}"},
    )  # fmt: skip

    # --- The rooms: each a group with its rectangle, floor height and room id (what the tests measure by) ----------
    for group_name, (room, rect, floor) in ROOMS.items():
        x0, x1, z0, z1 = rect
        bg.node(
            group_name, "Node3D", ".",
            {"metadata/room": f'"{room}"', "metadata/rect": f"Rect2({x0:g}, {z0:g}, {x1 - x0:g}, {z1 - z0:g})",
             "metadata/floor": f"{floor:g}"},
        )  # fmt: skip

    # Ground floors (one box a room, under its walls) and the slabs over them.
    rect_box("Start", "Floor", (-0.3, 16.3, 0.0, 14.8), -0.4, 0.0, MATS["floor"])
    rect_box("Side", "Floor", (-6.3, 16.3, -8.1, 0.0), -0.4, 0.0, MATS["floor"])
    stair_a = stair("Start", "StairA", STAIR_A[0], STAIR_A[1], 0.0)
    stair_b = stair("Side", "StairB", STAIR_B[0], STAIR_B[1], 0.0)
    bg.node("Ceilings", "Node3D", ".")
    slab_with_hole("Ceilings", "StartSlab", (-0.3, 16.3, 0.0, 14.8), stair_a, CEILING, MATS["upper_floor"])
    slab_with_hole("Ceilings", "SideSlab", (-6.3, 16.3, -8.1, 0.0), stair_b, CEILING, MATS["upper_floor"])

    # Ground walls: (group, name, axis, fixed, from, to, gaps). A gap is (centre, width, bottom, top).
    win = {w[0]: w for w in WINDOWS}

    def gaps_of(*ids: str) -> list[tuple[float, float, float, float]]:
        return [(win[i][4], WINDOW_GAP, 0.0, WINDOW_TOP) for i in ids]

    gw = GROUND_WALL
    bg.wall("Start", "WallW", "z", -0.15, 0.0, 14.8, CEILING, MATS["wall"], thick=gw)
    bg.wall("Start", "WallS", "x", 14.65, -0.3, 16.3, CEILING, MATS["wall"], gaps_of("start_1", "start_2"), gw)
    bg.wall(
        "Start", "WallE", "z", 16.15, 0.0, 14.8, CEILING, MATS["wall"], gaps_of("start_3", "start_4", "start_5"), gw
    )
    side_gaps = gaps_of("side_1", "side_2") + [(DOOR_X, DOOR_WIDTH, 0.0, DOOR_HEIGHT)]
    bg.wall("Side", "WallS", "x", -0.15, -6.3, 16.3, CEILING, MATS["wall"], side_gaps, gw)
    bg.wall("Side", "WallN", "x", -7.95, -6.3, 16.3, CEILING, MATS["wall"], thick=gw)
    bg.wall("Side", "WallE", "z", 16.15, -7.8, -0.3, CEILING, MATS["wall"], thick=gw)
    bg.wall("Side", "WallW", "z", -6.15, -8.1, -0.3, CEILING, MATS["wall"],
            [(BREACH[4], WINDOW_GAP, 0.0, BREACH_HEIGHT)], gw)  # fmt: skip

    # The start room's counter and its pillars (to the ceiling), and the side room's racks.
    cx0, cx1, cz0, cz1 = COUNTER
    rect_box("Start", "DispatchCounter", (cx0 + PILLAR, cx1 - PILLAR, cz0, cz1), 0.0, COUNTER_H, MATS["prop"])
    rect_box("Start", "DispatchCounterW", (cx0, cx0 + PILLAR, cz0 + PILLAR, cz1 - PILLAR), 0.0, COUNTER_H, MATS["prop"])
    rect_box("Start", "DispatchCounterE", (cx1 - PILLAR, cx1, cz0 + PILLAR, cz1 - PILLAR), 0.0, COUNTER_H, MATS["prop"])
    for i, (px, pz) in enumerate(((cx0, cz0), (cx1 - PILLAR, cz0), (cx0, cz1 - PILLAR), (cx1 - PILLAR, cz1 - PILLAR))):
        rect_box(
            "Start", f"Pillar{i + 1}", (px, px + PILLAR, pz, pz + PILLAR), 0.0, CEILING, MATS["wall"], bg.WALL_LAYERS
        )
    rx0, rx1, rz0, rz1 = RACK_ROW
    pillars = 4
    bay = (rx1 - rx0 - PILLAR) / (pillars - 1)
    for i in range(pillars):
        px = rx0 + i * bay
        rect_box("Side", f"Pillar{i + 1}", (px, px + PILLAR, rz0, rz1), 0.0, CEILING, MATS["wall"], bg.WALL_LAYERS)
        if i < pillars - 1:
            rect_box("Side", f"Rack{i + 1}", (px + PILLAR, px + bay, rz0 + 0.05, rz1 - 0.05), 0.0, RACK_H, MATS["rack"])

    # --- Upstairs: two halves joined by an opening with no door (row 3) -------------------------------------------
    up = STOREY
    uw = UPPER_WALL
    bg.wall("UpperA", "WallS", "x", 4.6, -0.25, 16.25, CEILING, MATS["upper_wall"],
            gaps_of("upper_a1", "upper_a2"), uw, up)  # fmt: skip
    bg.wall("UpperA", "WallW", "z", -0.15, -0.05, 4.5, CEILING, MATS["upper_wall"], thick=uw, y0=up)
    bg.wall("UpperA", "WallE", "z", 16.15, -0.05, 4.5, CEILING, MATS["upper_wall"], thick=uw, y0=up)
    bg.wall("UpperB", "WallS", "x", -0.15, -6.25, 16.25, CEILING, MATS["upper_wall"],
            [(OPENING_X, DOOR_WIDTH, 0.0, DOOR_HEIGHT)], uw, up)  # fmt: skip
    bg.wall("UpperB", "WallN", "x", -7.95, -6.25, 16.25, CEILING, MATS["upper_wall"],
            gaps_of("upper_b1", "upper_b2"), uw, up)  # fmt: skip
    bg.wall("UpperB", "WallW", "z", -6.15, -7.85, -0.25, CEILING, MATS["upper_wall"], thick=uw, y0=up)
    bg.wall("UpperB", "WallE", "z", 16.15, -7.85, -0.25, CEILING, MATS["upper_wall"], thick=uw, y0=up)
    bg.node("Roof", "Node3D", ".")
    rect_box("Roof", "Slab", (-6.25, 16.25, -8.05, 4.7), up + CEILING, up + CEILING + SLAB, MATS["ceiling"])
    # The start room's roof south of the upper floor: the dead walk on it to the upper floor's south windows.
    for name, rect in (
        ("ParapetS", (-0.3, 16.3, 14.5, 14.8)),
        ("ParapetW", (-0.3, 0.0, 4.7, 14.5)),
        ("ParapetE", (16.0, 16.3, 4.7, 14.5)),
    ):
        rect_box("Roof", name, rect, up, up + 0.6, MATS["wall"], bg.WALL_LAYERS)

    # --- Windows, the breach, and the dead's spawns outside each (rows 15 and 18) ---------------------------------
    bg.node("Windows", "Node3D", ".")
    bg.node("ZombieSpawns", "Node3D", ".")
    for spec in [*WINDOWS, BREACH]:
        is_breach = spec is BREACH
        at = window(spec, is_breach)
        out = BREACH_SPAWN_OUT if is_breach else SPAWN_OUT
        dx, dz = spec[5]
        spawn = (at[0] - dx * out, at[1], at[2] - dz * out)
        bg.node(f"Spawn_{spec[0]}", "Marker3D", "ZombieSpawns",
                {"transform": bg.xform(spawn), "metadata/barricade_id": f'"{spec[0]}"',
                 "metadata/room": f'"{spec[1]}"'})  # fmt: skip

    # --- The paid links (rows 11 and 19) ---------------------------------------------------------------------------
    bg.node("Doors", "Node3D", ".", {"script": 'ExtResource("doors")'})
    link("Door_Side", (DOOR_WIDTH, DOOR_HEIGHT, 0.3), (DOOR_X, DOOR_HEIGHT / 2, -0.15),
         [("Start", (DOOR_X, 0.0, -0.15 + STAND)), ("Side", (DOOR_X, 0.0, -0.15 - STAND))])  # fmt: skip
    for name, (x0, x1, z0, z1) in (("Stairs_Start", stair_a), ("Stairs_Side", stair_b)):
        mid_z = (z0 + z1) / 2
        rise = STAND * STOREY / STAIR_RUN
        link(name, (0.3, DOOR_HEIGHT, STAIR_WIDTH), (x0, DOOR_HEIGHT / 2, mid_z),
             [("Foot", (x0 - STAND, 0.0, mid_z)), ("Stair", (x0 + STAND, rise, mid_z))])  # fmt: skip

    # --- Players' start (row 17: 4 to 7 m from the nearest window) -------------------------------------------------
    bg.node("PlayerSpawns", "Node3D", ".")
    for i, (sx, sz) in enumerate(((7.0, 10.5), (9.0, 10.5), (7.0, 12.0), (9.0, 12.0)), start=1):
        bg.marker("PlayerSpawns", f"Player{i}", (sx, 0, sz), 180.0)

    # --- Lamps -----------------------------------------------------------------------------------------------------
    for i, (room, at) in enumerate(LAMPS, start=1):
        bg.omni(room, f"Lamp{i}", at, 1.4, 8.0, BULB, powered=False)

    # --- Outside -----------------------------------------------------------------------------------------------------
    bg.node("Outside", "Node3D", ".")
    yx0, yx1, yz0, yz1 = YARD
    # Ground round the building's box (x -6.3..16.3, z -8.1..14.8) and in its notch west of the start room.
    for name, rect in (
        ("GroundS", (yx0, yx1, 14.8, yz1)),
        ("GroundE", (16.3, yx1, -8.1, 14.8)),
        ("GroundW", (yx0, -6.3, -8.1, 14.8)),
        ("GroundNotch", (-6.3, -0.3, 0.0, 14.8)),
    ):
        rect_box("Outside", name, rect, -0.4, 0.0, MATS["yard"])
    rect_box("Outside", "Bank", (yx0, yx1, yz0, -8.1), -0.4, BANK_TOP, MATS["bank"])
    fences = [
        ("FenceS", (yx0, yx1, yz1 - 0.4, yz1)),
        ("FenceW", (yx0, yx0 + 0.4, -8.1, yz1)),
        ("FenceE", (yx1 - 0.4, yx1, -8.1, yz1)),
        ("FenceSplit", (-0.5, -0.1, 14.8, yz1 - 0.4)),  # the hall's yard and the rewind room's yard are apart
        ("BankRim", (yx0, yx1, yz0, yz0 + 0.4)),
    ]
    px0, px1, pz0, pz1 = POCKET
    fences += [
        ("PocketN", (px0, px1, pz0 - 0.3, pz0)),
        ("PocketS", (px0, px1, pz1, pz1 + 0.3)),
        ("PocketW", (px0 - 0.3, px0, pz0 - 0.3, pz1 + 0.3)),
    ]
    for name, (x0, x1, z0, z1) in fences:
        base = BANK_TOP if name == "BankRim" else 0.0
        rect_box("Outside", name, (x0, x1, z0, z1), base, base + FENCE_H, MATS["fence"], bg.WALL_LAYERS)
    rect_box("Outside", "PocketRoof", (px0 - 0.3, px1, pz0 - 0.3, pz1 + 0.3), CEILING, CEILING + SLAB, MATS["ceiling"])

    # --- Camera probes (row 28): every door, stair, opening and corner. Each faces the way a player walks through ----
    bg.node("CameraProbes", "Node3D", ".")
    sa_x0, sa_x1, sa_z0, sa_z1 = stair_a
    sb_x0, sb_x1, sb_z0, sb_z1 = stair_b
    for name, (x, y, z), (dx, dz) in (
        ("Door_Side", (DOOR_X, 0.0, -0.15), (0, -1)),
        ("Opening", (OPENING_X, up, -0.15), (0, -1)),
        ("StairA_Foot", (sa_x0 + 0.6, 0.4, (sa_z0 + sa_z1) / 2), (1, 0)),
        ("StairA_Mid", ((sa_x0 + sa_x1) / 2, STOREY / 2, (sa_z0 + sa_z1) / 2), (1, 0)),
        ("StairA_Top", (sa_x1 + 0.5, up, (sa_z0 + sa_z1) / 2), (1, 0)),
        ("StairB_Foot", (sb_x0 + 0.6, 0.4, (sb_z0 + sb_z1) / 2), (1, 0)),
        ("StairB_Mid", ((sb_x0 + sb_x1) / 2, STOREY / 2, (sb_z0 + sb_z1) / 2), (1, 0)),
        ("StairB_Top", (sb_x1 + 0.5, up, (sb_z0 + sb_z1) / 2), (1, 0)),
        ("Corner_CounterN", ((cx0 + cx1) / 2, 0.0, (2.2 + cz0) / 2), (1, 0)),
        ("Corner_CounterW", ((0.0 + cx0) / 2, 0.0, (cz0 + cz1) / 2), (0, 1)),
        ("Corner_RacksW", ((sb_x1 + 0.2 + rx0) / 2, 0.0, (rz0 + rz1) / 2), (0, 1)),
        ("Corner_RacksE", ((rx1 + 16.0) / 2, 0.0, (rz0 + rz1) / 2), (0, 1)),
        ("Corner_RacksN", ((rx0 + rx1) / 2, 0.0, (-7.8 + rz0) / 2), (1, 0)),
        ("Corner_StairAEnd", (sa_x1 + 0.2 + 1.0, 0.0, 3.2), (1, 0)),
        ("Corner_UpperA", (sa_x0 + 1.5, up, (sa_z1 + 0.2 + 4.5) / 2), (1, 0)),
    ):
        bg.probe(name, (x, y, z), dx, dz)

    # --- Measuring markers: the ring's lap (row 13) and the two loops (rows 8 and 14) --------------------------------
    bg.node("Measure", "Node3D", ".")
    bg.node("Ring", "Node3D", "Measure")
    ring = [
        ("1_DoorStart", (DOOR_X, 0.0, -0.15 + STAND)),
        ("2_StairAFoot", (sa_x0 - STAND, 0.0, (sa_z0 + sa_z1) / 2)),
        ("3_StairATop", (sa_x1 + STAND, up, (sa_z0 + sa_z1) / 2)),
        ("4_Opening", (OPENING_X, up, -0.15)),
        ("5_StairBTop", (sb_x1 + STAND, up, (sb_z0 + sb_z1) / 2)),
        ("6_StairBFoot", (sb_x0 - STAND, 0.0, (sb_z0 + sb_z1) / 2)),
        ("7_DoorSide", (DOOR_X, 0.0, -0.15 - STAND)),
    ]
    for name, at in ring:
        bg.marker("Measure/Ring", name, at)
    bg.node("LoopStart", "Node3D", "Measure")
    for i, (x, z) in enumerate(((cx0 - 1.5, cz0 - 1.5), (cx1 + 1.5, cz0 - 1.5), (cx1 + 1.5, cz1 + 1.5),
                                (cx0 - 1.5, cz1 + 1.5)), start=1):  # fmt: skip
        bg.marker("Measure/LoopStart", f"Corner{i}", (x, 0.0, z))
    # A point in the open middle of each room (or half): where its directions are judged from, and where a path to the
    # room ends.
    bg.node("Middles", "Node3D", "Measure")
    for name, at in MIDDLES.items():
        bg.marker("Measure/Middles", name, at)
    bg.node("LoopSide", "Node3D", "Measure")
    north, south = (-7.8 + rz0) / 2, (rz1 + -0.3) / 2
    west, east = (sb_x1 + 0.2 + rx0) / 2, (rx1 + 16.0) / 2
    for i, (x, z) in enumerate(((west, north), (east, north), (east, south), (west, south)), start=1):
        bg.marker("Measure/LoopSide", f"Corner{i}", (x, 0.0, z))

    root = lines.index(f'[node name="{ROOT}" type="Node3D"]')
    lines[root:root] = bg.resources
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {OUT}: {len(bg.node_names)} nodes")


if __name__ == "__main__":
    build()
