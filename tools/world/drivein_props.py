"""The drive-in's own props (tools/blender/build_drivein_props.py) in the lot: their scenes and where they stand.

Used by build_greybox.py. `write_scenes()` writes `game/world/drive_in/fixtures/<name>.tscn`: the glTF model and its
collision as hidden CSG shapes (the navigation and the camera tests read CSG; game/gameplay/zombies/navmesh_baker.gd).
A prop that replaces a greybox block keeps that block's collision box exactly, so the walking mesh and the camera
probes see the same lot. `place()` puts them in the lot (docs/design/map.md): every place is chosen clear of the
paths, doors, breaches, breaker posts and camera probes.
"""

import math
from pathlib import Path

SCENES = Path("game/world/drive_in/fixtures")
MODELS = "res://assets/drivein"

# name -> collision shapes in the prop's own frame: ("box", size, centre) or ("cyl", (radius, height), centre).
FIXTURES = {
    "speaker_post": [("cyl", (0.08, 1.45), (0, 0.725, 0))],
    "trash_can": [("cyl", (0.3, 1.0), (0, 0.5, 0))],
    "picnic_table": [("box", (1.8, 0.8, 1.5), (0, 0.4, 0))],
    "popcorn_machine": [("box", (0.74, 1.0, 0.54), (0, 0.5, 0))],
    "menu_board": [("box", (4.2, 1.6, 0.16), (0, 0.8, 0))],
    # The greybox's blocks, unchanged: KioskW/E, Counter, Projector.
    "ticket_booth": [("box", (2.4, 2.4, 2.4), (0, 1.2, 0))],
    "concession_counter": [("box", (10.0, 1.0, 2.0), (0, 0.5, 0))],
    "projector": [("box", (2.0, 1.3, 1.5), (0, 0.65, 0))],
    # ScreenFrame, ScreenLegN10/10 and ScreenStayN14/14, about the screen's foot (0, 0, -48).
    "screen_frame": [
        ("box", (33.6, 13.6, 0.8), (0, 10, -0.7)),
        ("box", (1.4, 4.2, 1.6), (-10, 2.1, 0)),
        ("box", (1.4, 4.2, 1.6), (10, 2.1, 0)),
        ("box", (0.8, 0.8, 7.0), (-14, 3.0, -4.8)),
        ("box", (0.8, 0.8, 7.0), (14, 3.0, -4.8)),
    ],
    "marquee": [
        ("box", (0.4, 5.6, 0.4), (-2.6, 2.8, 0)),
        ("box", (0.4, 5.6, 0.4), (2.6, 2.8, 0)),
        ("box", (6.2, 2.6, 0.5), (0, 4.2, 0)),
    ],
}

# The greybox blocks these props take the place of (build_greybox.py leaves them out).
REPLACED = {"Counter", "Projector", "KioskW", "KioskE", "PicnicTable", "ScreenFrame", "ScreenLegN10", "ScreenLeg10",
            "ScreenStayN14", "ScreenStay14"}  # fmt: skip

SPEAKER_AHEAD = 0.55  # metres from a car's nose to its speaker post, towards the screen
SPEAKER_CLEAR = 1.5  # no post this close to a lamp post


def _scene_name(name: str) -> str:
    return "".join(w.capitalize() for w in name.split("_"))


def write_scenes() -> None:
    SCENES.mkdir(parents=True, exist_ok=True)
    for name, shapes in FIXTURES.items():
        out = [
            "[gd_scene format=3]",
            "",
            f'[ext_resource type="PackedScene" path="{MODELS}/{name}.gltf" id="model"]',
            "",
            f'[node name="{_scene_name(name)}" type="Node3D"]',
            "",
            '[node name="Model" parent="." instance=ExtResource("model")]',
            "",
        ]
        for i, (kind, size, (x, y, z)) in enumerate(shapes, start=1):
            t = f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, {y:g}, {z:g})"
            node = "Blocker" if len(shapes) == 1 else f"Blocker{i}"
            if kind == "box":
                out += [f'[node name="{node}" type="CSGBox3D" parent="."]', f"transform = {t}", "visible = false",
                        "use_collision = true", "size = Vector3({:g}, {:g}, {:g})".format(*size), ""]  # fmt: skip
            else:
                out += [f'[node name="{node}" type="CSGCylinder3D" parent="."]', f"transform = {t}", "visible = false",
                        "use_collision = true", f"radius = {size[0]:g}", f"height = {size[1]:g}", "sides = 8", ""]  # fmt: skip
        (SCENES / f"{name}.tscn").write_text("\n".join(out).rstrip() + "\n", encoding="utf-8", newline="\n")


def ext_resources() -> list[str]:
    return [
        f'[ext_resource type="PackedScene" path="res://world/drive_in/fixtures/{n}.tscn" id="fx_{n}"]' for n in FIXTURES
    ]


def place(instance, group, car_slots, screen_c, lamps) -> int:
    """Put the props in the lot. `car_slots` is (row, radius, angle) of every parked car on the field, `lamps` the
    field's lamp posts (x, z). Returns the number of speaker posts."""

    def put(parent, name, fx, pos, rot=0.0):
        instance(parent, name, f"fx_{fx}", pos, rot)

    # The screen: its frame and back truss, legs and stays.
    put("Field", "ScreenFrame", "screen_frame", (0, 0, -48))
    # Speaker posts: one in front of every other car's nose, towards the screen, its speakers along the radius. Never
    # on a gap between two cars (the camera's way through) and never beside a lamp post.
    posts = group("SpeakerPosts", "Field")
    n = 0
    by_row: dict[int, list[tuple[float, float]]] = {}
    for ri, radius, a in car_slots:
        by_row.setdefault(ri, []).append((radius, a))
    for ri, slots in sorted(by_row.items()):
        for k, (radius, a) in enumerate(slots):
            if k % 2:
                continue
            r = radius - 2.25 - SPEAKER_AHEAD
            x = screen_c[0] + r * math.sin(math.radians(a))
            z = screen_c[1] + r * math.cos(math.radians(a))
            if any(math.hypot(x - lx, z - lz) < SPEAKER_CLEAR for lx, lz in lamps):
                continue
            n += 1
            put(posts, f"Post{n:02d}", "speaker_post", (x, 0, z), a + 90)
    # The picnic shelter on the east flank: two tables under the roof.
    put("Field/Props", "PicnicTableA", "picnic_table", (46.4, 0, -31), 90)
    put("Field/Props", "PicnicTableB", "picnic_table", (49.4, 0, -31), 90)
    cans = group("TrashCans", "Field")
    for i, (x, z) in enumerate([(-3.4, -4.8), (3.4, -4.8), (43.2, -29.2), (-42.4, -29.6)], start=1):
        put(cans, f"Can{i}", "trash_can", (x, 0, z))
    # The stand: the counter (the greybox's), the popcorn machine on it and the menu board on the back wall.
    put("Concession", "Counter", "concession_counter", (0, 0, 2), 180)
    put("Concession", "PopcornMachine", "popcorn_machine", (-2.6, 0.96, 2.05), 180)
    put("Concession", "MenuBoard", "menu_board", (0, 2.2, 7.72), 180)
    # The midway behind it: tables and cans by the stand's rear exits.
    put("Midway", "PicnicTableW", "picnic_table", (-11, 0, 11.5))
    put("Midway", "PicnicTableE", "picnic_table", (11, 0, 11.5))
    put("Midway", "CanW", "trash_can", (-8.4, 0, 9.3))
    put("Midway", "CanE", "trash_can", (8.4, 0, 9.3))
    # The booth's projector (the greybox's block), its lens at the port.
    put("ProjectionBooth", "Projector", "projector", (0, 4.05, 25.25))
    # The entrance: the two ticket booths (the greybox's kiosks), the marquee by the road, cans on the plaza.
    put("Road", "TicketBoothW", "ticket_booth", (-6, 0, 45.2))
    put("Road", "TicketBoothE", "ticket_booth", (6, 0, 45.2))
    put("Road", "Marquee", "marquee", (12.4, 0, 50.6))
    put("Road", "CanW", "trash_can", (-8.4, 0, 43.4))
    put("Road", "CanE", "trash_can", (8.4, 0, 43.4))
    return n
