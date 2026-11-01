"""The kit props that dress the drive-in lot: their scenes and where they stand (used by build_greybox.py).

Plain Python, no dependencies. The models are `game/assets/props/*.gltf`, written by tools/blender/build_props.py from
the Quaternius Toon Shooter Game Kit (CC0); `props.json` beside them gives each one's size. `write_scenes()` writes a
scene per prop into `game/world/drive_in/props/`: the model, and for a prop that stands in the way a hidden CSG block
of its size with collision. The blocks are what the zombies' navigation mesh is baked from (navmesh_baker.gd reads CSG
shapes with collision only), what the player walks into and what the camera's spring arm hits; clutter on the ground
(cones, pallets, planks, debris, a lone box, a spilt drum, a gas can) has none, so it never closes a path.

Where props go (docs/design/map.md): against walls or in clusters with no slot between them narrower than a passage,
never in a door, a breach or its apron, a camera passage or a shop spot, and nothing a player can step up on stands
within a jump of a taller block (a crate beside a container would be a stair out of the lot).
"""

import json
from pathlib import Path

ASSETS = Path("game/assets/props")
SCENES = Path("game/world/drive_in/props")

# prop -> its blocker: "box", "cyl" (round drums and tanks) or None (clutter, nothing to walk into).
BLOCKERS = {
    "barrier": "box",
    "crate": "box",
    "boxes": "box",
    "box": None,
    "barrel": "cyl",
    "barrel_spill": None,
    "container": "box",
    "container_small": "box",
    "pallet": None,
    "pallet_broken": None,
    "cone": None,
    "dumpster": "box",
    "gas_can": None,
    "debris": None,
    "tires": "box",
    "planks": None,
    "gas_tank": "cyl",
    "water_tank": "box",
}

# Area -> (prop, x, z, yaw in degrees). Metres in the lot's frame (x east, z south). A prop's long side runs along x
# at yaw 0. The comments name what a prop replaces from the greybox, which kept its footprint.
DRESSING: dict[str, list[tuple[str, float, float, float]]] = {
    "Midway": [
        # The alleys' dumpsters, against the alley ends, a box and a spilt drum beside each.
        ("dumpster", -13.8, -3.25, 0),
        ("box", -11.6, -3.2, 20),
        ("dumpster", 13.8, -3.25, 0),
        ("barrel_spill", 11.2, -2.6, 200),
        ("debris", -13.0, 3.0, 40),
        ("pallet_broken", 13.2, 4.0, 75),
        # Crate stack A (west of the court) and B (east, by the booth): a stack of cartons and a small container.
        ("boxes", -10.7, 15.2, 90),
        ("pallet", -12.3, 13.4, 10),
        ("box", -12.2, 16.8, 35),
        ("container_small", 10.7, 29.2, 90),
        ("planks", 12.6, 27.0, 60),
        # Along the fence by the road gate.
        ("cone", -3.0, 36.6, 0),
        ("cone", 3.0, 36.6, 0),
    ],
    "GeneratorYard": [
        # Container A: a shipping container and a small one, end to end.
        ("container", 25.55, 7.3, 0),
        ("container_small", 28.2, 7.3, 0),
        # Container B.
        ("container", 51.6, 27.3, 0),
        ("container_small", 54.23, 27.3, 0),
        # The drum row: six drums in two touching rows, a spilt one at the end.
        ("barrel", 20.69, 2.7, 0),
        ("barrel", 21.31, 2.7, 0),
        ("barrel", 20.69, 3.33, 0),
        ("barrel", 21.31, 3.33, 0),
        ("barrel", 20.69, 3.96, 0),
        ("barrel", 21.31, 3.96, 0),
        ("barrel_spill", 21.0, 6.6, 90),
        # The pallets: cartons on a pallet, a broken one, a gas can.
        ("pallet", 25.0, 30.6, 15),
        ("boxes", 26.8, 29.0, 0),
        ("pallet_broken", 28.6, 30.4, 25),
        ("gas_can", 29.6, 28.6, 70),
        # Gas bottles against the generator cage's north wall, outside; a water tank on the east fence.
        ("gas_tank", 38.8, 14.35, 0),
        ("gas_tank", 39.65, 14.35, 0),
        ("water_tank", 60.85, 18.0, 90),
        ("tires", 61.05, 24.0, 90),
        ("cone", 38.0, -1.6, 0),
        ("cone", 42.0, -1.6, 0),
    ],
    "BackLot": [
        ("tires", -61.05, 22.5, 90),
        ("debris", -36.0, 26.6, 10),
        ("barrel_spill", -46.0, 26.5, 160),
        ("pallet_broken", -29.0, 33.2, 50),
        ("planks", -54.5, 33.0, 120),
    ],
    "Road": [
        # Barriers before the roadblock to town, cones leading to them; kept off the road's low end walls (1.6 m), which
        # a barrier's top would put within a jump.
        ("barrier", 52.0, 54.0, 90),
        ("barrier", 52.0, 55.6, 90),
        ("cone", 50.0, 53.4, 0),
        ("cone", 47.0, 53.4, 0),
        ("cone", 44.0, 53.4, 0),
        ("debris", 26.0, 56.0, 30),
        ("box", -9.6, 41.0, 15),
        ("crate", 9.6, 45.0, 0),
        ("crate", 9.6, 45.64, 10),
    ],
    "Field": [
        ("pallet_broken", -49.0, -24.5, 30),
        ("cone", 48.0, -36.0, 0),
        ("cone", 50.0, -36.0, 0),
        ("debris", 56.0, -10.0, 60),
    ],
}

# The wrecks (the back lot's rows, the field's flanks, the road) are the kit's Broken Car; the parked cars are the
# lot's own sedan in five paints (world/drive_in/car.gd picks one).
WRECK = "res://world/drive_in/wreck.tscn"


def camel(name: str) -> str:
    return "".join(part.capitalize() for part in name.split("_"))


def sizes() -> dict[str, tuple[float, float, float]]:
    """Prop -> (width x, height y, depth z) in metres, from build_props.py's report."""
    report = json.loads((ASSETS / "props.json").read_text(encoding="utf-8"))
    return {k: (v["size_xzy"][0], v["size_xzy"][2], v["size_xzy"][1]) for k, v in report.items()}


def scene_text(name: str, size: tuple[float, float, float]) -> str:
    w, h, d = size
    lines = [
        "[gd_scene format=3]",
        "",
        f'[ext_resource type="PackedScene" path="res://assets/props/{name}.gltf" id="model"]',
        "",
        f'[node name="{camel(name)}" type="Node3D"]',
        "",
        '[node name="Model" parent="." instance=ExtResource("model")]',
    ]
    kind = BLOCKERS[name]
    if kind == "box":
        lines += [
            "",
            '[node name="Blocker" type="CSGBox3D" parent="."]',
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {h / 2:.3f}, 0)",
            "visible = false",
            "use_collision = true",
            f"size = Vector3({w:.3f}, {h:.3f}, {d:.3f})",
        ]
    elif kind == "cyl":
        lines += [
            "",
            '[node name="Blocker" type="CSGCylinder3D" parent="."]',
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {h / 2:.3f}, 0)",
            "visible = false",
            "use_collision = true",
            f"radius = {max(w, d) / 2:.3f}",
            f"height = {h:.3f}",
            "sides = 12",
        ]
    return "\n".join(lines) + "\n"


def write_scenes() -> None:
    SCENES.mkdir(parents=True, exist_ok=True)
    found = sizes()
    for name in BLOCKERS:
        (SCENES / f"{name}.tscn").write_text(scene_text(name, found[name]), encoding="utf-8", newline="\n")


def used() -> list[str]:
    """The props the lot places, in a fixed order (the scene's ext_resource list)."""
    return sorted({prop for spots in DRESSING.values() for prop, *_ in spots})


def ext_resources() -> list[str]:
    return [
        f'[ext_resource type="PackedScene" path="res://world/drive_in/props/{name}.tscn" id="prop_{name}"]'
        for name in used()
    ]


def dress(area: str, group, instance) -> None:
    """Place the area's props under `<area>/Dressing`, with the generator's `group` and `instance` helpers."""
    spots = DRESSING.get(area, [])
    if not spots:
        return
    parent = group("Dressing", area)
    counts: dict[str, int] = {}
    for prop, x, z, yaw in spots:
        counts[prop] = counts.get(prop, 0) + 1
        instance(parent, f"{camel(prop)}{counts[prop]}", f"prop_{prop}", (x, 0, z), yaw)
