"""A page that asks for the probes must not play the helicopter drop in a bench either (#1323).

`arrival_web.py --unasked` opens a night through the menu (`Main`, which adds the `WebProbe` node before any night). The
benches (`touch_assist.py`, `touch_melee.py`, ...) skip `Main`: they push the night screen on the router themselves, so
the first thing to read `WebProbe.asked()` is `NightScreen`'s static initialiser. This probe opens a night that way, on
a page served with the probes asked for (`smoke.serve`), and reads `window.__arrival`
(`game/tests/captures/arrival_bench.gd`):

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/arrival_bench.py <godot> <work folder> [--out <folder>]

`<godot>` is the pinned Godot (`gds tool path godot`); the copy of the project and its export are made in
`<work folder>`. It fails when the page was not asked for the probes, when `NightScreen.arrival_enabled` is true at the
start, when the night was opened with the drop on, or when the show was seen playing. Exits 1 on any of them.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke
import touch_assist

BENCH_SCENE = "res://tests/captures/arrival_bench.tscn"
READY_TIMEOUT_S = 240
IGNORED = ("A user gesture is required to request Pointer Lock",)


def state(page) -> dict:
    return page.evaluate("window.__arrival || {}") or {}


def verdict(seen: dict, errors: list[str]) -> list[str]:
    """What is wrong with a run, in words; empty when the page asked for the probes and the show never played."""
    wrong = []
    if not seen.get("probe_flag"):
        wrong.append("the page was not served with the probes asked for (window.deadnight_probe is not true)")
    if not seen.get("asked_at_start"):
        wrong.append("WebProbe.asked() read false on a page that asked for the probes")
    if seen.get("enabled_at_start"):
        wrong.append("NightScreen.arrival_enabled was true when the bench began")
    if seen.get("night_arrival"):
        wrong.append("the night was opened with the drop on (Night.arrival)")
    if seen.get("arriving_when_ready") or seen.get("arriving_seen"):
        wrong.append("the show played (Night.is_arriving() was true)")
    return wrong + [f"console error: {e}" for e in errors]


def run(url: str, out: Path | None, phone: bool = False) -> tuple[dict, list[str]]:
    """Opens the page; `phone` is how the touch benches open it: this machine's Chrome, a touch phone's viewport."""
    errors: list[str] = []
    with sync_playwright() as p:
        if phone:
            browser = p.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
            page = browser.new_context(
                viewport={"width": 844, "height": 390}, has_touch=True, is_mobile=True
            ).new_page()
        else:
            browser = p.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
            page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.on(
            "console",
            lambda m: errors.append(m.text) if m.type == "error" and not any(i in m.text for i in IGNORED) else None,
        )
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + READY_TIMEOUT_S
        while time.monotonic() < deadline and not state(page).get("done"):
            if out is not None and state(page).get("night_arrival") is not None and not (out / "night.png").exists():
                out.mkdir(parents=True, exist_ok=True)
                page.screenshot(path=out / "night.png")
            time.sleep(0.5)
        seen = state(page)
        if out is not None:
            out.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=out / "end.png")
        browser.close()
    if not seen.get("done"):
        raise TimeoutError(f"the bench never finished in {READY_TIMEOUT_S} s: window.__arrival {seen}")
    return seen, errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--out", type=Path, default=None, help="where the screenshots go")
    parser.add_argument("--phone", action="store_true", help="open it as the touch benches do (Chrome, touch phone)")
    parser.add_argument("--query", default="", help="the page's query, without the question mark")
    parser.add_argument("--reuse", action="store_true", help="serve the export already in <work>/build/web")
    args = parser.parse_args()
    web = args.work / "build" / "web" if args.reuse else touch_assist.export_bench(args.godot, args.work, BENCH_SCENE)
    server, port = smoke.serve(web)
    try:
        seen, errors = run(
            f"http://127.0.0.1:{port}/index.html" + (f"?{args.query}" if args.query else ""), args.out, args.phone
        )
    finally:
        server.shutdown()
    wrong = verdict(seen, errors)
    print(json.dumps(seen, indent=1))
    for line in wrong:
        print("FAILED:", line)
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
