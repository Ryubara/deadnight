"""Draws the figures of docs/research/maps/small-map-formula.md: the abstract topology of the small-map formula and
the size comparison with the drive-in lot.

    uv run --with matplotlib python tools/docs/small_map_figures.py --out docs/research/maps [--previews <folder>]

`--previews` also writes PNG copies of the topology for a pull request (the page uses the SVG).

Both are our own drawings from numbers on the page. The topology is a graph of the formula's rooms and links, not a
floorplan of the reference map: no shape, proportion or position of the reference's rooms is drawn. The lot's areas
are the floor rectangles of `game/tools/lot/lot_report.gd`.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
matplotlib.rcParams["svg.hashsalt"] = "small-map"  # stable ids, so a rerun leaves no diff
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle

SURFACE, INK, INK_2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e7e6e1"
REFERENCE, LOT = "#2a78d6", "#eb6834"

# The lot's floor rectangles [x0, x1, z0, z1] in metres (game/tools/lot/lot_report.gd, AREAS).
LOT_AREAS = {
    "Field": [[-62.0, 62.0, -52.0, -4.0]],
    "Concession": [[-10.0, 10.0, -4.0, 8.0]],
    "Midway": [[-16.0, 16.0, 8.0, 38.0], [-16.0, -10.0, -4.0, 8.0], [10.0, 16.0, -4.0, 8.0]],
    "Booth": [[-6.0, 6.0, 22.0, 32.0]],
    "Yard": [[16.0, 62.0, -4.0, 38.0]],
    "Back lot": [[-62.0, -16.0, -4.0, 38.0]],
    "Road": [[-16.0, 16.0, 38.0, 52.0], [-62.0, 62.0, 52.0, 64.0]],
}
PLAYER_SPAWN = (0.0, -43.0)  # the centre of Field/PlayerSpawns, measured from the greybox
# The reference's ground floor as an abstract bounding block (estimated, metres), and its total floor.
REFERENCE_BLOCK = (29.0, 21.0)
REFERENCE_TOTAL = 600.0

# Distances in metres: (label, reference estimate, lot measured).
DISTANCES = [
    ("Player start to the nearest window or breach", 5.5, 37.1),
    ("Longest sight line indoors / on the lot", 20.0, 70.0),
    ("The big loop through bought doors (a lap)", 60.0, 110.0),
    ("Shortest kiting loop", 30.0, 45.0),
]


def style(ax: plt.Axes) -> None:
    ax.set_facecolor(SURFACE)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    ax.tick_params(colors=INK_2, labelsize=9)


def scale_figure(out: Path) -> None:
    fig, (plan, bars) = plt.subplots(1, 2, figsize=(13, 6.2), gridspec_kw={"width_ratios": [1.05, 1]})
    fig.patch.set_facecolor(SURFACE)
    style(plan)
    for name, rects in LOT_AREAS.items():
        for x0, x1, z0, z1 in rects:
            plan.add_patch(Rectangle((x0, -z1), x1 - x0, z1 - z0, fill=False, edgecolor=LOT, linewidth=1.2))
        x0, x1, z0, z1 = rects[0]
        z_label = 14.0 if name == "Midway" else (z0 + z1) / 2
        plan.text((x0 + x1) / 2, -z_label, name, ha="center", va="center", fontsize=8, color=INK_2)
    w, d = REFERENCE_BLOCK
    sx, sz = PLAYER_SPAWN
    plan.add_patch(Rectangle((sx - w / 2, -sz - d / 2), w, d, color=REFERENCE, alpha=0.85, linewidth=0))
    side = REFERENCE_TOTAL**0.5
    plan.add_patch(Rectangle((-58.0, 6.0), side, side, color=REFERENCE, alpha=0.35, linewidth=0))
    plan.annotate(
        "the reference's ground floor,\n29 x 21 m, on our players' start",
        (sx + w / 2, -sz),
        (24, 36),
        fontsize=9,
        color=INK,
        arrowprops={"arrowstyle": "-", "color": INK_2, "linewidth": 0.8},
    )
    plan.text(-58.0 + side + 2, 6.0 + side / 2, "its whole floor,\n600 m², as a square", fontsize=9, color=INK)
    plan.set_xlim(-66, 66)
    plan.set_ylim(-68, 56)
    plan.set_aspect("equal")
    plan.set_xlabel("metres (x)", color=INK_2, fontsize=9)
    plan.set_ylabel("metres (north up)", color=INK_2, fontsize=9)
    plan.set_title("Same scale: the drive-in lot, 13,100 m² of floor", color=INK, fontsize=11, loc="left")

    style(bars)
    labels = [d[0] for d in DISTANCES]
    ys = range(len(DISTANCES))
    bars.barh([y - 0.2 for y in ys], [d[1] for d in DISTANCES], height=0.38, color=REFERENCE, label="Reference (est.)")
    bars.barh([y + 0.2 for y in ys], [d[2] for d in DISTANCES], height=0.38, color=LOT, label="Drive-in lot")
    for y, (_, ref, lot) in zip(ys, DISTANCES, strict=True):
        bars.text(ref + 1.5, y - 0.2, f"{ref:g} m", va="center", fontsize=9, color=INK)
        bars.text(lot + 1.5, y + 0.2, f"{lot:g} m", va="center", fontsize=9, color=INK)
    bars.set_yticks(list(ys), labels, fontsize=9, color=INK)
    bars.invert_yaxis()
    bars.set_xlim(0, 130)
    bars.set_xlabel("metres", color=INK_2, fontsize=9)
    bars.grid(axis="x", color=GRID, linewidth=0.8)
    bars.set_axisbelow(True)
    bars.legend(frameon=False, fontsize=9, loc="lower right")
    bars.set_title("Distances that set the pressure", color=INK, fontsize=11, loc="left")
    fig.tight_layout()
    fig.savefig(out, dpi=110, facecolor=SURFACE)
    plt.close(fig)


def node(ax: plt.Axes, x: float, y: float, w: float, h: float, title: str, lines: list[str], windows: int) -> None:
    ax.add_patch(
        FancyBboxPatch(
            (x - w / 2, y - h / 2),
            w,
            h,
            boxstyle="round,pad=0.02,rounding_size=0.12",
            facecolor="#eef4fc",
            edgecolor=REFERENCE,
            linewidth=1.6,
        )
    )
    ax.text(x, y + h / 2 - 0.22, title, ha="center", va="top", fontsize=11, color=INK, weight="bold")
    for i, line in enumerate(lines):
        ax.text(x, y + h / 2 - 0.62 - 0.3 * i, line, ha="center", va="top", fontsize=9, color=INK_2)
    for i in range(windows):  # one tick a window, along the node's lower edge
        wx = x - (windows - 1) * 0.16 + i * 0.32
        ax.add_patch(Rectangle((wx - 0.1, y - h / 2 - 0.12), 0.2, 0.12, color=LOT, linewidth=0))


def link(ax: plt.Axes, a: tuple[float, float], b: tuple[float, float], text: str, dx: float = 0, dy: float = 0) -> None:
    ax.plot([a[0], b[0]], [a[1], b[1]], color=INK, linewidth=2.2, solid_capstyle="round", zorder=0)
    mx, my = (a[0] + b[0]) / 2 + dx, (a[1] + b[1]) / 2 + dy
    ax.text(mx, my, text, ha="center", va="center", fontsize=9, color=INK, backgroundcolor=SURFACE)


def topology_figure(out_svg: Path, out_png: Path | None) -> None:
    fig, ax = plt.subplots(figsize=(11, 6.6))
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)
    ax.set_xlim(0, 11)
    ax.set_ylim(0, 6.6)
    ax.axis("off")
    start, side, up_a, up_b = (2.6, 1.55), (8.4, 1.55), (2.6, 4.75), (8.4, 4.75)
    link(ax, start, side, "door (price P)", dy=0.0)
    link(ax, start, up_a, "stairs, blocked\n(price P)", dx=-0.95)
    link(ax, side, up_b, "stairs, blocked\n(price P)", dx=0.95)
    link(ax, up_a, up_b, "open (no door)")
    node(
        ax,
        *start,
        3.3,
        1.5,
        "Start room (ground)",
        ["about 210 m², cramped, pillars", "5 windows, 2 cheap wall buys"],
        5,
    )
    node(
        ax,
        *side,
        3.3,
        1.5,
        "Side room (ground)",
        ["about 150 m², long, a pillar row", "3 entries (1 a dead-end breach), box, 2 buys"],
        3,
    )
    node(ax, *up_a, 3.0, 1.35, "Upstairs, half A", ["over the start", "2 windows, 2 wall buys"], 2)
    node(ax, *up_b, 3.0, 1.35, "Upstairs, half B", ["over the side room", "2 windows, 2 buys + cabinet"], 2)
    ax.text(
        5.5,
        6.35,
        "The small-map formula as a graph (our drawing, not a floorplan)",
        ha="center",
        fontsize=12,
        color=INK,
    )
    ax.text(
        5.5,
        3.15,
        "Upstairs about 220 m² in all.  Any two doors make a chain with a dead end;\n"
        "the third closes the one ring (about 60 m a lap).  Orange ticks: windows (12).",
        ha="center",
        va="center",
        fontsize=9,
        color=INK_2,
    )
    fig.tight_layout()
    fig.savefig(out_svg, facecolor=SURFACE, metadata={"Date": None})
    # The SVG is committed: no trailing spaces (the whitespace hook) and no date, so a rerun leaves no diff.
    lines = [line.rstrip() for line in out_svg.read_text().splitlines()]
    out_svg.write_text("\n".join(lines) + "\n", newline="\n")
    if out_png is not None:
        fig.savefig(out_png, dpi=110, facecolor=SURFACE)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, required=True, help="folder for the figures")
    parser.add_argument("--previews", type=Path, help="folder for a PNG copy of the topology")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    scale_figure(args.out / "small-map-scale.png")
    preview = None
    if args.previews is not None:
        args.previews.mkdir(parents=True, exist_ok=True)
        preview = args.previews / "small-map-topology.png"
    topology_figure(args.out / "small-map-topology.svg", preview)
    print("wrote small-map-scale.png and small-map-topology.svg in", args.out)


if __name__ == "__main__":
    main()
