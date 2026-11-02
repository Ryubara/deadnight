# Web export and the browser smoke run

How Deadnight is exported for the browser, how CI runs that build in headless Chromium, and what the numbers were
(issue #167; the browser checks asked for by #82 and #105). The preset is `game/export_presets.cfg`, the run is
`tools/web_smoke/smoke.py`, the CI job is `web` in `.github/workflows/ci.yml`.

A probe never listens, so it makes no sound at the machine. Playwright's headless Chromium starts with `--mute-audio`
(read off the process command line, Playwright 1.64.1, the headless shell and Chrome alike). It does not mute a headed
Chromium or Firefox, so under `gds quiet` (`GDS_QUIET=1`) `smoke.mute_args()` and `smoke.mute_firefox_prefs()` add
the mute. A new probe passes `args=[..., *smoke.mute_args()]` to `chromium.launch`.

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
- **A virtual gamepad** (`tools/web_smoke/pad_pause.py`, #494): an init script gives the page a `navigator.getGamepads`
  with a standard-mapping pad (17 buttons, 4 axes; Start is button 9, the right stick axes 2 and 3) and the probe holds
  a button for 0.9 s, since a software renderer reads a pad once a frame. A real `GamepadEvent` cannot be built from
  a plain object, and the engine lists the pad without one. `requestPointerLock` is stubbed, which is also a pad
  player's real case: a gamepad button is no user gesture, so the page never gets the lock. The probe's
  `pad_count`, `pad_start_presses` and `pause_presses` come from the `Input` singleton, so they show a press that a
  node ate on the way. Before the fix both counted 1 and the night did not pause ([cause](gamepad-devices.md)).
- Pointer lock works in headless Chromium (`document.pointerLockElement` is the canvas after the click that starts the
  night), but on Linux (the CI runner) every synthetic `page.mouse.move` under lock arrives as a motion and then the
  opposite motion (+15 px, -15 px), which cancel, so Playwright cannot turn the view there; Windows does not do it.
  Godot's web runtime listens for `pointermove` on the window and reads `movementX/Y`, so the smoke dispatches
  `PointerEvent('pointermove', {movementX})` on the canvas when the real moves did not turn the view
  (`tools/web_smoke/smoke.py`, `mouse_look_via` in its result). The yaw is on `window.deadnight` for it.
- The first Esc under pointer lock is the browser's: it frees the lock and the key never reaches the page, so the
  game gets no `pause`. On the web `Input.mouse_mode` reads the real lock (2 captured, 0 once freed), so `Player` asks
  `MouseGrip` every frame and, the frame a held lock is gone, turns the controls off and `NightScreen` opens its menu
  (#476). Until the lock comes back (Resume asks inside the click or key press) look and fire wait. Playwright cannot
  press the browser's own Esc, so `tools/web_smoke/pointer_lock.py` releases the lock with `document.exitPointerLock()`:
  before the change the night went on running with a free cursor, after it the menu was open 0.6 s later (the probe's
  refresh and a software renderer) and Resume, by key and by click, took the lock back. A headless Godot reads
  `Input.mouse_mode` back as VISIBLE whatever it was set to, so the unit tests put a stand-in platform under `MouseGrip`.
  Never run a probe that takes pointer lock on a Windows machine in use: headless Chromium there clips the real cursor to
  an invisible box at the top left, freed only by Esc. `pointer_lock.py` refuses to start there; CI (Linux) runs it.
- **A finger is a pointer move too (Deadnight #470).** The same `pointermove` listener also fires for a touch pointer, so
  on a phone every finger, the move stick's too, turned the view like a mouse and in device pixels (3 times too far at a
  pixel ratio of 3). The page's `head_include` stops touch pointer moves in the capture phase, and the player ignores
  mouse motion that is not the touch layer's own while the layer is up. `tools/web_smoke/touch_look.py` drives a
  phone-sized Chrome (844 x 390 CSS pixels, ratio 3, real touch events through `Input.dispatchTouchEvent`) and checks
  that the stick turns the view 0 and a 100 px look drag turns it as `TouchLook` promises (0.41 rad). Before the fix
  the stick turned it 0.37 rad and the drag 1.43 rad, one frame up to 0.43 rad.
- **With two fingers the first drag of each finger has a wrong `relative` (Deadnight #497).** Logged in Chrome with
  the stick finger and the look finger down: the look finger's first `InputEventScreenDrag` had `relative` equal to its
  own position (measured from the origin), the stick finger's first drag was measured from the look finger's press
  (`(-1080, 522)`), and the `velocity` of a finger was stale for its first three drags. One thumb is fine (the press
  seeds the position). `TouchControls` now keeps each finger's last position and reads the step from that; the same
  probe (`touch_look.py`, two-finger case) turned the view 2.42 rad for a 100 px drag before, 0.41 rad after.
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

## Loading a night (#509)

CI measured 82 to 107 s from pressing Play to a running night (the smoke waits 150 s, and main went red when a slow
runner took longer), against 20 to 30 s on a development machine. The same work on a different machine: this is where
it went and what was cut. Method: `tools/web_smoke/first_use.py` (`--software` for the headless shell's SwiftShader,
which is what CI runs; without it the machine's Chrome and GPU), which records every frame and every GL program the page
links; the steps the game marks (`WebProbe.mark`, the loading screen's own text) cut the time into parts. Press Play to
a running night, a fresh browser profile every run, three runs of the build of `main` and three of this change one
after the other on the same machine (16 threads, RTX 5080, other agents' work on the machine, so a run moves by 10 to
20 %).

| Press Play to a running night (3 runs) | SwiftShader, CI's renderer | Chrome 156, RTX 5080 (ANGLE D3D11) |
| --- | --- | --- |
| `main` before | 21.6, 21.8, 22.2 s | 20.6, 24.4, 24.7 s |
| This change | **6.7, 7.2, 7.6 s** | **16.7, 18.1, 19.2 s** |
| Programs linked / linked while playing | 221 / 0 before, 207 / 0 after | 222 / 0 before, 207 / 0 after |
| Longest frame while loading | 0.8 s before, 0.38 s after | 2.3 to 2.5 s before and after (the build of one lit shader) |

Where the time went in `main` (one run each, seconds):

| Step | SwiftShader | GPU |
| --- | ---: | ---: |
| Menu to the lot's first mark (screen change, the lot's scene) | 1.5 | 1.4 |
| Sounds decoded | 3.8 | 3.4 |
| The lot, lit then dark (21 steps) | 5.1 | 9.8 |
| The stage under four light conditions, props | 3.9 | 5.9 |
| The effects replayed in four light conditions | 6.1 | 2.6 |

What the profile showed:

- **On a renderer that draws on the CPU the cost is the pixels, not the programs.** Every warm-up frame draws the lot or
  the stage at the window's size (1280 x 720), 0.1 to 0.3 s a frame in SwiftShader, and the warm-up is some 100 frames:
  the same run in a 640 x 360 window took 14.3 s against 30.5 s in the run that measured it (a busy machine). A program
  does not depend on the size of the picture, so the warm-up now draws into a 160 x 90 `SubViewport` of the same world
  while the window's own 3D drawing is off (`NightWarmup.VIEW_SIZE`), and the window draws the night once at the end,
  so anything only its drawing needs is built behind the bar. The same programs are linked, none while playing.
- **The effects were replayed in all four light conditions.** In the three after the moon alone the replay linked 0
  programs (none of the effects' materials is lit) and took 1.5 s each in SwiftShader. It is drawn once, in the first
  condition (1.4 s of the 6.1).
- **Sounds were decoded behind the bar**: 240 files, 14 MB of samples, by a GDScript loop that runs once for every
  sample (3.4 to 3.8 s here). The audio service now loads them in the background while a menu is up
  (`AudioService.start_background_preload`, a quarter of each frame, 3 to 40 ms, after a second) and the loop calls
  nothing it can write out. The warm-up finds them cached (the step takes 0.02 s). Pressing Play before the menu has
  finished (the first second and a half of a page) leaves the rest to the warm-up, as before.
- **With a GPU the cost is the lit shaders, and each costs twice what it draws.** Of the 134 programs linked between
  Play and the night, 10 take 0.6 to 1.0 s each (8.4 s of 12.9 s of linking) and the other 124 take 0.14 s or less. The
  10 are the **default specialisation** the engine builds at the first draw of every lit shader: the colour program and
  the instanced colour program with every light type, lightmaps and reflection probes switched on, which no mesh of ours
  uses (a mesh is drawn with `DISABLE_LIGHTMAP` and only the light types that reach it). The menu's stage already pays
  six such pairs when the page loads, before Play; the lot and the stage add five. So **every lit `StandardMaterial3D`
  that differs from another in one setting costs 1.2 to 2 s of loading** whatever it draws. The seven painted and glowing
  lot materials (`assets/lot/materials`: the lines, the neon, the plaque, the screen face...) set
  `specular_mode = DISABLED`, a shader of their own for a material that looks the same with `metallic_specular = 0`.
  Switching them merged two shaders into two that existed: 14 programs and about 2 s fewer. The lamps tour
  (`tests/captures/lamps_tour`, 20 frames) is pixel for pixel the same before and after, except in the screen's own
  animated grain (a run against itself differs in the lamp flicker only).
- **Not a lever:** `rendering/shading/overrides/force_lambert_over_burley` (18.5 s in the same run as a 16.0 s build
  without it: no faster within the spread of the machine); the shadow filter quality and the lights per object (0 to
  20 % in the first-use spike, see [First-use hitches](first-use-hitches.md)). There are no threads in this build (a
  Discord Activity cannot send the headers a threaded export needs) and the browser cannot build half a program, so the
  loading cannot be spread over cores; the programs can only be fewer.

What is left with a GPU is 8 lit `StandardMaterial3D` settings combinations at 1.2 to 2 s each (an alpha-blended lit one,
a double-sided textured one, the emissive-and-textured one of the soldier and the dead): the next cut is a material that
looks different, so it is an artist's decision, not made here. `tests/night/test_load_cost.gd` fails when the night
draws more than 8, and lists them.

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

The smoke run takes the URL in place of a folder:
`uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python tools/web_smoke/smoke.py
https://web-production-f401d1.up.railway.app/index.html build/smoke-live`.

`tools/web_smoke/judder.py` (same arguments, `--gpu --unpaced` for the machine's GPU and no frame limit) measures
how evenly the soldier moves on the screen in the page: the numbers and what they showed are in
`physics-interpolation.md`. The smoke run also fails when the night's body is not drawn between physics ticks
(`window.deadnight.interpolated`).

`tools/web_smoke/hip_fire.py` (same arguments) drives the real mouse and reads the camera's field of view every drawn
frame (`window.deadnight.viewRows`, `game/core/view_web_probe.gd`): hip fire must leave it at 60, and aim, shoot, release
and hip shot, aim, release must be back at 60 within 0.9 s of the release (the spring takes 0.3 s; the rest is the
browser's latency, and a held zoom would add 0.8 s). Run it on the deployed URL after a change to the camera (#464).

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

## Copy and paste inside a Discord Activity (#516)

The maintainer: "Copy paste doesn't work when in discord activity". Two separate causes, both measured with
`tools/web_smoke/activity.py --clipboard` (a cross-origin iframe, under `gds quiet`, in the headless shell whose
clipboard is the browser's own, so the person's is never touched):

- **The frame may not use the clipboard API.** In an iframe of another origin `clipboard-read` and `clipboard-write`
  are policy features that default to the page's own origin: `document.permissionsPolicy.allowsFeature` says `false`
  and `navigator.clipboard.writeText` and `readText` throw `NotAllowedError`, even where the permission itself is
  granted. The engine's `DisplayServer.clipboard_set` and `clipboard_get` are exactly those two calls, so "Copy the code"
  copied nothing, and the screen still said "Code copied." (the engine does not report the failure).
  `document.execCommand("copy")` from a user gesture is not policy-controlled and works.
- **The engine cancels every key press on its canvas.** Its web runtime calls `preventDefault()` on every `keydown`,
  so Ctrl+V never makes the browser's own `paste` event (the one that needs no permission): the page saw the key
  and the engine ate it (`paste` events 0). Its own paste is `readText`, asynchronous, so even where the API is
  allowed the first Ctrl+V pastes the stale text. The code field stayed empty.

What `WebClipboard` (`game/core/web_clipboard.gd`) does, **only inside a frame** (a tab and the desktop keep the
engine's own calls, so they are unchanged):

- **Paste.** A capture-phase `keydown` for Ctrl/Cmd+V on the canvas is stopped before the engine sees it, so nobody
  cancels it. The browser pastes into the focused canvas (Chromium fires `paste` on a non-editable focused element),
  the page hands `clipboardData` to the game, and the next frame the text goes into the focused `LineEdit` or
  `TextEdit` (one line, the field's `max_length`, over the selection, `text_changed` emitted). A paste that lands in
  the engine's own touch text box (a phone's long press) is left to the engine.
- **Copy by a button** (`copy_text`): a hidden read-only text box and `execCommand("copy")` first (it needs the press
  that is still fresh), then `navigator.clipboard.writeText`; the page reports `write` as `pending`, `ok` or the
  error's name, and the game waits for it (two seconds at most). When it fails the screen shows the text in a
  read-only field, selected, with "press Ctrl+C", and never says "copied".
- **Ctrl+C** copies what the focused field has selected, or the text a screen offered, through a native `copy` event
  (the same hidden box takes the focus for the key's default action).
- **Share in Discord.** `discord-bridge.js` offers `window.deadnightDiscord.share`, the SDK's `shareLink`
  (no OAuth scope; the answer is `{success, didCopyLink, didSendMessage}`), with the room's code in the message and as
  `custom_id` (the SDK reads it back from the page address as `customId`; nothing joins by it yet). Discord's own window
  sends the code, so it needs no clipboard at all. `openInviteDialog` invites to the channel, not to a room code.
- **The probe line.** The Play together screen shows what the clipboard can do inside an Activity, and
  `window.deadnight.clipboard` and `clipboard_detail` carry it (`clipboard api read no, write no, button copy ok,
  Ctrl+V 1 seen 1 pasted, Ctrl+C 0 seen 0 copied`), so the maintainer can read Discord's real answer.

The harness runs `--embed plain` (no `allow`), `clipboard-denied` (the Activity answers
`Permissions-Policy: clipboard-read=(), clipboard-write=()`), `clipboard` (`allow="clipboard-read; clipboard-write"`),
`none` (a tab: no layer, the engine's own copy) and `--exec-refused` (only a native Ctrl+C can copy). It makes a night
without starting a game server (the proxy answers `/start` itself), so a run does not use the live backend's servers. The
before run, on `main`: paste 0, field empty, "Code copied." with the clipboard unchanged; after: both hold in every mode.

Not run: Discord's real clients (desktop, browser, phone). What Discord's iframe grants is not in its docs; the line
above says it. A real long press on a phone is not covered (its keyboard is the engine's text box).

## Sources

- [Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Playwright for Python](https://playwright.dev/python/docs/intro)
- [Embedded App SDK: commands](https://docs.discord.com/developers/developer-tools/embedded-app-sdk) (`shareLink`, `openInviteDialog`)
- [Permissions-Policy: clipboard-write](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/clipboard-write)
- [Audio streams (Godot): playback type, samples and their limits](https://docs.godotengine.org/en/stable/tutorials/audio/audio_streams.html)
