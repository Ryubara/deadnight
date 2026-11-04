"""The 55 level icons: a frame for the tier, a hand-placed drawing for the level, five bulbs for the level in its tier.

Writes one SVG per level (128 x 128: shapes and strokes, no `<text>`, which Godot's rasteriser does not draw) to
`game/assets/ui/levels/`. The drawings are original: each `g_*` function places its shapes by hand, nothing is traced
and nothing is generated from a recolour. Change a drawing here, run this, then run the atlas export (`game/tools/art/
export_level_icons.gd`); `tools/check_level_icons.py` fails when the three disagree. Docs: docs/research/progression.md,
"The icon pipeline".

Standard library only.

    python tools/level_icons/draw_icons.py
"""

from __future__ import annotations

import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "ui" / "levels"

INK = "#1c1730"
NIGHT = "#2c2542"
SHADE = "#3b3350"
CREAM = "#f4ebd3"
HOT = "#ff3d4c"
BRICK = "#b8322e"
SKY = "#3fb6d8"
BUTTER = "#f6c744"
AMBER = "#e8a33a"
GREY = "#8d93a0"
STEEL = "#c9ced8"
GREEN = "#6fa86b"
OLIVE = "#5c6d37"
WOOD = "#95703d"
PINK = "#ff8fb8"
BUN = "#e9b870"
GOLD = "#d9a21b"

# Outline in the 0..100 box a drawing lives in.
LINE = 4.5
THIN = 3.0

# Tier number -> (name, frame shape, plate colour, rim colour). Every shape's colours differ from each other at 24 px.
TIERS = {
    1: ("Doors Open", "ticket", "#f4ebd3", "#c9b98e"),
    2: ("Cartoon", "token", "#7fcbe6", "#3f8fb0"),
    3: ("Newsreel", "sign", "#d98255", "#9c4f2c"),
    4: ("Intermission", "ticket", "#c79a52", "#7a5726"),
    5: ("Trailers", "token", "#e1e8ef", "#98a5b4"),
    6: ("Second Feature", "sign", "#8294e6", "#4c5aa8"),
    7: ("Main Feature", "ticket", "#9ad36a", "#5a8f35"),
    8: ("Late Show", "token", "#a98be6", "#6a4bb0"),
    9: ("Midnight Show", "sign", "#43d6c0", "#15907f"),
    10: ("Headliner", "ticket", "#ff6fae", "#b0275f"),
    11: ("Last Reel", "token", "#f2333f", "#e0a92a"),
}

# Where a drawing's 100 x 100 box sits in each frame: centre x, centre y, scale.
FRAME_BOX = {"ticket": (67.0, 59.0, 0.8), "token": (64.0, 57.0, 0.8), "sign": (64.0, 57.0, 0.8)}


# ---- small drawing words ----
def _attrs(fill: str, stroke: str | None, width: float, extra: str) -> str:
    text = f'fill="{fill}"'
    if stroke:
        text += f' stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"'
    return f"{text} {extra}".rstrip()


def path(d: str, fill: str = "none", stroke: str | None = INK, width: float = LINE, extra: str = "") -> str:
    return f'<path d="{d}" {_attrs(fill, stroke, width, extra)}/>'


def line(d: str, stroke: str = INK, width: float = LINE) -> str:
    return path(d, "none", stroke, width)


def bar(d: str, colour: str, width: float = 7.0, edge: float = LINE) -> str:
    """A line with an outline of its own: the ink under it, wider."""
    return line(d, INK, width + edge * 2) + line(d, colour, width)


def circle(x: float, y: float, r: float, fill: str, stroke: str | None = INK, width: float = LINE) -> str:
    return f'<circle cx="{x:g}" cy="{y:g}" r="{r:g}" {_attrs(fill, stroke, width, "")}/>'


def oval(x: float, y: float, rx: float, ry: float, fill: str, stroke: str | None = INK, width: float = LINE) -> str:
    return f'<ellipse cx="{x:g}" cy="{y:g}" rx="{rx:g}" ry="{ry:g}" {_attrs(fill, stroke, width, "")}/>'


def box(
    x: float, y: float, w: float, h: float, fill: str, r: float = 0, stroke: str | None = INK, width: float = LINE
) -> str:
    round_corner = f' rx="{r:g}"' if r else ""
    return f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}"{round_corner} {_attrs(fill, stroke, width, "")}/>'


def poly(points: list[tuple[float, float]], fill: str, stroke: str | None = INK, width: float = LINE) -> str:
    text = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
    return f'<polygon points="{text}" {_attrs(fill, stroke, width, "")}/>'


def turned(angle: float, x: float, y: float, *parts: str) -> str:
    return f'<g transform="rotate({angle:g} {x:g} {y:g})">{"".join(parts)}</g>'


def moved(dx: float, dy: float, *parts: str) -> str:
    return f'<g transform="translate({dx:g} {dy:g})">{"".join(parts)}</g>'


def on_circle(x: float, y: float, r: float, degrees: float) -> tuple[float, float]:
    return x + r * math.cos(math.radians(degrees)), y + r * math.sin(math.radians(degrees))


def star_points(x: float, y: float, outer: float, inner: float, points: int = 5) -> list[tuple[float, float]]:
    step = 180.0 / points
    return [on_circle(x, y, outer if i % 2 == 0 else inner, -90.0 + i * step) for i in range(points * 2)]


def star(x: float, y: float, outer: float, fill: str, stroke: str | None = INK, width: float = THIN) -> str:
    return poly(star_points(x, y, outer, outer * 0.42), fill, stroke, width)


def sparkle(x: float, y: float, r: float, fill: str = CREAM) -> str:
    """A four-pointed glint."""
    return poly(star_points(x, y, r, r * 0.3, 4), fill, INK, 2.0)


# ---- Doors Open ----
def g_admission_stub() -> str:
    outline = "M8 28 H92 V42 A8 8 0 0 0 92 58 V72 H8 V58 A8 8 0 0 0 8 42 Z"
    return turned(
        -12,
        50,
        50,
        path(outline, HOT),
        path("M30 30 V70", "none", INK, 2.5, 'stroke-dasharray="3 5"'),
        box(40, 38, 38, 6, CREAM, 2, None),
        box(40, 52, 26, 6, CREAM, 2, None),
    )


def g_ticket_roll() -> str:
    strip = path("M36 44 L98 50 L90 60 L96 72 L92 80 L30 74 Z", HOT)
    holes = path("M60 49 L56 75", "none", CREAM, 3.0, 'stroke-dasharray="3 4"')
    holes += path("M78 51 L74 77", "none", CREAM, 3.0, 'stroke-dasharray="3 4"')
    roll = circle(34, 38, 32, BUTTER) + circle(34, 38, 21, "none", AMBER, 3.5) + circle(34, 38, 12, CREAM)
    return strip + holes + roll + circle(34, 38, 4.5, INK, None)


def g_tin_token() -> str:
    return (
        oval(50, 58, 40, 34, GREY)
        + box(10, 48, 80, 10, GREY, 0, None)
        + oval(50, 46, 40, 34, STEEL)
        + oval(50, 46, 29, 24, "none", GREY, 3.5)
        + poly(star_points(50, 46, 19, 8), HOT, INK, 3.0)
        + line("M26 26 Q34 19 44 18", CREAM, 3.5)
    )


def g_turnstile_arm() -> str:
    return (
        bar("M42 44 L58 72", GREY, 8)
        + bar("M42 44 L62 20", GREY, 8)
        + box(8, 30, 36, 64, STEEL, 5)
        + box(4, 88, 44, 9, SHADE, 3)
        + box(16, 38, 20, 12, NIGHT, 2, INK, 3)
        + path("M22 44 H30 M27 41 L30 44 L27 47", "none", GREEN, 2.6)
        + line("M17 62 H35 M17 72 H35", GREY, 3.2)
        + bar("M44 44 H96", HOT, 9)
        + circle(44, 44, 13, BUTTER)
        + circle(44, 44, 4.5, INK, None)
    )


def g_popcorn_box() -> str:
    puffs = "".join(
        circle(x, y, 11, CREAM, INK, 4)
        for x, y in ((24, 30), (42, 20), (60, 22), (77, 32), (34, 36), (52, 36), (68, 40))
    )
    shape = "M18 42 H82 L72 96 H28 Z"
    stripes = "".join(line(f"M{x} 44 L{x + dx} 94", CREAM, 8) for x, dx in ((30, 4), (50, 0), (70, -4)))
    return puffs + path(shape, HOT, None) + stripes + path(shape)


# ---- Cartoon ----
def g_whitewall_tyre() -> str:
    tread = [on_circle(50, 50, 46 if i % 2 == 0 else 42.5, i * 7.5) for i in range(48)]
    lugs = "".join(circle(*on_circle(50, 50, 11, a), 2.4, INK, None) for a in range(0, 360, 72))
    return (
        poly(tread, NIGHT)
        + circle(50, 50, 32, CREAM)
        + circle(50, 50, 20, GREY)
        + circle(50, 50, 6, STEEL, INK, 3)
        + lugs
    )


def g_hubcap() -> str:
    flutes = [on_circle(50, 50, 47 if i % 2 == 0 else 38, i * 15) for i in range(24)]
    fins = ""
    for degrees in range(0, 360, 45):
        ax, ay = on_circle(50, 50, 23, degrees + 22.5)
        bx, by = on_circle(50, 50, 36, degrees + 22.5)
        fins += line(f"M{ax:.1f} {ay:.1f} L{bx:.1f} {by:.1f}", INK, 4.0)
    wing = "M50 50 L10 34 Q6 50 10 66 Z M50 50 L90 34 Q94 50 90 66 Z"
    return poly(flutes, STEEL) + fins + path(wing, HOT, INK, 4) + circle(50, 50, 11, BUTTER, INK, 4)


def _fuzzy_square(x: float, y: float, side: float, tufts: int = 6) -> list[tuple[float, float]]:
    """A square with a tufted edge: each side is a run of small teeth."""
    half = side / 2.0
    edge = []
    for corner, (ax, ay, bx, by) in enumerate(((-1, -1, 1, -1), (1, -1, 1, 1), (1, 1, -1, 1), (-1, 1, -1, -1))):
        for i in range(tufts * 2):
            t = i / (tufts * 2)
            out = 2.6 if i % 2 else 0.0
            nx, ny = ((0, -1), (1, 0), (0, 1), (-1, 0))[corner]
            edge.append((x + half * (ax + (bx - ax) * t) + nx * out, y + half * (ay + (by - ay) * t) + ny * out))
    return edge


def g_fuzzy_dice() -> str:
    pips_a = "".join(circle(x, y, 4.4, CREAM, None) for x, y in ((24, 44), (34, 54), (44, 64)))
    pips_b = "".join(circle(x, y, 4.2, INK, None) for x, y in ((60, 58), (80, 58), (60, 78), (80, 78)))
    return (
        line("M34 34 L52 3 L70 44", INK, 3.5)
        + turned(-14, 34, 54, poly(_fuzzy_square(34, 54, 42), HOT), pips_a)
        + turned(12, 70, 68, poly(_fuzzy_square(70, 68, 40), CREAM), pips_b)
    )


def g_speaker_on_post() -> str:
    slots = "".join(line(f"M26 {y} H62", SHADE, 3.2) for y in (28, 35, 42, 49))
    return (
        box(44, 60, 13, 34, GREY)
        + oval(50.5, 94, 22, 4.5, SHADE)
        + path("M22 14 Q44 2 66 14", "none", INK, 5.5)
        + box(12, 14, 76, 48, STEEL, 10)
        + box(21, 22, 46, 33, CREAM, 5, INK, 3.5)
        + slots
        + circle(77, 30, 5.5, HOT, INK, 3)
        + circle(77, 46, 5.5, BUTTER, INK, 3)
        + path("M84 62 q10 6 2 12 q-10 6 -2 12 q6 6 -14 6", "none", INK, 3.5)
    )


def g_back_room_key() -> str:
    shaft = "M42 46 L86 90 M66 70 L78 58 M76 80 L88 68"
    return (
        bar(shaft, BUTTER, 8.5)
        + circle(30, 34, 24, BUTTER)
        + circle(30, 34, 9, INK, None)
        + line("M20 19 Q28 13 38 16", CREAM, 3.5)
    )


# ---- Newsreel ----
def g_paper_cup() -> str:
    cup = "M22 36 H78 L68 96 H32 Z"
    bands = path("M24.5 50 H75.5 L72.5 68 H27.5 Z", SKY, None)
    straw = bar("M54 30 L60 8 L82 3", CREAM, 6, 4)
    return (
        straw
        + path(cup, CREAM, None)
        + bands
        + path(cup)
        + box(16, 24, 68, 13, STEEL, 5)
        + line("M28 30 H42", CREAM, 3.0)
    )


def g_hot_dog() -> str:
    back = box(10, 28, 80, 30, BUN, 15)
    sausage = box(2, 36, 96, 22, BRICK, 11)
    mustard = line("M14 47 q7 -9 14 0 t14 0 t14 0 t14 0 t14 0", BUTTER, 5)
    front = path("M8 54 H92 Q92 76 72 76 H28 Q8 76 8 54 Z", "#f3cf94")
    return turned(-18, 50, 50, back, sausage, mustard, front)


def g_milkshake() -> str:
    glass = "M26 32 L34 68 Q38 76 45 76 V88 H33 V96 H67 V88 H55 V76 Q62 76 66 68 L74 32 Z"
    cream = "".join(circle(x, y, r, CREAM, INK, 4) for x, y, r in ((36, 26, 10), (64, 26, 10), (50, 18, 12)))
    return (
        bar("M62 30 L80 2", HOT, 5, 3.5)
        + cream
        + path(glass, PINK)
        + line("M30 40 H70", CREAM, 3.5)
        + line("M44 8 Q48 2 56 2", INK, 3.0)
        + circle(50, 10, 7, HOT, INK, 3.5)
    )


def g_candy_box() -> str:
    sweets = "".join(
        circle(x, y, 5.2, c, INK, 3)
        for x, y, c in ((34, 56, BUTTER), (50, 56, CREAM), (66, 56, HOT), (42, 70, SKY), (58, 70, BUTTER))
    )
    return turned(
        6,
        50,
        50,
        path("M14 30 L28 10 H72 L86 30 Z", BUTTER),
        box(14, 30, 72, 64, HOT),
        box(24, 44, 52, 38, NIGHT, 4, INK, 3.5),
        sweets,
        box(14, 30, 72, 7, CREAM),
    )


def g_film_reel() -> str:
    holes = "".join(circle(*on_circle(50, 50, 25, a), 10, INK, None) for a in range(0, 360, 60))
    return (
        path("M50 92 H98", "none", INK, 12)
        + path("M50 92 H96", "none", SHADE, 5)
        + circle(50, 50, 44, GREY, INK, 5)
        + holes
        + circle(50, 50, 8, CREAM, INK, 3.5)
    )


# ---- Intermission ----
def g_pennant() -> str:
    flag = "M20 14 L96 44 L20 74 Z"
    return turned(
        -6,
        50,
        50,
        box(8, 4, 12, 94, WOOD, 3),
        circle(14, 4, 5, BUTTER, INK, 3.5),
        path(flag, HOT),
        path("M20 14 L38 21 V67 L20 74 Z", CREAM),
        star(55, 44, 11, BUTTER),
    )


def g_flash_bulb() -> str:
    burst = poly([on_circle(50, 44, 48 if i % 2 == 0 else 28, i * 20) for i in range(18)], BUTTER)
    return turned(
        14,
        50,
        50,
        burst,
        circle(50, 40, 22, CREAM),
        path("M41 58 H59 V76 H41 Z", GREY),
        line("M41 64 H59 M41 70 H59", INK, 2.6),
        box(45, 76, 10, 9, SHADE, 2),
        line("M43 49 L50 34 L57 49", HOT, 3.5),
    )


def g_megaphone() -> str:
    return turned(
        -12,
        50,
        50,
        bar("M36 64 L40 92", SHADE, 8),
        path("M12 40 L66 12 V88 L12 60 Z", HOT),
        path("M30 31 V69 L12 60 V40 Z", CREAM),
        oval(66, 50, 9, 38, CREAM),
        box(3, 38, 11, 24, NIGHT, 3),
        line("M84 34 Q92 50 84 66", INK, 5),
    )


def g_directors_chair() -> str:
    return (
        bar("M22 92 L76 58", WOOD, 6)
        + bar("M78 92 L24 58", WOOD, 6)
        + bar("M14 94 H36", WOOD, 6)
        + bar("M64 94 H86", WOOD, 6)
        + bar("M18 12 V58", WOOD, 6)
        + bar("M82 12 V58", WOOD, 6)
        + box(10, 12, 80, 26, HOT, 2)
        + star(50, 25, 9, BUTTER)
        + box(12, 50, 76, 11, HOT, 2)
    )


def g_ushers_torch() -> str:
    return turned(
        -24,
        50,
        50,
        path("M16 42 L-14 26 V74 L16 58 Z", CREAM, None, 0, 'opacity=".85"'),
        path("M14 32 L50 34 V66 L14 68 Z", BUTTER),
        box(50, 37, 50, 26, GREY, 6),
        line("M64 44 H86 M64 50 H86 M64 56 H86", INK, 3.0),
        box(8, 28, 9, 44, STEEL, 3),
    )


# ---- Trailers ----
def g_marquee_letter() -> str:
    letter = "M12 8 H52 Q90 8 90 46 Q90 84 52 84 H12 Z M36 30 V62 H50 Q64 62 64 46 Q64 30 50 30 Z"
    bulbs = "".join(
        circle(x, y, 4.2, CREAM, INK, 2.2)
        for x, y in ((24, 20), (24, 46), (24, 72), (44, 19), (62, 22), (76, 34), (79, 50), (72, 64), (58, 73), (42, 73))
    )
    return (
        moved(5, 5, path(letter, HOT, INK, LINE, 'fill-rule="evenodd"'))
        + path(letter, BUTTER, INK, LINE, 'fill-rule="evenodd"')
        + bulbs
    )


def g_lobby_card() -> str:
    return turned(
        -7,
        50,
        50,
        box(8, 14, 84, 72, CREAM, 2),
        box(16, 22, 68, 40, "#2b3a67", 0, INK, 3.5),
        circle(66, 34, 8, BUTTER, None),
        path("M16 62 Q28 44 44 50 Q58 54 84 42 V62 Z", NIGHT, INK, 3.0),
        path("M34 52 V36 M34 42 L28 36 M34 42 L40 37", "none", INK, 3.5),
        box(16, 68, 42, 6, HOT, 2, None),
        box(16, 77, 26, 4, GREY, 2, None),
        circle(84, 74, 5, HOT, INK, 3),
    )


def g_poster_tube() -> str:
    roll = path("M94 50 m0 -7 a5 7 0 1 1 -4 12 a3 4 0 1 1 3 -6", "none", INK, 2.6)
    return turned(
        -42,
        50,
        50,
        box(-10, 30, 92, 40, AMBER, 3),
        box(6, 30, 12, 40, HOT, 0),
        box(58, 30, 12, 40, HOT, 0),
        box(-14, 27, 11, 46, NIGHT, 3),
        box(80, 34, 14, 32, CREAM, 2),
        oval(94, 50, 11, 16, CREAM),
        roll,
    )


def g_ticket_punch() -> str:
    ticket = turned(
        -8,
        50,
        18,
        path("M10 4 H90 V32 H10 Z", CREAM),
        poly(star_points(48, 18, 10, 4.2), INK, None),
        line("M72 6 V30", INK, 2.2),
    )
    grip_a = "M50 52 Q20 56 18 96"
    grip_b = "M50 52 Q80 56 82 96"
    jaws = path("M50 58 L32 44 V24 L42 24 V40 L50 46 L58 40 V24 L68 24 V44 Z", STEEL, INK, 4)
    return ticket + bar(grip_a, HOT, 9) + bar(grip_b, HOT, 9) + jaws + circle(50, 54, 7, BUTTER, INK, 3.5)


def g_clapper() -> str:
    stripes = "".join(
        poly([(18 + i * 18, 56), (28 + i * 18, 56), (36 + i * 18, 44), (26 + i * 18, 44)], CREAM, None)
        for i in range(4)
    )
    return (
        box(10, 44, 80, 50, NIGHT)
        + box(12, 44, 76, 12, INK, 0, None)
        + stripes
        + turned(
            -14,
            12,
            40,
            box(10, 26, 80, 14, CREAM),
            line("M24 27 L18 39 M42 27 L36 39 M60 27 L54 39 M78 27 L72 39", INK, 7),
        )
        + box(20, 64, 34, 6, CREAM, 2, None)
        + box(20, 76, 22, 6, CREAM, 2, None)
    )


# ---- Second Feature ----
def g_radio_mast() -> str:
    lattice = "M50 12 L24 96 M50 12 L76 96 M43 34 H57 M36 56 H64 M29 78 H71 M43 34 L64 56 M57 34 L36 56 M36 56 L71 78 M64 56 L29 78"
    waves = line("M26 8 Q18 18 26 30 M74 8 Q82 18 74 30", INK, 8) + line(
        "M26 8 Q18 18 26 30 M74 8 Q82 18 74 30", CREAM, 3.5
    )
    waves += line("M12 2 Q0 18 12 38 M88 2 Q100 18 88 38", INK, 8) + line(
        "M12 2 Q0 18 12 38 M88 2 Q100 18 88 38", CREAM, 3.5
    )
    return waves + line(lattice, INK, 8.5) + line(lattice, STEEL, 3.5) + circle(50, 12, 8, HOT)


def g_dish_aerial() -> str:
    dish = "M6 26 A52 52 0 0 0 76 84 Z"
    return (
        path("M36 62 L28 94 H62 L52 62 Z", GREY)
        + box(16, 90, 58, 7, SHADE, 2)
        + path(dish, STEEL)
        + path("M15 37 Q34 67 66 76", "none", GREY, 3)
        + line("M34 58 L66 28", INK, 5)
        + circle(68, 26, 7.5, HOT)
        + line("M78 12 Q90 20 90 34 M84 2 Q100 14 99 34", INK, 4.5)
    )


def g_walkie_talkie() -> str:
    slots = "".join(line(f"M34 {y} H62", INK, 3.4) for y in (46, 54, 62))
    return turned(
        9,
        50,
        50,
        bar("M38 26 V2", STEEL, 4, 3.5),
        box(56, 16, 12, 12, HOT, 2),
        box(26, 24, 48, 74, OLIVE, 7),
        box(18, 42, 9, 22, HOT, 2),
        box(32, 32, 30, 8, CREAM, 2, INK, 3),
        slots,
        circle(40, 80, 6, BUTTER, INK, 3.5),
        circle(60, 80, 6, SHADE, INK, 3.5),
    )


def g_flare() -> str:
    return turned(
        22,
        50,
        50,
        box(38, 46, 24, 52, HOT, 3),
        box(38, 58, 24, 9, CREAM),
        box(34, 42, 32, 8, SHADE, 2),
        path("M50 -2 Q72 18 66 34 Q62 42 50 42 Q38 42 34 34 Q28 18 50 -2 Z", AMBER),
        path("M50 14 Q60 24 57 33 Q55 38 50 38 Q45 38 43 33 Q40 24 50 14 Z", CREAM, INK, 3),
        circle(18, 22, 3.4, BUTTER, INK, 2.2),
        circle(82, 16, 3.4, BUTTER, INK, 2.2),
        circle(76, 44, 2.8, BUTTER, INK, 2.2),
    )


def g_marquee_arrow() -> str:
    bulbs = "".join(
        circle(x, y, 3.6, CREAM, None)
        for x, y in ((18, 50), (32, 50), (46, 50), (60, 50), (74, 50), (62, 28), (62, 72), (74, 38), (74, 62))
    )
    return path("M4 34 H54 V12 L96 50 L54 88 V66 H4 Z", HOT, INK, 5) + bulbs


# ---- Main Feature ----
def g_rocket() -> str:
    body = "M50 2 Q74 26 72 60 L64 78 H36 L28 60 Q26 26 50 2 Z"
    return turned(
        42,
        50,
        50,
        path("M38 76 L50 100 L62 76 Z", BUTTER),
        path("M28 52 L8 86 L36 76 Z", HOT),
        path("M72 52 L92 86 L64 76 Z", HOT),
        path(body, CREAM),
        path("M50 2 Q62 14 67 28 H33 Q38 14 50 2 Z", HOT),
        circle(50, 46, 10, SKY),
    )


def g_ray_gun() -> str:
    return turned(
        -10,
        50,
        50,
        path("M30 58 L20 92 H40 L50 58 Z", NIGHT),
        path("M24 30 H62 L88 42 L62 56 H24 Z", STEEL),
        box(46, 24, 7, 38, HOT, 2, INK, 3.5),
        box(58, 26, 7, 34, HOT, 2, INK, 3.5),
        circle(24, 43, 15, SKY),
        circle(92, 42, 7, BUTTER),
        line("M18 37 Q22 33 28 34", CREAM, 3.2),
    )


def g_robot_head() -> str:
    slits = "".join(line(f"M{x} 72 V82", CREAM, 3) for x in (38, 46, 54, 62))
    return (
        bar("M50 26 V10", GREY, 4, 3.5)
        + circle(50, 8, 7, HOT)
        + box(4, 46, 14, 28, GREY, 3)
        + box(82, 46, 14, 28, GREY, 3)
        + box(14, 26, 72, 68, STEEL, 9)
        + circle(34, 50, 12, BUTTER)
        + circle(66, 50, 12, BUTTER)
        + circle(34, 50, 4.5, INK, None)
        + circle(66, 50, 4.5, INK, None)
        + box(30, 70, 40, 14, NIGHT, 2, INK, 3.5)
        + slits
    )


def g_space_helmet() -> str:
    return (
        bar("M84 22 L94 4", GREY, 4, 3.5)
        + circle(50, 44, 42, "#a6e4f5", INK, 5)
        + path("M86 30 A40 40 0 0 1 20 74 Q60 78 86 30 Z", SKY, None)
        + circle(50, 44, 42, "none", INK, 5)
        + line("M22 32 Q32 14 52 11", CREAM, 6)
        + circle(26, 46, 3.6, CREAM, None)
        + box(14, 76, 72, 20, HOT, 5)
        + circle(32, 86, 4, BUTTER, INK, 2.2)
        + circle(50, 86, 4, BUTTER, INK, 2.2)
        + circle(68, 86, 4, BUTTER, INK, 2.2)
    )


def g_flying_saucer() -> str:
    return (
        path("M34 60 L12 100 H88 L66 60 Z", BUTTER, None, 0, 'opacity=".75"')
        + path("M28 42 Q50 -2 72 42 Z", SKY)
        + line("M36 30 Q40 20 50 17", CREAM, 3.8)
        + oval(50, 48, 49, 16, GREY, INK, 5)
        + "".join(circle(x, 50, 4.2, BUTTER, None) for x in (18, 34, 50, 66, 82))
    )


# ---- Late Show ----
def g_skull() -> str:
    head = "M50 6 C20 6 8 28 12 50 C14 60 22 66 28 68 V84 Q28 94 38 94 H62 Q72 94 72 84 V68 C78 66 86 60 88 50 C92 28 80 6 50 6 Z"
    return (
        path(head, CREAM, INK, 5)
        + oval(32, 46, 12.5, 14, NIGHT, None)
        + oval(68, 46, 12.5, 14, NIGHT, None)
        + path("M50 58 L42 70 H58 Z", NIGHT, None)
        + line("M42 80 V92 M50 80 V92 M58 80 V92", INK, 3.5)
    )


def g_bat() -> str:
    wings = (
        "M50 26 L43 28 L38 12 L33 34 Q18 34 1 16 Q2 42 10 60 Q20 48 29 62 Q37 52 44 72 L50 86 "
        "L56 72 Q63 52 71 62 Q80 48 90 60 Q98 42 99 16 Q82 34 67 34 L62 12 L57 28 Z"
    )
    return (
        path(wings, NIGHT, INK, 3.5)
        + oval(50, 48, 11, 16, SHADE, None)
        + circle(44, 40, 3.8, HOT, None)
        + circle(56, 40, 3.8, HOT, None)
        + path("M44 50 L46 57 L48 50 Z M52 50 L54 57 L56 50 Z", CREAM, None)
    )


def g_spider_web() -> str:
    spokes = ""
    for degrees in range(0, 360, 45):
        x, y = on_circle(50, 46, 44, degrees)
        spokes += f"M50 46 L{x:.1f} {y:.1f} "
    rings = ""
    for r in (15, 29, 44):
        for a in range(0, 360, 45):
            x0, y0 = on_circle(50, 46, r, a)
            x1, y1 = on_circle(50, 46, r, a + 45)
            mx, my = on_circle(50, 46, r * 0.76, a + 22.5)
            rings += f"M{x0:.1f} {y0:.1f} Q{mx:.1f} {my:.1f} {x1:.1f} {y1:.1f} "
    legs = "M62 72 L50 64 M62 76 L46 76 M62 80 L50 90 M82 72 L94 64 M82 76 L98 76 M82 80 L94 90"
    return (
        circle(50, 46, 47, NIGHT, INK, 4)
        + line(spokes + rings, CREAM, 3.8)
        + line(legs, INK, 6.5)
        + line(legs, HOT, 2.6)
        + oval(72, 77, 13, 11, HOT, INK, 3.5)
        + circle(72, 64, 6.5, HOT, INK, 3.5)
    )


def g_tombstone() -> str:
    return turned(
        4,
        50,
        50,
        path("M20 92 V38 Q20 6 50 6 Q80 6 80 38 V92 Z", GREY, INK, 5),
        box(44, 24, 12, 38, CREAM, 1, INK, 3),
        box(34, 34, 32, 12, CREAM, 1, INK, 3),
        line("M70 58 L62 66 L68 72 L60 82", INK, 2.8),
    ) + path("M2 96 Q18 80 34 86 Q50 74 68 86 Q84 80 98 96 Z", GREEN)


def g_rubber_monster() -> str:
    teeth = "".join(path(f"M{x} 74 l5 10 l5 -10 Z", CREAM, INK, 2.4) for x in (30, 40, 50, 60))
    return (
        line("M34 28 Q30 10 20 6 M66 28 Q70 10 80 6", INK, 5)
        + circle(20, 7, 6, HOT, INK, 3.2)
        + circle(80, 7, 6, HOT, INK, 3.2)
        + path("M8 58 Q8 20 50 20 Q92 20 92 58 Q92 96 50 96 Q8 96 8 58 Z", GREEN, INK, 5)
        + circle(50, 48, 18, CREAM, INK, 4)
        + circle(54, 48, 9, HOT, None)
        + circle(54, 48, 4, INK, None)
        + path("M24 73 Q50 94 76 73 Z", INK, INK, 3)
        + teeth
    )


# ---- Midnight Show ----
def g_crescent_moon() -> str:
    moon = "M60 4 A47 47 0 1 0 96 66 A38 38 0 1 1 60 4 Z"
    return path(moon, BUTTER, INK, 5) + star(70, 34, 15, CREAM) + star(88, 14, 7, CREAM, INK, 2.5)


def g_hurricane_lamp() -> str:
    return (
        path("M22 84 Q2 40 50 4 Q98 40 78 84", "none", INK, 5.5)
        + path("M38 30 Q16 54 36 80 H64 Q84 54 62 30 Z", CREAM, INK, LINE)
        + path("M50 42 Q62 56 58 66 Q55 72 50 72 Q45 72 42 66 Q38 56 50 42 Z", AMBER, INK, 3.2)
        + box(32, 22, 36, 10, HOT, 2)
        + path("M26 80 H74 L82 97 H18 Z", HOT)
        + line("M30 88 H70", CREAM, 3.2)
    )


def g_fog_light() -> str:
    return (
        path("M50 28 L102 44 V88 L50 68 Z", CREAM, None, 0, 'opacity=".8"')
        + line("M68 54 q7 -6 14 0 t14 0 M60 66 q7 -6 14 0 t14 0 M72 78 q6 -5 12 0 t12 0", INK, 3.4)
        + box(20, 84, 28, 10, SHADE, 2)
        + box(30, 74, 8, 12, GREY, 0, INK, 3.5)
        + circle(34, 48, 32, STEEL, INK, 5)
        + circle(34, 48, 23, BUTTER, INK, 3.5)
        + line("M18 38 H50 M14 48 H54 M18 58 H50", AMBER, 3)
        + line("M23 33 Q28 28 35 28", CREAM, 3.4)
    )


def g_lightning_bolt() -> str:
    bolt = "M60 2 L18 56 H44 L32 98 L84 38 H56 L72 2 Z"
    return moved(6, 2, path(bolt, HOT, INK, 5)) + moved(-2, 0, path(bolt, BUTTER, INK, 5))


def g_projector() -> str:
    return (
        path("M78 50 L100 34 V84 L78 68 Z", CREAM, INK, 3.5)
        + circle(24, 26, 19, GREY)
        + circle(24, 26, 5.5, INK, None)
        + circle(54, 22, 15, GREY)
        + circle(54, 22, 4.5, INK, None)
        + box(8, 44, 62, 34, NIGHT, 5)
        + box(16, 52, 24, 7, CREAM, 2, None)
        + box(16, 63, 14, 5, HOT, 2, None)
        + path("M68 50 L84 44 V74 L68 68 Z", BUTTER, INK, 4)
        + bar("M24 78 V94", GREY, 5, 4)
        + bar("M56 78 V94", GREY, 5, 4)
    )


# ---- Headliner ----
def g_spotlight() -> str:
    return (
        oval(54, 88, 40, 8, BUTTER)
        + path("M46 46 L22 88 H84 L68 40 Z", CREAM, None, 0, 'opacity=".85"')
        + turned(
            16,
            50,
            32,
            bar("M28 34 V16 H72 V34", GREY, 5, 3.5),
            box(30, 14, 40, 40, GREY, 5),
            line("M42 20 V38 M50 20 V38 M58 20 V38", INK, 3),
            box(24, 46, 52, 11, BUTTER, 3),
        )
        + box(10, 0, 80, 8, NIGHT, 2)
        + line("M50 7 V14", INK, 7)
    )


def g_big_star() -> str:
    points = star_points(50, 52, 50, 21)
    return (
        moved(4, 3, poly(points, HOT, INK, 5))
        + poly(points, BUTTER, INK, 5)
        + line("M42 30 L50 12", CREAM, 4.2)
        + sparkle(88, 16, 9)
        + sparkle(12, 84, 7)
    )


def g_trophy() -> str:
    handles = "M26 22 H8 Q6 50 30 54 M74 22 H92 Q94 50 70 54"
    return (
        bar(handles, AMBER, 5, 3.5)
        + path("M24 8 H76 V36 Q76 66 50 66 Q24 66 24 36 Z", BUTTER, INK, 5)
        + line("M34 14 V38", CREAM, 4.5)
        + star(52, 32, 13, HOT)
        + box(43, 64, 14, 16, AMBER)
        + box(26, 78, 48, 16, NIGHT, 3)
        + box(36, 84, 28, 4, BUTTER, 1, None)
    )


def g_curtain() -> str:
    left = "M6 16 H51 Q50 46 28 58 Q34 78 22 96 H6 Z"
    right = "M94 16 H49 Q50 46 72 58 Q66 78 78 96 H94 Z"
    fringe = "".join(path(f"M{x} 22 l5 9 l5 -9 Z", BUTTER, INK, 2.4) for x in range(10, 90, 10))
    return (
        box(8, 14, 84, 82, NIGHT, 0, None)
        + path(left, HOT)
        + path(right, HOT)
        + line("M16 34 Q20 48 14 94 M28 32 Q30 44 22 54 M84 34 Q80 48 86 94 M72 32 Q70 44 78 54", BRICK, 3.2)
        + box(19, 52, 15, 10, BUTTER, 2, INK, 3)
        + box(66, 52, 15, 10, BUTTER, 2, INK, 3)
        + box(2, 6, 96, 16, BRICK, 2)
        + fringe
    )


def g_searchlight() -> str:
    return (
        path("M48 38 L16 0 H46 L70 24 Z", CREAM, None, 0, 'opacity=".85"')
        + path("M36 96 L56 62 L76 96 Z", HOT)
        + turned(
            -42,
            58,
            54,
            box(40, 26, 42, 54, GREY, 5),
            line("M54 34 V72 M66 34 V72", INK, 3),
            oval(40, 53, 12, 34, BUTTER),
            line("M40 22 V84 M30 53 H50", AMBER, 3),
            oval(40, 53, 12, 34, "none"),
        )
        + circle(60, 60, 6, BUTTER, INK, 3)
        + box(18, 90, 72, 8, NIGHT, 3)
        + circle(30, 96, 6, SHADE, INK, 3.5)
        + circle(78, 96, 6, SHADE, INK, 3.5)
    )


# ---- Last Reel ----
def g_gold_bulb() -> str:
    glass = "M50 6 C24 6 14 26 18 42 C22 54 34 58 36 72 H64 C66 58 78 54 82 42 C86 26 76 6 50 6 Z"
    return (
        path(glass, BUTTER, INK, 5)
        + box(36, 72, 28, 18, STEEL, 2)
        + line("M36 78 H64 M36 84 H64", INK, 2.8)
        + box(44, 90, 12, 7, NIGHT, 2)
        + line("M42 72 L38 46 Q44 38 50 46 Q56 38 62 46 L58 72", AMBER, 7)
        + line("M42 72 L38 46 Q44 38 50 46 Q56 38 62 46 L58 72", INK, 2.8)
        + line("M30 20 Q36 13 46 13", CREAM, 4.5)
    )


def g_film_strip() -> str:
    frames = "".join(box(x, 34, 22, 32, c, 2, INK, 2.8) for x, c in ((2, SKY), (28, BUTTER), (54, HOT), (80, CREAM)))
    holes = "".join(box(x, y, 6, 6, CREAM, 1, None) for x in range(-8, 112, 13) for y in (24, 70))
    return turned(-32, 50, 50, box(-12, 18, 124, 64, NIGHT, 0, INK, 5), frames, holes)


def g_laurel() -> str:
    leaves = ""
    for side in (-1, 1):
        for i in range(7):
            degrees = 90 + side * (24 + i * 23)
            x, y = on_circle(50, 48, 37, degrees)
            leaves += f'<g transform="rotate({degrees + side * 112:g} {x:.1f} {y:.1f})">'
            leaves += path(f"M{x - 14:.1f} {y:.1f} q14 -12 28 0 q-14 12 -28 0 Z", BUTTER, INK, 3.2)
            leaves += "</g>"
    return (
        line("M50 88 A40 40 0 0 1 16 30 M50 88 A40 40 0 0 0 84 30", INK, 3.6)
        + leaves
        + star(50, 46, 20, CREAM)
        + path("M38 84 L50 90 L62 84 L64 97 L50 93 L36 97 Z", CREAM, INK, 3.5)
    )


def g_golden_ticket() -> str:
    shape = "M2 24 H98 V40 A10 10 0 0 0 98 60 V76 H2 V60 A10 10 0 0 0 2 40 Z"
    return (
        turned(
            -14,
            50,
            50,
            path(shape, BUTTER, INK, 5),
            path("M12 33 H88 V67 H12 Z", "none", GOLD, 3),
            star(50, 50, 17, HOT),
            line("M22 42 V58 M78 42 V58", GOLD, 5),
        )
        + sparkle(90, 14, 10)
        + sparkle(12, 88, 8)
    )


def g_the_last_reel() -> str:
    teeth = "".join(circle(*on_circle(50, 50, 37, a), 4.2, BUTTER, None) for a in range(0, 360, 30))
    return (
        circle(50, 50, 47, NIGHT, BUTTER, 6)
        + circle(50, 50, 47.5 + 3, "none", INK, 2.5)
        + teeth
        + poly(star_points(50, 50, 28, 12), BUTTER, CREAM, 3)
    )


# Level -> (working name, drawing). The names are the ladder's (docs/design/progression.md).
GLYPHS = {
    1: ("Admission stub", g_admission_stub),
    2: ("Ticket roll", g_ticket_roll),
    3: ("Tin token", g_tin_token),
    4: ("Turnstile arm", g_turnstile_arm),
    5: ("Popcorn box", g_popcorn_box),
    6: ("Whitewall tyre", g_whitewall_tyre),
    7: ("Hubcap", g_hubcap),
    8: ("Fuzzy dice", g_fuzzy_dice),
    9: ("Speaker on its post", g_speaker_on_post),
    10: ("Back-room key", g_back_room_key),
    11: ("Paper cup and straw", g_paper_cup),
    12: ("Hot dog", g_hot_dog),
    13: ("Milkshake", g_milkshake),
    14: ("Candy box", g_candy_box),
    15: ("Film reel", g_film_reel),
    16: ("Pennant", g_pennant),
    17: ("Flash bulb", g_flash_bulb),
    18: ("Megaphone", g_megaphone),
    19: ("Director's chair", g_directors_chair),
    20: ("Usher's torch", g_ushers_torch),
    21: ("Marquee letter", g_marquee_letter),
    22: ("Lobby card", g_lobby_card),
    23: ("Poster tube", g_poster_tube),
    24: ("Ticket punch", g_ticket_punch),
    25: ("Clapper", g_clapper),
    26: ("Radio mast", g_radio_mast),
    27: ("Dish aerial", g_dish_aerial),
    28: ("Walkie-talkie", g_walkie_talkie),
    29: ("Flare", g_flare),
    30: ("Marquee arrow", g_marquee_arrow),
    31: ("Rocket", g_rocket),
    32: ("Ray gun", g_ray_gun),
    33: ("Robot head", g_robot_head),
    34: ("Space helmet", g_space_helmet),
    35: ("Flying saucer", g_flying_saucer),
    36: ("Skull", g_skull),
    37: ("Bat", g_bat),
    38: ("Spider web", g_spider_web),
    39: ("Tombstone", g_tombstone),
    40: ("Rubber monster", g_rubber_monster),
    41: ("Crescent moon", g_crescent_moon),
    42: ("Hurricane lamp", g_hurricane_lamp),
    43: ("Fog light", g_fog_light),
    44: ("Lightning bolt", g_lightning_bolt),
    45: ("Projector", g_projector),
    46: ("Spotlight", g_spotlight),
    47: ("Star", g_big_star),
    48: ("Trophy", g_trophy),
    49: ("Curtain", g_curtain),
    50: ("Searchlight", g_searchlight),
    51: ("Gold bulb", g_gold_bulb),
    52: ("Film strip", g_film_strip),
    53: ("Laurel", g_laurel),
    54: ("Golden ticket", g_golden_ticket),
    55: ("The last reel", g_the_last_reel),
}


# ---- frames ----
def frame_ticket(plate: str, rim: str) -> str:
    outer = "M4 14 H124 V47 A12 12 0 0 0 124 71 V104 H4 V71 A12 12 0 0 0 4 47 Z"
    inner = "M9 19 H119 V43 A16 16 0 0 0 119 75 V99 H9 V75 A16 16 0 0 0 9 43 Z"
    perforation = f'<path d="M27 23 V95" fill="none" stroke="{rim}" stroke-width="2.5" stroke-dasharray="4 5"/>'
    return path(outer, rim, INK, 3) + path(inner, plate, None) + perforation


def frame_token(plate: str, rim: str) -> str:
    teeth = []
    for i in range(32):
        degrees = i * 11.25
        r = 55 if i % 2 == 0 else 50.5
        teeth += [on_circle(64, 57, r, degrees - 3.2), on_circle(64, 57, r, degrees + 3.2)]
    return poly(teeth, rim, INK, 3) + circle(64, 57, 46, plate, None) + circle(64, 57, 42, "none", rim, 1.8)


def frame_sign(plate: str, rim: str) -> str:
    outer = "M9 3 H119 V68 Q119 92 64 113 Q9 92 9 68 Z"
    inner = "M14 15 H114 V67 Q114 88 64 107 Q14 88 14 67 Z"
    bulbs = "".join(circle(x, 9, 2.8, CREAM, None) for x in (24, 40, 56, 72, 88, 104))
    return path(outer, rim, INK, 3) + path(inner, plate, None) + bulbs


FRAMES = {"ticket": frame_ticket, "token": frame_token, "sign": frame_sign}


def tier_of(level: int) -> int:
    return (level - 1) // 5 + 1


def bulbs(lit: int) -> str:
    """Five bulbs under the frame, `lit` of them on: the level inside its tier."""
    text = ""
    for i in range(5):
        text += circle(34 + i * 15, 120, 5.2, BUTTER if i < lit else SHADE, INK, 2.0)
    return text


def icon_svg(level: int) -> str:
    tier_name, shape, plate, rim = TIERS[tier_of(level)]
    name, draw = GLYPHS[level]
    x, y, scale = FRAME_BOX[shape]
    placed = f"translate({x - 50 * scale:g} {y - 50 * scale:g}) scale({scale:g})"
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">\n'
        f"<title>{name}</title>\n"
        f"<desc>{tier_name}</desc>\n"
        f'<g id="frame">{FRAMES[shape](plate, rim)}</g>\n'
        f'<g id="glyph" transform="{placed}">{draw()}</g>\n'
        f'<g id="bulbs">{bulbs((level - 1) % 5 + 1)}</g>\n'
        "</svg>\n"
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for level in GLYPHS:
        (OUT / f"level_{level:02d}.svg").write_text(icon_svg(level), encoding="utf-8", newline="\n")
    print(f"wrote {len(GLYPHS)} icons to {OUT}")


if __name__ == "__main__":
    main()
