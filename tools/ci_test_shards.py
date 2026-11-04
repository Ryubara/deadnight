"""Which test folders a `godot` job shard runs, so the suite is split across parallel jobs (#524).

    python3 tools/ci_test_shards.py --root game --shard 2      # prints "-a res://tests/net -a res://tests/world ..."
    python3 tools/ci_test_shards.py --root game --self-test    # every test folder and file belongs to exactly one shard

The suite took 15 to 20 minutes in one job, then 12 to 15 minutes in each of three. The folders and scripts below are
balanced by the seconds they took on a runner (the `godot` job's log, `docs/research/ci-time.md`); a folder that is not
named goes to the last shard, so a new folder is never left out of CI. Re-balance the lists when one shard's job drifts
past the others or past about 9 minutes.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SHARDS = 6
# Shards 1 to 5 are named; shard 6 takes everything else, so keep it a light one. Seconds are the mean of two runs of
# `main` on the runner (1 = fast, 2 = a 15 % slower one); the job adds about a minute of setup (checkout, import).
NAMED: dict[int, tuple[str, ...]] = {
    # ~375 s: the rest of the night folder (those not moved below), and the once-per-run steps
    1: ("night",),
    # ~350 s
    2: ("player",),
    # ~355 s
    3: ("zombies",),
    # ~365 s: real sockets and real freezes, the time is the test
    4: ("net",),
    # ~350 s: ui and the small folders
    5: (
        "ui",
        "bots",
        "weapons",
        "core",
        "challenges",
        "grenades",
        "dev",
        "outline",
        "art",
        "character",
        "tuning",
        "test_main_scene.gd",
    ),
    # ~370 s
    6: ("rules", "world"),
}
# The `night` folder alone is 900 s (the bot suites are minutes long each), so its heaviest scripts are named one by
# one and move to the shards with room (#676, #775). Any other script of a split folder stays with the folder's own
# shard (1), and a new one is never left out. GdUnit4 takes a folder or a script as `-a`, not "a folder without
# these", hence the per-script entries. Seconds on the runner, mean of two runs.
MOVED: dict[str, int] = {
    "night/test_bot_bands.gd": 2,  # 206: eight seeded nights per band
    "night/test_bot_soak.gd": 3,  # 80
    "night/test_bot_orders_night.gd": 3,  # 68
    "night/test_bot_combat.gd": 3,  # 51
    "night/test_bot_team.gd": 3,  # 43
    "night/test_bot_errand_buys.gd": 3,  # 31
    "night/test_bot_own_ammo.gd": 5,  # 40
    "night/test_bot_train.gd": 6,  # 18
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
