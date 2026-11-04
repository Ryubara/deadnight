"""Runs the look-lag probe over the frame rates and hitches of #905 and writes one csv per run.

    python tools/look/run_matrix.py <godot console exe> <out folder> [--modes solo,online]

Headless, one after another (each run is a night of its own), then
`python tools/look/analyse.py <out folder>/*.csv` prints the table.
"""

import subprocess
import sys
from pathlib import Path

CASES = [
    ("144", ["--fps=144"]),
    ("60", ["--fps=60"]),
    ("30", ["--fps=30"]),
    ("15", ["--fps=15"]),
    ("60_hitch120", ["--fps=60", "--hitch=120:20"]),
    ("144_hitch60", ["--fps=144", "--hitch=60:10"]),
    ("30_ticks3", ["--fps=30", "--ticks=3"]),
]


def main() -> None:
    godot, out = sys.argv[1], Path(sys.argv[2])
    modes = ["solo", "online"]
    if "--modes" in sys.argv:
        modes = sys.argv[sys.argv.index("--modes") + 1].split(",")
    out.mkdir(parents=True, exist_ok=True)
    game = Path(__file__).resolve().parents[2] / "game"
    for mode in modes:
        for name, extra in CASES:
            csv = out / f"{mode}_{name}.csv"
            command = [
                godot, "--headless", "--path", str(game),
                "res://tests/captures/look_lag_probe.tscn", "--",
                f"--mode={mode}", "--seconds=7", f"--out={csv}", *extra,
            ]  # fmt: skip
            subprocess.run(command, check=True, capture_output=True, timeout=240)
            print("done", csv.name, flush=True)


if __name__ == "__main__":
    main()
