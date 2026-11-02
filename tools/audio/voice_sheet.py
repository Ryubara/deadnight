"""A contact sheet of the soldier's script: every moment, its lines, their characters and length.

    uv run --with matplotlib python tools/audio/voice_sheet.py --out <folder> [--pages 2]

Reads `game/assets/audio/voice/soldier/manifest.json` (written by `elevenlabs_voice.py`) and draws the table as
`voice_script_<n>.png`, one page after another, so the script can be read (and read aloud) without opening the data.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

MANIFEST = Path("game/assets/audio/voice/soldier/manifest.json")
ROW = 0.205
COLORS = ["#ebf4ff", "#ffffff"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pages", type=int, default=2)
    args = parser.parse_args()
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    events: dict[str, list[tuple[str, dict]]] = {}
    for file, entry in manifest.items():
        events.setdefault(entry["event"], []).append((file, entry))
    names = list(events)
    per_page = -(-sum(len(v) for v in events.values()) // args.pages)
    pages: list[list[str]] = [[]]
    count = 0
    for name in names:
        if count >= per_page and len(pages) < args.pages:
            pages.append([])
            count = 0
        pages[-1].append(name)
        count += len(events[name])
    args.out.mkdir(parents=True, exist_ok=True)
    total_chars = sum(e["characters"] for e in manifest.values() if e["source"] == "text-to-speech")
    for n, page in enumerate(pages, 1):
        rows = sum(len(events[name]) for name in page) + len(page)
        fig = plt.figure(figsize=(15, rows * ROW + 1.0), dpi=80)
        ax = fig.add_axes((0, 0, 1, 1))
        ax.set_xlim(0, 15)
        ax.set_ylim(rows + 3.2, 0)
        ax.axis("off")
        ax.text(
            0.2, 0.9, f"The soldier's script (Deadnight #384), page {n} of {len(pages)}", fontsize=13, weight="bold"
        )
        ax.text(
            0.2,
            1.7,
            f"{len(manifest)} takes, {total_chars} characters requested (tags included). Brian, eleven_v4, stability 0.0.",
            fontsize=9,
            color="#4a5568",
        )
        y = 2.7
        for name in page:
            seconds = [e["seconds"] for _, e in events[name]]
            ax.add_patch(plt.Rectangle((0, y - 0.7), 15, 0.95, color="#2b6cb0"))
            ax.text(
                0.2,
                y,
                f"{name}   {len(seconds)} takes, {sum(e['characters'] for _, e in events[name])} chars, "
                f"{min(seconds):.1f} to {max(seconds):.1f} s",
                fontsize=9,
                color="white",
                weight="bold",
                va="center",
            )
            y += 1
            for i, (file, e) in enumerate(events[name]):
                ax.add_patch(plt.Rectangle((0, y - 0.5), 15, 1, color=COLORS[i % 2]))
                ax.text(0.2, y, file.removesuffix(".ogg"), fontsize=8, va="center", family="monospace")
                ax.text(2.6, y, e["text"], fontsize=8.5, va="center")
                ax.text(13.4, y, f"{e['characters']:>3} ch", fontsize=8, va="center", family="monospace")
                ax.text(14.2, y, f"{e['seconds']:.1f} s", fontsize=8, va="center", family="monospace")
                y += 1
        path = args.out / f"voice_script_{n}.png"
        fig.savefig(path)
        plt.close(fig)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
