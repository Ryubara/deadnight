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

# prop -> its blocker: "box", "cyl" (round drums and tanks), "trunk" (a tree: only its trunk, TRUNK_RADIUS wide and up to
# TRUNK_HEIGHT, above a jump, so nobody climbs a tree) or None (clutter, nothing to walk into).
TRUNK_RADIUS = 0.3
TRUNK_HEIGHT = 2.4
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
    "water_tank_floor": "box",
    "tree": "trunk",
    "tree_tall": "trunk",
    "tree_small": "trunk",
    "tree_pine": "trunk",
    "trash_open": "box",
    "sofa": "box",
    "sofa_small": "box",
    "sign": None,
    "pipes": "box",
    "fence": "box",
    "fence_long": "box",
    "brick_wall": "box",
    "brick_wall_low": "box",
    "barrier_large": "box",
    "barrier_fixed": "box",
    "papers": None,
    "papers_b": None,
    "papers_c": None,
    "street_light": None,
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
        # The west alley, a dead end for ambushes: drums and crates on the fence, a pallet on the stand's wall.
        ("barrel", -15.3, 0.0, 0),
        ("barrel", -15.3, 0.7, 0),
        ("barrel", -14.6, 0.35, 0),
        ("crate", -15.35, 6.0, 0),
        ("crate", -14.7, 6.05, 15),
        ("pallet", -10.9, 5.4, 90),
        ("gas_can", -11.3, 1.2, 30),
        ("planks", -12.6, 6.9, 80),
        # The east alley: cartons on the fence, a stack of tyres on the stand's wall.
        ("box", 15.2, 0.6, 10),
        ("box", 15.25, 1.45, 355),
        ("crate", 15.3, 6.3, 0),
        ("tires", 10.75, 6.4, 90),
        ("debris", 12.6, 1.2, 120),
        # Behind the stand, between and beside its rear exits (x -5 and 5 stay clear).
        ("boxes", -9.35, 8.59, 0),  # beside the trash can of #264
        ("crate", -6.95, 8.75, 10),
        ("barrel", -9.6, 9.7, 0),
        ("gas_can", -8.2, 10.2, 300),
        ("pallet", -2.0, 9.3, 0),
        ("boxes", 0.6, 8.59, 0),
        ("box", 2.0, 8.95, 20),
        ("barrel", 7.2, 8.75, 0),
        ("barrel", 7.85, 8.75, 0),
        ("barrel", 7.5, 9.35, 0),
        ("planks", 9.0, 10.0, 15),
        # The court's fences, clear of the links (z 17.75 to 22.25), the locker (x 14.6, z 12) and the spawns.
        ("box", 15.2, 9.3, 0),
        ("pallet_broken", -15.0, 10.6, 90),
        ("barrel", -15.3, 25.0, 0),
        ("barrel", -15.3, 25.7, 0),
        ("barrel_spill", -14.4, 27.4, 100),
        ("crate", -15.3, 30.0, 0),
        ("crate", -15.3, 30.65, 5),
        ("crate", -14.65, 30.3, 350),
        ("tires", -15.3, 33.0, 90),
        ("barrel", 15.3, 25.0, 0),
        ("barrel", 15.3, 25.7, 0),
        ("gas_tank", 15.3, 31.6, 0),
        # Along the booth: a container on its west side, film crates on its east side.
        ("container", -7.15, 27.5, 90),
        ("boxes", 6.59, 30.6, 90),
        ("crate", 6.75, 28.4, 0),
        ("crate", 6.75, 29.05, 10),
        ("barrel", 7.0, 24.6, 0),
        # South of the booth, either side of the road gate (x -3 to 3 stays clear).
        ("barrier", -8.0, 35.6, 0),
        ("barrier", 8.0, 35.6, 0),
        ("pallet", -10.5, 33.8, 30),
        # Two piles in the court between the stand and the booth, and one by the west fence.
        ("crate", 9.8, 17.0, 0),
        ("crate", 10.45, 17.05, 10),
        ("barrel", 10.1, 17.7, 0),
        ("barrel", -12.0, 11.0, 0),
        ("barrel", -11.4, 11.2, 0),
        ("boxes", -12.5, 25.0, 0),
        ("pallet", 12.0, 33.4, 70),
        ("box", 11.0, 34.8, 30),
        # The east pass's models: a pile of pipes by the west fence, a sign by the
        # road gate and loose papers over the court.
        ("pipes", -12.0, 31.5, 0),
        ("sign", 4.2, 36.2, 200),
        ("papers", -3.0, 14.0, 0),
        ("papers_b", 5.0, 13.0, 40),
        ("papers_c", -8.0, 19.0, 110),
        ("papers", 8.0, 20.5, 70),
        ("papers_b", -1.0, 34.0, 200),
        ("papers_c", 12.0, 10.5, 15),
        ("papers", -13.0, 2.5, 300),
        ("papers_b", 12.5, -1.0, 90),
    ],
    "Concession": [
        # Behind the counter (its south side; the kiting lane behind it stays 3.8 m wide): cartons and crates of stock.
        ("boxes", -3.0, 3.39, 0),
        ("box", -1.2, 3.6, 10),
        ("crate", 2.6, 3.5, 0),
        ("crate", 3.3, 3.5, 5),
        # The back corners, clear of the rear exits, the crane's spot and the locker.
        ("boxes", -9.24, 7.4, 0),
        ("crate", 9.4, 7.4, 0),
        ("crate", 8.75, 7.4, 10),
        ("gas_can", 7.6, 7.5, 80),
        ("box", 9.35, -3.35, 15),
        ("box", -9.35, -3.3, 340),
        ("crate", -9.4, 0.5, 0),
        ("crate", -9.4, 1.15, 10),
        ("papers", -6.0, -1.0, 30),
        ("papers_b", 6.0, 0.5, 120),
        ("papers_c", 0.0, 6.0, 250),
    ],
    "ProjectionBooth": [
        # Film crates under the upper floor, in the corners away from the door and the ramp's foot.
        ("crate", 5.3, 31.3, 0),
        ("crate", 4.65, 31.3, 5),
        ("crate", 5.3, 30.65, 350),
        ("boxes", 5.2, 24.6, 90),
        ("box", 1.9, 24.0, 20),
        ("barrel", 0.0, 31.3, 0),
        ("box", 0.9, 31.3, 15),
        ("papers_b", 3.0, 26.0, 60),
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
        ("tires", 61.34, 24.0, 90),
        ("cone", 38.0, -1.6, 0),
        ("cone", 42.0, -1.6, 0),
        # Density pass: pipes on the north fence, a skip by the fuel tanks, hoardings and drums on the south fence,
        # crates on the cage's south wall, a tree in the south-east corner, litter.
        ("pipes", 50.0, -3.4, 90),
        ("trash_open", 60.75, 9.0, 90),
        ("barrier_large", 40.0, 37.5, 0),
        ("barrier_large", 43.05, 37.5, 0),
        ("barrel", 46.5, 37.45, 0),
        ("barrel", 47.13, 37.45, 0),
        ("barrel", 46.82, 36.83, 0),
        ("crate", 39.0, 21.52, 0),
        ("crate", 39.63, 21.52, 0),
        ("gas_can", 41.0, 13.9, 30),
        ("tree_small", 59.5, 33.0, 0),
        ("sign", 17.6, 16.6, 90),
        ("debris", 33.0, 31.0, 50),
        ("planks", 54.0, 18.5, 80),
        ("box", 30.5, 9.6, 15),
        ("papers", 24.0, 15.0, 0),
        ("papers_b", 48.0, 8.0, 30),
        ("papers_c", 36.0, 30.0, 70),
        ("papers_b", 22.0, 26.0, 110),
    ],
    "BackLot": [
        ("tires", -61.34, 22.5, 90),
        ("debris", -36.0, 26.6, 10),
        ("barrel_spill", -46.0, 26.5, 160),
        ("pallet_broken", -29.0, 33.2, 50),
        ("planks", -54.5, 33.0, 120),
        # Only low junk here (under 0.9 m): the bus (3 m) and the scrap stacks (2.6 m) must not get a step up.
        # The lane between the first two wreck rows (z 7 to 13).
        ("debris", -50.0, 10.0, 20),
        ("pallet_broken", -42.5, 9.6, 60),
        ("tires", -34.0, 10.0, 0),
        ("barrel", -27.5, 9.0, 0),
        ("barrel", -26.9, 9.3, 0),
        ("planks", -38.0, 11.2, 100),
        ("cone", -23.0, 10.6, 0),
        # The wide lane round the bus and the scrap stacks (z 15 to 29), clear of the locker (x -24, z 18).
        ("barrel", -43.5, 25.4, 0),
        ("barrel", -42.9, 25.6, 0),
        ("barrel", -43.2, 26.2, 0),
        ("tires", -36.5, 17.4, 30),
        ("box", -30.0, 17.4, 10),
        ("crate", -28.2, 25.0, 0),
        ("crate", -28.8, 25.3, 20),
        ("pallet", -38.0, 26.0, 20),
        ("debris", -51.0, 28.2, 70),
        ("gas_can", -33.5, 26.8, 40),
        # The last lane before the road fence (z 31 to 38), clear of the spawns at x -60 and -30.
        ("barrier", -38.0, 34.0, 0),
        ("barrier", -36.4, 34.0, 0),
        ("cone", -40.0, 33.4, 0),
        ("barrel", -55.0, 35.0, 0),
        ("barrel", -54.4, 35.3, 0),
        ("crate", -24.0, 34.5, 0),
        ("crate", -24.0, 35.15, 5),
        ("box", -23.2, 34.8, 25),
        # Along the field's fence (z -4), clear of the gate (x -43 to -37) and the spawn at x -60.
        ("pallet_broken", -50.0, -1.6, 10),
        ("barrel", -30.0, -3.2, 0),
        ("barrel", -29.4, -3.2, 0),
        ("tires", -25.0, -2.6, 0),
        ("crate", -16.75, 2.0, 0),
        ("crate", -16.75, 2.65, 10),
        # More junk through the lanes; one container in the open, far from every wall, the bus and the scrap stacks.
        ("container", -40.0, 18.0, 0),
        ("barrel", -57.0, 10.0, 0),
        ("barrel", -56.4, 10.2, 0),
        ("barrel_spill", -55.0, 11.5, 30),
        ("box", -46.0, 10.4, 15),
        ("box", -45.3, 10.9, 40),
        ("crate", -31.0, 11.5, 0),
        ("crate", -30.4, 11.6, 10),
        ("tires", -20.0, 10.0, 90),
        ("pallet", -48.0, 17.0, 40),
        ("planks", -55.0, 16.5, 10),
        ("gas_can", -48.5, 16.0, 0),
        ("debris", -40.0, 27.8, 120),
        ("barrel", -34.0, 27.5, 0),
        ("barrel", -33.4, 27.7, 0),
        ("cone", -45.0, 32.5, 0),
        ("cone", -43.0, 32.5, 0),
        ("box", -57.5, 33.0, 20),
        ("pallet_broken", -20.5, 31.5, 10),
        ("crate", -18.5, 26.0, 0),
        ("crate", -18.5, 26.65, 10),
        # The east pass's models: sofas and pipes dumped in the lanes, a fallen sign, papers everywhere.
        ("sofa", -52.0, 32.5, 10),
        ("sofa_small", -21.0, 25.5, 90),
        ("pipes", -46.0, 3.0, 90),
        ("pipes", -27.0, 32.6, 90),
        ("sign", -59.5, 15.0, 90),
        ("papers", -50.0, 12.0, 0),
        ("papers_b", -40.0, 9.0, 80),
        ("papers_c", -30.0, 15.5, 160),
        ("papers", -48.0, 27.0, 20),
        ("papers_b", -36.0, 33.0, 300),
        ("papers_c", -22.0, 7.0, 45),
        ("papers", -55.0, 1.0, 210),
        ("papers_b", -33.0, 21.0, 10),
    ],
    "Road": [
        # The ticket plaza behind the road door (#686): litter by the kiosks, queue barriers to them, a tree in each north
        # corner, street lights (models only: the lot's lights are the lamps) on the side walls, a sign at the gate.
        ("box", -9.6, 41.0, 15),
        ("crate", 9.6, 45.0, 0),
        ("crate", 9.6, 45.64, 10),
        ("fence_long", -3.0, 42.0, 90),
        ("fence_long", 3.0, 42.0, 90),
        ("tree_small", -14.0, 40.0, 0),
        ("tree_small", 14.0, 40.0, 0),
        ("street_light", -15.4, 46.0, 0),
        ("street_light", 15.4, 46.0, 0),
        ("street_light", -15.4, 53.0, 0),
        ("street_light", 15.4, 53.0, 0),
        ("sign", 2.6, 39.0, 0),
        ("papers", -5.0, 49.0, 20),
        ("papers_c", 6.0, 50.5, 80),
        # The south wall, where the road used to run on: the lot's junk stacked against it, a wreck nose-in (the greybox's),
        # clear of the machine at x -1.2 to 1.2 and the ground in front of it. Each solid prop touches the wall or stands
        # a body's width off it (`test_lot_gaps.gd`), and none is a step towards the wall's top (`test_drive_in_jump_reach.gd`).
        ("container_small", -14.92, 56.97, 0),
        ("crate", -12.5, 57.485, 0),
        ("crate", -11.8, 57.485, 0),
        ("dumpster", 5.0, 57.28, 0),
        ("container", 10.5, 56.95, 0),
        ("tires", 15.1, 57.34, 0),
        ("planks", 3.6, 56.9, 0),
        ("cone", -4.0, 53.6, 0),
        ("cone", 4.0, 53.6, 0),
        ("debris", 12.0, 52.5, 30),
        ("papers_b", -3.0, 55.0, 40),
        ("papers", 7.0, 53.5, 0),
    ],
    "Field": [
        ("pallet_broken", -49.0, -24.5, 30),
        ("cone", 48.0, -36.0, 0),
        ("cone", 50.0, -36.0, 0),
        ("debris", 56.0, -10.0, 60),
        # Density pass. Trees on the flanks and beside the screen (only their trunks are solid), kept 5 m or more from
        # the breaches and clear of the outer car row.
        ("tree", -57.0, -36.0, 0),
        ("tree_pine", -58.5, -26.0, 40),
        ("tree_tall", -57.5, -9.0, 15),
        ("tree", -47.0, -6.5, 70),
        ("tree", 57.0, -38.0, 0),
        ("tree_pine", 58.5, -12.0, 20),
        ("tree_tall", 47.0, -6.5, 200),
        ("tree_small", 57.5, -49.5, 0),
        ("tree_small", -17.5, -50.0, 0),
        ("tree_small", 17.5, -50.0, 0),
        ("tree", -59.3, -51.0, 30),
        ("tree_tall", -59.3, -41.0, 80),
        ("tree_small", -56.5, -30.5, 0),
        ("tree", -59.5, -16.0, 140),
        ("tree_pine", -53.0, -49.0, 10),
        ("tree", -50.5, -44.0, 200),
        ("tree_tall", 59.3, -42.0, 250),
        ("tree_small", 56.5, -30.5, 0),
        ("tree", 59.5, -16.0, 60),
        ("tree_pine", 53.0, -49.0, 100),
        ("tree", 50.5, -44.0, 320),
        ("tree_small", -24.0, -50.5, 0),
        ("tree_small", 24.0, -50.5, 0),
        # Junk against the perimeter fence (3.0 m): nothing in it is a step to a fence top.
        ("tires", -61.34, -40.0, 90),
        ("sofa", -61.2, -31.0, 90),
        ("trash_open", -60.75, -14.0, 90),
        ("barrel", -61.4, -6.0, 0),
        ("barrel", -60.77, -6.0, 0),
        ("tires", 61.34, -40.0, 90),
        ("sofa_small", 61.2, -30.0, 90),
        ("pipes", 61.4, -12.0, 0),
        ("sofa_small", 48.0, -26.0, 0),
        # Barriers along the north fence on either side of the screen, beyond the last car.
        ("barrier", -44.0, -51.3, 0),
        ("barrier", -45.52, -51.3, 0),
        ("barrier", -47.04, -51.3, 0),
        ("barrier", 44.0, -51.3, 0),
        ("barrier", 45.52, -51.3, 0),
        ("barrier", 47.04, -51.3, 0),
        # The south strip by the 2.4 m fence: only low things (a drum's top plus a jump stays under the fence).
        ("pallet", -22.0, -5.6, 10),
        ("box", -21.0, -5.2, 30),
        ("barrel", -28.0, -4.7, 0),
        ("barrel", -28.63, -4.7, 0),
        ("barrel_spill", -31.0, -6.2, 80),
        ("pallet_broken", 24.0, -5.8, 20),
        ("crate", 30.0, -4.6, 0),
        ("crate", 30.63, -4.6, 0),
        ("cone", 36.5, -6.0, 0),
        ("cone", 43.5, -6.0, 0),
        ("sign", -43.5, -5.5, 0),
        ("sign", 43.5, -5.2, 0),
        ("cone", -8.0, -46.5, 0),
        ("cone", 8.0, -46.5, 0),
        ("debris", -50.0, -49.5, 20),
        ("debris", 50.0, -50.0, 160),
        ("planks", -56.0, -44.0, 30),
        # Litter in the aisles.
        ("papers", 0.0, -30.0, 0),
        ("papers_b", 1.5, -20.0, 40),
        ("papers_c", -22.5, -35.0, 10),
        ("papers", 22.0, -18.0, 70),
        ("papers_b", -45.0, -20.0, 120),
        ("papers_c", 48.0, -20.0, 30),
        ("papers", -10.0, -45.0, 90),
        ("papers_b", 12.0, -44.0, 15),
        ("papers_c", -30.0, -8.0, 60),
        ("papers", 32.0, -8.0, 140),
        ("papers_b", -55.0, -30.0, 20),
        ("papers_c", 55.0, -44.0, 75),
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
    elif kind in ("cyl", "trunk"):
        radius, height = (max(w, d) / 2, h) if kind == "cyl" else (TRUNK_RADIUS, min(h, TRUNK_HEIGHT))
        lines += [
            "",
            '[node name="Blocker" type="CSGCylinder3D" parent="."]',
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {height / 2:.3f}, 0)",
            "visible = false",
            "use_collision = true",
            f"radius = {radius:.3f}",
            f"height = {height:.3f}",
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
