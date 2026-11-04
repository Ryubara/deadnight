"""Fail when the level icons' drawings, SVGs, atlases and manifest disagree.

`tools/level_icons/draw_icons.py` writes the SVGs and `game/tools/art/export_level_icons.gd` rasterises them into the
two atlases, with a hash of every SVG and atlas in a manifest. An SVG that changed without a new export is caught here,
with no Godot and no pixels to compare across machines: the hashes differ. So is an atlas changed by hand, and an SVG
edited by hand that the drawing script would overwrite. Docs: docs/research/progression.md, "The icon pipeline".

Standard library only, so the pre-commit hook and the CI job run it as is.

    python tools/check_level_icons.py             # check the repository this file is in
    python tools/check_level_icons.py --root DIR  # the repository at DIR
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "level_icons"))
import draw_icons

SVG_FOLDER = "game/assets/ui/levels"
ATLAS_FOLDER = "game/assets/ui/level_atlas"
REDO = "run tools/level_icons/draw_icons.py, then godot --headless --path game -s res://tools/art/export_level_icons.gd"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def problems(root: Path) -> list[str]:
    found: list[str] = []
    svgs = root / SVG_FOLDER
    atlases = root / ATLAS_FOLDER
    manifest_path = atlases / "level_icons.json"
    if not manifest_path.exists():
        return [f"{manifest_path} is missing"]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    listed = {entry["svg"]: entry for entry in manifest["levels"]}
    on_disk = {path.name for path in svgs.glob("*.svg")}
    for name in sorted(on_disk ^ set(listed)):
        found.append(f"{name} is in only one of the folder and the manifest")
    for level in draw_icons.GLYPHS:
        name = f"level_{level:02d}.svg"
        path = svgs / name
        if not path.exists():
            found.append(f"{name} is missing")
            continue
        if path.read_bytes() != draw_icons.icon_svg(level).encode("utf-8"):
            found.append(f"{name} is not what the drawing script writes")
        if name in listed and sha256(path) != listed[name]["sha256"]:
            found.append(f"{name} changed and the atlases did not")
    for atlas in manifest["atlases"].values():
        path = atlases / atlas["file"]
        if not path.exists() or sha256(path) != atlas["sha256"]:
            found.append(f"{atlas['file']} is not the atlas the export wrote")
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    found = problems(args.root)
    for problem in found:
        print(f"level icons: {problem}", file=sys.stderr)
    if found:
        print(f"level icons: {REDO}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
