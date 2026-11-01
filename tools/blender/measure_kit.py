"""Measure a Poly Pizza model bundle (the Quaternius Toon Shooter kit) for the style bible (docs/design/style.md).

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/measure_kit.py -- \
        --bundle <workspace>/refs/polypizza/bundles/qraiSXoAru \
        --extra Zombie=<workspace>/refs/polypizza/VlXjG0N8Eg/model.glb \
        --out <workspace>/scratch/deadnight/<branch>/kit.json

`--bundle` is a folder with `index.json` (id, title, tris, category, animated) and `models/<id>.glb`; `--extra` adds
single rigged models as Title=path. Writes the measurements as JSON and the same numbers as markdown tables beside
it (`.md`). Everything is measured in world space, in the armature's rest pose, after the glTF import's unit
conversion (1 Blender unit = 1 m, Z up).
"""

import argparse
import json
import math
import statistics
import sys
from collections import Counter
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib  # noqa: E402

GUNS = {
    "Ak47", "Pistol", "Revolver", "Revolver Small", "Smg", "Shotgun", "Sniper", "Short Cannon",
    "Grenade Launcher", "Rocket Launcher",
}
MELEE = {"Knife", "Shovel"}
THROWN = {"Grenade", "Fire Grenade"}


def classify(entry, size):
    title = entry["title"]
    if entry.get("animated"):
        return "character"
    if title in GUNS:
        return "gun"
    if title in MELEE:
        return "melee"
    if title in THROWN:
        return "thrown"
    if size < 1.0:
        return "prop-small"
    if size < 3.0:
        return "prop-medium"
    return "prop-large"


def to_srgb(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def hexcol(rgb, linear=True):
    vals = [to_srgb(c) if linear else c for c in rgb[:3]]
    return "#" + "".join(f"{round(v * 255):02x}" for v in vals)


def material_colour(mat):
    """(hex, image) for a material: its flat base colour, or the image feeding the base colour."""
    if not mat or not mat.node_tree:
        return None, None
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if not bsdf:
        return None, None
    sock = bsdf.inputs["Base Color"]
    if sock.is_linked and sock.links[0].from_node.type == "TEX_IMAGE":
        return None, sock.links[0].from_node.image
    return hexcol(sock.default_value), None


def bevel_widths(o):
    """Short side of bevel strips: narrow quads (aspect >= 3) folded 15-75 degrees against both long neighbours."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    bm.normal_update()
    widths = []
    for f in bm.faces:
        if len(f.edges) != 4:
            continue
        e = list(f.edges)
        pairs = [(e[0], e[2]), (e[1], e[3])]
        lens = [(p[0].calc_length() + p[1].calc_length()) / 2 for p in pairs]
        short, long_ = min(lens), max(lens)
        if short <= 1e-6 or long_ / short < 3:
            continue
        long_pair = pairs[lens.index(long_)]
        ok = True
        for edge in long_pair:
            others = [g for g in edge.link_faces if g is not f]
            if len(others) != 1:
                ok = False
                break
            ang = math.degrees(f.normal.angle(others[0].normal, 0.0))
            if not 15 <= ang <= 75:
                ok = False
                break
        if ok:
            widths.append(short)
    bm.free()
    return widths


def islands(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    seen, count = set(), 0
    for f in bm.faces:
        if f.index in seen:
            continue
        count += 1
        stack = [f]
        while stack:
            g = stack.pop()
            if g.index in seen:
                continue
            seen.add(g.index)
            stack.extend(h for e in g.edges for h in e.link_faces if h.index not in seen)
    bm.free()
    return count


def atlas_usage(meshes, image):
    """Area-weighted colours sampled at each face's UV centre, and the mean UV area per face in texels."""
    w, h = image.size
    px = list(image.pixels)
    colours, texels = Counter(), []
    for o in meshes:
        me = o.data
        uv = me.uv_layers.active
        if not uv:
            continue
        for poly in me.polygons:
            us = [uv.data[i].uv for i in poly.loop_indices]
            cu = sum(u.x for u in us) / len(us)
            cv = sum(u.y for u in us) / len(us)
            x = min(w - 1, max(0, int((cu % 1.0) * w)))
            y = min(h - 1, max(0, int((cv % 1.0) * h)))
            i = (y * w + x) * 4
            colours[hexcol(px[i : i + 3], linear=False)] += poly.area
            # Shoelace area of the UV polygon, in texels.
            a = 0.0
            for k in range(len(us)):
                p, q = us[k], us[(k + 1) % len(us)]
                a += p.x * q.y - q.x * p.y
            texels.append(abs(a) / 2 * w * h)
    total = sum(colours.values()) or 1
    top = [(c, round(v / total * 100, 1)) for c, v in colours.most_common(16)]
    return {
        "size": [w, h],
        "distinct_colours": len(colours),
        "top_colours_pct": top,
        "median_uv_texels_per_face": round(statistics.median(texels), 2) if texels else None,
    }


def character_metrics(objs, body):
    arm = kitlib.armature_of(objs)
    pts = [p for o in body for p in kitlib.world_verts(o)]
    mn, mx = kitlib.bbox(pts)
    height = mx.z - mn.z
    # Head: vertices weighted mostly to the Head bone, plus meshes parented to it.
    head_pts = []
    for o in body:
        wv = kitlib.world_verts(o)
        if o.parent_type == "BONE" and o.parent_bone in ("Head", "Neck"):
            head_pts += wv
            continue
        gi = {g.index: g.name for g in o.vertex_groups}
        for v, p in zip(o.data.vertices, wv):
            if v.groups:
                top = max(v.groups, key=lambda g: g.weight)
                if gi.get(top.group) in ("Head", "Eyelid.L", "Eyelid.R") or gi.get(top.group, "").startswith("Tongue"):
                    head_pts.append(p)
    hmn, hmx = kitlib.bbox(head_pts)
    bones = {b.name: arm.matrix_world @ b.head_local for b in arm.data.bones}
    head_h = hmx.z - hmn.z
    return {
        "height_m": round(height, 3),
        "span_x_m": round(mx.x - mn.x, 3),
        "depth_m": round(mx.y - mn.y, 3),
        "head_height_m": round(head_h, 3),
        "head_width_m": round(hmx.x - hmn.x, 3),
        "heads_tall": round(height / head_h, 2),
        "head_share_pct": round(head_h / height * 100, 1),
        "shoulder_width_m": round((bones["UpperArm.L"] - bones["UpperArm.R"]).length, 3),
        "hip_height_pct": round((bones["UpperLeg.L"].z - mn.z) / height * 100, 1),
        "neck_height_pct": round((bones["Head"].z - mn.z) / height * 100, 1),
        "bones": len(arm.data.bones),
        "bone_names": [b.name for b in arm.data.bones],
        "clips": sorted({a.name.split("|")[-1] for a in bpy.data.actions}),
    }


def measure(title, path, entry):
    objs = kitlib.import_glb(path)
    kitlib.rest_pose(objs)
    body, held, stray = kitlib.split_parts(objs)
    pts = [p for o in body for p in kitlib.world_verts(o)]
    mn, mx = kitlib.bbox(pts)
    dims = mx - mn
    size = max(dims)
    mats, images = Counter(), set()
    for o in body:
        for poly in o.data.polygons:
            m = o.data.materials[poly.material_index] if o.data.materials else None
            colour, img = material_colour(m)
            if img:
                images.add(img)
            elif colour:
                mats[(m.name.split(".")[0], colour)] += poly.area
    widths = [w for o in body for w in kitlib_bevels(o)]
    rec = {
        "id": entry.get("id"),
        "title": title,
        "class": classify(entry, size),
        "index_tris": entry.get("tris"),
        "tris": sum(kitlib.tris(o) for o in body),
        "held_tris": sum(kitlib.tris(o) for o in held),
        "held_items": sorted(o.name for o in held),
        "stray_tris": sum(kitlib.tris(o) for o in stray),
        "meshes": len(body),
        "dims_m": [round(d, 3) for d in dims],
        "size_m": round(size, 3),
        "materials": len(mats) + len(images),
        "colours": sorted({c for (_, c) in mats}),
        "material_area": {f"{n} {c}": a for (n, c), a in mats.items()},
        "parts": sum(islands(o) for o in body),
        "bevel_median_m": round(statistics.median(widths), 4) if widths else None,
        "bevel_strips": len(widths),
    }
    rec["bevel_pct_of_size"] = round(rec["bevel_median_m"] / size * 100, 2) if widths else None
    if len(body) == 1 and not kitlib.armature_of(objs):
        o = body[0]
        origin = o.matrix_world.translation
        rec["origin_pct"] = [round((origin[i] - mn[i]) / dims[i] * 100) if dims[i] else 0 for i in range(3)]
    if images:
        img = next(iter(images))
        rec["atlas"] = atlas_usage(body, img)
    if kitlib.armature_of(objs):
        rec.update(character_metrics(objs, body))
    return rec


def kitlib_bevels(o):
    return bevel_widths(o)


def markdown(recs):
    out = []
    chars = [r for r in recs if r["class"] == "character"]
    out.append("| Character | Tris (body) | Held tris | Height m | Heads tall | Head % | Shoulders m | Hips % | Bones | Clips |")
    out.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for r in chars:
        out.append(
            f"| {r['title']} | {r['tris']} | {r['held_tris']} | {r['height_m']} | {r['heads_tall']} | "
            f"{r['head_share_pct']} | {r['shoulder_width_m']} | {r['hip_height_pct']} | {r['bones']} | {len(r['clips'])} |"
        )
    out.append("")
    out.append("| Class | Count | Tris min | Tris median | Tris max | Size m median | Bevel mm median | Bevel % size |")
    out.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    by = {}
    for r in recs:
        by.setdefault(r["class"], []).append(r)
    for cls in ["character", "gun", "melee", "thrown", "prop-small", "prop-medium", "prop-large"]:
        rs = by.get(cls, [])
        if not rs:
            continue
        t = [r["tris"] for r in rs]
        bev = [r["bevel_median_m"] for r in rs if r["bevel_median_m"]]
        pct = [r["bevel_pct_of_size"] for r in rs if r["bevel_pct_of_size"]]
        out.append(
            f"| {cls} | {len(rs)} | {min(t)} | {round(statistics.median(t))} | {max(t)} | "
            f"{round(statistics.median(r['size_m'] for r in rs), 2)} | "
            f"{round(statistics.median(bev) * 1000, 1) if bev else '-'} | {round(statistics.median(pct), 2) if pct else '-'} |"
        )
    out.append("")
    out.append("| Weapon | Class | Tris | Length m | Dims m | Parts | Materials | Bevel mm | Origin % |")
    out.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for r in sorted((r for r in recs if r["class"] in ("gun", "melee", "thrown")), key=lambda r: -r["size_m"]):
        bev = round(r["bevel_median_m"] * 1000, 1) if r["bevel_median_m"] else "-"
        out.append(
            f"| {r['title']} | {r['class']} | {r['tris']} | {r['size_m']} | {r['dims_m']} | {r['parts']} | "
            f"{r['materials']} | {bev} | {r.get('origin_pct')} |"
        )
    out.append("")
    pal = Counter()
    for r in recs:
        for k, a in r["material_area"].items():
            pal[k] += a
    out.append("| Material | Colour | Area m2 (kit total) |")
    out.append("| --- | --- | --- |")
    for k, a in pal.most_common(40):
        name, col = k.rsplit(" ", 1)
        out.append(f"| {name} | `{col}` | {round(a, 2)} |")
    return "\n".join(out) + "\n"


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle", required=True, type=Path)
    ap.add_argument("--extra", action="append", default=[], help="Title=path.glb of a rigged model")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)

    index = json.loads((args.bundle / "index.json").read_text(encoding="utf-8"))
    jobs = [(e["title"], args.bundle / "models" / f"{e['id']}.glb", e) for e in index]
    for spec in args.extra:
        title, path = spec.split("=", 1)
        jobs.append((title, Path(path), {"id": None, "title": title, "animated": True}))

    recs = []
    for title, path, entry in jobs:
        recs.append(measure(title, path, entry))
        print(f"measured {title}: {recs[-1]['tris']} tris", flush=True)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(recs, indent=1), encoding="utf-8")
    args.out.with_suffix(".md").write_text(markdown(recs), encoding="utf-8")
    print(f"wrote {args.out} and {args.out.with_suffix('.md')}")


main()
