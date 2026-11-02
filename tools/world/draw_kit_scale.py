"""Draw the small-map kit's scale diagram (docs/research/maps/kit-scale.png): openings against a 1.8 m player.

    uv run --with matplotlib python tools/world/draw_kit_scale.py [--out docs/research/maps/kit-scale.png]

Each panel is an elevation in metres: the reference's estimated opening dashed (a range, from the scale table of
docs/research/maps/small-map-art.md), the kit's target solid, and the drive-in lot's equivalent in grey where it has
one. The numbers are the page's; change them there first.
"""

import argparse
import math

import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle

INK = "#2b2b2b"
KIT = "#b8862b"  # the purchase door's yellow, darkened to read on white
REF = "#4a6fa5"
LOT = "#9a9a9a"
PLAYER = "#5c6d37"  # the Soldier's olive


def player(ax, x):
    """A 1.8 m player: a 0.7 m wide capsule (the body), a head ring at 1.6 m (the camera pivot)."""
    ax.add_patch(
        FancyBboxPatch(
            (x - 0.35, 0.0), 0.7, 1.8, boxstyle="round,pad=0,rounding_size=0.3", fc=PLAYER, ec=INK, lw=0.8, alpha=0.85
        )
    )
    ax.plot([x - 0.5, x + 0.5], [1.6, 1.6], color=INK, lw=0.6, ls=":")
    ax.text(x, 1.66, "pivot 1.6", ha="center", va="bottom", fontsize=6.5, color=INK)


def opening(ax, x, w, z0, h, colour, ls="-", lw=1.8, label=None):
    ax.add_patch(Rectangle((x - w / 2, z0), w, h, fill=False, ec=colour, ls=ls, lw=lw))
    if label:
        ax.text(x, z0 + h + 0.06, label, ha="center", va="bottom", fontsize=7, color=colour)


def panel(ax, title):
    ax.set_title(title, fontsize=9, loc="left", color=INK)
    ax.set_aspect("equal")
    ax.axhline(0, color=INK, lw=1.2)
    ax.set_ylim(-0.2, 4.4)
    ax.tick_params(labelsize=7)
    ax.set_yticks([0, 0.9, 1.8, 2.4, 2.8, 3.0, 4.0])
    ax.grid(axis="y", color="#e4e4e4", lw=0.6)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="docs/research/maps/kit-scale.png")
    a = ap.parse_args()
    fig, axes = plt.subplots(1, 4, figsize=(14, 4.2), gridspec_kw={"width_ratios": [1.9, 1.1, 1.7, 1.6]})

    ax = axes[0]
    panel(ax, "Purchase doorway")
    ax.set_xlim(-0.6, 5.8)
    player(ax, 0.0)
    opening(ax, 1.5, 1.2, 0, 2.2, REF, "--", label="ref. 1.2-1.4")
    opening(ax, 1.5, 1.4, 0, 2.4, REF, "--")
    opening(ax, 1.5, 1.4, 0, 2.4, KIT, lw=2.2)
    ax.text(1.5, 1.1, "kit\n1.4 x 2.4", ha="center", fontsize=7.5, color=KIT)
    opening(ax, 4.0, 3.0, 0, 2.6, LOT, lw=1.2, label="lot door 3.0 x 2.6")

    ax = axes[1]
    panel(ax, "Zombie window")
    ax.set_xlim(-0.6, 2.6)
    player(ax, 0.0)
    opening(ax, 1.4, 1.0, 0.8, 1.0, REF, "--")
    opening(ax, 1.4, 1.3, 1.0, 1.3, REF, "--", label="ref. sill 0.8-1.0")
    opening(ax, 1.4, 1.2, 0.9, 1.3, KIT, lw=2.2)
    ax.text(1.4, 0.45, "kit 1.2 x 1.3\nsill 0.9", ha="center", fontsize=7.5, color=KIT)

    ax = axes[2]
    panel(ax, "Stair (section) and storey")
    ax.set_xlim(-0.6, 5.6)
    player(ax, 0.0)
    xs, zs = [0.6], [0.0]
    for i in range(15):
        xs += [xs[-1], xs[-1] + 0.3]
        zs += [zs[-1] + 0.2, zs[-1] + 0.2]
    ax.plot(xs, zs, color=KIT, lw=2.0)
    ax.text(
        3.0, 0.9, "kit: 15 x 0.2 m risers,\n0.3 m treads, 33.7 deg,\n1.4 m wide (ref. 1.2-1.4)", fontsize=7.2, color=KIT
    )
    ax.axhline(2.8, color=KIT, lw=1.2, ls="-")
    ax.text(5.5, 2.83, "kit ceiling 2.8 (beam 2.4)", ha="right", va="bottom", fontsize=7, color=KIT)
    ax.axhspan(2.8, 3.0, color=KIT, alpha=0.12)
    ax.axhline(3.2, color=REF, lw=1.0, ls="--")
    ax.text(-0.5, 3.24, "ref. floor to floor about 3.2", fontsize=7, color=REF)
    ax.axhline(3.75, color=LOT, lw=1.0)
    ax.text(-0.5, 3.79, "lot booth floor 3.75 (ramp, 25 deg, 2.0 wide)", fontsize=7, color=LOT)

    ax = axes[3]
    panel(ax, "Under a 2.8 m ceiling: the camera")
    ax.set_xlim(-3.2, 1.0)
    player(ax, 0.0)
    ax.axhline(2.8, color=KIT, lw=1.2)
    for deg, col in ((0, INK), (24, KIT), (40, "#b8322e")):
        r = math.radians(deg)
        cx, cz = -2.3 * math.cos(r), 1.6 + 2.3 * math.sin(r)
        ax.plot([0, cx], [1.6, cz], color=col, lw=1.0)
        ax.add_patch(plt.Circle((cx, cz), 0.25, fill=False, ec=col, lw=1.0))
        ax.text(cx, cz - 0.4, f"{deg} deg down", ha="center", fontsize=6.8, color=col)
    ax.text(
        -3.1,
        4.05,
        "arm 2.3 m, lens margin 0.25 m: the arm\nshortens past about 24 deg down (14 under a 2.4 m beam)",
        fontsize=7,
        color=INK,
    )

    fig.legend(
        handles=[
            plt.Line2D([], [], color=REF, ls="--", label="reference, estimated from the images"),
            plt.Line2D([], [], color=KIT, lw=2.2, label="kit target"),
            plt.Line2D([], [], color=LOT, label="drive-in lot today"),
        ],
        loc="lower center",
        ncol=3,
        fontsize=8,
        frameon=False,
    )
    fig.tight_layout(rect=(0, 0.06, 1, 1))
    fig.savefig(a.out, dpi=110)
    print("WROTE", a.out)


if __name__ == "__main__":
    main()
