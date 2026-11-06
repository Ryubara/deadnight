"""The label limits of `check_budget.py` hold on every kind of runner and still catch a slower section (#1255).

    python3 -m unittest discover -s tools/perf

The reports are made up from what 46 runs of `godot (1)` measured on 2026-11-05 (the three kinds of runner the calibration
tells apart, and the slowest and the fastest share of the frame each section took), run through the real
`budget.json`.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

import check_budget

BUDGET = json.loads((Path(__file__).resolve().parent / "budget.json").read_text(encoding="utf-8"))
LABELS = ("server.challenges", "server.xp")

# Per kind of runner (the calibration's milliseconds name it): the median frame, and the medians of the two sections.
# The sections cost about the same on all of them, the calibration does not: that is what the old ratio got wrong.
RUNNERS = {
    "fast (calibration 3.2)": {
        "calibration_ms": 3.16,
        "frame_ms": 9.8,
        "server.challenges": 0.0320,
        "server.xp": 0.0065,
    },
    "middle (calibration 4.5)": {
        "calibration_ms": 4.52,
        "frame_ms": 12.2,
        "server.challenges": 0.0394,
        "server.xp": 0.0078,
    },
    "slow (calibration 6.0)": {
        "calibration_ms": 6.04,
        "frame_ms": 13.9,
        "server.challenges": 0.0410,
        "server.xp": 0.0083,
    },
    # The same kind of runner as the middle one, taken slow by a neighbour: the frame and the sections slow together.
    "middle, busy (calibration 4.6)": {
        "calibration_ms": 4.58,
        "frame_ms": 13.85,
        "server.challenges": 0.0510,
        "server.xp": 0.0090,
    },
    # The highest and the lowest share of the frame each section took in 46 runs: the limit sits between the highest and
    # twice the lowest.
    "highest challenges": {"calibration_ms": 4.58, "frame_ms": 13.85, "server.challenges": 0.0510, "server.xp": 0.0085},
    "highest xp": {"calibration_ms": 3.03, "frame_ms": 9.52, "server.challenges": 0.0300, "server.xp": 0.0070},
    "lowest challenges": {"calibration_ms": 5.99, "frame_ms": 12.60, "server.challenges": 0.0340, "server.xp": 0.0070},
    "lowest xp": {"calibration_ms": 6.05, "frame_ms": 12.77, "server.challenges": 0.0360, "server.xp": 0.0060},
}


def report(runner: dict, factor: float = 1.0, labels: tuple[str, ...] = LABELS) -> dict:
    """Ninety steady rows of a runner; the named sections cost `factor` times what they did."""
    rows = []
    for index in range(90):
        row = {
            "t": float(index),
            "frames": 60,
            "cap": 99,
            "alive": 95,
            "round": 12,
            "calibration_ms": runner["calibration_ms"],
            "frame_ms": runner["frame_ms"],
            "labels_ms": {label: runner[label] * (factor if label in labels else 1.0) for label in LABELS},
        }
        rows.append(row)
    return {"samples": rows}


def broken_by(runner: dict, factor: float = 1.0, labels: tuple[str, ...] = LABELS) -> list[str]:
    budget = {
        "min_steady_rows": 15,
        "max_label_share_of_frame": BUDGET["max_label_share_of_frame"],
    }
    return check_budget.judge(report(runner, factor, labels), budget)[0]


class LabelShareOfFrame(unittest.TestCase):
    def test_the_budget_names_both_sections(self) -> None:
        self.assertEqual(sorted(BUDGET["max_label_share_of_frame"]), sorted(LABELS))
        self.assertNotIn("max_label_ratio_of_calibration", BUDGET)

    def test_unchanged_code_passes_on_every_kind_of_runner(self) -> None:
        for name, runner in RUNNERS.items():
            with self.subTest(runner=name):
                self.assertEqual(broken_by(runner), [])

    def test_a_section_twice_as_slow_fails_on_every_kind_of_runner(self) -> None:
        for name, runner in RUNNERS.items():
            for label in LABELS:
                with self.subTest(runner=name, label=label):
                    broken = broken_by(runner, 2.0, (label,))
                    self.assertEqual(len(broken), 1)
                    self.assertIn(label, broken[0])


LEAK_BUDGET = json.loads((Path(__file__).resolve().parent / "leak_budget.json").read_text(encoding="utf-8"))
# What a flat night held at the steady rows (the dispatch of 2026-11-06) and how many seconds of the wall clock the
# runner took for one second of the night: 0.26 s on a laptop, 0.3 to 0.5 on the runners (#1319).
GROWTH_ONLY = {key: value for key, value in LEAK_BUDGET.items() if key != "max"}
LEAK_START = {"nodes": 5000.0, "objects": 15000.0, "resources": 2600.0, "mem_static_mb": 260.0, "orphans": 0}


def night(wall_per_row: float, rise_per_night_minute: dict[str, float] | None = None) -> dict:
    """1 080 steady rows, a row a second of the night (60 steps), each count rising at the given rate."""
    rise = rise_per_night_minute or {}
    rows = []
    for index in range(LEAK_BUDGET["skip_rows"] + 1080):
        row = {"t": index * wall_per_row, "frames": 60, "cap": 30, "alive": 20, "round": 10}
        for key, start in LEAK_START.items():
            row[key] = start + rise.get(key, 0.0) * index / 60.0
        rows.append(row)
    return {"samples": rows}


class GrowthIsReadInNightMinutes(unittest.TestCase):
    def test_a_flat_night_passes_on_a_fast_and_a_slow_runner(self) -> None:
        for wall in (0.26, 0.3, 0.5):
            with self.subTest(wall_per_row=wall):
                self.assertEqual(check_budget.judge(night(wall), LEAK_BUDGET)[0], [])

    def test_the_same_rise_reads_the_same_on_every_runner(self) -> None:
        rise = {"nodes": 20.0, "mem_static_mb": 0.9}
        reads = []
        for wall in (0.26, 0.5, 0.9):
            rows = check_budget.steady_rows(night(wall, rise)["samples"], LEAK_BUDGET)
            reads.append(check_budget.slope_per_minute(rows, "nodes", LEAK_BUDGET["fixed_fps"]))
        for read in reads:
            self.assertAlmostEqual(read, 20.0, places=3)

    def test_the_old_wall_clock_read_moved_with_the_runner(self) -> None:
        rows = check_budget.steady_rows(night(0.26, {"nodes": 20.0})["samples"], LEAK_BUDGET)
        slow = check_budget.steady_rows(night(0.5, {"nodes": 20.0})["samples"], LEAK_BUDGET)
        wall_fast = check_budget.slope_per_minute(rows, "nodes")
        wall_slow = check_budget.slope_per_minute(slow, "nodes")
        self.assertGreater(wall_fast, 1.5 * wall_slow)

    def test_a_real_leak_fails_on_every_runner_and_names_the_count(self) -> None:
        for key, limit in LEAK_BUDGET["growth_per_minute"].items():
            for wall in (0.26, 0.5):
                with self.subTest(key=key, wall_per_row=wall):
                    broken = check_budget.judge(night(wall, {key: 1.2 * limit}), GROWTH_ONLY)[0]
                    self.assertEqual(len(broken), 1)
                    self.assertIn(key, broken[0])

    def test_half_the_limit_is_not_a_leak(self) -> None:
        rise = {key: 0.5 * limit for key, limit in LEAK_BUDGET["growth_per_minute"].items()}
        self.assertEqual(check_budget.judge(night(0.3, rise), GROWTH_ONLY)[0], [])


if __name__ == "__main__":
    unittest.main()
