"""Block out a few pieces of the small-map kit to test its scale and palette (docs/research/maps/small-map-art.md).

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_kit_blockout.py -- --out <scratch folder> \
        [--soldier game/assets/characters/soldier/soldier.glb] [--zombie game/assets/characters/zombies/zombie_farmhand.glb]

It writes, into `--out`: `kit_sheet.png` (the pieces in a row beside the Soldier and a zombie on a 0.5 m grid,
Workbench, atlas colours), `kit_vignette.png` (the pieces put together as a room corner at night, Eevee, lit the way
the page says: cool moon through the window, a warm pool under the lamp) from the shoulder camera's height, and
`kit_blockout.json` (triangles and sizes). Nothing is written into the game: these are throwaway blockouts, and the
real pieces are the follow-up issues' work. The builder is the drive-in props' manner (`build_drivein_props.py`):
chamfered boxes and low-sided cylinders, one atlas, each face on one swatch.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib
from smallmap_kit import (
    BEVEL,
    BIG_BEVEL,
    CLEAR,
    DOOR_H,
    DOOR_W,
    MODULE,
    RISE,
    RISERS,
    SILL,
    STAIR_W,
    STOREY,
    TREAD,
    WALL_T,
    WIN_H,
    WIN_W,
    Piece,
    atlas_material,
    hex_rgb,
    palette_image,
    srgb_to_linear,
)

# --- The pieces ------------------------------------------------------------------------------------------------------
# Each stands on its origin (the middle of its footprint, on the floor) and faces Blender -Y (the room side).


def wall_door_narrow(p):
    """A 2 m cinder-block wall module with a 1.4 x 2.4 m doorway and a purchase door in it (Yellow, as on the lot)."""
    jamb = (MODULE - DOOR_W) / 2
    for s in (-1, 1):
        p.box((jamb, WALL_T, CLEAR), (s * (DOOR_W + jamb) / 2, 0, CLEAR / 2), "Concrete", BIG_BEVEL)
    p.box((DOOR_W, WALL_T, CLEAR - DOOR_H), (0, 0, (CLEAR + DOOR_H) / 2), "Concrete", BIG_BEVEL)
    # The frame: two posts and a head, proud of the wall by 40 mm on the room side.
    for s in (-1, 1):
        p.box((0.1, WALL_T + 0.08, DOOR_H + 0.05), (s * (DOOR_W / 2 + 0.03), 0, (DOOR_H + 0.05) / 2), "DarkWood")
    p.box((DOOR_W + 0.26, WALL_T + 0.08, 0.12), (0, 0, DOOR_H + 0.06), "DarkWood")
    # The door: three planks, two battens and a brace, all in the purchase colour; a blank cream plate for the price.
    w = (DOOR_W - 0.08) / 3
    for i in range(3):
        p.box((w - 0.02, 0.06, DOOR_H - 0.06), (-w + i * w, -0.05, DOOR_H / 2), "Yellow", 0.015)
    for z in (0.45, DOOR_H - 0.45):
        p.box((DOOR_W - 0.12, 0.05, 0.16), (0, -0.1, z), "Yellow", 0.015)
    p.box((0.14, 0.05, 1.75), (0, -0.1, DOOR_H / 2), "Yellow", 0.015, rot=(0, 33, 0))
    p.box((0.42, 0.03, 0.22), (0, -0.14, 1.55), "Cream", 0.01)


def wall_window_boarded(p):
    """A 2 m wall module with a 1.2 x 1.3 m window, sill at 0.9 m, boarded from the room side: where the dead come in."""
    jamb = (MODULE - WIN_W) / 2
    top = SILL + WIN_H
    p.box((MODULE, WALL_T, SILL), (0, 0, SILL / 2), "Concrete", BIG_BEVEL)
    p.box((MODULE, WALL_T, CLEAR - top), (0, 0, (CLEAR + top) / 2), "Concrete", BIG_BEVEL)
    for s in (-1, 1):
        p.box((jamb, WALL_T, WIN_H), (s * (WIN_W + jamb) / 2, 0, SILL + WIN_H / 2), "Concrete", BIG_BEVEL)
    p.box((WIN_W + 0.2, WALL_T + 0.12, 0.08), (0, -0.02, SILL - 0.02), "Concrete")  # the sill, proud
    for s in (-1, 1):
        p.box((0.08, WALL_T + 0.04, WIN_H), (s * (WIN_W / 2 - 0.02), 0, SILL + WIN_H / 2), "DarkWood")
    p.box((WIN_W, WALL_T + 0.04, 0.08), (0, 0, top - 0.02), "DarkWood")
    # Five boards across the room face, each a little off level, alternating, nailed past both jambs.
    for i in range(5):
        z = SILL + 0.16 + i * 0.25
        tilt = (-4, 3, -2, 5, -3)[i]
        p.box((WIN_W + 0.3, 0.05, 0.19), (0.03 * (-1) ** i, -WALL_T / 2 - 0.04, z), "Wood", 0.012, rot=(0, tilt, 0))


def pillar_beam(p):
    """A 0.5 m square pillar with a cap and a plinth, carrying a 4 m beam under the ceiling."""
    p.box((0.6, 0.6, 0.12), (0, 0, 0.06), "Concrete", BEVEL)
    p.box((0.5, 0.5, CLEAR - 0.6), (0, 0, (CLEAR - 0.6) / 2 + 0.1), "Concrete", BIG_BEVEL)
    p.box((0.62, 0.62, 0.14), (0, 0, CLEAR - 0.47), "Concrete", BEVEL)
    p.box((4.0, 0.36, 0.4), (0, 0, CLEAR - 0.2), "Concrete", BIG_BEVEL)


def stair_straight(p):
    """A straight timber flight, 1.4 m wide, one storey (15 risers of 0.2 m, 0.3 m treads), a pipe rail on one side.

    The origin is the middle of the foot; the flight climbs towards +Y. In the game it walks on a hidden ramp.
    """
    run = (RISERS - 1) * TREAD
    for i in range(RISERS - 1):
        z = (i + 1) * RISE
        y = i * TREAD + TREAD / 2
        p.box((STAIR_W - 0.1, TREAD + 0.03, 0.06), (0, y, z - 0.03), "Wood", 0.012)
        p.box((STAIR_W - 0.14, 0.04, RISE - 0.06), (0, y - TREAD / 2 + 0.02, z - RISE / 2 - 0.03), "DarkWood", 0.0)
    ang = math.degrees(math.atan2(STOREY, run + TREAD))
    length = math.hypot(run + TREAD, STOREY)
    for s in (-1, 1):
        p.box(
            (0.08, length, 0.3),
            (s * (STAIR_W / 2 - 0.04), (run + TREAD) / 2, STOREY / 2 - 0.1),
            "DarkWood",
            0.02,
            rot=(ang, 0, 0),
        )
    # The rail: posts every 1.4 m and a sloped top 0.95 m over the nosings.
    x = -(STAIR_W / 2 - 0.04)  # the open side (-X); the wall side (+X) needs none
    for i in (0, 5, 10):
        y = i * TREAD + 0.1
        z0 = (i + 1) * RISE
        p.cyl(0.025, 0.95, (x, y, z0 + 0.475), "Grey", sides=6)
    p.cyl(0.03, length - 1.2, (x, (run + TREAD) / 2 - 0.3, STOREY / 2 + 1.0), "Grey", sides=6, rot=(ang - 90, 0, 0))


def sandbags(p):
    """A 2 m sandbag line, 0.9 m tall: the upstairs firing step. Rows of chunky bags, staggered."""
    rows = 5
    for r in range(rows):
        z = 0.09 + r * 0.18
        deep = 2 if r < 3 else 1
        off = 0.0 if r % 2 == 0 else 0.29
        for d in range(deep):
            y = (d - (deep - 1) / 2) * 0.31
            x = -1.0 + 0.29 + off
            while x < 1.0 - 0.1:
                p.box((0.56, 0.32, 0.19), (min(x, 0.72), y, z), "Sandbag", 0.06)
                x += 0.58


def pendant_lamp(p):
    """A ceiling lamp: cord, enamel shade and bulb. Hung from 2.8 m, the shade's rim at 2.15 m. The light guide."""
    p.cyl(0.012, 0.55, (0, 0, CLEAR - 0.275), "Black", sides=4)
    p.cyl(0.05, 0.06, (0, 0, CLEAR - 0.56), "DarkGrey", sides=6)
    p.cyl(0.3, 0.2, (0, 0, CLEAR - 0.6), "Green", sides=10, r2=0.06)


def bulb(p):
    """The pendant lamp's bulb, its own object so only it glows (in the game an unshaded swatch plus a glow quad)."""
    p.cyl(0.07, 0.1, (0, 0, CLEAR - 0.67), "Popcorn", sides=6)


PIECES = {
    "wall_door_narrow": (wall_door_narrow, 1500),
    "wall_window_boarded": (wall_window_boarded, 1500),
    "pillar_beam": (pillar_beam, 1500),
    "stair_straight": (stair_straight, 1500),
    "sandbags": (sandbags, 1500),
    "pendant_lamp": (pendant_lamp, 800),
}


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" and not o.hide_render for c in o.bound_box]
    return Vector([min(p[k] for p in pts) for k in range(3)]), Vector([max(p[k] for p in pts) for k in range(3)])


def character(path, height):
    """Import a game character, hide its strays and held items, stand it `height` metres tall (its Idle frame)."""
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
            if idle.slots:  # Blender 5: an action plays only through a slot
                arm.animation_data.action_slot = idle.slots[0]
            bpy.context.scene.frame_set(int(idle.frame_range[0]))
    bpy.context.view_layer.update()
    mn, mx = bounds(objs)
    roots = [o for o in objs if o.parent is None]
    k = height / (mx.z - mn.z)
    for o in roots:
        o.scale = [v * k for v in o.scale]
    bpy.context.view_layer.update()
    return objs


def place(objs, at, yaw=0.0):
    for o in objs:
        if o.parent is None:
            # glTF roots import in quaternion mode, where rotation_euler is ignored: turn the world matrix instead.
            o.matrix_world = (
                Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ o.matrix_world
            )
    bpy.context.view_layer.update()


def grid_floor(mat, mn, mx, z=0.0):
    """A dark floor with a line every 0.5 m (a brighter one every 2 m): the kit's grid, so sizes can be read."""
    p = Piece("Grid")
    w, d = mx[0] - mn[0], mx[1] - mn[1]
    p.box((w, d, 0.02), ((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, z - 0.01), "Soot", 0.0)
    n = round(w / 0.5)
    for i in range(n + 1):
        x = mn[0] + i * 0.5
        p.box(
            (0.015 if i % 4 else 0.03, d, 0.004), (x, (mn[1] + mx[1]) / 2, z + 0.002), "Grey2" if i % 4 else "Grey", 0.0
        )
    m = round(d / 0.5)
    for j in range(m + 1):
        y = mn[1] + j * 0.5
        p.box(
            (w, 0.015 if j % 4 else 0.03, 0.004), ((mn[0] + mx[0]) / 2, y, z + 0.002), "Grey2" if j % 4 else "Grey", 0.0
        )
    return p.obj(mat)


def ortho_camera(mn, mx, angle, elev=0.45, pad=1.08):
    centre = (mn + mx) / 2
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    a = math.radians(angle)
    d = Vector((math.sin(a), -math.cos(a), elev)).normalized()
    cam.location = centre + d * 60
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    span = mx - mn
    cam.data.ortho_scale = max(span.x, span.z * 2.2) * pad
    cam.data.clip_end = 200
    bpy.context.scene.camera = cam
    return cam


def render_sheet(out, built, mat, soldier, zombie, compare):
    """The pieces in a row, the Soldier, a zombie and Deadnight's own props at the left, on the 0.5 m grid."""
    x = 0.0
    groups = []
    if soldier:
        groups.append(character(soldier, 1.8))
    if zombie:
        groups.append(character(zombie, 1.63))
    for path in compare:  # the game's props, at their own (game) scale: the style the kit must match
        before = set(bpy.data.objects)
        kitlib.gltf_import(path)
        groups.append([o for o in bpy.data.objects if o not in before])
    groups += [[o] for o in built]
    for objs in groups:
        mn, mx = bounds(objs)
        place(objs, (x - mn.x, -(mn.y + mx.y) / 2, -mn.z))
        x += (mx.x - mn.x) + 0.5
    allobjs = [o for g in groups for o in g]
    mn, mx = bounds(allobjs)
    grid_floor(mat, Vector((math.floor(mn.x) - 0.5, -3.0, 0)), Vector((math.ceil(mx.x) + 0.5, 3.5, 0)))
    ortho_camera(mn, mx, 28, elev=0.32)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_cavity = True
    sc.display.shading.show_object_outline = True
    sc.render.resolution_x = 2800
    sc.render.resolution_y = 900
    sc.world = bpy.data.worlds.new("W")
    sc.world.color = (0.03, 0.035, 0.06)
    sc.render.filepath = str(out / "kit_sheet.png")
    bpy.ops.render.render(write_still=True)


def light(kind, name, colour, energy, at, **kw):
    ld = bpy.data.lights.new(name, kind)
    ld.color = [srgb_to_linear(c) for c in hex_rgb(colour)]
    ld.energy = energy
    for k, v in kw.items():
        setattr(ld, k, v)
    o = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(o)
    o.location = at
    return o


def render_vignette(out, soldier, zombie):
    """The pieces as a room corner, seen from behind the player at the shoulder camera's height, lit at night."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = bpy.data.images.load(str(out / "kit_palette.png"))
    mat = atlas_material(img)
    bulb_mat = atlas_material(img, "Bulb", emit="#ffd9a0")
    objs = {}
    for name, (fn, _b) in PIECES.items():
        p = Piece(name)
        fn(p)
        objs[name] = p.obj(mat)
    bp = Piece("Bulb")
    bulb(bp)
    bo = bp.obj(bulb_mat)
    bo.location = (-1.5, -0.6, 0)
    # The room: 6 x 6 m inside, back wall on y = +3 (window, plain, door), stair along the east wall.
    fl = Piece("Floor")
    fl.box((7.0, 7.0, 0.2), (0, 0, -0.1), "Grey2", 0.0)
    for i in range(-3, 4):  # a seam every metre: the floor tiles
        fl.box((0.03, 7.0, 0.004), (i * 1.0, 0, 0.002), "DarkGrey", 0.0)
        fl.box((7.0, 0.03, 0.004), (0, i * 1.0, 0.002), "DarkGrey", 0.0)
    fl.obj(mat)
    back = 3.0 + WALL_T / 2
    objs["wall_window_boarded"].location = (-2.0, back, 0)
    objs["wall_window_boarded"].rotation_euler.z = math.radians(180)
    plain = Piece("WallPlain")
    plain.box((MODULE, WALL_T, CLEAR), (0, 0, CLEAR / 2), "Concrete", BIG_BEVEL)
    plain.box((0.9, 0.04, 1.2), (0, -0.17, 1.5), "Chalk", 0.0)  # a blank chalk-board patch where a message goes
    po = plain.obj(mat)
    po.location = (0.0, back, 0)
    objs["wall_door_narrow"].location = (2.0, back, 0)
    side = Piece("WallWest")
    side.box((WALL_T, 7.0, CLEAR), (-3.0 - WALL_T / 2, 0, CLEAR / 2), "Plaster", BIG_BEVEL)
    side.obj(mat)
    objs["stair_straight"].location = (2.2, -3.4, 0)
    objs["sandbags"].location = (-2.0, 2.45, 0)
    objs["pillar_beam"].location = (0.0, 0.2, 0)
    objs["pillar_beam"].rotation_euler.z = math.radians(90)
    objs["pendant_lamp"].location = (-1.5, -0.6, 0)
    # A crate under the lamp where a buy would stand, from the game's props (a stand-in for a shop spot).
    crate = Piece("ShopStandIn")
    crate.box((1.2, 0.6, 0.6), (0, 0, 0.3), "Green", BEVEL)
    crate.box((1.22, 0.62, 0.1), (0, 0, 0.42), "Yellow", 0.0)  # the locker's yellow band (map.md, Shop spots)
    co = crate.obj(mat)
    co.location = (-1.5, -0.6, 0)
    if soldier:
        s = character(soldier, 1.8)
        place(s, (0.3, -2.6, 0), yaw=180)  # the model faces -Y: turned to face into the room, away from the camera
    if zombie:
        z = character(zombie, 1.63)
        place(z, (-2.0, 1.6, 0), yaw=0)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.world = bpy.data.worlds.new("Night")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*[srgb_to_linear(c) for c in hex_rgb("#4d5c8c")], 1)
    bg.inputs["Strength"].default_value = 0.35  # the lot's cool ambient: the shadow side still reads
    # Moonlight through the window (outside the back wall, low and cool), the lamp's warm pool, a dim fill.
    moon = light("SPOT", "Moon", "#9db4e8", 2500, (-2.0, 6.5, 2.6), spot_size=math.radians(30), spot_blend=0.3)
    moon.rotation_euler = (Vector((-1.6, 0.0, 0.0)) - moon.location).to_track_quat("-Z", "Y").to_euler()
    light("POINT", "Lamp", "#ffb866", 160, (-1.5, -0.6, CLEAR - 0.75), shadow_soft_size=0.1)
    light("POINT", "Spill", "#ffb866", 60, (2.0, 4.6, 1.6))  # light from the next room, under the door's edge
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.lens = 22
    # The shoulder camera: pivot 1.6 m over the feet, 0.6 m to the right, 2.3 m back (PlayerTuning).
    feet = Vector((0.3, -2.6, 0))
    pivot = feet + Vector((0, 0, 1.6))
    cam.location = pivot + Vector((0.6, -2.3, 0.25))
    cam.rotation_euler = Vector((0.0, 1.0, -0.12)).to_track_quat("-Z", "Y").to_euler()  # straight ahead, as in play
    sc.camera = cam
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 900
    sc.view_settings.view_transform = (
        "Filmic"
        if "Filmic" in [i.identifier for i in sc.view_settings.bl_rna.properties["view_transform"].enum_items]
        else "AgX"
    )
    sc.render.filepath = str(out / "kit_vignette.png")
    bpy.ops.render.render(write_still=True)
    # The same room from above and behind: where things stand.
    cam.data.lens = 18
    cam.location = (-0.5, -6.5, 6.5)
    cam.rotation_euler = (Vector((0.2, 1.0, 0.6)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = str(out / "kit_vignette_over.png")
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--soldier", default="game/assets/characters/soldier/soldier.glb")
    ap.add_argument("--zombie", default="game/assets/characters/zombies/zombie_farmhand.glb")
    ap.add_argument(
        "--compare",
        default="game/assets/drivein/trash_can.gltf,game/assets/drivein/ticket_booth.gltf,game/assets/props/crate.gltf",
    )
    a = ap.parse_args(argv)
    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = palette_image(out / "kit_palette.png")
    mat = atlas_material(img)
    built, report = [], {}
    for name, (fn, budget) in PIECES.items():
        p = Piece(name)
        fn(p)
        o = p.obj(mat)
        xs = [v.co for v in o.data.vertices]
        size = [round(max(c[k] for c in xs) - min(c[k] for c in xs), 2) for k in range(3)]
        report[name] = {"tris": tris(o), "budget": budget, "size_xyz": size}
        print("PIECE", name, json.dumps(report[name]))
        built.append(o)
    (out / "kit_blockout.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    render_sheet(out, built, mat, a.soldier, a.zombie, [c for c in a.compare.split(",") if c])
    render_vignette(out, a.soldier, a.zombie)
    print("BLOCKOUT", out)


if __name__ == "__main__":  # the kit's build scripts import its staging helpers
    main()
