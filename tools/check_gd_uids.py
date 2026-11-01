"""Fail when a committed GDScript file has no committed `.gd.uid`, or a `.gd.uid` outlives its script.

Godot 4.4+ writes a `<script>.gd.uid` beside every script on import. The uid must be committed with the script: if it
is not, every checkout regenerates it as an untracked file, and a scene that refers to the script by uid can break.

It reads the git index (`git ls-files`), not the working folder: an import creates the missing uids on disk, so the
folder would always look fine. Standard library only, so the pre-commit hook and the CI job run it as is.

    python tools/check_gd_uids.py            # checks the repository it runs in
    python tools/check_gd_uids.py --root DIR # checks the repository at DIR
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_SUFFIX = ".gd"
UID_SUFFIX = ".gd.uid"


def tracked_files(root: Path) -> set[str]:
    """Every path the git index knows, relative to `root`, with forward slashes."""
    out = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        capture_output=True,
    ).stdout
    return {p.decode("utf-8") for p in out.split(b"\0") if p}


def find_problems(tracked: set[str]) -> list[str]:
    """One message per script without a uid and per uid without a script, sorted."""
    problems: list[str] = []
    for path in sorted(tracked):
        if path.endswith(UID_SUFFIX):
            script = path[: -len(".uid")]
            if script not in tracked:
                problems.append(f"{path}: no {script} beside it (delete the stale uid)")
        elif path.endswith(SCRIPT_SUFFIX) and path + ".uid" not in tracked:
            problems.append(f"{path}: its {path}.uid is not committed (open the project once, then git add it)")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="repository to check (default: the current one)")
    args = parser.parse_args(argv)
    problems = find_problems(tracked_files(args.root))
    for problem in problems:
        print(problem)
    if problems:
        print(f"{len(problems)} problem(s): every committed .gd needs its committed .gd.uid", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
