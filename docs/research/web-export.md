# Web export and the browser smoke run

How Deadnight is exported for the browser, how CI runs that build in headless Chromium, and what the numbers were
(issue #167; the browser checks asked for by #82 and #105). The preset is `game/export_presets.cfg`, the run is
`tools/web_smoke/smoke.py`, the CI job is `web` in `.github/workflows/ci.yml`.

## The preset

- **Web, Compatibility renderer** (WebGL2), release export, `build/web/index.html` (git-ignored).
- **No threads** (`variant/thread_support=false`, `variant/extensions_support=false`). A threaded export needs
  `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers on every response; a Discord Activity is served
  through Discord's proxy, which we do not control, so the build must run without them. The smoke run serves the build
  with no special headers, so a change that needs them fails CI. Console line: `single-threaded, no GDExtension support`.
- **`*.json` in the include filter.** `parts.json`, `clips.json` and `zombies.json` are read as plain files
  (`FileAccess`/`JSON`), not as imported resources. In Godot 4.7.2 they reach the `.pck` even without the filter (an
  export with an empty include filter is byte-identical, same md5, and the wardrobe loads from it), so the filter is
  insurance for other plain files (`.cfg`, `.txt`) and for a Godot that stops treating `.json` as a resource. CI checks
  the three names are in the pack and the wardrobe screen is opened in the browser, which reads `parts.json`.
- **Excluded:** `addons/gdUnit4`, `addons/godot_mcp` (untracked, per machine), `tests/`, `reports/`, `_capture.*`.
- VRAM compression is desktop formats only (`for_mobile=false`); a mobile browser decodes to RGBA. Revisit with the
  mobile GPU check in #82.

Size of `build/web`: `index.wasm` 39.5 MB (10.1 MB gzipped), `index.pck` 5.3 MB (4.8 MB gzipped), `index.js` 0.3 MB.

## Export templates

The templates are pinned in the kit's `tools.toml` as `godot-templates` (4.7.2, about 1 GB, sha512, installed into the
pinned Godot's own `editor_data/`). CI gets them with `gds workspace init --fetch godot,godot-templates` and the cached
download folder, so nothing is downloaded by URL inside the workflow and no hash is repeated there.

## The smoke run

`smoke.py` serves `build/web`, opens it in headless Chromium (Playwright 1.64.1, `chromium-headless-shell` with
SwiftShader on CI), and:

1. waits for the main menu (the game publishes what it shows in `window.deadnight`, `game/core/web_probe.gd`; a browser
   cannot see inside a Godot canvas), screenshots it and measures frame times;
2. opens the wardrobe (reads `parts.json`) and goes back;
3. starts a night with the keyboard, walks a square and fires for a while, sampling the crowd and frame times each second;
4. fails on any console `error`, uncaught page error, failed request or HTTP status 400 or more, and writes screenshots,
   `console.txt` and `result.json`.

Things that were not obvious:

- Godot reads input once per frame: a key tap shorter than a frame can be lost, so keys are held for 150 ms.
- After Back from a screen, nothing has focus; the router spends the first arrow or accept key giving it focus. The
  run presses Down, Up, Up to get back to Play.
- There is no pointer lock in headless Chromium, so the camera cannot be turned and the zombies are usually off screen:
  the crowd is read from the probe, not seen.
- Playwright 1.64 launches `chromium-headless-shell`, which is always software-rendered. `--gpu` uses the installed
  Chrome (`channel="chrome"`) for numbers with a real GPU.

## Numbers (1280x720, local server, single run)

| Where | Menu frame p50 / p95 | Night frame p50 / p95 (worst second) | Load to menu |
| --- | --- | --- | --- |
| Chrome 156 on an RTX 5080 (ANGLE D3D11), 240 s night | 5.6 / 6.2 ms | 5.6 / 12.1 ms | 3.9 s |
| Headless shell, SwiftShader on the same PC, 45 s night | 33 / 50 ms | 67 / 83 ms (12 to 15 fps) | 1.7 s |
| GitHub runner (ubuntu-24.04, SwiftShader, no GPU), 45 s night | 133 / 150 ms | worst second p95 850 ms (about 1 to 2 fps) | 2.0 s |

- The GPU run is paced by the display (5.6 ms is 180 Hz), so it shows no dropped frames, not the headroom. Over 183 s
  of night (31,000 frames), 6 of 181 one-second windows contained a frame over 33 ms and one a frame over 100 ms: the
  211 ms frame is the night loading as it starts; the other 50 to 75 ms frames (about one second in thirty) are not
  traced yet.
- The first round is **6 zombies** (`remaining` 6, all alive at once from about 24 s after Play); the player dies at
  183 s. That is the whole crowd this run reaches: #105's bigger crowds need a bot, because the player here
  cannot aim. **Open:** a way to start the night in the autopilot mode from the browser (for example a `?autopilot`
  query read by the probe), to measure rounds of 20+ zombies and a weak laptop.
- SwiftShader numbers say the build works on a machine with no GPU, not how a laptop GPU behaves. CI records them, never
  gates on them: on the runner the night is so slow that only 3 of the 6 zombies had arrived after 45 s, yet the run passes.
- No console errors. Console output was the three engine start-up lines, plus one "GPU stall due to ReadPixels"
  warning from SwiftShader.
- #82: WebGL2 in Chromium shows the menu, the wardrobe and the night with no shader error in the console. Firefox and a
  mobile GPU are still not run.

## Sources

- [Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Playwright for Python](https://playwright.dev/python/docs/intro)
