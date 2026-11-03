"""Write a fixture scene for each of the small-map kit's roof and outside pieces (issue #638), as the drive-in props
have (game/world/drive_in/fixtures/): the model and hidden CSG blockers, what navigation and the camera tests read.

Plain Python, no dependencies; run it from the repository root after `tools/blender/build_smallmap_outside.py`:

    python tools/world/build_smallmap_outside_fixtures.py

Blender's (x, y, z) is Godot's (x, z, -y); a piece faces Blender -Y, Godot +Z. The roof's numbers repeat the build
script's (`ROOF_*` below), which a test checks against the model's bounds.
"""

import math
from pathlib import Path

OUT = Path("game/world/smallmap/fixtures")
ASSETS = "res://assets/smallmap"

# The build script's roof (tools/blender/build_smallmap_outside.py).
ROOF_SPAN, PITCH, OVERHANG, RAFTER_D, PLATE_TOP = 8.0, math.radians(30), 0.4, 0.2, 0.14
SHEATH, COURSE = 0.05, 0.05
HALF = ROOF_SPAN / 2
LIFT = PLATE_TOP + RAFTER_D / math.cos(PITCH) - 0.15 * math.tan(PITCH)
RIDGE_Z = LIFT + HALF * math.tan(PITCH)
SLOPE_L = HALF / math.cos(PITCH) + OVERHANG


def num(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def box(at, size, turn_x=0.0):
    """A blocker: centre `at` and `size` in Godot axes, turned `turn_x` degrees about X."""
    c, s = math.cos(math.radians(turn_x)), math.sin(math.radians(turn_x))
    basis = f"1, 0, 0, 0, {num(c)}, {num(s)}, 0, {num(-s)}, {num(c)}"
    return (
        "CSGBox3D",
        f"Transform3D({basis}, {num(at[0])}, {num(at[1])}, {num(at[2])})",
        [("size", f"Vector3({', '.join(num(v) for v in size)})")],
    )


def cylinder(at, radius, height):
    return (
        "CSGCylinder3D",
        f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {num(at[0])}, {num(at[1])}, {num(at[2])})",
        [("radius", num(radius)), ("height", num(height)), ("sides", 8)],
    )


def polygon(points, depth, z):
    """A blocker extruded from a polygon in the XY plane, `depth` metres back from `z`."""
    pts = ", ".join(f"{num(x)}, {num(y)}" for x, y in points)
    return (
        "CSGPolygon3D",
        f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, {num(z)})",
        [("polygon", f"PackedVector2Array({pts})"), ("depth", num(depth))],
    )


def roof_slopes():
    """Both slopes as slabs from the rafters' undersides to the tar paper's top."""
    out = []
    thick = RAFTER_D + SHEATH + COURSE + 0.01
    w = -RAFTER_D + thick / 2
    for s in (-1, 1):  # Blender's slope sign: -1 the front (Godot +Z)
        u = SLOPE_L / 2
        y = s * (u * math.cos(PITCH) + w * math.sin(PITCH))
        z = RIDGE_Z - u * math.sin(PITCH) + w * math.cos(PITCH)
        out.append(box((0, z, -y), (2.0, thick, SLOPE_L), s * -math.degrees(PITCH)))
    return out


TREES = {"bare_tree_a": (0.2, 4.5), "bare_tree_b": (0.26, 6.0), "bare_tree_c": (0.32, 8.0)}

FIXTURES = {
    **{name: [cylinder((0, h * 0.42 / 2, 0), r * 1.1, h * 0.42)] for name, (r, h) in TREES.items()},
    "utility_pole": [box((0, 3.5, 0), (0.3, 7.0, 0.3))],
    "utility_wire": [],  # overhead: nothing to block
    "barbed_coil": [box((0, 0.45, 0), (2.0, 0.9, 0.85))],
    "fence_post": [box((0, 0.8, 0), (0.12, 1.6, 0.12))],
    "wire_fence": [box((1.0, 0.8, 0.065), (2.0, 1.6, 0.1))],
    "neon_sign": [
        box((-3.425, 3.1, -0.2), (0.3, 6.2, 0.3)),
        box((3.425, 3.1, -0.2), (0.3, 6.2, 0.3)),
        box((0, 6.9, 0), (8.85, 2.3, 0.2)),
    ],
    "roof_bay": roof_slopes(),
    "roof_bay_broken": roof_slopes(),
    "roof_gable": [polygon([(-HALF, 0), (HALF, 0), (HALF, LIFT), (0, RIDGE_Z), (-HALF, LIFT)], 0.2, 0.1)],
}


def scene(name, blockers):
    title = "".join(part.title() for part in name.split("_"))
    lines = [
        "[gd_scene format=3]",
        "",
        f'[ext_resource type="PackedScene" path="{ASSETS}/{name}.gltf" id="model"]',
        "",
        f'[node name="{title}" type="Node3D"]',
        "",
        '[node name="Model" parent="." instance=ExtResource("model")]',
    ]
    for i, (kind, transform, props) in enumerate(blockers, 1):
        lines += [
            "",
            f'[node name="Blocker{i}" type="{kind}" parent="."]',
            f"transform = {transform}",
            "visible = false",
            "use_collision = true",
        ] + [f"{k} = {v}" for k, v in props]
    return "\n".join(lines) + "\n"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, blockers in FIXTURES.items():
        (OUT / f"{name}.tscn").write_text(scene(name, blockers), encoding="utf-8", newline="\n")
    print("wrote", len(FIXTURES), "fixtures to", OUT)


if __name__ == "__main__":
    main()
