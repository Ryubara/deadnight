"""The column measure for a faint vertical line (issue #1249).

For each column x of a screenshot: how far it stands from columns x-3 and x+3, row by row, in levels of grey (0 to 255).
Where the two sides are alike that is the issue's "distance from the mean of x-3 and x+3". Where they are not (a panel's
edge is a step, and the mean of the two sides reads half the step) the row takes the smaller of the two distances, so a
step reads 0 and only a ridge, a line brighter than both sides, reads high. A column the picture does not own, a seam
or a scratch, reads high on most rows; grain and the content around it average out. `worst` is the column with the highest mean offset, `share` the part of the rows where
that column is at least `ROW_LEVELS` above its two neighbours.

    uv run --with numpy --with pillow python tools/web_smoke/column_line.py <png> [<png> ...]
"""

from __future__ import annotations

import io
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

# The columns compared with: this many pixels either side.
SIDE = 3
# A row counts for the line when its column is this many levels above the neighbours.
ROW_LEVELS = 5.0
# A line the eye can read: the issue's "faint" line was about 10 levels on most rows; this is the bar for "gone".
READABLE_LEVELS = 3.0


@dataclass(frozen=True)
class Line:
    """The strongest column of one screenshot."""

    x: int
    mean: float
    share: float
    width: int

    def readable(self) -> bool:
        return self.mean >= READABLE_LEVELS and self.share >= 0.5

    def text(self) -> str:
        return f"x={self.x}/{self.width} mean=+{self.mean:.1f} on {self.share * 100:.0f}% of rows"


def grey(source: bytes | Path) -> np.ndarray:
    """The picture as float grey levels, rows by columns."""
    data = source if isinstance(source, bytes) else Path(source).read_bytes()
    return np.asarray(Image.open(io.BytesIO(data)).convert("L"), dtype=np.float32)


def offsets(picture: np.ndarray) -> np.ndarray:
    """Each pixel over the lower of the pixels `SIDE` to its left and right; the edge columns are left out."""
    mid = picture[:, SIDE:-SIDE]
    return np.minimum(mid - picture[:, : -2 * SIDE], mid - picture[:, 2 * SIDE :])


def strongest(picture: np.ndarray) -> Line:
    """The column that stands highest over its neighbours."""
    diff = offsets(picture)
    means = diff.mean(axis=0)
    at = int(np.argmax(means))
    return Line(
        x=at + SIDE,
        mean=float(means[at]),
        share=float((diff[:, at] >= ROW_LEVELS).mean()),
        width=picture.shape[1],
    )


def measure(source: bytes | Path) -> Line:
    return strongest(grey(source))


def still(pictures: list[np.ndarray]) -> np.ndarray:
    """What the shots share: their per-pixel median (the screen without the film that moves over it)."""
    return np.median(np.stack(pictures), axis=0)


def series(pictures: list[np.ndarray]) -> list[Line]:
    """The strongest column of each shot with what the shots share taken away."""
    shared = still(pictures)
    return [strongest(picture - shared) for picture in pictures]


if __name__ == "__main__":
    for name in sys.argv[1:]:
        print(f"{Path(name).name}: {measure(Path(name)).text()}")
