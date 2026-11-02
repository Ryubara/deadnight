"""Hip fire in the browser: it never zooms, and the aim's zoom lets go at once (issue #464).

Opens the web build (a folder, or the URL of a deployed one), starts a night, and drives the real mouse the way a
player does while the game records the camera's field of view every drawn frame (game/core/view_web_probe.gd):

1. hip fire: hold the trigger for 1.5 s, let go, wait 2.5 s. The field of view must not move from the hip's.
2. aim, shoot, let go of the aim: the field of view reaches the aim's, starts to go within `LEAVE_S` seconds of the
   release and is back at the hip's within `BLEND_S`, with no hold.
3. hip shot, then aim, then let go of the aim: likewise.
4. turn first (#477): the body faces away from the view, the trigger is tapped or held: no shot may leave until the
   body is within 10 degrees of the view (about 0.35 s for a half circle), and a tap makes exactly one shot.
5. aim, a tap of the trigger 0, 50 and 100 ms later, let go of the aim (#478): likewise, and the body's aim pose goes
   within `LEAVE_S` too (an aimed shot leaves no hip-fire hold).

    uv run --with playwright==1.64.1 python tools/web_smoke/hip_fire.py build/web build/hip-fire
    uv run --with playwright==1.64.1 python tools/web_smoke/hip_fire.py https://... build/hip-fire-live --gpu

Writes `result.json` (the numbers per scenario and the build's address) and screenshots (`hip_idle.png`,
`hip_fire_held.png`, `aim_held.png`) into the output folder. Exits 1 when a check fails. A build
without the probe (before #464) has no `viewRows` and the run says so.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from judder import play
from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright
from smoke import SOFTWARE_GL, SYNTHETIC_MOUSE_MOVE_JS, UNPACED, VIEWPORT, gl_info, probe, serve

# After the button is let go the view must start to move within LEAVE_S and be back at the hip's within BLEND_S. The
# aim's own spring settles in about 0.3 s (the unit tests hold it to 0.5 s); the rest is the browser's input and frame
# latency (the software renderer draws 10 to 15 frames a second). A hold left behind by a shot, as the hip-fire hold
# was before #433, is 0.8 s on top: the zoom would not start to go for that long, and it would be back after 1.1 s.
LEAVE_S = 0.4
BLEND_S = 0.9
# How far the field of view may differ from the hip's while nothing aims, in degrees.
HIP_TOLERANCE = 0.05
# How close to the aim's field of view the zoom must get while the button is held, and to the hip's after it.
ZOOM_TOLERANCE = 0.5
CENTER = (640, 360)
# The gaps between the aim button and a tap of the trigger that the maintainer's report (#478) is about.
QUICK_GAPS_MS = (0, 50, 100)


def clear_rows(page) -> None:
    page.evaluate("() => { const d = window.deadnight; d.viewRows.length = 0; d.viewRecord = true; }")


def stop_rows(page) -> list[list[float]]:
    flat = page.evaluate("() => { const d = window.deadnight; d.viewRecord = false; return d.viewRows.slice(); }")
    size = page.evaluate("() => window.deadnight.viewRow")
    return [flat[i : i + size] for i in range(0, len(flat) - size + 1, size)]


def row_count(page) -> int:
    return page.evaluate("() => window.deadnight.viewRows.length / window.deadnight.viewRow")


def hip_fire(page, out: Path) -> dict:
    clear_rows(page)
    page.wait_for_timeout(500)
    page.screenshot(path=out / "hip_idle.png")
    page.mouse.down()
    page.wait_for_timeout(750)
    page.screenshot(path=out / "hip_fire_held.png")
    page.wait_for_timeout(750)
    page.mouse.up()
    page.wait_for_timeout(2500)
    rows = stop_rows(page)
    fovs = [r[1] for r in rows]
    weights = [r[2] for r in rows]
    held = [r[3] for r in rows]
    return {
        "frames": len(rows),
        "fov_min": min(fovs, default=0.0),
        "fov_max": max(fovs, default=0.0),
        "aim_weight_max": max(weights, default=0.0),
        "body_held_seen": max(held, default=0.0) > 0.5,
        "ok": bool(rows) and max(fovs) - min(fovs) <= HIP_TOLERANCE and max(weights) < 0.001,
    }


def after_release(rows: list[list[float]], at: int, hip: float, aim: float) -> dict:
    """The zoom reached before the release and the seconds from the release until the view is back at the hip's."""
    before = rows[:at]
    after = rows[at:]
    zoomed = min((r[1] for r in before), default=hip)
    leaves = None
    back = None
    for r in after:
        seconds = (r[0] - after[0][0]) / 1000.0
        if leaves is None and r[1] > aim + ZOOM_TOLERANCE:
            leaves = seconds
        if abs(r[1] - hip) <= HIP_TOLERANCE * 2:
            back = seconds
            break
    # How long the body's aim pose (the hip-fire hold, 0.8 s after a shot from the hip) outlives the release.
    hold_left = None
    for r in after:
        if r[3] < 0.5:
            hold_left = (r[0] - after[0][0]) / 1000.0
            break
    return {
        "frames": len(rows),
        "fov_zoomed": zoomed,
        "fov_leaves_after_s": leaves,
        "fov_back_after_s": back,
        "pose_hold_left_after_s": hold_left,
        "ok": bool(before)
        and bool(after)
        and abs(zoomed - aim) <= ZOOM_TOLERANCE
        and leaves is not None
        and leaves <= LEAVE_S
        and back is not None
        and back <= BLEND_S,
    }


def aim_shoot_release(page, hip: float, aim: float, out: Path) -> dict:
    clear_rows(page)
    page.mouse.down(button="right")
    page.wait_for_timeout(1200)
    page.screenshot(path=out / "aim_held.png")
    page.mouse.down()
    page.wait_for_timeout(60)
    page.mouse.up()
    page.wait_for_timeout(100)
    at = row_count(page)
    page.mouse.up(button="right")
    page.wait_for_timeout(1500)
    return after_release(stop_rows(page), int(at), hip, aim)


def quick_aim_tap(page, hip: float, aim: float, gap_ms: int) -> dict:
    """#478: the aim button, a tap of the trigger `gap_ms` later, the button let go. The tap is an aimed shot (the
    button is down), so no hip-fire hold exists: the zoom and the pose both go with the button."""
    clear_rows(page)
    page.mouse.down(button="right")
    page.wait_for_timeout(gap_ms)
    page.mouse.down()
    page.wait_for_timeout(60)
    page.mouse.up()
    page.wait_for_timeout(1000)
    at = row_count(page)
    page.mouse.up(button="right")
    page.wait_for_timeout(1500)
    found = after_release(stop_rows(page), int(at), hip, aim)
    found["gap_ms"] = gap_ms
    left = found["pose_hold_left_after_s"]
    found["ok"] = found["ok"] and left is not None and left <= LEAVE_S
    return found


TURN_STEP_PX = 15
FACING_AWAY = 2.9  # radians between the body and the view: nearly a half circle


def turn_view_away(page) -> None:
    """Turns the view with the page's own mouse events until it is nearly 180 degrees from the body."""
    for _ in range(400):
        rows = page.evaluate("() => window.deadnight.viewRows.slice(-window.deadnight.viewRow)")
        if rows and rows[-1] >= FACING_AWAY:
            return
        page.evaluate(SYNTHETIC_MOUSE_MOVE_JS, TURN_STEP_PX)
        page.wait_for_timeout(20)


def shot_ready_times(rows: list[list[float]], after_ms: float) -> list[tuple[float, float]]:
    """(seconds after `after_ms`, the body's distance from the view in radians) for every frame a shot may leave."""
    return [((r[0] - after_ms) / 1000.0, r[6]) for r in rows if r[5] > 0.5 and r[0] >= after_ms]


def turn_first(page, out: Path, hold: bool) -> dict:
    """#477: the body faces away from the view; a press (a tap, or a held trigger) turns it and the shot waits."""
    clear_rows(page)
    turn_view_away(page)
    page.wait_for_timeout(300)
    start = page.evaluate("() => window.deadnight.viewRows.slice(-window.deadnight.viewRow)")
    away = start[6]
    pressed_at = page.evaluate("() => performance.now()")
    page.mouse.down()
    if hold:
        page.wait_for_timeout(150)
        page.screenshot(path=out / "turn_first_turning.png")
        page.wait_for_timeout(700)
        page.screenshot(path=out / "turn_first_firing.png")
        page.wait_for_timeout(300)
        page.mouse.up()
    else:
        page.wait_for_timeout(60)
        page.mouse.up()
        page.wait_for_timeout(1000)
    page.wait_for_timeout(500)
    rows = stop_rows(page)
    ready = shot_ready_times(rows, pressed_at)
    first = ready[0] if ready else None
    # The turn of that far at 8 rad/s, less the tolerance (10 degrees), with a frame or two of the browser's.
    wanted = (away - 0.1745) / 8.0
    return {
        "hold": hold,
        "view_error_at_press": away,
        "first_shot_ready_after_s": first[0] if first else None,
        "view_error_at_first_shot": first[1] if first else None,
        "ticks_ready": len(ready),
        "expected_wait_s": wanted,
        "ok": bool(ready)
        and away >= FACING_AWAY - 0.05
        and first[0] >= wanted - 0.1
        and first[1] <= 0.1745 + 0.02
        and (hold or len(ready) <= 3),
    }


def hip_aim_release(page, hip: float, aim: float) -> dict:
    clear_rows(page)
    page.mouse.down()
    page.wait_for_timeout(60)
    page.mouse.up()
    page.wait_for_timeout(200)
    page.mouse.down(button="right")
    page.wait_for_timeout(1200)
    at = row_count(page)
    page.mouse.up(button="right")
    page.wait_for_timeout(1500)
    return after_release(stop_rows(page), int(at), hip, aim)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="folder with the exported index.html, or the URL of a deployed build")
    parser.add_argument("out", type=Path)
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--unpaced", action="store_true")
    parser.add_argument("--hip-fov", type=float, default=60.0)
    parser.add_argument("--aim-fov", type=float, default=40.0)
    parser.add_argument("--label", default="")
    parser.add_argument(
        "--no-turn-first", action="store_true", help="skip #477 (a build older than it has no shot_ready column)"
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else serve(Path(args.build))
    url = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    result: dict = {"build": args.build, "label": args.label, "gpu": args.gpu, "blend_s": BLEND_S}
    ok = False
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True, args=UNPACED if args.unpaced else [])
        else:
            browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
        page = browser.new_page(viewport=VIEWPORT)
        try:
            play(page, url)
            result["gl"] = gl_info(page)
            if not page.evaluate("() => !!(window.deadnight && window.deadnight.viewRows)"):
                result["error"] = "this build has no view probe (it is older than #464)"
            else:
                page.mouse.move(*CENTER)
                page.wait_for_timeout(500)
                result["hip_fire"] = hip_fire(page, args.out)
                result["aim_shoot_release"] = aim_shoot_release(page, args.hip_fov, args.aim_fov, args.out)
                page.wait_for_timeout(1000)
                result["hip_aim_release"] = hip_aim_release(page, args.hip_fov, args.aim_fov)
                for gap in QUICK_GAPS_MS:
                    page.wait_for_timeout(1000)
                    result[f"quick_aim_tap_{gap}ms"] = quick_aim_tap(page, args.hip_fov, args.aim_fov, gap)
                for hold in () if args.no_turn_first else (False, True):
                    page.wait_for_timeout(1500)
                    result["turn_first_" + ("held" if hold else "tap")] = turn_first(page, args.out, hold)
                keys = ["hip_fire", "aim_shoot_release", "hip_aim_release"]
                keys += [] if args.no_turn_first else ["turn_first_tap", "turn_first_held"]
                keys += [f"quick_aim_tap_{g}ms" for g in QUICK_GAPS_MS]
                ok = all(result[k]["ok"] for k in keys)
            result["state"] = probe(page)
        except PlaywrightError as error:
            result["error"] = str(error)
        finally:
            browser.close()
            if server is not None:
                server.shutdown()
    result["ok"] = ok
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
