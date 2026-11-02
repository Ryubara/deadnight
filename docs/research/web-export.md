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
- VRAM compression is desktop formats only (`for_mobile=false`); a mobile browser decodes to RGBA. Revisit with a
  mobile GPU check (#82 has none yet).

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
4. counts the GL programs linked in each page frame between Play and a running night and fails when one frame links
   more than 12 (a loading screen that stops for seconds; `first-use-hitches.md`);
5. fails on any console `error`, uncaught page error, failed request or HTTP status 400 or more, and writes screenshots,
   `console.txt` and `result.json`.

Things that were not obvious:

- Godot reads input once per frame: a key tap shorter than a frame can be lost, so keys are held for 150 ms.
- After Back from a screen, nothing has focus; the router spends the first arrow or accept key giving it focus. The
  run presses Down, Up, Up to get back to Play.
- Pointer lock works in headless Chromium (`document.pointerLockElement` is the canvas after the click that starts the
  night), but on Linux (the CI runner) every synthetic `page.mouse.move` under lock arrives as a motion and then the
  opposite motion (+15 px, -15 px), which cancel, so Playwright cannot turn the view there; Windows does not do it.
  Godot's web runtime listens for `pointermove` on the window and reads `movementX/Y`, so the smoke dispatches
  `PointerEvent('pointermove', {movementX})` on the canvas when the real moves did not turn the view
  (`tools/web_smoke/smoke.py`, `mouse_look_via` in its result). The yaw is on `window.deadnight` for it.
- **A finger is a pointer move too (Deadnight #470).** The same `pointermove` listener also fires for a touch pointer, so
  on a phone every finger, the move stick's too, turned the view like a mouse and in device pixels (3 times too far at a
  pixel ratio of 3). The page's `head_include` stops touch pointer moves in the capture phase, and the player ignores
  mouse motion that is not the touch layer's own while the layer is up. `tools/web_smoke/touch_look.py` drives a
  phone-sized Chrome (844 x 390 CSS pixels, ratio 3, real touch events through `Input.dispatchTouchEvent`) and checks
  that the stick turns the view 0 and a 100 px look drag turns it as `TouchLook` promises (0.41 rad). Before the fix
  the stick turned it 0.37 rad and the drag 1.43 rad, one frame up to 0.43 rad.
- The zombies are usually off screen: the crowd is read from the probe, not seen.
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
- #82: WebGL2 in Chromium shows the menu, the wardrobe and the night with no shader error in the console. The skin
  tour (`tools/web_smoke/skin_tour.py`: the menu, the three transitions, the settings and the credits at 1080p) also ran
  in Chrome and Firefox with a GPU and in the software renderer: no console error and no black or white frame, numbers
  in [the main menu page](main-menu.md). A mobile GPU is still not run.

## Playing the web build

**<https://web-production-f401d1.up.railway.app>** is the head of `main`, in a browser, with no install (issue #172).
It is a Railway-generated domain; a custom domain is the maintainer's to add (service `web`, Settings, Networking).

```text
merge to main
   |
   v
ci: godot (tests) + web (export, smoke run in headless Chromium)       <- the build that is deployed is the one tested
   |  artifact web-build
   v
ci: deploy   bash deploy/web/deploy.sh build/web $GITHUB_SHA
   |  railway up (Dockerfile + Caddyfile + build/web)
   v
Railway project gdstudio-net-test, service `web`
   |  image build: gzip and brotli the .wasm, .pck, .js, .html once
   |  health check GET /healthz, then traffic moves to the new deployment
   v
https://web-production-f401d1.up.railway.app
```

What serves it (`deploy/web/`): a Caddy 2.11 container. `.wasm` is `application/wasm`, `.pck` is
`application/octet-stream`, and the large files are compressed **once, when the image is built** (`index.wasm`
39.5 MB, 10.1 MB as gzip, 7.9 MB as brotli; `index.pck` 5.3 MB, 4.8 MB gzip, 4.6 MB brotli), then picked by the
browser's `Accept-Encoding`. Every response says `Cache-Control: no-cache`: the file names have no hash, so a browser
asks each load whether the file changed (an ETag, so a 304 when it did not) and a deploy or a rollback is live on the
next page load. No cross-origin isolation headers are sent, because the export has no threads.

Why this way, and not another:

- **CI uploads the tested build with `railway up`.** The alternative, a Railway service built from the GitHub
  repository, would have to export the game inside the image build: the 1 GB of export templates, and Git LFS (the
  models and textures are LFS objects, which Railway's GitHub builds do not fetch). It would also deploy a build that
  CI never ran in a browser.
- **A Dockerfile that downloads a build CI published** needs a public place for that build: a GitHub release is a
  tag (a maintainer decision), and a branch holding a 50 MB binary per merge would grow the repository without end.
- The deploy needs one secret, a Railway **project token**, which can deploy to that one project and environment and
  nothing else.

The game server is deployed from the same job file (`deploy-server`, `deploy/server/deploy.sh deadnight-server`): it
builds the image from the commit `godot` tested (with the LFS files, since the server imports the whole project) and
waits for the deployment to be `SUCCESS`. Both deploys use the one `RAILWAY_TOKEN`. They finish a few minutes apart, and
a client of one protocol version is turned away by a server of another for that time
([Multiplayer](multiplayer.md)).

### Setting it up (once, the maintainer)

A project token cannot be created by the agent's login (`projectTokenCreate` answers "Not Authorized" to the CLI's
session), so this is a dashboard step: Railway, project `gdstudio-net-test`, Settings, Tokens, new token for the
`production` environment, then

```sh
gh secret set RAILWAY_TOKEN --repo Ryubara/deadnight   # paste the token when asked
```

Until the secret exists the `deploy` job warns "Not deployed" and stops; it never fails the run. Afterwards,
**Actions, ci, Run workflow** on `main` deploys the current head without a push.

### Rolling back

- **Fastest:** the Railway dashboard, service `web`, Deployments, the earlier deployment, Rollback. The same from a shell
  (the CLI has no rollback command, the API has):

  ```sh
  railway deployment list --service web --json     # ids, newest first; "cliMessage" is "main <short sha>"
  railway api 'mutation { deploymentRollback(id: "<deployment id>") }'
  ```

  Rolling back keeps the build, but the next merge to `main` deploys over it.
- **Lasting:** revert the commit on `main`; the merge deploys the reverted build.
- **Redo a deploy:** re-run the `deploy` job of an earlier `ci` run on `main` (`gh run rerun <id> --job <deploy job id>`);
  it uses that run's `web-build` artifact, which GitHub keeps for 90 days.

### Running it locally

```sh
bash deploy/web/deploy.sh path/to/build/web <commit> <stage folder>   # needs RAILWAY_TOKEN, or `railway link` in the shell
docker build -t deadnight-web <stage folder> && docker run --rm -e PORT=8080 -p 8080:8080 deadnight-web
```

The smoke run takes the URL in place of a folder: `uv run --with playwright==1.64.1 python tools/web_smoke/smoke.py
https://web-production-f401d1.up.railway.app/index.html build/smoke-live`.

`tools/web_smoke/judder.py` (same arguments, `--gpu --unpaced` for the machine's GPU and no frame limit) measures
how evenly the soldier moves on the screen in the page: the numbers and what they showed are in
`physics-interpolation.md`. The smoke run also fails when the night's body is not drawn between physics ticks
(`window.deadnight.interpolated`).

### Over the internet

`smoke.py` pointed at the URL (Houston, Texas, on a home connection, headless Chromium with a fresh profile, so
nothing cached; the Railway edge answered from `iah1`): the menu, the wardrobe and a 45 s night, **no console error,
no failed request, no HTTP status of 400 or more**, with the 4 console lines the engine prints on every start.

| Measure | Value |
| --- | --- |
| Time to the main menu, first visit after a deploy | 5.0 s |
| Time to the main menu, three more visits | 2.3 to 2.4 s |
| `index.wasm` download alone (curl) | 0.39 s as brotli (7.9 MB), 0.37 s as gzip (10.1 MB), 1.3 s uncompressed (39.5 MB) |

The 5.0 s is the first run after the deploy (probably a cold edge; not investigated). The local
server needed 1.7 to 3.9 s (Numbers, above), so the network adds little on this connection; a connection of 20 Mbit/s
needs about 3 s for the 7.9 MB wasm on top of that. Frame times come from the machine that opens the page, not from the
server.

## Frame times at the start of a night

`tools/web_smoke/first_use.py` records every frame and every GL program linked in the first 20 s of a night, in a fresh
Chrome profile, with the machine's GPU. Play now builds the lot and warms up everything the night draws behind a loading
screen, which takes about 31 s there (24 s before): `smoke.py` waits up to 150 s for it. The numbers are in
[First-use hitches](first-use-hitches.md).

## Audio in the browser

Asked by #88: does the web build play a night's voices without crackle on a modest laptop, and do the things the mix
relies on (the duck, a player's distance filter) survive the browser? `tools/web_smoke/audio_load.py` answers with the
real export: it exports the game with `game/tools/web_audio_load/web_audio_load.tscn` as its main scene (a release web
template refuses a scene on the command line, so it changes `run/main_scene` for the length of the export and puts it
back), plays steps of looping voices in headless Chromium or in the machine's Chrome (`--gpu`), and **taps the speakers**:
every connection the game makes to the browser's audio destination goes through one gain node and an `AudioWorklet`
that counts the output's level, its silent 128-sample blocks (an underrun) and its jumps over 0.2 of full scale (a
click). Run it with `--playback sample|stream` (how the engine plays its players) and `--latency MS`.

**What the browser does.** Godot 4.3 and later plays players in a web export as *samples* by default
(`audio/general/default_playback_type.web`): the browser's own `AudioBufferSourceNode`s, mixed by the browser, not by the
engine's audio worklet. The documentation says that with samples, bus effects and a player's filter do not work, and
that `Stream` playback restores them at the cost of latency on a build without threads
([Audio streams](https://docs.godotengine.org/en/stable/tutorials/audio/audio_streams.html)). Measured (one voice of
the crickets, from the same place in its file, so only the setting differs):

| One voice | Samples (the default) | Streams |
| --- | ---: | ---: |
| Open | -50.9 dBFS | -46.2 dBFS |
| Distance filter at 800 Hz (`attenuation_filter_cutoff_hz`) | -50.9 (no change) | -77.3 (-31 dB) |
| `AudioEffectAmplify` -12 dB on the bus (the duck) | -50.8 (no change) | -58.0 (-11.8 dB) |
| The bus's own volume -12 dB (a settings slider) | -62.8 (-11.9 dB) | -57.8 (-11.6 dB) |

So in the browser the sting's duck, the rear cue, the occlusion low-pass and the engine's built-in distance dulling are
**not applied**, and the settings sliders are. The spatial level also differs between the two (32 positional voices read
-27.7 dBFS as samples and -24.0 as streams), so the mix was tuned for streams and the browser plays a slightly different
one.

**Voices and crackle** (the same voices as the real pool: 8, 16, 32 positional, then 32 with 12 flat; a steady hum so a
silent block is a dropout; Chrome 156 with a GPU, and the headless shell with a software renderer; blocks counted
over 3 s, 1,125 of them in a phase):

| Voices | Samples: silent blocks, jumps | Streams: silent blocks, jumps | Frame mean / p95 (GPU) |
| --- | ---: | ---: | ---: |
| 8 / 16 / 32 | 0, 0 | 9 / 0 / 0, 0 | 1.0 to 1.3 / 1.9 to 3.9 ms |
| 44 (the whole pool) | 0, 0 | 15, 0 | 1.1 to 1.7 / 2.3 to 5.1 ms |
| 44 and a 60 ms stall every 0.5 s | **0**, 0 | **114**, 8 | 1.5 to 2.3 / 3.2 to 7.3 ms |

- **The pool is fine.** 44 voices cost about 0.5 ms of frame time, in both modes, and as samples never dropped a block
  or clicked, with the software renderer and the GPU alike. The 32 and 12 stay.
- **Samples cannot crackle from a slow frame; streams can.** The engine's worklet is fed from the main thread (the
  build has no threads), so a stall of 50 ms or more starves it: a 60 ms stall every half second dropped 4 to 10% of the
  blocks, and asking for more latency (`audio/driver/output_latency.web` 100 and 150 ms instead of 50) did not help (39
  silent blocks at both). The night does stall like that, about one second in thirty at 50 to 75 ms
  ([above](#numbers-1280x720-local-server-single-run)) and on every shot and kill (#387).
- **The decision, left as it is:** samples. The web build gets a crackle-free mix without the duck and the filters. The
  ways to get the duck back are in [Sound](../design/audio.md#in-the-browser) and
  [the audio research](audio.md#open-questions): the bus volume works in samples, so a duck made of bus volume would too.

## Sources

- [Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Playwright for Python](https://playwright.dev/python/docs/intro)
- [Audio streams (Godot): playback type, samples and their limits](https://docs.godotengine.org/en/stable/tutorials/audio/audio_streams.html)
