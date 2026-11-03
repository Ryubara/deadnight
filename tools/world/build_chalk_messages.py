"""Write the small map's chalk messages (game/assets/smallmap/chalk_messages.png and .json): our own short lines in our
own lettering, scrawled in chalk (docs/research/maps/small-map-art.md, Lighting and atmosphere).

The letters are a stroke alphabet drawn here on a 4 x 6 grid (no font), put down as many small dabs along each stroke,
each letter a little off level and off the line, then grained so the strokes break up the way dry chalk does on block.
The picture is greyscale, one message a row; the game's `ChalkMessage` reads its row through `chalk_messages.json` and
draws it additively in the Chalk swatch's colour where a moon shaft or a lamp lands, so it reads only in the light.

Run it from the repository root and commit what it writes (a fixed seed, so a rerun changes nothing):

    uv run --with pillow python tools/world/build_chalk_messages.py
"""

import itertools
import json
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_texture_imports import ensure_import

OUT = Path("game/assets/smallmap")
SIZE = 1024
ROW = 128  # pixels a message's row takes; the letters are about 60 of it
UNIT = 9.0  # pixels a grid unit; a letter is 4 x 6 units
GAP = 1.7  # units between letters
SPACE = 3.0  # units a space takes
SEED = 1958

# Our own lines. Each is short enough for one row and says something about this night: light, the dead, the way on.
MESSAGES = [
    "KEEP THE LIGHTS ON",
    "STAY IN THE LIGHT",
    "THEY COME AT DARK",
    "NOT THIS WAY",
    "HOLD THE WINDOWS",
    "UP THERE >",
]

# The strokes of each letter: polylines on a 4 x 6 grid, y down. Only the letters the messages use.
P_BOWL = [(0, 6), (0, 0), (3, 0), (4, 1), (4, 2), (3, 3), (0, 3)]
GLYPHS: dict[str, list[list[tuple[float, float]]]] = {
    "A": [[(0, 6), (2, 0), (4, 6)], [(0.9, 3.6), (3.1, 3.6)]],
    "C": [[(4, 1), (3, 0), (1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5)]],
    "D": [[(0, 0), (0, 6), (2.5, 6), (4, 4.5), (4, 1.5), (2.5, 0), (0, 0)]],
    "E": [[(4, 0), (0, 0), (0, 6), (4, 6)], [(0, 3), (3, 3)]],
    "G": [[(4, 1), (3, 0), (1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5), (4, 3.5), (2.4, 3.5)]],
    "H": [[(0, 0), (0, 6)], [(4, 0), (4, 6)], [(0, 3), (4, 3)]],
    "I": [[(0.6, 0), (0.4, 6)]],
    "K": [[(0, 0), (0, 6)], [(4, 0), (0, 3.6)], [(1.3, 2.6), (4, 6)]],
    "L": [[(0, 0), (0, 6), (4, 6)]],
    "M": [[(0, 6), (0, 0), (2, 3.2), (4, 0), (4, 6)]],
    "N": [[(0, 6), (0, 0), (4, 6), (4, 0)]],
    "O": [[(1, 0), (3, 0), (4, 1), (4, 5), (3, 6), (1, 6), (0, 5), (0, 1), (1, 0)]],
    "P": [P_BOWL],
    "R": [P_BOWL, [(2, 3), (4, 6)]],
    "S": [[(4, 1), (3, 0), (1, 0), (0, 1), (0, 2), (1, 3), (3, 3), (4, 4), (4, 5), (3, 6), (1, 6), (0, 5)]],
    "T": [[(0, 0), (4, 0)], [(2, 0), (2, 6)]],
    "U": [[(0, 0), (0, 5), (1, 6), (3, 6), (4, 5), (4, 0)]],
    "W": [[(0, 0), (1, 6), (2, 2.4), (3, 6), (4, 0)]],
    "Y": [[(0, 0), (2, 3), (4, 0)], [(2, 3), (2, 6)]],
    ">": [[(0, 3), (5, 3)], [(3, 1), (5, 3), (3, 5)]],
}


def width_of(ch: str) -> float:
    if ch == " ":
        return SPACE
    return max(x for stroke in GLYPHS[ch] for x, _ in stroke)


def scrawl(draw: ImageDraw.ImageDraw, rng: random.Random, text: str, top: float) -> float:
    """Draws `text` in chalk dabs from the left of the row at `top`; returns the pixel width it took."""
    x = 14.0
    for ch in text:
        if ch == " ":
            x += SPACE * UNIT
            continue
        tilt = math.radians(rng.uniform(-10, 10))
        lift = rng.uniform(-5, 5) + 6 * math.sin(x / 170.0) - x * 0.012  # the line climbs a little
        scale = rng.uniform(0.86, 1.14)
        ox, oy = x, top + (ROW - 6 * UNIT) / 2 + lift
        for stroke in GLYPHS[ch]:
            pts = []
            for gx, gy in stroke:
                sx, sy = (gx - 2) * UNIT * scale, (gy - 3) * UNIT * scale
                pts.append(
                    (
                        ox + 2 * UNIT + sx * math.cos(tilt) - sy * math.sin(tilt) + rng.uniform(-1.8, 1.8),
                        oy + 3 * UNIT + sx * math.sin(tilt) + sy * math.cos(tilt) + rng.uniform(-1.8, 1.8),
                    )
                )
            pressure = rng.uniform(0.8, 1.0)
            for (x0, y0), (x1, y1) in itertools.pairwise(pts):
                steps = max(2, int(math.hypot(x1 - x0, y1 - y0) / 1.2))
                for k in range(steps + 1):
                    t = k / steps
                    r = rng.uniform(2.2, 3.6)
                    cx = x0 + (x1 - x0) * t + rng.uniform(-0.7, 0.7)
                    cy = y0 + (y1 - y0) * t + rng.uniform(-0.7, 0.7)
                    v = int(255 * pressure * rng.uniform(0.75, 1.0))
                    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=v)
        x += (width_of(ch) * scale + GAP + rng.uniform(-0.4, 0.5)) * UNIT
    return x + 14.0


def main() -> None:
    rng = random.Random(SEED)
    img = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(img)
    layout = []
    for i, text in enumerate(MESSAGES):
        used = scrawl(draw, rng, text, i * ROW)
        if used > SIZE:
            raise SystemExit(f"{text!r} is {used:.0f} px, over {SIZE}")
        layout.append({"text": text, "x": 0, "y": i * ROW, "w": math.ceil(used), "h": ROW})
    # The grain of chalk on block: the strokes break up, more at their edges (a soft blur, then a speckled cut).
    img = img.filter(ImageFilter.GaussianBlur(0.7))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            v = px[x, y]
            if v:
                keep = rng.random()
                px[x, y] = 0 if keep < 0.18 * (1.2 - v / 255) else int(v * (0.65 + 0.35 * keep))
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "chalk_messages.png", optimize=True)
    ensure_import(OUT / "chalk_messages.png")  # lossless, mipmaps on (tools/check_texture_imports.py)
    (OUT / "chalk_messages.json").write_text(
        json.dumps({"size": SIZE, "messages": layout}, indent=1) + "\n", encoding="utf-8", newline="\n"
    )
    for row in layout:
        print(f"{row['text']}: {row['w']} x {row['h']} px")


main()
