"""Which test folders a `godot` job shard runs, so the suite is split across parallel jobs (#524).

    python3 tools/ci_test_shards.py --root game --shard 2      # prints "-a res://tests/net -a res://tests/world ..."
    python3 tools/ci_test_shards.py --root game --self-test    # every test folder and file belongs to exactly one shard

The suite took 15 to 20 minutes in one job. The folders below are balanced by the time they took on a runner (the
`godot` job's log, `docs/research/ci-time.md`); a folder that is not named goes to the last shard, so a new folder is
never left out of CI. Re-balance the lists when one shard's job drifts well past the others.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SHARDS = 3
# Shards 1 and 2 are named; shard 3 takes everything else.
NAMED: dict[int, tuple[str, ...]] = {
    1: ("night", "rules"),
    2: ("net", "world", "zombies"),
}
# The `night` folder alone took 13 minutes of shard 1's 15 (the bot suites are minutes long each), so its heaviest
# scripts are named one by one and move to the shards with room. Any other script of a split folder stays with the
# folder's own shard, and a new one is never left out. GdUnit4 takes a folder or a script as `-a`, not "a folder
# without these", hence the per-script entries.
MOVED: dict[str, int] = {
    "night/test_bot_bands.gd": 3,
    "night/test_bot_soak.gd": 2,
    "night/test_bot_orders_night.gd": 2,
}


def entries(root: Path) -> list[str]:
    """Every test folder and every test script directly under tests/, as `res://` paths."""
    tests = root / "tests"
    found = []
    split = {name.split("/")[0] for name in MOVED}
    for path in sorted(tests.iterdir()):
        if path.name.startswith("."):
            continue
        if path.is_dir() and path.name in split:
            found.extend(f"res://tests/{path.name}/{test.name}" for test in sorted(path.glob("test_*.gd")))
            continue
        if path.is_dir() or (path.suffix == ".gd" and path.name.startswith("test_")):
            found.append(f"res://tests/{path.name}")
    return found


def shard_of(entry: str) -> int:
    name = entry.removeprefix("res://tests/")
    if name in MOVED:
        return MOVED[name]
    for shard, names in NAMED.items():
        if name in names or name.split("/")[0] in names:
            return shard
    return SHARDS


def paths(root: Path, shard: int) -> list[str]:
    if not 1 <= shard <= SHARDS:
        sys.exit(f"shard {shard} is not between 1 and {SHARDS}")
    return [entry for entry in entries(root) if shard_of(entry) == shard]


def self_test(root: Path) -> None:
    every = entries(root)
    assert every, "no test folders found"
    seen: list[str] = []
    for shard in range(1, SHARDS + 1):
        found = paths(root, shard)
        assert found, f"shard {shard} runs nothing"
        seen.extend(found)
    assert sorted(seen) == sorted(every), "a test folder is in no shard, or in two"
    for names in NAMED.values():
        for name in names:
            assert any(e.startswith(f"res://tests/{name}") for e in every), f"{name} is named but is not a test folder"
    for name in MOVED:
        assert f"res://tests/{name}" in every, f"{name} is moved to a shard but is not a test script"
    print(f"ok: {len(every)} entries in {SHARDS} shards")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("game"), help="the Godot project folder")
    parser.add_argument("--shard", type=int)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test(args.root)
    elif args.shard is None:
        parser.error("--shard or --self-test")
    else:
        print(" ".join(f"-a {entry}" for entry in paths(args.root, args.shard)))


if __name__ == "__main__":
    main()
