"""Write the lot's surface textures and materials (game/assets/lot/): the greybox's paint (docs/design/style.md).

The kit is flat colour, so a lot texture is a grey pattern in a few flat tones (planks, block courses, slabs, ribs)
that the material tints with one palette colour: the colour stays the palette's and the pattern says what the
surface is. Every material projects its texture in world space (triplanar), so a CSG box of any size keeps the
pattern at its real scale, and none needs UVs. Cheap on the Compatibility renderer: one 256 x 256 greyscale
texture a material, no normal maps, no lights beyond the scene's.

Run it from the repository root and commit what it writes (a fixed seed, so a rerun changes nothing):

    uv run --with pillow python tools/world/build_lot_textures.py
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path("game/assets/lot")
RES = "res://assets/lot"
SIZE = 256

# Texture -> the metres one tile of it covers in the world (the material's triplanar scale is 1 / metres).
TILES = {
    "asphalt": 4.0,
    "gravel": 2.0,
    "concrete": 4.0,
    "planks": 2.0,
    "corrugated": 2.0,
    "blocks": 3.2,
    "checker": 2.0,
    "shutter": 2.0,
}

# Material -> (texture or None for flat paint, sRGB tint, emission or None). The tints are the style bible's palette
# (Grey #818491, Grey2 #5f5f5f, Yellow #d1ab46, Blue #3b4b8c, Wood #95703d, Cardboard #9b7048, Tree_Green #6b7f26,
# Black #252525), darkened or lightened in steps where a surface needs its own value; nothing is the old debug red.
MATERIALS = {
    "outskirts": ("gravel", "#2b2c2a", None),
    "field_ground": ("asphalt", "#5a5d66", None),
    "field_struct": ("planks", "#c9c4b0", None),
    "field_fence": ("planks", "#7d6446", None),
    "screen_face": (None, "#dfe8f5", "#8fa4c8"),
    "concession_ground": ("checker", "#d6cdb4", None),
    "concession_wall": ("blocks", "#d8b67a", None),
    "concession_roof": ("corrugated", "#5f5f5f", None),
    "concession_prop": ("planks", "#95703d", None),
    "midway_ground": ("concrete", "#8f8c84", None),
    "midway_wall": ("corrugated", "#818491", None),
    "booth_ground": ("planks", "#6e5232", None),
    "booth_wall": ("blocks", "#9a9ca6", None),
    "booth_prop": ("concrete", "#6f717b", None),
    "yard_ground": ("gravel", "#7a705a", None),
    "yard_wall": ("corrugated", "#6b7f26", None),
    "yard_prop": ("corrugated", "#3b4b8c", None),
    "yard_gen": (None, "#d1ab46", "#8a7020"),
    "backlot_ground": ("gravel", "#544c3c", None),
    "backlot_wall": ("planks", "#5e4a36", None),
    "backlot_prop": ("corrugated", "#6a5a4a", None),
    "neon": (None, "#ff7a3a", "#ff5a20"),
    "road_ground": ("asphalt", "#4a4c54", None),
    "road_wall": ("concrete", "#9a9ca4", None),
    "road_kiosk": ("blocks", "#d8cfb5", None),
    "road_line": (None, "#d1ab46", None),
    "door": ("shutter", "#d1ab46", None),
    "roadblock": ("concrete", "#818491", None),
    "breach_ground": ("gravel", "#3d3829", None),
    "line_paint": (None, "#d8d2bc", None),
}


def value_noise(rng: random.Random, cells: int) -> list[list[float]]:
    """Smooth tileable noise in 0..1, `cells` lattice cells across the texture."""
    grid = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    step = SIZE / cells
    out = []
    for y in range(SIZE):
        gy, fy = divmod(y / step, 1)
        y0, y1 = int(gy) % cells, (int(gy) + 1) % cells
        sy = fy * fy * (3 - 2 * fy)
        row = []
        for x in range(SIZE):
            gx, fx = divmod(x / step, 1)
            x0, x1 = int(gx) % cells, (int(gx) + 1) % cells
            sx = fx * fx * (3 - 2 * fx)
            top = grid[y0][x0] + (grid[y0][x1] - grid[y0][x0]) * sx
            bottom = grid[y1][x0] + (grid[y1][x1] - grid[y1][x0]) * sx
            row.append(top + (bottom - top) * sy)
        out.append(row)
    return out


def tones(noise: list[list[float]], cuts: list[float], levels: list[int]) -> Image.Image:
    """Quantise noise into flat tones: the toon look is a few hard-edged values, never a gradient."""
    img = Image.new("L", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            v = noise[y][x]
            px[x, y] = levels[sum(v > c for c in cuts)]
    return img


def wrap_line(draw: ImageDraw.ImageDraw, pts: list[tuple[float, float]], fill: int, width: int) -> None:
    """A polyline drawn nine times, shifted by the tile, so it wraps across the edges."""
    for ox in (-SIZE, 0, SIZE):
        for oy in (-SIZE, 0, SIZE):
            draw.line([(x + ox, y + oy) for x, y in pts], fill=fill, width=width)


def wrap_ellipse(draw: ImageDraw.ImageDraw, cx: float, cy: float, rx: float, ry: float, fill: int) -> None:
    for ox in (-SIZE, 0, SIZE):
        for oy in (-SIZE, 0, SIZE):
            draw.ellipse((cx - rx + ox, cy - ry + oy, cx + rx + ox, cy + ry + oy), fill=fill)


def asphalt(rng: random.Random) -> Image.Image:
    img = tones(value_noise(rng, 8), [0.38, 0.62], [214, 230, 245])
    draw = ImageDraw.Draw(img)
    for _ in range(420):  # aggregate: single light and dark chips
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        draw.point((x, y), fill=rng.choice((196, 255)))
    for _ in range(3):  # cracks
        x, y = rng.uniform(0, SIZE), rng.uniform(0, SIZE)
        a = rng.uniform(0, math.tau)
        pts = [(x, y)]
        for _ in range(rng.randint(5, 9)):
            a += rng.uniform(-0.7, 0.7)
            x, y = x + 9 * math.cos(a), y + 9 * math.sin(a)
            pts.append((x, y))
        wrap_line(draw, pts, 150, 2)
    return img


def gravel(rng: random.Random) -> Image.Image:
    img = tones(value_noise(rng, 4), [0.45], [220, 238])
    draw = ImageDraw.Draw(img)
    for _ in range(260):
        r = rng.uniform(2.0, 4.5)
        wrap_ellipse(
            draw, rng.uniform(0, SIZE), rng.uniform(0, SIZE), r, r * rng.uniform(0.6, 1.0), rng.choice((180, 200, 255))
        )
    return img


def concrete(rng: random.Random) -> Image.Image:
    img = Image.new("L", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    half = SIZE // 2  # 2 m slabs
    for i in range(2):
        for j in range(2):
            draw.rectangle(
                (i * half, j * half, (i + 1) * half - 1, (j + 1) * half - 1), fill=rng.choice((226, 236, 246, 252))
            )
    for _ in range(5):  # stains
        wrap_ellipse(draw, rng.uniform(0, SIZE), rng.uniform(0, SIZE), rng.uniform(6, 16), rng.uniform(5, 12), 214)
    for k in (0, half):
        draw.line((k, 0, k, SIZE), fill=150, width=3)
        draw.line((0, k, SIZE, k), fill=150, width=3)
    return img


def planks(rng: random.Random) -> Image.Image:
    img = Image.new("L", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    width = SIZE // 8  # 0.25 m boards, standing up
    for i in range(8):
        x0 = i * width
        draw.rectangle((x0, 0, x0 + width - 1, SIZE), fill=rng.choice((212, 226, 240, 252)))
        for _ in range(2):  # grain: one shade, long and straight
            gx = x0 + rng.randint(6, width - 6)
            g0 = rng.randint(0, SIZE)
            wrap_line(draw, [(gx, g0), (gx, g0 + rng.randint(40, 120))], 200, 1)
        joint = rng.randint(0, SIZE - 1)  # the board's butt joint, with a nail each side
        wrap_line(draw, [(x0, joint), (x0 + width, joint)], 120, 2)
        for ny in (joint - 6, joint + 6):
            for nx in (x0 + 7, x0 + width - 8):
                draw.rectangle((nx, ny % SIZE, nx + 1, ny % SIZE + 1), fill=110)
        draw.line((x0, 0, x0, SIZE), fill=100, width=3)
    return img


def corrugated(rng: random.Random) -> Image.Image:
    img = Image.new("L", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    period = 16  # 0.125 m ribs: a lit face, a shadowed face, a mid face
    for x0 in range(0, SIZE, period):
        draw.rectangle((x0, 0, x0 + 7, SIZE), fill=250)
        draw.rectangle((x0 + 8, 0, x0 + 11, SIZE), fill=196)
        draw.rectangle((x0 + 12, 0, x0 + 15, SIZE), fill=222)
    for _ in range(4):  # streaks below the fixings
        x = rng.randrange(0, SIZE, period)
        y = rng.randint(0, SIZE)
        wrap_line(draw, [(x + 3, y), (x + 3, y + rng.randint(30, 70))], 180, 4)
    draw.line((0, 0, SIZE, 0), fill=140, width=2)  # the sheet's lap, once a tile
    return img


def blocks(rng: random.Random) -> Image.Image:
    img = Image.new("L", (SIZE, SIZE), 170)
    draw = ImageDraw.Draw(img)
    bw, bh = 32, 16  # 0.4 x 0.2 m, running bond
    for row in range(SIZE // bh):
        shift = (bw // 2) * (row % 2)
        for col in range(-1, SIZE // bw + 1):
            x0 = col * bw + shift
            fill = rng.choice((228, 238, 246, 252))
            for ox in (-SIZE, 0, SIZE):
                draw.rectangle((x0 + ox + 2, row * bh + 2, x0 + ox + bw - 1, row * bh + bh - 1), fill=fill)
    return img


def checker(rng: random.Random) -> Image.Image:
    img = Image.new("L", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    t = SIZE // 4  # 0.5 m diner tiles
    for i in range(4):
        for j in range(4):
            draw.rectangle((i * t, j * t, (i + 1) * t - 1, (j + 1) * t - 1), fill=250 if (i + j) % 2 == 0 else 110)
    for k in range(0, SIZE, t):
        draw.line((k, 0, k, SIZE), fill=190, width=1)
        draw.line((0, k, SIZE, k), fill=190, width=1)
    return img


def shutter(rng: random.Random) -> Image.Image:
    img = Image.new("L", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    slat = 16  # 0.125 m roller-shutter slats
    for y0 in range(0, SIZE, slat):
        draw.rectangle((0, y0, SIZE, y0 + 11), fill=250)
        draw.rectangle((0, y0 + 12, SIZE, y0 + 13), fill=150)
        draw.rectangle((0, y0 + 14, SIZE, y0 + 15), fill=214)
    return img


def material(name: str, tex: str | None, tint: str, emission: str | None) -> str:
    def col(h: str) -> str:
        h = h.lstrip("#")
        r, g, b = (int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))
        return f"Color({r:.3f}, {g:.3f}, {b:.3f}, 1)"

    head = '[gd_resource type="StandardMaterial3D" format=3]\n\n'
    body = ["[resource]", f'resource_name = "{name}"']
    if tex:
        head = (
            f'[gd_resource type="StandardMaterial3D" load_steps=2 format=3]\n\n'
            f'[ext_resource type="Texture2D" path="{RES}/textures/{tex}.png" id="1"]\n\n'
        )
        body.append(f"albedo_color = {col(tint)}")
        body.append('albedo_texture = ExtResource("1")')
    else:
        body.append(f"albedo_color = {col(tint)}")
    body.append("roughness = 1.0")
    if emission:
        body.append("emission_enabled = true")
        body.append(f"emission = {col(emission)}")
    if tex:
        s = 1.0 / TILES[tex]
        body.append(f"uv1_scale = Vector3({s:g}, {s:g}, {s:g})")
        body.append("uv1_triplanar = true")
        body.append("uv1_triplanar_sharpness = 4.0")
        body.append("uv1_world_triplanar = true")
    return head + "\n".join(body) + "\n"


def main() -> None:
    (OUT / "textures").mkdir(parents=True, exist_ok=True)
    (OUT / "materials").mkdir(parents=True, exist_ok=True)
    makers = {
        "asphalt": asphalt, "gravel": gravel, "concrete": concrete, "planks": planks,
        "corrugated": corrugated, "blocks": blocks, "checker": checker, "shutter": shutter,
    }  # fmt: skip
    for i, (name, make) in enumerate(makers.items()):
        make(random.Random(1958 + i)).save(OUT / "textures" / f"{name}.png", optimize=True)
    for name, (tex, tint, emission) in MATERIALS.items():
        (OUT / "materials" / f"{name}.tres").write_text(
            material(name, tex, tint, emission), encoding="utf-8", newline="\n"
        )
    print(f"wrote {len(makers)} textures and {len(MATERIALS)} materials to {OUT}")


if __name__ == "__main__":
    main()
