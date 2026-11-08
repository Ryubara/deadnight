# The menu's 3D stage

The live drive-in behind the reworked main menu (issue #397; the design is in [Main menu](main-menu.md)). Code:
`game/ui/stage/`, the host screen `game/ui/screens/menu_stage_screen.tscn`, the web run
`tools/web_smoke/menu_stage.py`.

## What is in it

| Part | What it is |
| --- | --- |
| `MenuStage` | The lot built in code from the game's own models and materials: the movie screen (its own soft picture shader, `menu_screen.gdshader`), two rows of cars with an aisle, speaker posts, two lamps with additive glow quads, the booth and the counter, a fence, fog, the night sky shader of the lot. No physics body, no CSG, no navigation mesh, no shadows, 8 lights at most |
| `MenuHero` | The Soldier from `CharacterAssembler` in the saved look (`LookStore`), the saved showcase weapon (`loadout/weapon`) put in the hands by `HeldWeapon`, the one builder the night's `PlayerAnimation` calls too (the weapon's own hold, its solved grip, `WeaponHandsIK`, `HandGripPose`), over the Idle clip |
| `MenuZombie`, `WanderPath` | Five dead beyond the fence, each a Walk clip and a loop of two waypoints, a function of the stage's clock |
| `StagePose`, `StageCameraRig` | One pose per tab (azimuth, distance, height, field of view, where the soldier sits across the picture, how he is turned) and critically damped springs between them |
| `MenuStageView` | A control with a `SubViewport` of its own world, drawn into a `TextureRect`; three levels and the setting `video/menu_scene` |
| `StageGovernor` | Steps the stage down on a slow machine and back up when frames recover (auto mode) |

## Decisions and what they cost

- **The camera is placed by where the soldier should sit in the picture** (`frame_x`), not by a fixed offset, and the
  sideways shift is worked out for at most 16:9: a wider window keeps the soldier beside the same panels. A test
  projects the focus and checks it lands at `frame_x`.
- **No Tween.** The camera, the idle and the dead advance from `advance(delta)`; a capture or a test steps them by
  hand, so the picture repeats (the [Tween lesson](https://ryubara.github.io/gdstudio/engines/godot/test-speed/#what-hand-stepping-needs)).
- **The weapon is held by the game's own hand pose** at 0 degrees of pitch with the soldier turned side-on to the
  camera, so he reads as looking down the lot. The first try, the aim clip alone, held a rifle in one hand pointing at
  the lens; the low-ready pose made him hunch. The showcase weapons are the ones the night puts in a hand today
  (`MenuHero.available()` asks `WeaponHoldMap.hold_for`), so a weapon joins the list by getting its model.
- **The menu has no hand placement of its own** (#621). It first copied the night's set-up, and #507's solved grips
  reached `PlayerAnimation` only, so the menu kept the kit's fist. `HeldWeapon` is the one place that mounts the
  weapon and poses the hands; `test_menu_grips.gd` measures the menu soldier's hands on all eight weapons against the
  night's limits and fails when a menu file builds a hand pose itself. `tools/web_smoke/menu_grips.py` steps the
  Loadout row in the browser.
- **Own screen shader.** The lot's screen shader hashes with `sin` on pixel-sized arguments (grain that shimmered at
  1080p in the capture); the menu's is smooth waves only.
- **Sky.** The lot's screen glow on the horizon turned the menu sky pale blue; it is turned down in the stage.

## The three levels

| Level | What it draws | When |
| --- | --- | --- |
| Live | every frame, at the window's own pixels, 4x multisampling | default |
| Half | every frame at half the width and height (4x multisampling too: a quarter of the pixels) | the governor, when the mean frame is over 25 ms for two windows (3 s) |
| Still | one frame per change (a tab, a turn, a new look), the camera cuts, the dead stand | the setting `video/menu_scene` set to still, or the governor when the mean frame is over 40 ms at Half for two windows, or over 120 ms at Live (a software renderer) |

The governor reads the page's own frame time over 1.5 s windows (or 90 frames), ignores the first 12 frames and the
first 2 s, clamps one long frame, and does not run under Movie Maker. A covered menu (another screen on the router)
draws nothing (`set_active(false)`). Reduced motion cuts the camera and stops the dead.

The soldier is posed on every step of every level, a still's and reduced motion's included (a step of 0 seconds): his
arms are `WeaponHandsIK`'s, which aims in the **world** (`aim_yaw`), so a turn or a weapon switch has to reach the aim
as well as the body (`MenuHero.face`). Until #940 only an animated stage did, and a still showed the arms-out rest pose
with the weapon pointing behind him. `tests/ui/test_menu_hero_arms.gd` sweeps every weapon at every 15 degrees in
all three cases and fails on a hand or the muzzle behind the chest plane.

**It steps back up** (#893). Half to Live after 4.5 s of windows at 20 ms or less (a 60 Hz display held; counted in
seconds, because a 240 Hz display fills a window of 90 frames in 0.4 s). A climb that fails (Live drops again within
30 s) doubles the wait for the next (4.5, 9, 18 s), and after two failures the stage stays at Half for the session, so a
machine that cannot hold Live changes look at most three times. The still is final (nothing is drawn to measure).
Before this, one window over 25 ms (a few seconds of other programs when the menu opened) left Half for the whole
session: a probe that busied the main thread for 5 s at launch read Half at 3 s and still Half at 15 s with 4.2 ms
frames; now it reads Live again at about 9.5 s (`tests/captures/menu_stage_sharp.tscn --level=auto --load=30
--load_for=5`).

## Sharpness (#893)

The maintainer saw a pixelated menu character with jaggies. Three things were stacked, each reproduced with
`tests/captures/menu_stage_sharp.tscn` (a real window, the real view, one pose) on an RTX 5080:

- **The viewport was not the window's pixels.** The view is sized in the project's 1920 x 1080 canvas
  (`canvas_items`, expand), and a `SubViewportContainer` with `stretch` drew its viewport at that size: 1920 x 1080
  in a 2560 x 1440 window (stretched by a third), and 2337 x 1080 for the phone page's 1688 x 780 canvas (more
  pixels than the screen has). The view now sizes the viewport itself, from its rectangle times the window's
  stretch scale (`get_final_transform`), at most 1440 tall, and shows it in a `TextureRect`; a
  `SubViewportContainer` cannot do that (stretch on: it owns the size, a warning says so; off: it grows to the
  viewport's size).
- **2x multisampling** (the viewport has its own `msaa_3d`; the project setting does not reach it): the hair's and
  the brow's edges still stair-stepped at 1080p. Now 4x, as the HUD portrait and the look preview.
- **Half for the session** (above).

The film grain is not a cause: it is an additive speckle over the finished picture (`film_grain.gdshader`).

Cost of 4x, SwiftShader (fill-bound, so a ratio, never a frame rate; `tools/web_smoke/menu_stage.py --cases ...`, two
runs of each build interleaved, mean frame in ms): 1080p before 371, 2x 383, 4x 373 (the same pixels); phone page
(844 x 390 at a pixel ratio of 2) before 426, 2x 265, 4x 274. The phone draws 1.3 million pixels where it drew
2.5 million, so 4x there costs less than the old 2x. On the RTX 5080 through ANGLE (`--gpu --unpaced`) every arm
is 6 to 8 ms with the machine busy, no difference to read; natively at 1080p a frame is 0.70 ms with no
multisampling, 0.75 with 2x and 0.86 with 4x.
A weak laptop GPU is still not measured: Half, and now the climb back, are the guard.

## Frame time in the web build

Chrome 156 headless over Playwright 1.64.1, the single-threaded Web export, `tools/web_smoke/menu_stage.py`, the stage
opened alone (`index.html?stage`), 12.5 s with a camera move every 2.5 s. RTX 5080 through ANGLE (`--gpu --unpaced`):

| Case | Mean / p50 / p95 / worst frame (ms) |
| --- | --- |
| Today's menu, 1280 x 720 | 4.4 / 4.3 / 5.4 / 14.8 |
| Stage live, 1280 x 720 | 3.3 / 3.1 / 5.0 / 12.5 |
| Stage live, 1920 x 1080 | 3.4 / 3.1 / 4.8 / 34.5 |
| Stage live, phone landscape 844 x 390 | 2.7 / 2.6 / 3.7 / 8.2 |
| Stage still, 1920 x 1080 | 0.9 / 0.8 / 1.2 / 7.2 |

No frame linked a GL program after the first three seconds, and the console had no error. On a strong GPU the stage
costs nothing the sky shader did not. **Software rendering (SwiftShader, a CPU) is another story**: 380 ms a frame
live (2.6 a second, against 42 ms for today's menu), 47 ms still; that is why the governor goes straight to the still
there, and why the numbers say "it runs", never "it is fast". A weak laptop or phone GPU is not measured here: the
governor is the guard until someone has one.

## What sits on it

The tab bar, the panels and the input hints are on this stage now ([menu shell](menu-shell.md)). The showcase weapon is
cosmetic (the night starts with the starter program), and the poses of Shop and Challenges were tuned against the
panels: a phone gets its own Loadout and Challenges poses (`StagePose.for_tab(tab, compact)`) so the soldier stays
clear of the wider panels. On a renderer that draws on the CPU the stage starts as a still, because the governor needed
a few seconds to notice (`StageGovernor.is_software`). A browser hides the adapter from the engine ("WebKit WebGL"), so
on the web the page asks WebGL for the unmasked renderer (`MenuStageView.detect_adapter`); the first CI run of the shell
showed why: with the stage live on the runner's software renderer a screenshot of the page timed out at 30 s. The
browser smoke run now fails when the stage is not a still on a software renderer (`window.deadnight.stage`). Firefox
masks the renderer, so there the governor, which now also ends its warm-up after four seconds of long frames, is what
catches it.
