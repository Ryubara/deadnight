"""Runs the balance simulator (nine cells in parallel Godot processes) and draws its report.

    uv run --with matplotlib python tools/balance/run_report.py --out <folder> [--nights 400] [--seed 1]

The simulator itself is GDScript (`game/tools/balance/`): it plays thousands of seeded nights through
the real rules. This script only launches it, merges the nine cells (three skill levels by 1, 2 and 4
players) and draws the charts and the summary table. Needs the pinned Godot from the GDStudio kit
(`gds tool path godot`).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SKILLS = ["weak", "average", "strong"]
PLAYERS = [1, 2, 4]
GAME = Path(__file__).resolve().parents[2] / "game"


def _find_kit() -> Path:
    """The kit checkout beside the game, found by walking up to the workspace."""
    for parent in Path(__file__).resolve().parents:
        if (parent / "repos" / "gdstudio" / "python").is_dir():
            return parent / "repos" / "gdstudio"
        if (parent / "gdstudio" / "python").is_dir():
            return parent / "gdstudio"
    sys.exit("no GDStudio workspace around this checkout")


KIT = _find_kit()

# The reference palette of the dataviz skill: categorical slots in fixed order, light surface.
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
GRID = "#e7e6e1"
SERIES = {"weak": "#eb6834", "average": "#2a78d6", "strong": "#1baf7a"}
TYPE_COLORS = {
    "walker": "#2a78d6",
    "runner": "#eb6834",
    "crawler": "#1baf7a",
    "brute": "#eda100",
    "headliner": "#e87ba4",
}
SPECIAL = "#e87ba4"
SPIKE_FLOOR = 0.05  # the same as BalanceBatch.SPIKE_FLOOR


def godot_path() -> str:
    out = subprocess.run(
        ["uv", "run", "--project", str(KIT / "python"), "gds", "tool", "path", "godot"],
        capture_output=True,
        text=True,
        check=True,
    )
    return out.stdout.strip()


def run_cell(
    godot: str, out: Path, skill: str, players: int, nights: int, seed: int, step: float, sets: list[str] | None = None
) -> dict:
    path = out / "cells" / f"{skill}_{players}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        godot,
        "--headless",
        "--path",
        str(GAME),
        "-s",
        "res://tools/balance/balance_cli.gd",
        "--",
        f"--skill={skill}",
        f"--players={players}",
        f"--nights={nights}",
        f"--seed={seed}",
        f"--step={step}",
        f"--out={path}",
        *[f"--set={s}" for s in sets or []],
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if "SCRIPT ERROR" in result.stdout + result.stderr or not path.exists():
        sys.exit(f"cell {skill} x{players} failed:\n{result.stdout}\n{result.stderr}")
    return json.loads(path.read_text())


# --- Reading a cell (the same numbers as BalanceBatch in GDScript) ---


def survival(cell: dict, r: int) -> float:
    return cell["reached"][r] / cell["nights"]


def threat(cell: dict, r: int) -> float:
    return cell["pressure"][r] / cell["reached"][r] if cell["reached"][r] else 0.0


def hazard(cell: dict, r: int) -> float:
    return cell["died_in"][r] / cell["reached"][r] if cell["reached"][r] else 0.0


def median_round(cell: dict) -> int:
    return max((r for r in range(1, len(cell["reached"])) if survival(cell, r) >= 0.5), default=0)


def specials(cell: dict) -> list[int]:
    return sorted(int(r) for r, s in cell["special"].items() if s)


def spike(cell: dict, r: int) -> float:
    before = threat(cell, r - 1)
    after = threat(cell, r + 1) if r + 1 < len(cell["reached"]) else 0.0
    around = (before + after) / 2 if after > 0 else before
    return (threat(cell, r) + SPIKE_FLOOR) / (around + SPIKE_FLOOR)


# --- Charts ---


def style(plt):
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
            "grid.linewidth": 0.8,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "font.size": 10,
            "axes.titlesize": 11,
            "axes.titlelocation": "left",
            "legend.frameon": False,
        }
    )


def mark_specials(ax, rounds: list[int], ymax: float) -> None:
    for r in rounds:
        ax.axvspan(r - 0.45, r + 0.45, color=SPECIAL, alpha=0.3, lw=0)


def chart_survival(cells, out: Path, plt) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(13, 4), sharey=True)
    for ax, players in zip(axes, PLAYERS):
        rounds = range(1, 31)
        mark_specials(ax, specials(cells[("average", players)]), 1)
        for skill in SKILLS:
            cell = cells[(skill, players)]
            ys = [survival(cell, r) * 100 for r in rounds]
            ax.plot(rounds, ys, color=SERIES[skill], lw=2, label=skill)
        ax.set_title(f"{players} player{'s' if players > 1 else ''}")
        ax.set_xlabel("round")
        ax.set_xlim(1, 24)
        ax.set_ylim(0, 102)
        ax.axhline(50, color=INK_2, lw=0.8, ls=":")
    axes[0].set_ylabel("nights that reach the round (%)")
    axes[0].legend(title="player skill", loc="lower left")
    fig.suptitle("Survival by round. Shaded rounds are special rounds.", x=0.01, ha="left", color=INK)
    fig.tight_layout()
    fig.savefig(out / "survival.png", dpi=130)
    plt.close(fig)


def chart_spike(cells, out: Path, plt) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(13, 4), sharey=True)
    for ax, players in zip(axes, PLAYERS):
        cell = cells[("average", players)]
        special = set(specials(cell))
        last = max(r for r in range(1, len(cell["reached"])) if survival(cell, r) >= 0.2)
        rounds = list(range(1, last + 1))
        colors = [SPECIAL if r in special else SERIES["average"] for r in rounds]
        ax.bar(rounds, [threat(cell, r) for r in rounds], color=colors, width=0.7)
        for r in sorted(special):
            if r <= last:
                ax.annotate(
                    f"x{spike(cell, r):.1f}",
                    (r, threat(cell, r)),
                    ha="center",
                    va="bottom",
                    fontsize=9,
                    color=INK_2,
                )
        ax.set_title(f"{players} player{'s' if players > 1 else ''}, average skill")
        ax.set_xlabel("round")
    axes[0].set_ylabel("pressure: worst health lost, 0 to 1")
    fig.suptitle(
        "How hard each round is: special rounds (pink) against their neighbours; the label is the spike",
        x=0.01,
        ha="left",
        color=INK,
    )
    fig.tight_layout()
    fig.savefig(out / "special_spike.png", dpi=130)
    plt.close(fig)


def chart_economy(cells, out: Path, plt) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(13, 4))
    ax = axes[0]
    for skill in SKILLS:
        cell = cells[(skill, 1)]
        rounds = [r for r in range(1, 25) if cell["reached"][r] >= 10]
        ax.plot(
            rounds, [cell["earned"][r] / cell["reached"][r] for r in rounds], color=SERIES[skill], lw=2, label=skill
        )
    ax.set_title("Points earned in a round (solo)")
    ax.set_xlabel("round")
    ax.legend(title="player skill")
    ax = axes[1]
    for players, shade in zip(PLAYERS, ["#9ec5f4", "#3987e5", "#184f95"]):
        cell = cells[("average", players)]
        rounds = [r for r in range(1, 25) if cell["reached"][r] >= 10]
        ax.plot(rounds, [cell["earned"][r] / cell["reached"][r] for r in rounds], color=shade, lw=2, label=f"{players}")
    ax.set_title("Points earned per player (average skill)")
    ax.set_xlabel("round")
    ax.legend(title="players")
    ax = axes[2]
    cell = cells[("average", 1)]
    items = sorted(cell["spent_on"].items(), key=lambda kv: kv[1])
    ax.barh(
        [k.replace("_", " ") for k, _ in items],
        [v / cell["nights"] for _, v in items],
        color=SERIES["average"],
        height=0.6,
    )
    ax.set_title("Spent per night by item (solo, average)")
    ax.grid(axis="y", visible=False)
    fig.tight_layout()
    fig.savefig(out / "economy.png", dpi=130)
    plt.close(fig)


def chart_ttk(cells, out: Path, plt) -> None:
    types = ["walker", "runner", "crawler", "brute", "headliner"]
    fig, axes = plt.subplots(1, 2, figsize=(12, 4))
    for ax, key, title in zip(axes, [1, 2], ["Seconds under fire until the kill", "Shots fired at it"]):
        width = 0.26
        for i, skill in enumerate(SKILLS):
            cell = cells[(skill, 1)]
            ys = []
            for t in types:
                n, secs, shots = cell["ttk"].get(t, [0, 0.0, 0])
                ys.append((secs if key == 1 else shots) / n if n else 0)
            xs = [j + (i - 1) * width for j in range(len(types))]
            ax.bar(xs, ys, width=width * 0.9, color=SERIES[skill], label=skill)
        ax.set_xticks(range(len(types)), types)
        ax.set_title(title + " (solo)")
        ax.grid(axis="x", visible=False)
    axes[0].legend(title="player skill")
    fig.tight_layout()
    fig.savefig(out / "time_to_kill.png", dpi=130)
    plt.close(fig)


def summary(cells, out: Path, nights: int) -> str:
    lines = [f"# Balance report ({nights} nights per cell, 9 cells)", ""]
    lines += ["| skill | players | median round | mean round | reach r10 | reach r15 | points earned | points spent |"]
    lines += ["| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for skill in SKILLS:
        for players in PLAYERS:
            c = cells[(skill, players)]
            mean = sum(c["reached"][1:]) / c["nights"]
            lines.append(
                f"| {skill} | {players} | {median_round(c)} | {mean:.1f} | {survival(c, 10):.0%} | "
                f"{survival(c, 15):.0%} | {c['earned_total'] / c['nights']:.0f} | {c['spent_total'] / c['nights']:.0f} |"
            )
    lines += ["", "## Special rounds", ""]
    lines += [
        "| skill | players | round | kind | reached | threat | spike | death rate |",
        "| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |",
    ]
    for skill in SKILLS:
        for players in PLAYERS:
            c = cells[(skill, players)]
            for r in specials(c):
                if survival(c, r) >= 0.1:
                    lines.append(
                        f"| {skill} | {players} | {r} | {c['special'][str(r)]} | {survival(c, r):.0%} | "
                        f"{threat(c, r):.2f} | x{spike(c, r):.2f} | {hazard(c, r):.0%} |"
                    )
    lines += [
        "",
        "## Time to kill, solo average",
        "",
        "| type | kills | seconds under fire | shots |",
        "| --- | ---: | ---: | ---: |",
    ]
    for t, (n, secs, shots) in sorted(cells[("average", 1)]["ttk"].items()):
        lines.append(f"| {t} | {n} | {secs / n:.2f} | {shots / n:.1f} |")
    lines += ["", "## Round by round, average skill", ""]
    lines += ["| round | special | pressure 1p | pressure 2p | pressure 4p | death 1p | death 2p | death 4p |"]
    lines += ["| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    ref = cells[("average", 1)]
    for r in range(1, 19):
        row = [f"{threat(cells[('average', p)], r):.2f}" for p in PLAYERS]
        row += [f"{hazard(cells[('average', p)], r):.0%}" for p in PLAYERS]
        lines.append(f"| {r} | {ref['special'].get(str(r), '')} | " + " | ".join(row) + " |")
    text = "\n".join(lines) + "\n"
    (out / "report.md").write_text(text)
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--nights", type=int, default=400)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--step", type=float, default=0.25)
    parser.add_argument(
        "--set", action="append", default=[], help="a tuning override, path=value (see TuningOverrides)"
    )
    parser.add_argument("--brief", action="store_true", help="no charts, only the tables")
    parser.add_argument("--reuse", action="store_true", help="draw from the cells already in --out")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    style(plt)
    godot = None if args.reuse else godot_path()
    keys = [(s, p) for s in SKILLS for p in PLAYERS]
    if args.reuse:
        cells = {k: json.loads((args.out / "cells" / f"{k[0]}_{k[1]}.json").read_text()) for k in keys}
    else:
        with ThreadPoolExecutor(max_workers=len(keys)) as pool:
            futures = {
                k: pool.submit(run_cell, godot, args.out, k[0], k[1], args.nights, args.seed, args.step, args.set)
                for k in keys
            }
            cells = {k: f.result() for k, f in futures.items()}
    nights = cells[("average", 1)]["nights"]
    if not args.brief:
        for chart in (chart_survival, chart_spike, chart_economy, chart_ttk):
            chart(cells, args.out, plt)
    print(summary(cells, args.out, nights))


if __name__ == "__main__":
    main()
