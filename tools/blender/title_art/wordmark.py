"""The DEADNIGHT title wordmark: a 1950s drive-in sign letter built from the game's display face (Bungee Inline,
SIL OFL 1.1, committed under game/assets/fonts with its licence).

Plain Python (no Blender), run with:

    uv run --with pillow --with numpy --with scipy python wordmark.py --out <dir>

Each treatment is drawn at a large supersampled size and saved as a transparent PNG master per lockup:

- `marquee`: cream sign-paint faces, the face's inline line widened into a red pinstripe, a deep red block
  extrusion down and right (the painted sign's "block shadow"), an ink keyline round the whole letter.
- `neon`: the game's lit sign (game/ui/skin/neon_sign.gd): DEAD in the red tube colour, NIGHT in amber, as painted
  channel letters with the lit tube running in the inline, a dark extrusion, an ink keyline and a coloured glow.

Lockups: `wide` (one line) and `stacked` (DEAD over NIGHT, both lines the same width).
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[3]
FONT = ROOT / "game/assets/fonts/bungee_inline/BungeeInline-Regular.ttf"

# Colours: the game's tokens (game/addons/gds_ui/tokens/ui_tokens.gd, game/ui/menu/menu_look.gd,
# game/ui/skin/neon_sign.gd). No new hues.
INK = "#1c1612"  # PAPER_INK
CREAM = "#f4ead2"  # ink
PAPER_SHADE = "#d8cba9"
RED = "#d6392f"  # the program's one accent
RED_DEEP = "#7a1d18"
RED_DARK = "#3e0f0d"
TUBE_RED = "#ff3d4d"
TUBE_AMBER = "#ffb347"
TUBE_CORE = "#fff4dc"

CAP = 720  # cap height in pixels at the supersampled size


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def disk_grow(mask, r):
    """Binary dilation by a disc of radius r (distance transform, fast for big radii)."""
    if r <= 0:
        return mask.copy()
    return ndimage.distance_transform_edt(~mask) <= r


def soft_grow(mask, r):
    """An anti-aliased coverage of the mask grown by r pixels."""
    d = ndimage.distance_transform_edt(~mask)
    return np.clip(r + 0.5 - d, 0.0, 1.0).astype(np.float32)


def close(mask, r):
    grown = disk_grow(mask, r)
    return ndimage.distance_transform_edt(grown) > r


def set_line(text, size, tracking):
    """The glyph coverage (float 0..1) for one line, letters placed one by one with extra tracking, and each
    letter's x range (for colouring)."""
    font = ImageFont.truetype(str(FONT), size)
    asc, desc = font.getmetrics()
    widths = [font.getlength(ch) for ch in text]
    total = int(sum(widths) + tracking * (len(text) - 1)) + 4
    im = Image.new("L", (total, asc + desc), 0)
    d = ImageDraw.Draw(im)
    x = 0.0
    spans = []
    for ch, w in zip(text, widths):
        d.text((x, 0), ch, font=font, fill=255)
        spans.append((int(x), int(x + w)))
        x += w + tracking
    a = np.asarray(im, dtype=np.float32) / 255.0
    rows = np.where(a.max(axis=1) > 0.5)[0]
    top, bottom = rows[0], rows[-1] + 1
    return a[top:bottom], spans


def lockup(kind):
    """Glyph coverage and a per-pixel letter index (0..8) for the lockup, at CAP cap height."""
    # Bungee's cap height is about 0.727 of the size (measured: 218 px at 300).
    size = int(CAP / 0.727)
    track = int(size * -0.005)
    if kind == "wide":
        g, spans = set_line("DEADNIGHT", size, track)
        idx = np.zeros(g.shape, dtype=np.int8)
        for i, (x0, x1) in enumerate(spans):
            idx[:, x0 : x1 + track] = i
        return g, idx
    # Stacked: NIGHT at CAP, DEAD scaled so both lines are the same width.
    night, _ns = set_line("NIGHT", size, track)
    dead0, _ = set_line("DEAD", size, track)
    scale = night.shape[1] / dead0.shape[1]
    dsize = int(size * scale)
    dead, _ds = set_line("DEAD", dsize, int(track * scale))
    w = max(night.shape[1], dead.shape[1])
    gap = int(CAP * 0.12)
    h = dead.shape[0] + gap + night.shape[0]
    g = np.zeros((h, w), dtype=np.float32)
    idx = np.zeros((h, w), dtype=np.int8)
    ox = (w - dead.shape[1]) // 2
    g[: dead.shape[0], ox : ox + dead.shape[1]] = dead
    ox2 = (w - night.shape[1]) // 2
    g[dead.shape[0] + gap :, ox2 : ox2 + night.shape[1]] = night
    idx[: dead.shape[0] + gap // 2, :] = 0
    idx[dead.shape[0] + gap // 2 :, :] = 4
    return g, idx


def paste(base_rgb, base_a, col, alpha):
    """Composite a flat colour (or per-pixel colour array) with coverage `alpha` over straight-alpha layers."""
    a = alpha[..., None]
    c = col if col.ndim == 3 else col[None, None, :]
    ba = base_a[..., None]
    oa = a + ba * (1 - a)
    base_rgb[:] = np.where(oa > 1e-6, (c * a + base_rgb * ba * (1 - a)) / np.maximum(oa, 1e-6), 0.0)
    base_a[:] = oa[..., 0]


def build(kind, treatment, extrude_dir=(0.45, 0.9)):
    g, idx = lockup(kind)
    pad = int(CAP * 0.5)
    g = np.pad(g, pad)
    idx = np.pad(idx, pad, mode="edge")
    glyph = g > 0.5
    # The inline is a hairline gap through each stroke: closing fills it, giving the solid letter.
    sil = close(glyph, int(CAP * 0.03))
    inline = sil & ~glyph
    sil_cov = np.maximum(g, inline.astype(np.float32))
    # The block extrusion: the solid letter swept down and right.
    depth = int(CAP * 0.15)
    dx, dy = extrude_dir
    n = np.hypot(dx, dy)
    dx, dy = dx / n, dy / n
    ext = np.zeros_like(sil)
    shade = np.zeros(sil.shape, dtype=np.float32)
    for t in range(1, depth + 1, 2):
        sh = ndimage.shift(sil.astype(np.uint8), (t * dy, t * dx), order=0).astype(bool)
        newly = sh & ~ext
        shade[newly] = t / depth
        ext |= sh
    ext &= ~sil
    whole = sil | ext
    key_r = int(CAP * 0.055)
    keyline = soft_grow(whole, key_r)
    h, w = g.shape
    out_rgb = np.zeros((h, w, 3), dtype=np.float32)
    out_a = np.zeros((h, w), dtype=np.float32)
    dead = idx < 4

    if treatment == "neon":
        tube_col = np.where(dead[..., None], rgb(TUBE_RED)[None, None], rgb(TUBE_AMBER)[None, None])
        # A wide soft glow in each letter's colour behind everything.
        glow_src = soft_grow(sil, int(CAP * 0.02))
        glow = (
            np.asarray(
                Image.fromarray((glow_src * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(CAP * 0.16)),
                dtype=np.float32,
            )
            / 255.0
        )
        paste(out_rgb, out_a, tube_col, np.clip(glow * 0.85, 0, 1))
    elif treatment == "marquee":
        warm = (
            np.asarray(
                Image.fromarray((soft_grow(whole, 0) * 255).astype(np.uint8)).filter(
                    ImageFilter.GaussianBlur(CAP * 0.14)
                ),
                dtype=np.float32,
            )
            / 255.0
        )
        paste(out_rgb, out_a, rgb(TUBE_AMBER), np.clip(warm * 0.45, 0, 1))
    paste(out_rgb, out_a, rgb(INK), keyline)
    # Extrusion: deep at the face, darker toward its far edge.
    if treatment == "neon":
        ext_col = rgb("#2a1f2e")[None, None] * (1 - shade[..., None] * 0.5)
    elif treatment == "board":
        ext_col = rgb(RED_DARK)[None, None] * (1 - shade[..., None] * 0.4)
    else:
        ext_col = rgb(RED_DEEP)[None, None] * (1 - shade[..., None]) + rgb(RED_DARK)[None, None] * shade[..., None]
    paste(out_rgb, out_a, ext_col, ext.astype(np.float32))
    # A thin ink line between face and extrusion so the face reads at small sizes.
    face_edge = soft_grow(sil, int(CAP * 0.012))
    paste(out_rgb, out_a, rgb(INK), face_edge)
    # Faces.
    ys = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    rows = np.where(sil.any(axis=1))[0]
    if treatment == "neon":
        face = np.where(dead[..., None], rgb("#b8242c")[None, None], rgb("#d98a2b")[None, None])
        paste(out_rgb, out_a, face, sil_cov)
        # The lit tube in the inline: a hot core with a coloured sleeve.
        sleeve = soft_grow(inline, int(CAP * 0.03))
        core = soft_grow(inline, int(CAP * 0.011))
        sleeve_col = np.where(dead[..., None], rgb(TUBE_RED)[None, None], rgb(TUBE_AMBER)[None, None])
        bloom = (
            np.asarray(
                Image.fromarray((sleeve * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(CAP * 0.03)),
                dtype=np.float32,
            )
            / 255.0
        )
        paste(out_rgb, out_a, sleeve_col, np.clip(bloom * 1.2, 0, 1) * sil_cov)
        paste(out_rgb, out_a, sleeve_col, sleeve * sil_cov)
        paste(out_rgb, out_a, rgb(TUBE_CORE), core * sil_cov)
    elif treatment == "board":
        top, bottom = rows[0], rows[-1]
        t = np.clip((ys - top / h) / max((bottom - top) / h, 1e-6), 0, 1)
        face = rgb(RED)[None, None] * (1 - t * 0.2) + rgb(RED_DEEP)[None, None] * (t * 0.2)
        paste(out_rgb, out_a, np.broadcast_to(face, (h, w, 3)).copy(), sil_cov)
        stripe = soft_grow(inline, int(CAP * 0.016))
        paste(out_rgb, out_a, rgb(CREAM), stripe * sil_cov)
    else:
        # Cream sign paint, a touch shaded toward the foot of each line.
        top, bottom = rows[0], rows[-1]
        t = np.clip((ys - top / h) / max((bottom - top) / h, 1e-6), 0, 1)
        face = rgb(CREAM)[None, None] * (1 - t * 0.18) + rgb(PAPER_SHADE)[None, None] * (t * 0.18)
        paste(out_rgb, out_a, np.broadcast_to(face, (h, w, 3)).copy(), sil_cov)
        stripe = soft_grow(inline, int(CAP * 0.016))
        paste(out_rgb, out_a, rgb(RED), stripe * sil_cov)
    # Trim to the drawn area plus a small margin.
    ys_, xs_ = np.where(out_a > 0.01)
    m = int(CAP * 0.05)
    y0, y1 = max(ys_.min() - m, 0), min(ys_.max() + m, h)
    x0, x1 = max(xs_.min() - m, 0), min(xs_.max() + m, w)
    rgba = np.dstack([out_rgb[y0:y1, x0:x1], out_a[y0:y1, x0:x1]])
    if treatment == "board":
        return sign_board(rgba)
    return Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def sign_board(letters):
    """The letters on a marquee board, after the game's own marquee prop (game/assets/drivein/marquee.gltf): a
    cream panel in a red frame ringed with bulbs, cut with the program's half-round ticket notches at each end,
    and a hard offset shadow, as on a printed poster."""
    lh, lw = letters.shape[:2]
    band = int(CAP * 0.26)  # the red frame
    margin = int(CAP * 0.2)  # cream between frame and letters
    shadow = int(CAP * 0.1)
    bw, bh = lw + 2 * (band + margin), lh + 2 * (band + margin)
    W, H = bw + shadow + int(CAP * 0.4), bh + shadow + int(CAP * 0.4)
    ox, oy = int(CAP * 0.2), int(CAP * 0.2)
    out_rgb = np.zeros((H, W, 3), dtype=np.float32)
    out_a = np.zeros((H, W), dtype=np.float32)

    def rect(x0, y0, x1, y1):
        m = np.zeros((H, W), dtype=bool)
        m[y0:y1, x0:x1] = True
        return m

    notch_r = int(bh * 0.16)
    yy, xx = np.mgrid[0:H, 0:W]

    def notched(x0, y0, x1, y1):
        m = rect(x0, y0, x1, y1)
        cy = (y0 + y1) / 2
        for cx in (x0, x1):
            m &= (xx - cx) ** 2 + (yy - cy) ** 2 > notch_r**2
        return m

    plate = notched(ox, oy, ox + bw, oy + bh)
    shadow_m = np.roll(np.roll(plate, shadow, axis=0), shadow, axis=1)
    paste(out_rgb, out_a, rgb(INK), shadow_m.astype(np.float32) * 0.85)
    paste(out_rgb, out_a, rgb(INK), soft_grow(plate, int(CAP * 0.03)))
    paste(out_rgb, out_a, rgb(RED), plate.astype(np.float32))
    inner = notched(ox + band, oy + band, ox + bw - band, oy + bh - band)
    paste(out_rgb, out_a, rgb(INK), soft_grow(inner, int(CAP * 0.025)))
    paste(out_rgb, out_a, rgb(CREAM), inner.astype(np.float32))
    # Bulbs round the frame, evenly spaced along its middle line, none in the notches.
    r = band * 0.24
    pitch = band * 0.95
    path = []
    x0, y0, x1, y1 = ox + band / 2, oy + band / 2, ox + bw - band / 2, oy + bh - band / 2
    nx = int((x1 - x0) / pitch)
    ny = int((y1 - y0) / pitch)
    for i in range(nx + 1):
        x = x0 + (x1 - x0) * i / nx
        path += [(x, y0), (x, y1)]
    for j in range(1, ny):
        y = y0 + (y1 - y0) * j / ny
        if abs(y - (oy + bh / 2)) < notch_r + r * 1.5:
            continue
        path += [(x0, y), (x1, y)]
    glow = np.zeros((H, W), dtype=np.float32)
    ring = np.zeros((H, W), dtype=np.float32)
    core = np.zeros((H, W), dtype=np.float32)
    for bx, by in path:
        d = np.hypot(
            xx[int(by - 2 * r) : int(by + 2 * r), int(bx - 2 * r) : int(bx + 2 * r)] - bx,
            yy[int(by - 2 * r) : int(by + 2 * r), int(bx - 2 * r) : int(bx + 2 * r)] - by,
        )
        sl = (slice(int(by - 2 * r), int(by + 2 * r)), slice(int(bx - 2 * r), int(bx + 2 * r)))
        ring[sl] = np.maximum(ring[sl], np.clip(r + 0.5 - d, 0, 1))
        core[sl] = np.maximum(core[sl], np.clip(r * 0.55 + 0.5 - d, 0, 1))
        glow[sl] = np.maximum(glow[sl], np.clip(1.6 * r - d, 0, 1))
    blur = (
        np.asarray(
            Image.fromarray((ring * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r * 0.9)), dtype=np.float32
        )
        / 255.0
    )
    paste(out_rgb, out_a, rgb(TUBE_AMBER), np.clip(blur * 1.3, 0, 1) * 0.8)
    paste(out_rgb, out_a, rgb("#ffc66b"), ring)
    paste(out_rgb, out_a, rgb(TUBE_CORE), core)
    # The letters, centred on the panel.
    lx, ly = ox + band + margin, oy + band + margin
    la = letters[..., 3]
    sub_rgb = out_rgb[ly : ly + lh, lx : lx + lw]
    sub_a = out_a[ly : ly + lh, lx : lx + lw]
    paste(sub_rgb, sub_a, letters[..., :3], la)
    out_rgb[ly : ly + lh, lx : lx + lw] = sub_rgb
    out_a[ly : ly + lh, lx : lx + lw] = sub_a
    rgba = np.dstack([out_rgb, out_a])
    return Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--treatments", nargs="*", default=["marquee", "neon", "board"])
    ap.add_argument("--lockups", nargs="*", default=["wide", "stacked"])
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for t in args.treatments:
        for k in args.lockups:
            im = build(k, t)
            p = args.out / f"wordmark_{t}_{k}.png"
            im.save(p)
            print(f"wrote {p} {im.size}")


if __name__ == "__main__":
    main()
