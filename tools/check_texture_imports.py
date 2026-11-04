"""Fail when a texture's `.import` settings would let the Godot editor change them, or would blur a palette.

The editor's "Detect 3D" (`detect_3d/compress_to=1`, the default) watches every texture: the first time one is used by
a 3D material, the editor switches it to VRAM compression with mipmaps and rewrites its `.import` file. Headless
imports (agents, CI) never do, so every editor session left the checkout dirty (issue #441). For a palette or atlas
it is also wrong: block compression and mipmaps blend neighbouring swatches, so the editor showed other colours than
the build.

So every texture states its settings and Detect 3D is off:

- palettes and atlases (the default for every texture): lossless (`compress/mode=0`), no mipmaps, Detect 3D off;
- the textures in `TILING`, which repeat across large surfaces or are shown far under their size and alias without
  mipmaps: lossless, mipmaps on, Detect 3D off.

A new texture that is neither a palette nor a tiling texture (a normal map, a 2D sprite sheet that wants compression)
gets its own entry in `RULES` before it is committed.

Standard library only, so the pre-commit hook and the CI job run it as is.

    python tools/check_texture_imports.py                 # check every texture .import under game/
    python tools/check_texture_imports.py --fix           # rewrite the settings that differ
    python tools/check_texture_imports.py --fix FILES...  # only these (the pre-commit hook passes the staged ones)
    python tools/check_texture_imports.py --root DIR      # the repository at DIR
"""

from __future__ import annotations

import argparse
import fnmatch
import sys
from pathlib import Path

# Lossless, Detect 3D off; mipmaps only where the texture tiles.
PALETTE = {"compress/mode": "0", "mipmaps/generate": "false", "detect_3d/compress_to": "0"}
TILING = {"compress/mode": "0", "mipmaps/generate": "true", "detect_3d/compress_to": "0"}

# First match wins; paths are relative to the repository, with forward slashes. Anything not listed is a palette.
RULES: list[tuple[str, dict[str, str]]] = [
    # The lot's 256 px greyscale ground and wall textures repeat every few metres: without mipmaps the far ground
    # shimmers (docs/design/style.md, the lot's textures).
    ("game/assets/lot/textures/*", TILING),
    # The small map's chalk lettering is read from across a room at a slant: mipmaps keep it from sparkling.
    ("game/assets/smallmap/chalk_messages.*", TILING),
    # The level icons are drawn at 24 px from 64 px cells: without mipmaps the name tags sparkle.
    ("game/assets/ui/level_atlas/*", TILING),
]

IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp", ".svg", ".tga", ".bmp", ".exr", ".hdr", ".ktx2")


def wanted(rel: str) -> dict[str, str]:
    for pattern, settings in RULES:
        if fnmatch.fnmatch(rel, pattern):
            return settings
    return PALETTE


def is_texture_import(text: str) -> bool:
    return 'importer="texture"' in text


def read_params(text: str) -> dict[str, str]:
    params: dict[str, str] = {}
    section = ""
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            section = s[1:-1]
        elif section == "params" and "=" in s:
            key, value = s.split("=", 1)
            params[key] = value
    return params


def rewrite(text: str, settings: dict[str, str]) -> str:
    """The same file with `settings` in its [params] section (changed in place, missing keys added at the end)."""
    lines = text.split("\n")
    out: list[str] = []
    section = ""
    seen: set[str] = set()
    params_end = None
    for line in lines:
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            if section == "params" and params_end is None:
                params_end = len(out)
            section = s[1:-1]
        elif section == "params" and "=" in s:
            key = s.split("=", 1)[0]
            if key in settings:
                line = f"{key}={settings[key]}"
                seen.add(key)
        out.append(line)
    missing = [f"{k}={v}" for k, v in settings.items() if k not in seen]
    if missing:
        if section == "params" and params_end is None:
            # [params] is the last section: add before the trailing blank lines.
            end = len(out)
            while end > 0 and out[end - 1].strip() == "":
                end -= 1
            out[end:end] = missing
        elif params_end is not None:
            out[params_end:params_end] = missing
        else:
            out += ["", "[params]", "", *missing, ""]
    return "\n".join(out)


def repo_root(path: Path) -> Path:
    for parent in path.resolve().parents:
        if (parent / "tools" / "check_texture_imports.py").exists():
            return parent
    raise ValueError(f"{path} is not inside the repository")


def ensure_import(image: Path) -> Path | None:
    """Write the `.import` beside a texture a build script has just saved, with the settings its rule wants.

    For a new file it writes a minimal one (importer and [params]); Godot's first import keeps those params and adds
    the rest. An existing one keeps everything else. An image outside the repository is left alone.

    Not for images Godot extracts from a .glb: Godot writes such an image only when its `.import` is missing or carries
    the glTF md5, and turns mipmaps back on when it does, so the pre-commit hook fixes those after the import.
    """
    image = Path(image).resolve()
    imp = image.with_name(image.name + ".import")
    try:
        root = repo_root(image)
    except ValueError:
        return None  # written outside the repository (a scratch build): Godot never sees it
    settings = wanted(imp.relative_to(root).as_posix())
    if imp.exists():
        text = imp.read_text(encoding="utf-8")
        if is_texture_import(text):
            new = rewrite(text, settings)
            if new != text:
                imp.write_text(new, encoding="utf-8", newline="")
            return imp
    body = ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", ""]
    body += [f"{k}={v}" for k, v in settings.items()]
    imp.write_text("\n".join(body) + "\n", encoding="utf-8", newline="")
    return imp


def texture_imports(root: Path, files: list[str]) -> list[Path]:
    if files:
        paths = [Path(f) if Path(f).is_absolute() else root / f for f in files]
        return [
            p
            for p in paths
            if p.name.endswith(".import") and p.name[: -len(".import")].lower().endswith(IMAGE_SUFFIXES)
        ]
    game = root / "game"
    return sorted(
        p
        for p in game.rglob("*.import")
        if ".godot" not in p.parts and p.name[: -len(".import")].lower().endswith(IMAGE_SUFFIXES)
    )


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="*", help="texture .import files (default: every one under game/)")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    ap.add_argument("--fix", action="store_true", help="rewrite the settings that differ")
    args = ap.parse_args(argv)
    root = args.root.resolve()

    problems: list[str] = []
    for path in texture_imports(root, args.files):
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        if not is_texture_import(text):
            continue
        rel = path.relative_to(root).as_posix()
        settings = wanted(rel)
        have = read_params(text)
        diff = [f"{k}={have.get(k, '(missing)')}, wants {v}" for k, v in settings.items() if have.get(k) != v]
        if not diff:
            continue
        problems.append(f"{rel}: " + "; ".join(diff))
        if args.fix:
            path.write_text(rewrite(text, settings), encoding="utf-8", newline="")

    if problems:
        verb = "fixed" if args.fix else "wrong"
        print(
            f"{len(problems)} texture import(s) {verb} (issue #441: Detect 3D off, palettes lossless without "
            "mipmaps, tiling textures as listed in tools/check_texture_imports.py):"
        )
        for p in problems:
            print(f"  {p}")
        if args.fix:
            print("Import again (godot --headless --path game --import) and commit the .import files.")
        else:
            print("Fix with: python tools/check_texture_imports.py --fix")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
