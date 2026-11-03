"""Measure every weapon model in `game/assets/weapons/` from its files: the numbers of docs/research/weapon-models.md.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/measure_weapons.py -- [--dir game/assets/weapons] --out <json>

For each `<name>/<name>.glb`, `<name>_far.glb` and `<name>_ammo.glb` it reports: triangles (per mesh node too), loose
parts (after welding the glTF's split vertices), materials, the share of faces drawn flat, the bounds (length along X,
height along Z, width along Y, Blender axes), where the origin sits in them (per cent along from the muzzle end, per
cent up from the bottom), the palette cells the faces' UVs land on (by area) and whether every face sits on one swatch
centre, the attachment empties (`Muzzle`, `Grip`, `Trigger`, `Support`, `Face`) and the moving nodes with their pivots.
The hold files (`game/gameplay/player/holds/*.tres`) give each model's `model_scale`, so the report also has the size in
the game (model x `model_scale` x the Soldier's 0.8). Prints one `MEASURE` line per file and writes the JSON.
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib
import weaponlib as wl

SOLDIER_SCALE = 0.8  # the player scene's scale on the Soldier (docs/design/weapon-hold.md)
SOCKETS = ("Muzzle", "Grip", "Trigger", "Support", "Face")


def hold_scales(root):
    """{model folder: (hold file, model_scale)} from the hold files that name a weapon scene."""
    out = {}
    for f in sorted((root / "game/gameplay/player/holds").glob("*.tres")):
        text = f.read_text(encoding="utf-8")
        scene = re.search(r'scene = "res://assets/weapons/([^/]+)/', text)
        scale = re.search(r"model_scale = ([0-9.]+)", text)
        if scene and scale:
            out.setdefault(scene.group(1), (f.stem, float(scale.group(1))))
    return out


def cell_of(u, v):
    """The palette cell (index into weaponlib.PALETTE order) a UV lands on; Blender UV, v up."""
    col = min(wl.GRID - 1, max(0, math.floor(u * wl.GRID)))
    row = min(wl.GRID - 1, max(0, math.floor((1 - v) * wl.GRID)))
    return row * wl.GRID + col


def loose_parts(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    seen, parts = set(), 0
    for v in bm.verts:
        if v in seen:
            continue
        parts += 1
        stack = [v]
        while stack:
            u = stack.pop()
            if u in seen:
                continue
            seen.add(u)
            stack.extend(e.other_vert(u) for e in u.link_edges)
    bm.free()
    return parts


def measure(path, names):
    objs = kitlib.import_glb(path)
    bpy.context.view_layer.update()
    meshes = [o for o in objs if o.type == "MESH"]
    empties = [o for o in objs if o.type == "EMPTY"]
    root = next((o for o in meshes if o.parent is None or o.parent.type != "MESH"), meshes[0])
    pts, tris, parts, mats, flat, faces, area = [], 0, 0, set(), 0, 0, {}
    on_centre, per_node = 0, {}
    for o in meshes:
        me = o.data
        me.calc_loop_triangles()
        t = len(me.loop_triangles)
        tris += t
        parts += loose_parts(me)
        mats.update(m.name for m in me.materials if m)
        mw = o.matrix_world
        pts += [mw @ v.co for v in me.vertices]
        uv = me.uv_layers.active
        for poly in me.polygons:
            faces += 1
            # Flat: every corner's normal is the face's (the glTF splits vertices at each face for flat shading).
            if all(me.corner_normals[li].vector.dot(poly.normal) > 0.999 for li in poly.loop_indices):
                flat += 1
            if uv:
                us = [uv.data[li].uv for li in poly.loop_indices]
                c = cell_of(*us[0])
                area[c] = area.get(c, 0.0) + poly.area * mw.median_scale**2
                cu, cv = (c % wl.GRID + 0.5) / wl.GRID, 1 - (c // wl.GRID + 0.5) / wl.GRID
                if all(abs(x.x - cu) < 1e-3 and abs(x.y - cv) < 1e-3 for x in us):
                    on_centre += 1
        per_node[o.name] = {"tris": t, "pivot": [round(c, 4) for c in o.matrix_world.translation]}
    mn = [min(p[i] for p in pts) for i in range(3)]
    mx = [max(p[i] for p in pts) for i in range(3)]
    size = [mx[i] - mn[i] for i in range(3)]
    total = sum(area.values()) or 1.0
    cells = {names[c] if c < len(names) else f"cell{c}": round(a / total, 3) for c, a in sorted(area.items())}
    sockets = {}
    for e in empties:
        base = re.sub(r"\.\d+$", "", e.name)
        if base in SOCKETS:
            sockets[base] = [round(c, 4) for c in e.matrix_world.translation]
    moving = {k: v for k, v in per_node.items() if k != root.name}
    return {
        "tris": tris,
        "parts": parts,
        "materials": sorted(mats),
        "flat_share": round(flat / max(1, faces), 3),
        "on_swatch_centre": round(on_centre / max(1, faces), 3),
        "length": round(size[0], 3),
        "width": round(size[1], 3),
        "height": round(size[2], 3),
        "min": [round(c, 4) for c in mn],
        "max": [round(c, 4) for c in mx],
        # Guns point along -X: per cent along from the muzzle end (min X), per cent up from the bottom.
        "origin_along": round(100 * (0 - mn[0]) / size[0], 1) if size[0] else None,
        "origin_up": round(100 * (0 - mn[2]) / size[2], 1) if size[2] else None,
        "cells": cells,
        "sockets": sockets,
        "moving": moving,
        "root_tris": per_node[root.name]["tris"],
    }


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path("."))
    ap.add_argument("--dir", type=Path, default=Path("game/assets/weapons"))
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args(argv)
    names = list(wl.PALETTE)
    holds = hold_scales(args.root)
    report = {}
    for folder in sorted(p for p in (args.root / args.dir).iterdir() if p.is_dir()):
        name = folder.name
        for suffix, lod in (("", "near"), ("_far", "far"), ("_ammo", "ammo")):
            path = folder / f"{name}{suffix}.glb"
            if not path.exists():
                continue
            m = measure(path.resolve(), names)
            if name in holds:
                hold, scale = holds[name]
                m["hold"], m["model_scale"] = hold, scale
                m["game_length"] = round(m["length"] * scale * SOLDIER_SCALE, 3)
                m["game_height"] = round(m["height"] * scale * SOLDIER_SCALE, 3)
            g, mz = m["sockets"].get("Grip"), m["sockets"].get("Muzzle")
            if g and mz:
                m["grip_to_muzzle"] = round(math.dist(g, mz), 3)
            report[f"{name}/{lod}"] = m
            print(
                f"MEASURE {name} {lod}: {m['tris']} tris, {m['parts']} parts, L {m['length']} H {m['height']} "
                f"W {m['width']}, origin {m['origin_along']}% along {m['origin_up']}% up, cells {m['cells']}, "
                f"sockets {sorted(m['sockets'])}, moving {sorted(m['moving'])}"
            )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(f"WROTE {args.out}")


main()
