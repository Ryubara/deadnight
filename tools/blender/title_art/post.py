"""Deadnight title art: every target image from the rendered masters and the Marquee wordmark.

Plain Python (no Blender):

    uv run --with pillow --with numpy python post.py --renders <dir> --wordmark <dir> --out <dir>

For each candidate (`<shot>_land.png` 16:9 and `<shot>_port.png` 2:3 masters in --renders) it writes one folder of
targets (sizes and safe areas: docs/design/branding.md), a check sheet per candidate and `contact_sheet.png`.
Video frames (`video_<shot>_<w>/f_####.png`) become `discord_video_<w>.mp4` with the title faded in at the end,
encoded with the pinned ffmpeg (`gds tool path ffmpeg`).
"""

import argparse
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
TEXT_FONT = ROOT / "game/assets/fonts/barlow_condensed/BarlowCondensed-SemiBold.ttf"

CANDIDATES = {  # name: (label, land focus x, port focus x)
    "feature": ("A  Feature presentation", 0.45, 0.5),
    "headlights": ("B  Into the headlights", 0.5, 0.5),
    "marquee": ("C  The way in", 0.5, 0.5),
    "headliner": ("D  The headliner", 0.5, 0.5),
    "backtoback": ("E  Back to back", 0.5, 0.5),
}

# Each target: file, size, master (land or port), focus y of the crop (0 top, 1 bottom), title lockup (None: no
# text), title width as a share of the image width, title top as a share of its height, how much to darken the
# whole image (ambient backgrounds), and a darkening behind the title.
T = dict
TARGETS = [
    # Discord Activity (sizes from the maintainer): the cover carries the title inside the centre 13:11 (the shelf
    # crops 16:9 to 13:11), the background carries none.
    T(file="discord/cover_1024x576.png", size=(1024, 576), src="land", fy=0.5, title="wide", tw=0.56, ty=0.07),
    T(file="discord/cover_1920x1080.png", size=(1920, 1080), src="land", fy=0.5, title="wide", tw=0.56, ty=0.07),
    T(file="discord/background_1024x576.png", size=(1024, 576), src="land", fy=0.5, title=None),
    T(file="discord/background_1920x1080.png", size=(1920, 1080), src="land", fy=0.5, title=None),
    # Boot splash and web loading image: the desktop crops to the window (cover), the web letterboxes, so the
    # title stays inside the centre 4:3.
    T(file="splash/splash_1920x1080.png", size=(1920, 1080), src="land", fy=0.5, title="wide", tw=0.58, ty=0.08),
    T(file="splash/keyart_3840x2160.png", size=(3840, 2160), src="land", fy=0.5, title="wide", tw=0.58, ty=0.08),
    # Steam store.
    T(file="steam/header_920x430.png", size=(920, 430), src="land", fy=0.42, title="wide", tw=0.72, ty=0.07),
    T(file="steam/small_462x174.png", size=(462, 174), src="land", fy=0.62, title="wide", tw=0.9, ty=0.07, dim=0.25),
    T(file="steam/main_1232x706.png", size=(1232, 706), src="land", fy=0.5, title="wide", tw=0.62, ty=0.07),
    T(file="steam/vertical_748x896.png", size=(748, 896), src="port", fy=0.55, title="stacked", tw=0.74, ty=0.05),
    T(file="steam/page_background_1438x810.png", size=(1438, 810), src="land", fy=0.5, title=None, dim=0.45),
    T(file="steam/event_cover_800x450.png", size=(800, 450), src="land", fy=0.5, title="wide", tw=0.66, ty=0.07),
    T(file="steam/event_header_1920x622.png", size=(1920, 622), src="land", fy=0.42, title="wide", tw=0.5, ty=0.08),
    # Steam library.
    T(file="steam/library_capsule_600x900.png", size=(600, 900), src="port", fy=0.5, title="stacked", tw=0.78, ty=0.05),
    T(file="steam/library_header_920x430.png", size=(920, 430), src="land", fy=0.42, title="wide", tw=0.72, ty=0.07),
    T(file="steam/library_hero_3840x1240.png", size=(3840, 1240), src="land", fy=0.62, title=None),
    # itch.io.
    T(file="itch/cover_630x500.png", size=(630, 500), src="land", fy=0.5, title="wide", tw=0.86, ty=0.06),
    T(file="itch/banner_960x300.png", size=(960, 300), src="land", fy=0.4, title="wide", tw=0.72, ty=None, dim=0.15),
    # Social.
    T(file="social/og_1200x630.png", size=(1200, 630), src="land", fy=0.5, title="wide", tw=0.62, ty=0.08),
    T(file="social/post_1600x900.png", size=(1600, 900), src="land", fy=0.5, title="wide", tw=0.6, ty=0.08),
]


# Per-candidate overrides of a target. The small capsule is too small for the whole scene under a full-width title:
# B crops tight on the car's headlamps and the Soldier on its roof (box: left, top, right as shares of the master,
# the height following the target's aspect) and sets the stacked title at the left, `th` of the height.
OVERRIDES = {
    "headlights": {
        "steam/small_462x174.png": {
            "box": (0.023, 0.355, 0.68),
            "title": "stacked",
            "th": 0.84,
            "tx": 0.035,
            "dim": 0.0,
        },
    },
}


def crop_box(img, size, box):
    w, h = img.size
    x0, y0, x1 = box
    cw = round((x1 - x0) * w)
    ch = round(cw * size[1] / size[0])
    top = min(max(round(y0 * h), 0), h - ch)
    return img.crop((round(x0 * w), top, round(x0 * w) + cw, top + ch)).resize(size, Image.LANCZOS)


def place_title_left(img, mark, th, tx):
    """The title at the left, `th` of the image height, centred vertically, over a scrim that fades out rightward."""
    w, h = img.size
    mh = round(h * th)
    m = mark.resize((round(mark.width * mh / mark.height), mh), Image.LANCZOS)
    x, y = round(w * tx), (h - mh) // 2
    xs = np.arange(w, dtype=np.float32)[None, :]
    fade = np.clip(1 - (xs - (x + m.width)) / max(w * 0.12, 1), 0, 1)
    a = np.asarray(img.convert("RGB"), dtype=np.float32) * (1 - 0.55 * fade[..., None])
    out = Image.fromarray(a.astype(np.uint8)).convert("RGBA")
    out.alpha_composite(m, (x, y))
    return out.convert("RGB"), (x, y, m.width, m.height)


def crop_to(img, size, fx, fy):
    """The largest rectangle of the target's aspect in `img`, centred on (fx, fy) as far as it fits, resized."""
    w, h = img.size
    tw, th = size
    a = tw / th
    if w / h > a:
        cw, ch = round(h * a), h
    else:
        cw, ch = w, round(w / a)
    x0 = min(max(round(fx * w - cw / 2), 0), w - cw)
    y0 = min(max(round(fy * h - ch / 2), 0), h - ch)
    return img.crop((x0, y0, x0 + cw, y0 + ch)).resize(size, Image.LANCZOS)


def darken(img, amount):
    a = np.asarray(img.convert("RGB"), dtype=np.float32) * (1 - amount)
    return Image.fromarray(a.astype(np.uint8))


def scrim(img, top, bottom, strength=0.55):
    """Darken the band behind the title, fading out below it (and a little above), so the title holds on any sky."""
    _w, h = img.size
    y = np.arange(h, dtype=np.float32)[:, None]
    fade = np.clip(1 - (y - bottom) / max(h * 0.18, 1), 0, 1) * np.clip((y - top + h * 0.15) / max(h * 0.15, 1), 0, 1)
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    a *= 1 - strength * fade[..., None]
    return Image.fromarray(a.astype(np.uint8))


def place_title(img, mark, tw, ty):
    w, h = img.size
    mw = round(w * tw)
    m = mark.resize((mw, round(mark.height * mw / mark.width)), Image.LANCZOS)
    x = (w - m.width) // 2
    y = (h - m.height) // 2 if ty is None else round(h * ty)
    out = scrim(img, y, y + m.height, 0.5 if ty is not None else 0.35).convert("RGBA")
    out.alpha_composite(m, (x, y))
    return out.convert("RGB"), (x, y, m.width, m.height)


def export_candidate(shot, renders, marks, out):
    land = Image.open(renders / f"{shot}_land.png").convert("RGB")
    port = Image.open(renders / f"{shot}_port.png").convert("RGB")
    _, lfx, pfx = CANDIDATES[shot]
    report = {}
    for t in TARGETS:
        src = land if t["src"] == "land" else port
        fx = lfx if t["src"] == "land" else pfx
        t = {**t, **OVERRIDES.get(shot, {}).get(t["file"], {})}
        img = crop_box(src, t["size"], t["box"]) if t.get("box") else crop_to(src, t["size"], fx, t["fy"])
        if t.get("dim"):
            img = darken(img, t["dim"])
        box = None
        if t["title"]:
            if t.get("th"):
                img, box = place_title_left(img, marks[t["title"]], t["th"], t["tx"])
            else:
                img, box = place_title(img, marks[t["title"]], t["tw"], t["ty"])
        p = out / shot / t["file"]
        p.parent.mkdir(parents=True, exist_ok=True)
        img.save(p, optimize=True)
        report[t["file"]] = {"size": list(img.size), "title_box": box, "bytes": p.stat().st_size}
    # The library logo: the wordmark alone on transparency, 1280 wide.
    logo = marks["wide"]
    lw = 1280
    logo = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)
    p = out / shot / "steam/library_logo_1280.png"
    logo.save(p, optimize=True)
    report["steam/library_logo_1280.png"] = {"size": list(logo.size), "bytes": p.stat().st_size}
    (out / shot / "targets.json").write_text(json.dumps(report, indent=1))
    return report


def label(img, text, size=34, fill=(244, 234, 210)):
    d = ImageDraw.Draw(img)
    d.text((0, 0), text, font=ImageFont.truetype(str(TEXT_FONT), size), fill=fill)


def contact_sheet(out, shots):
    """One row per candidate: the 16:9 key art with the title, the library capsule, and the small capsule, header
    and hero at their own sizes (or half)."""
    rows = []
    for shot in shots:
        d = out / shot
        key = Image.open(d / "splash/splash_1920x1080.png").resize((960, 540), Image.LANCZOS)
        cap = Image.open(d / "steam/library_capsule_600x900.png").resize((360, 540), Image.LANCZOS)
        small = Image.open(d / "steam/small_462x174.png")
        header = Image.open(d / "steam/header_920x430.png").resize((460, 215), Image.LANCZOS)
        hero = Image.open(d / "steam/library_hero_3840x1240.png").resize((462, 149), Image.LANCZOS)
        row = Image.new("RGB", (960 + 360 + 462 + 40, 540 + 50), (13, 11, 20))
        lab = Image.new("RGB", (row.width, 50), (13, 11, 20))
        label(lab, CANDIDATES[shot][0] + f"   ({shot})")
        row.paste(lab, (10, 6))
        row.paste(key, (10, 50))
        row.paste(cap, (980, 50))
        x = 1350
        row.paste(small, (x, 50))
        row.paste(header, (x, 50 + 174 + 1))
        row.paste(hero, (x, 50 + 174 + 215 + 2))
        rows.append(row)
    head = Image.new("RGB", (rows[0].width, 70), (13, 11, 20))
    label(
        head,
        "DEADNIGHT title art: pick one composition. Per row: key art / splash, library capsule 600x900, "
        "small capsule 462x174 (1:1), header 920x430 (half), library hero (no text)",
        26,
    )
    sheet = Image.new("RGB", (rows[0].width, 70 + sum(r.height for r in rows)), (13, 11, 20))
    sheet.paste(head, (10, 20))
    y = 70
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(out / "contact_sheet.png", optimize=True)


def video(frames_dir, mark, out_mp4, ffmpeg, max_bytes=None, fps=24, title_from=0.55):
    """Fade the wordmark in over the last part of the clip and encode H.264. With max_bytes the bitrate is chosen
    for the length and checked; a file over it is encoded again at a lower rate."""
    frames = sorted(frames_dir.glob("f_*.png"))
    tmp = frames_dir.parent / (frames_dir.name + "_titled")
    tmp.mkdir(exist_ok=True)
    n = len(frames)
    for i, f in enumerate(frames):
        img = Image.open(f).convert("RGB")
        t = i / max(n - 1, 1)
        k = float(np.clip((t - title_from) / 0.2, 0, 1))
        if k > 0:
            titled, _ = place_title(img, mark, 0.56, 0.07)
            img = Image.blend(img, titled, k)
        img.save(tmp / f"t_{i:04d}.png")
    seconds = n / fps
    rate = int((max_bytes * 8 * 0.92) / seconds / 1000) if max_bytes else None
    for _attempt in range(4):
        base = [
            ffmpeg,
            "-y",
            "-loglevel",
            "error",
            "-framerate",
            str(fps),
            "-i",
            str(tmp / "t_%04d.png"),
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-preset",
            "slow",
            "-movflags",
            "+faststart",
            "-an",
        ]
        if rate:
            log = str(tmp / "pass")
            subprocess.run(
                base + ["-b:v", f"{rate}k", "-pass", "1", "-passlogfile", log, "-f", "mp4", "NUL"], check=True
            )
            subprocess.run(base + ["-b:v", f"{rate}k", "-pass", "2", "-passlogfile", log, str(out_mp4)], check=True)
        else:
            subprocess.run(base + ["-crf", "20", str(out_mp4)], check=True)
        if not max_bytes or out_mp4.stat().st_size <= max_bytes:
            break
        rate = int(rate * 0.85)
    size = out_mp4.stat().st_size
    if (max_bytes and size > max_bytes) or seconds > 10:
        raise SystemExit(f"{out_mp4.name}: {size} bytes, {seconds:.2f} s; Discord takes at most {max_bytes} and 10 s")
    return size, seconds


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--renders", type=Path, required=True)
    ap.add_argument("--wordmark", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--shots", nargs="*", default=list(CANDIDATES))
    ap.add_argument("--ffmpeg")
    ap.add_argument("--video-only", action="store_true")
    ap.add_argument("--video-widths", type=int, nargs="*", default=[640, 1920])
    args = ap.parse_args()
    marks = {k: Image.open(args.wordmark / f"wordmark_marquee_{k}.png").convert("RGBA") for k in ("wide", "stacked")}
    shots = [s for s in args.shots if (args.renders / f"{s}_land.png").exists()]
    if not args.video_only:
        for s in shots:
            export_candidate(s, args.renders, marks, args.out)
            print(f"exported {s}")
        contact_sheet(args.out, shots)
        print(f"wrote {args.out / 'contact_sheet.png'}")
    if args.ffmpeg:
        for s in args.shots:
            for w in args.video_widths:
                # Discord's cap (0.5 MB) on both: the 1080p copy fits it too, and stays under the repository's
                # 512 KB limit for a file outside Git LFS.
                cap = 500_000
                fd = args.renders / f"video_{s}_{w}"
                if fd.exists():
                    p = args.out / s / "discord" / f"video_{w}x{w * 9 // 16}.mp4"
                    p.parent.mkdir(parents=True, exist_ok=True)
                    size, secs = video(fd, marks["wide"], p, args.ffmpeg, cap)
                    print(f"wrote {p} {size} bytes {secs:.2f} s")


if __name__ == "__main__":
    main()
