"""Draws docs/research/round-scaling.png: our curves beside Call of Duty Zombies', before and after.

    uv run --with matplotlib python tools/balance/scaling_chart.py --before <game dir of main> \
        --after game --before-cells <report folder> --after-cells <report folder> --out <png>

Health and count are the formulas of the research page (docs/research/round-scaling.md), the weapons
and round tuning are read from the two game folders' own files, and points a round come from two
balance reports (average solo players). Prints the tables the page and the pull request quote.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

SURFACE, INK, INK_2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e7e6e1"
COLORS = {"cod": "#e87ba4", "before": "#8a8985", "after": "#2a78d6"}
WEAPON_COLORS = {"pistol": "#52514e", "smg": "#eb6834", "shotgun": "#eda100", "rifle": "#2a78d6"}
ROUNDS = range(1, 26)
COD_TO_OURS = 50.0 / 150.0  # round 1 health in our units over the original's


def cod_health(r: int) -> float:
    """Zombie health: 150 in round 1, 100 more a round to round 9, then 10% more a round."""
    return 150.0 + 100.0 * (r - 1) if r <= 9 else 950.0 * 1.1 ** (r - 9)


def cod_count(r: int, players: int = 1) -> int:
    table = {1: [6, 8, 13, 18, 24, 27, 28, 28, 29], 2: [7, 9, 15, 21, 27, 31, 32, 33, 34]}
    if r <= 9:
        return table.get(players, table[2])[r - 1] if players <= 2 else table[2][r - 1]
    return 24 + math.floor((0.5 if players == 1 else players - 1) * 0.18 * r * r)


def read_tres(path: Path) -> dict[str, float]:
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r"^(\w+) = (-?[\d.]+)$", line.strip())
        if m:
            out[m.group(1)] = float(m.group(2))
    return out


def read_rounds(game: Path) -> dict[str, float]:
    text = (game / "gameplay/rules/default_tuning.tres").read_text()
    block = text.split('script = ExtResource("4_468ln")', 1)[1].split("[sub_resource", 1)[0]
    return {m.group(1): float(m.group(2)) for m in re.finditer(r"^(\w+) = (-?[\d.]+)$", block, re.MULTILINE)}


def our_health(t: dict[str, float], r: int) -> float:
    knee = int(t["health_knee_round"])
    if r <= knee:
        return t["health_base"] + t["health_step"] * (r - 1)
    return (t["health_base"] + t["health_step"] * (knee - 1)) * t["health_growth"] ** (r - knee)


def our_count(t: dict[str, float], r: int, players: int = 1) -> int:
    n = r - 1
    solo = t["count_base"] + t["count_linear"] * n + t["count_quadratic"] * n * n
    return max(1, round(solo * (1 + t["count_per_extra_player"] * (players - 1))))


def ttk(w: dict[str, float], health: float, distance_full: bool = True) -> float:
    """Seconds under fire to kill a zombie of `health` with body shots, reloads spread over the shots."""
    per_shot = w["damage"] * w.get("pellets", 1)
    shots = math.ceil(health / per_shot)
    return shots * w["fire_interval"] + w["reload_time"] * shots / w["magazine_size"]


def points_per_round(folder: Path) -> list[float]:
    cell = json.loads((folder / "cells/average_1.json").read_text())
    return [
        cell["earned"][r] / cell["reached"][r] if cell["reached"][r] >= 20 else float("nan")
        for r in range(len(cell["reached"]))
    ]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", type=Path, required=True)
    ap.add_argument("--after", type=Path, required=True)
    ap.add_argument("--before-cells", type=Path, required=True)
    ap.add_argument("--after-cells", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    plt.rcParams.update(
        {
            "figure.facecolor": SURFACE,
            "axes.facecolor": SURFACE,
            "savefig.facecolor": SURFACE,
            "axes.edgecolor": GRID,
            "axes.labelcolor": INK_2,
            "text.color": INK,
            "xtick.color": INK_2,
            "ytick.color": INK_2,
            "axes.grid": True,
            "grid.color": GRID,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "font.size": 9,
        }
    )
    tb, ta = read_rounds(a.before), read_rounds(a.after)
    fig, ax = plt.subplots(2, 2, figsize=(11, 7.5))
    xs = list(ROUNDS)
    h = ax[0][0]
    h.plot(
        xs,
        [cod_health(r) * COD_TO_OURS for r in xs],
        color=COLORS["cod"],
        lw=2,
        label="Call of Duty (x1/3, round 1 = ours)",
    )
    h.plot(xs, [our_health(tb, r) for r in xs], color=COLORS["before"], lw=2, ls="--", label="Deadnight before")
    h.plot(xs, [our_health(ta, r) for r in xs], color=COLORS["after"], lw=2, label="Deadnight after")
    h.set(title="Walker health by round", xlabel="round", ylabel="health", yscale="log")
    h.legend(frameon=False)
    c = ax[0][1]
    c.plot(xs, [cod_count(r) for r in xs], color=COLORS["cod"], lw=2, label="Call of Duty, solo")
    c.plot(xs, [our_count(tb, r) for r in xs], color=COLORS["before"], lw=2, ls="--", label="Deadnight before")
    c.plot(xs, [our_count(ta, r) for r in xs], color=COLORS["after"], lw=2, label="Deadnight after")
    c.set(title="Zombies in a round, solo", xlabel="round", ylabel="zombies")
    c.legend(frameon=False)
    t = ax[1][0]
    rows = []
    for name in ("pistol", "smg", "shotgun", "rifle"):
        wb = read_tres(a.before / f"gameplay/weapons/defs/{name}.tres")
        wa = read_tres(a.after / f"gameplay/weapons/defs/{name}.tres")
        t.plot(xs, [ttk(wa, our_health(ta, r)) for r in xs], color=WEAPON_COLORS[name], lw=2, label=name)
        if wb != wa or tb != ta:
            t.plot(xs, [ttk(wb, our_health(tb, r)) for r in xs], color=WEAPON_COLORS[name], lw=1.2, ls="--")
        rows.append((name, [(r, ttk(wb, our_health(tb, r)), ttk(wa, our_health(ta, r))) for r in (1, 5, 10, 15, 20)]))
    t.set(title="Seconds to kill a walker, body shots (dashed: before)", xlabel="round", ylabel="seconds", yscale="log")
    t.legend(frameon=False, ncol=2)
    p = ax[1][1]
    pb, pa = points_per_round(a.before_cells), points_per_round(a.after_cells)
    p.plot(range(len(pb)), pb, color=COLORS["before"], lw=2, ls="--", label="before")
    p.plot(range(len(pa)), pa, color=COLORS["after"], lw=2, label="after")
    p.set(
        title="Points earned in a round, average solo (rounds 20+ nights)",
        xlabel="round",
        ylabel="points",
        xlim=(1, 18),
    )
    p.legend(frameon=False)
    fig.tight_layout()
    a.out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(a.out, dpi=110)
    print(
        "| Round | CoD health | in our units | ours before | ours after | CoD zombies 1p | ours before | ours after |"
    )
    for r in (1, 3, 5, 8, 10, 12, 15, 20, 25):
        print(
            f"| {r} | {cod_health(r):.0f} | {cod_health(r) * COD_TO_OURS:.0f} | {our_health(tb, r):.0f} | {our_health(ta, r):.0f} | {cod_count(r)} | {our_count(tb, r)} | {our_count(ta, r)} |"
        )
    print()
    print("| Weapon | " + " | ".join(f"R{r}" for r in (1, 5, 10, 15, 20)) + " |")
    for name, vals in rows:
        print(
            f"| {name} | "
            + " | ".join(f"{b:.1f} -> {af:.1f}" if abs(b - af) > 0.049 else f"{af:.1f}" for _, b, af in vals)
            + " |"
        )
    print()
    print(
        "points: "
        + ", ".join(
            f"R{r} {pb[r]:.0f} -> {pa[r]:.0f}"
            for r in (1, 3, 5, 8, 10, 12, 14)
            if r < len(pb) and not math.isnan(pb[r]) and not math.isnan(pa[r])
        )
    )


if __name__ == "__main__":
    main()
