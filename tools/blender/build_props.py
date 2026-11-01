"""Bring the Toon Shooter kit's environment props into Deadnight: one palette atlas for the whole prop family.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_props.py -- --bundle <kit bundle> [--out game/assets/props]
        [--only crate,barrel]

`<kit bundle>` is the Poly Pizza bundle of the Quaternius Toon Shooter Game Kit (its `models/<id>.glb`). For each prop
in PROPS it imports the kit file, joins its meshes, scales it by SCALE (the style bible's factor, docs/design/style.md
Scale), stands it on its origin (the middle of its footprint, at the ground), collapses every face onto one swatch of
the shared props palette (the zombie's pattern: one material per asset family, the style bible's Budgets), cuts the
triangles of the two kit files that are over the props budget, and writes `<out>/<name>.gltf` + `.bin`, all of them
pointing at one `<out>/props_palette.png`. It prints one `PROP` line per file (triangles, size in metres, materials
remapped) and `<out>/props.json` with the same numbers, which tools/world/lot_props.py reads for the blockers. The parked cars
(CAR_PAINTS) are Deadnight's own, built here from boxes on the same palette.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib as kl

SCALE = 0.8  # the style bible's factor for the kit (characters and what they hold); the props follow it
ROUGHNESS = 0.415  # every kit material
METALLIC = 0.0  # the kit's 0.4 reads as dark at night with no reflections to show; props are paint, wood and card

# Deadnight name -> (kit id, triangle budget). The budgets are the style bible's: under 1 m 800, 1-3 m 1.5k, over 3 m
# 5k. A file over its budget is cut with a collapse decimation to just under it.
PROPS = {
    "barrier": ("wCUxgt2jSP", 1500),  # Barrier Single: a concrete road barrier with hazard stripes
    "crate": ("NlXe0ZJGUd", 800),  # Crate
    "boxes": ("V9KbWC8Vd6", 1500),  # Cardboard Boxes: a stack
    "box": ("rdKKO0DvMG", 800),  # Cardboard Boxes: one
    "barrel": ("1orHe0kCc1", 1500),  # Exploding Barrel: a red drum
    "barrel_spill": ("8MVBwVyqQA", 1500),  # Exploding Barrel Spil: a drum on its side in a pool of oil
    "container": ("dQXRtm5GbO", 5000),  # Shipping Container
    "container_small": ("B79i6fHgVU", 1500),  # Container Small
    "pallet": ("cUAsYHDqfD", 1500),  # Pallet
    "pallet_broken": ("Gp43iUyyAX", 1500),  # Pallet Broken
    "cone": ("lAx8JytxGD", 800),  # Traffic Cone
    "dumpster": ("PKsbolkZSr", 1500),  # Dumpster
    "broken_car": ("Y67erogmR9", 5000),  # Broken Car (5,432 in the kit)
    "gas_can": ("jRymgnHTTb", 800),  # Gas Can
    "debris": ("WrIiMMxyEP", 1500),  # Debris Pile
    "tires": ("mmq7GmG1AK", 1500),  # Tires (1,776 in the kit)
    "planks": ("hwQ1Fx5P8U", 1500),  # Wood Planks
    "gas_tank": ("RoCvKBGkoC", 1500),  # Gas Tank: a yellow gas bottle
    "water_tank": ("XVB8vUbnZb", 1500),  # Water Tank
}

# Props the lot repeats many times, cut below their class budget for the web (WebGL2 in a software renderer is
# triangle-bound): the lot has 19 wrecks, 4 of them on the field the night starts on.
LIGHTER = {"broken_car": 2400}

# The props palette: the kit's own colours (sRGB), one swatch each. A kit material takes the swatch nearest its base
# colour. DarkRed replaces the Gas Can's DarkRed, which the kit left at Blender's default grey (the style bible).
PALETTE = {
    "Grey": "#818491",
    "Grey2": "#5f5f5f",
    "DarkGrey": "#414141",
    "Black": "#252525",
    "White": "#bec2b5",
    "Yellow": "#d1ab46",
    "Orange": "#b4662f",
    "Red": "#8c3735",
    "DarkRed": "#5c2422",
    "Blue": "#3b4b8c",
    "Green": "#496321",
    "Wood": "#95703d",
    "WoodLight": "#bd9451",
    "Cardboard": "#9b7048",
    "Tape": "#9b9581",
    "Oil": "#684d37",
    "Rust": "#5f4b35",
    "Rust2": "#6d6150",
}
# Kit material names whose colour is wrong in the file, and the swatch they take instead.
OVERRIDES = {"DarkRed": "DarkRed", "Light": "White"}
GRID = 5  # swatches per side
SWATCH_PX = 8  # the atlas is 40 x 40


def hex_rgb(h):
    return tuple(int(h[i : i + 2], 16) / 255 for i in (1, 3, 5))


def linear_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def swatch_uv(name):
    i = list(PALETTE).index(name)
    col, row = i % GRID, i // GRID
    return Vector(((col + 0.5) / GRID, 1 - (row + 0.5) / GRID))


def nearest_swatch(material_name, linear_rgba):
    base = material_name.split(".")[0]
    if base in OVERRIDES:
        return OVERRIDES[base]
    rgb = [linear_to_srgb(c) for c in linear_rgba[:3]]
    return min(PALETTE, key=lambda n: sum((a - b) ** 2 for a, b in zip(hex_rgb(PALETTE[n]), rgb, strict=True)))


def palette_image(path):
    size = GRID * SWATCH_PX
    img = bpy.data.images.new("props_palette", size, size, alpha=False)
    px = [0.0] * (size * size * 4)
    for i, h in enumerate(PALETTE.values()):
        r, g, b = hex_rgb(h)
        col, row = i % GRID, i // GRID
        for y in range(SWATCH_PX):
            for x in range(SWATCH_PX):
                py = size - 1 - (row * SWATCH_PX + y)  # Blender's pixel rows start at the bottom
                k = (py * size + col * SWATCH_PX + x) * 4
                px[k : k + 4] = [r, g, b, 1.0]
    img.pixels = px
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    return img


def atlas_material(img):
    m = bpy.data.materials.new("Props")
    m.use_backface_culling = True  # closed shapes: glTF writes doubleSided false
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    bsdf.inputs["Metallic"].default_value = METALLIC
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def build(name, kit_id, budget, bundle, out, palette_path):
    src = Path(bundle) / "models" / f"{kit_id}.glb"
    objs = kl.import_glb(src)
    factors = kl.gltf_base_colours(src)
    meshes = [o for o in objs if o.type == "MESH" and not kl.is_stray(o, kl.armature_of(objs))]
    for o in objs:
        if o not in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    # Join into one object, transforms applied.
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.name = name
    o.data.name = name
    me = o.data
    # Each face onto the swatch of its kit material's colour.
    swatch_of_slot = []
    for slot in o.material_slots:
        mname = slot.material.name if slot.material else ""
        f = factors.get(mname) or factors.get(mname.split(".")[0]) or [0.8, 0.8, 0.8, 1]
        swatch_of_slot.append(nearest_swatch(mname, f))
    for layer in list(me.uv_layers):
        me.uv_layers.remove(layer)
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        s = swatch_uv(swatch_of_slot[poly.material_index] if swatch_of_slot else "Grey")
        for li in poly.loop_indices:
            uv.data[li].uv = s
    me.materials.clear()
    me.materials.append(atlas_material_cache(palette_path))
    for attr in [a.name for a in me.color_attributes]:
        me.color_attributes.remove(me.color_attributes[attr])
    # Scale, then the origin: the middle of the footprint, on the ground.
    pts = [Matrix.Scale(SCALE, 4) @ v.co for v in me.vertices]
    mn, mx = kl.bbox(pts)
    shift = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    me.transform(Matrix.Translation(-shift) @ Matrix.Scale(SCALE, 4))
    me.update()
    kit_tris = kl.tris(o)
    target = min(budget, LIGHTER.get(name, budget))
    if kit_tris > target:
        dec = o.modifiers.new("Budget", "DECIMATE")
        dec.ratio = (target * 0.97) / kit_tris
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=dec.name)
    # Flat faces, as in the kit.
    for p in me.polygons:
        p.use_smooth = False
    tris = kl.tris(o)
    size = [round(mx[k] - mn[k], 3) for k in range(3)]
    export(o, out, name)
    info = {
        "kit_id": kit_id,
        "kit_tris": kit_tris,
        "tris": tris,
        "budget": budget,
        # Blender's X, Y, Z = Godot's X, -Z, Y: width (x), depth (z), height (y), in metres.
        "size_xzy": size,
        "swatches": sorted(set(swatch_of_slot)),
    }
    print("PROP", name, json.dumps(info))
    bpy.data.objects.remove(o, do_unlink=True)
    return info


def export(o, out, name):
    """Write `<out>/<name>.gltf` + `.bin`; the texture stays the shared palette file next to it."""
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(
        filepath=str(Path(out) / f"{name}.gltf"),
        export_format="GLTF_SEPARATE",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_keep_originals=True,
        export_normals=True,
    )


# The parked cars: Deadnight's own 1950s sedan, built from chamfered boxes in the kit's manner, in five paints (body,
# roof). Its blocks are the collision boxes of world/drive_in/car.tscn (body 1.9 x 0.8 x 4.5 from 0.2 m up, cabin 1.7 x
# 0.7 x 2.3 up to 1.65 m, 0.3 m behind the middle), so the car looks as big as it is solid. Blender axes: +Y is the
# front (Godot's -Z), +Z up.
CAR_PAINTS = {
    "car_red": ("Red", "White"),
    "car_blue": ("Blue", "White"),
    "car_green": ("Green", "Green"),
    "car_yellow": ("Yellow", "White"),
    "car_cream": ("White", "Red"),
}
CAR_CHAMFER = 0.08  # the style bible: big props chamfer about 100 mm (kit scale), 80 mm at 0.8


def build_car(name, paint, roof, out, palette_path):
    import weaponlib as wl

    wl.PALETTE, wl.GRID = PALETTE, GRID  # the props palette, not the weapons'
    b = wl.Builder(name, "near", atlas_material_cache(palette_path))
    ch = CAR_CHAMFER
    b.box((0, 0, 0.6), (1.9, 4.5, 0.8), paint, bevel=ch)  # body
    b.box((0, -0.3, 1.3), (1.7, 2.3, 0.7), roof, bevel=ch)  # cabin
    b.box((0, -0.3, 1.26), (1.72, 1.9, 0.4), "DarkGrey", bevel=0)  # side windows
    b.box((0, -0.3, 1.26), (1.5, 2.32, 0.4), "DarkGrey", bevel=0)  # windscreen and rear window
    b.box((0, 0, 0.78), (1.92, 3.6, 0.08), "White", bevel=0)  # the side stripe
    for y in (2.27, -2.27):
        b.box((0, y, 0.38), (1.98, 0.16, 0.2), "Grey", bevel=0)  # bumpers
    b.box((0, 2.26, 0.66), (1.0, 0.04, 0.2), "DarkGrey", bevel=0)  # grille
    for x in (-0.66, 0.66):
        b.box((x, 2.25, 0.72), (0.26, 0.04, 0.2), "White", bevel=0)  # headlights
        b.box((x * 1.27, -1.82, 1.06), (0.12, 0.9, 0.16), paint, bevel=0)  # tail fins
        b.box((x * 1.27, -2.255, 0.9), (0.12, 0.04, 0.22), "Red", bevel=0)  # tail lights
    for x in (-0.84, 0.84):
        for y in (1.45, -1.45):
            b.cyl((x * 0.95, y, 0.33), (x * 1.08, y, 0.33), 0.33, "Black", segs=8, bevel=0)  # tyres
            b.cyl((x * 1.08, y, 0.33), (x * 1.1, y, 0.33), 0.15, "White", segs=6, bevel=0)  # hubcaps
    o = b.join()
    for p in o.data.polygons:
        p.use_smooth = False
    tris = kl.tris(o)
    export(o, out, name)
    info = {"kit_id": "", "kit_tris": 0, "tris": tris, "budget": 1500, "size_xzy": [1.98, 4.7, 1.65], "swatches": []}
    print("PROP", name, json.dumps(info))
    return info


_material = {}


def atlas_material_cache(palette_path):
    if "m" not in _material:
        img = bpy.data.images.load(str(palette_path))
        _material["m"] = atlas_material(img)
    return _material["m"]


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle", required=True)
    ap.add_argument("--out", default="game/assets/props")
    ap.add_argument("--only", default="")
    args = ap.parse_args(argv)
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    names = [n for n in PROPS if not args.only or n in args.only.split(",")]
    kl.reset()
    palette_path = out / "props_palette.png"
    palette_image(palette_path)
    report_path = out / "props.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    for name in names:
        kit_id, budget = PROPS[name]
        kl.reset()
        _material.clear()
        report[name] = build(name, kit_id, budget, args.bundle, out, palette_path)
    for name, (paint, roof) in CAR_PAINTS.items():
        if args.only and name not in args.only.split(","):
            continue
        kl.reset()
        _material.clear()
        report[name] = build_car(name, paint, roof, out, palette_path)
        names.append(name)
    report = {k: report[k] for k in (*PROPS, *CAR_PAINTS) if k in report}
    report_path.write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {len(names)} props to {out} (tris total {sum(r['tris'] for r in report.values())})")
    assert all(math.isfinite(r["tris"]) for r in report.values())


main()
