"""Build the small-map kit's lamps (group 4, docs/research/maps/small-map-art.md): the enamel pendant lamp and the
wall lantern, on the kit atlas of `smallmap_kit.py`.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_smallmap_lights.py -- [--out game/assets/smallmap] \
        [--sheet <scratch>/lights_sheet.png]

It writes, into `--out`: the kit atlas (`smallmap_palette.png` and its lossless `.import`), `pendant_lamp.gltf` and
`wall_lantern.gltf` (+ `.bin`), and `smallmap_lights.json` (triangles, budget and size of each). `--sheet` also renders
a contact sheet: the pieces at their real height beside the game's Soldier (1.8 m) and drive-in props on the 0.5 m
grid, and a close-up of each.

Both follow the kit's conventions: origin on the floor in the middle of the footprint, the room side facing Blender -Y
(Godot +Z), one material on the kit atlas. The bulb is part of the same mesh, on its own swatch (Popcorn, which no other
face of these pieces uses), so in the game one emission texture lights it and nothing else (`KitLamp`, the drive-in's
`ModelGlow` manner): one mesh, one draw, and no shader the lot does not already build.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib
from palette_import import ensure_import
from smallmap_kit import CLEAR, Piece, atlas_material, palette_image, swatch_uv

# The swatch the bulbs sit on: the game lights exactly this cell of the atlas (KitLamp.BULB_SWATCH).
BULB = "Popcorn"
# The inside of the enamel shade: the game lets it glow a little, the bounce of the bulb (KitLamp.SHADE_SWATCH).
SHADE_INSIDE = "Cream"

# The pendant lamp (the page's scale table): shade 0.6 m across, its rim 2.15 m up, hung from a 2.8 m ceiling.
SHADE_R = 0.3
RIM_Z = 2.15
# The wall lantern: 0.25 x 0.2 x 0.4 m, its foot 1.8 m up (over the Soldier's head), its back on the wall (y = 0).
LANTERN_FOOT = 1.8


def lathe(p, profile, colours, sides, at=(0.0, 0.0, 0.0)):
    """A closed solid of revolution round Z: `profile` is a closed loop of (radius, z) points, `colours[i]` the swatch
    of the band from point i to point i + 1. Flat-shaded bands, so the hard edges of the kit's look stay."""
    tmp = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(tmp.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    band_of = []
    for i in range(len(profile)):
        j = (i + 1) % len(profile)
        if profile[i][0] < 1e-4 and profile[j][0] < 1e-4:
            continue
        for k in range(sides):
            k2 = (k + 1) % sides
            quad = [rings[i][k], rings[i][k2], rings[j][k2], rings[j][k]]
            if profile[i][0] < 1e-4:
                quad = [rings[i][k], rings[j][k2], rings[j][k]]
            elif profile[j][0] < 1e-4:
                quad = [rings[i][k], rings[i][k2], rings[j][k]]
            tmp.faces.new(quad)
            band_of.append(colours[i])
    bmesh.ops.remove_doubles(tmp, verts=tmp.verts, dist=1e-5)
    m = Matrix.Translation(Vector(at))
    bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    me = bpy.data.meshes.new("tmp")
    tmp.to_mesh(me)
    tmp.free()
    n0 = len(p.bm.faces)
    p.bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    p.bm.faces.ensure_lookup_table()
    for f, colour in zip(p.bm.faces[n0:], band_of, strict=True):
        u = swatch_uv(colour)
        for loop in f.loops:
            loop[p.uv].uv = u


def bulb(p, at, r=0.055, down=True):
    """A pear-shaped bulb on the bulb swatch: its round end toward `down` (a pendant's hangs, a lantern's stands)."""
    s = -1 if down else 1
    profile = [(0.0, 0.0), (0.022, 0.0), (0.024, s * 0.025), (r, s * 0.06), (r * 0.8, s * 0.1), (0.0, s * 0.115)]
    if not down:
        profile = list(reversed(profile))
    lathe(p, profile, [BULB] * len(profile), 8, at)


def pendant_lamp(p):
    """An enamel pendant: ceiling rose, cord, socket, a wide shallow shade (green enamel outside, cream inside, a dark
    rolled rim) and a pear bulb that just shows under the rim. Hung from the 2.8 m ceiling, the rim at 2.15 m."""
    p.cyl(0.075, 0.03, (0, 0, CLEAR - 0.015), "DarkGrey", sides=8)
    top = RIM_Z + 0.2
    p.cyl(0.01, CLEAR - 0.03 - (top + 0.07), (0, 0, (CLEAR - 0.03 + top + 0.07) / 2), "Black", sides=4)
    p.cyl(0.04, 0.08, (0, 0, top + 0.03), "DarkGrey", sides=8, r2=0.032)
    # The shade, one closed solid: down the outside from the neck, round the rolled rim, back up the inside.
    profile = [
        (0.045, 0.2),  # the neck, outside
        (0.075, 0.19),
        (0.15, 0.135),
        (0.235, 0.07),
        (0.285, 0.03),
        (SHADE_R, 0.012),  # the rolled rim
        (SHADE_R, -0.012),
        (0.272, -0.006),
        (0.215, 0.05),  # the inside
        (0.12, 0.125),
        (0.045, 0.16),
    ]
    colours = ["Green"] * 4 + ["DarkGrey"] * 3 + [SHADE_INSIDE] * 3 + ["DarkGrey"]
    lathe(p, profile, colours, 12, (0, 0, RIM_Z))
    bulb(p, (0, 0, RIM_Z + 0.105), down=True)


def wall_lantern(p):
    """A caged wall lantern: a back plate on the wall, an arm, a rusty hood and foot, a cage of four posts and bars
    round an upright bulb. Its back is on the wall (y = 0) and it stands out 0.2 m into the room (-Y)."""
    z0 = LANTERN_FOOT
    p.box((0.12, 0.02, 0.22), (0, -0.01, z0 + 0.2), "DarkGrey", 0.0)
    p.box((0.035, 0.05, 0.035), (0, -0.045, z0 + 0.3), "Rust", 0.0)
    cy = -0.125  # the cage's middle, out from the wall
    p.box((0.18, 0.15, 0.04), (0, cy, z0 + 0.02), "Rust", 0.01)
    p.box((0.25, 0.16, 0.045), (0, -0.12, z0 + 0.3425), "Rust", 0.012)  # the hood, the widest part
    p.box((0.13, 0.09, 0.035), (0, cy, z0 + 0.3825), "Rust", 0.01)  # its cap, up to 0.4 m
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((0.016, 0.016, 0.28), (sx * 0.072, cy + sy * 0.057, z0 + 0.18), "DarkGrey", 0.0)
    for z in (z0 + 0.12, z0 + 0.24):  # two rings round the cage
        for sy in (-1, 1):
            p.box((0.16, 0.012, 0.012), (0, cy + sy * 0.057, z), "DarkGrey", 0.0)
        for sx in (-1, 1):
            p.box((0.012, 0.126, 0.012), (sx * 0.072, cy, z), "DarkGrey", 0.0)
    for sx in (-1, 1):  # two bars on the front
        p.box((0.01, 0.01, 0.28), (sx * 0.024, cy - 0.057, z0 + 0.18), "DarkGrey", 0.0)
    p.cyl(0.03, 0.04, (0, cy, z0 + 0.06), "DarkGrey", sides=8)  # the socket
    bulb(p, (0, cy, z0 + 0.08), r=0.045, down=False)


PIECES = {
    # name: (builder, triangle budget). Both are small props (style bible: a prop under 1 m is a few hundred).
    "pendant_lamp": (pendant_lamp, 600),
    "wall_lantern": (wall_lantern, 600),
}


def tris(o):
    return sum(len(f.vertices) - 2 for f in o.data.polygons)


def export(o, out, name):
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


# --- The contact sheet ------------------------------------------------------------------------------------------------


def imported(path, height=None):
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    objs = [o for o in bpy.data.objects if o not in before]
    arm = kitlib.armature_of(objs)
    for o in objs:
        if o.type == "MESH" and (kitlib.is_stray(o, arm) or o.parent_bone.startswith(kitlib.HAND_BONE_PREFIXES)):
            o.hide_render = True
    if arm and arm.animation_data and bpy.data.actions:
        idle = next((a for a in bpy.data.actions if a.name.lower().startswith("idle")), None)
        if idle:
            arm.animation_data.action = idle
            if idle.slots:
                arm.animation_data.action_slot = idle.slots[0]
            bpy.context.scene.frame_set(int(idle.frame_range[0]))
    bpy.context.view_layer.update()
    if height:
        mn, mx = bounds(objs)
        k = height / (mx.z - mn.z)
        for o in objs:
            if o.parent is None:
                o.scale = [v * k for v in o.scale]
        bpy.context.view_layer.update()
    return objs


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" and not o.hide_render for c in o.bound_box]
    return Vector([min(q[k] for q in pts) for k in range(3)]), Vector([max(q[k] for q in pts) for k in range(3)])


def move(objs, by):
    for o in objs:
        if o.parent is None:
            o.matrix_world = Matrix.Translation(Vector(by)) @ o.matrix_world
    bpy.context.view_layer.update()


def grid(mat, x0, x1, y0, y1):
    p = Piece("Grid")
    p.box((x1 - x0, y1 - y0, 0.02), ((x0 + x1) / 2, (y0 + y1) / 2, -0.01), "Soot", 0.0)
    for i in range(round((x1 - x0) / 0.5) + 1):
        x = x0 + i * 0.5
        p.box(
            (0.03 if i % 4 == 0 else 0.015, y1 - y0, 0.004),
            (x, (y0 + y1) / 2, 0.002),
            "Grey" if i % 4 == 0 else "Grey2",
            0.0,
        )
    for j in range(round((y1 - y0) / 0.5) + 1):
        y = y0 + j * 0.5
        p.box(
            (x1 - x0, 0.03 if j % 4 == 0 else 0.015, 0.004),
            ((x0 + x1) / 2, y, 0.002),
            "Grey" if j % 4 == 0 else "Grey2",
            0.0,
        )
    return p.obj(mat)


def render(path, cam_target, span, angle, elev, px, py):
    sc = bpy.context.scene
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    a = math.radians(angle)
    d = Vector((math.sin(a), -math.cos(a), elev)).normalized()
    cam.location = Vector(cam_target) + d * 40
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = span
    cam.data.clip_end = 200
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_cavity = True
    sc.display.shading.show_object_outline = True
    sc.render.resolution_x = px
    sc.render.resolution_y = py
    sc.world = bpy.data.worlds.new("W")
    sc.world.color = (0.03, 0.035, 0.06)
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)


def contact_sheet(path, out, soldier, compare):
    """The pieces at their real height in a 2.8 m bay (a ceiling slab over the lamp, a wall behind the lantern) beside
    the Soldier and the game's own props on the 0.5 m grid; then a close-up of each piece."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = bpy.data.images.load(str(out / "smallmap_palette.png"))
    mat = atlas_material(img)
    x = 0.0
    shown = []
    if soldier:
        s = imported(soldier, 1.8)
        mn, mx = bounds(s)
        move(s, (x - mn.x, -(mn.y + mx.y) / 2, -mn.z))
        x += mx.x - mn.x + 0.5
        shown += s
    for c in compare:
        objs = imported(c)
        mn, mx = bounds(objs)
        move(objs, (x - mn.x, -(mn.y + mx.y) / 2, -mn.z))
        x += mx.x - mn.x + 0.5
        shown += objs
    pieces = {}
    for name in PIECES:
        objs = [o for o in bpy.data.objects if o.name == name]
        if not objs:
            gl = imported(out / f"{name}.gltf")
            objs = [o for o in gl if o.type == "MESH"]
        pieces[name] = objs
    # The lamp under a slab at 2.8 m, the lantern on a strip of wall: what they hang from.
    x += 0.5
    slab = Piece("Ceiling")
    slab.box((1.0, 1.0, 0.1), (x + 0.5, 0, CLEAR + 0.05), "Concrete", 0.0)
    slab.obj(mat)
    move(pieces["pendant_lamp"], (x + 0.5, 0, 0))
    x += 1.5
    wall = Piece("Wall")
    wall.box((0.8, 0.1, CLEAR), (x + 0.4, 0.15, CLEAR / 2), "Plaster", 0.0)
    wall.obj(mat)
    move(pieces["wall_lantern"], (x + 0.4, 0.1, 0))
    x += 1.3
    grid(mat, -0.5, math.ceil(x) + 0.5, -2.0, 2.5)
    render(path, ((x - 0.5) / 2, 0, 1.45), x + 1.0, 28, 0.32, 2400, 1000)
    # Close-ups: each piece alone, a little from below (as a player sees a lamp) and from the front.
    for name, objs in pieces.items():
        for o in bpy.data.objects:
            o.hide_render = o not in objs
        mn, mx = bounds(objs)
        c = (mn + mx) / 2
        close = path.with_name(path.stem + f"_{name}.png")
        render(close, c, max(mx - mn) * 1.6, 30, -0.35, 900, 900)
        render(path.with_name(path.stem + f"_{name}_front.png"), c, max(mx - mn) * 1.6, 0, 0.15, 900, 900)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="game/assets/smallmap")
    ap.add_argument("--sheet", default="")
    ap.add_argument("--soldier", default="game/assets/characters/soldier/soldier.glb")
    ap.add_argument(
        "--compare",
        default="game/assets/drivein/trash_can.gltf,game/assets/props/crate.gltf,game/assets/drivein/speaker_post.gltf",
    )
    a = ap.parse_args(argv)
    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    palette = out / "smallmap_palette.png"
    img = palette_image(palette)
    ensure_import(palette)  # lossless, no mipmaps, Detect 3D off (tools/check_texture_imports.py)
    mat = atlas_material(img)
    report = {}
    for name, (fn, budget) in PIECES.items():
        p = Piece(name)
        fn(p)
        o = p.obj(mat)
        n = tris(o)
        xs = [v.co for v in o.data.vertices]
        lo = [round(min(c[k] for c in xs), 3) for k in range(3)]
        hi = [round(max(c[k] for c in xs), 3) for k in range(3)]
        info = {"tris": n, "budget": budget, "size_xyz_blender": [round(hi[k] - lo[k], 3) for k in range(3)]}
        info["min_xyz_blender"], info["max_xyz_blender"] = lo, hi
        print("PIECE", name, json.dumps(info))
        if n > budget:
            raise SystemExit(f"{name}: {n} tris over its budget {budget}")
        export(o, out, name)
        report[name] = info
    (out / "smallmap_lights.json").write_text(
        json.dumps(report, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    if a.sheet:
        contact_sheet(Path(a.sheet).resolve(), out, a.soldier, [c for c in a.compare.split(",") if c])
    print("BUILT", out)


main()
