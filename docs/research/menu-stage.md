# The menu's 3D stage

The live drive-in behind the reworked main menu (issue #397; the design is in [Main menu](main-menu.md)). Code:
`game/ui/stage/`, the host screen `game/ui/screens/menu_stage_screen.tscn`, the web run
`tools/web_smoke/menu_stage.py`.

## What is in it

| Part | What it is |
| --- | --- |
| `MenuStage` | The lot built in code from the game's own models and materials: the movie screen (its own soft picture shader, `menu_screen.gdshader`), two rows of cars with an aisle, speaker posts, two lamps with additive glow quads, the booth and the counter, a fence, fog, the night sky shader of the lot. No physics body, no CSG, no navigation mesh, no shadows, 8 lights at most |
| `MenuHero` | The Soldier from `CharacterAssembler` in the saved look (`LookStore`), the saved showcase weapon (`loadout/weapon`) on the same bone mount and hold data the night uses, posed by `WeaponHandsIK` over the Idle clip |
| `MenuZombie`, `WanderPath` | Five dead beyond the fence, each a Walk clip and a loop of two waypoints, a function of the stage's clock |
| `StagePose`, `StageCameraRig` | One pose per tab (azimuth, distance, height, field of view, where the soldier sits across the picture, how he is turned) and critically damped springs between them |
| `MenuStageView` | A `SubViewportContainer` with its own world; three levels and the setting `video/menu_scene` |
| `StageGovernor` | Steps the stage down on a slow machine (auto mode) |

## Decisions and what they cost

- **The camera is placed by where the soldier should sit in the picture** (`frame_x`), not by a fixed offset, and the
  sideways shift is worked out for at most 16:9: a wider window keeps the soldier beside the same panels. A test
  projects the focus and checks it lands at `frame_x`.
- **No Tween.** The camera, the idle and the dead advance from `advance(delta)`; a capture or a test steps them by
  hand, so the picture repeats (the [Tween lesson](https://github.com/Ryubara/gdstudio/blob/main/docs/lessons/2026-11-01-tweens-do-not-move-in-hand-stepped-tests.md)).
- **The weapon is held by the game's own hand pose** at 0 degrees of pitch with the soldier turned side-on to the
  camera, so he reads as looking down the lot. The first try, the aim clip alone, held a rifle in one hand pointing at
  the lens; the low-ready pose made him hunch. The showcase weapons are the ones whose class has a model today
  (`MenuHero.available()`), so a weapon joins the list by getting its model.
- **Own screen shader.** The lot's screen shader hashes with `sin` on pixel-sized arguments (grain that shimmered at
  1080p in the capture); the menu's is smooth waves only.
- **Sky.** The lot's screen glow on the horizon turned the menu sky pale blue; it is turned down in the stage.

## The three levels

| Level | What it draws | When |
| --- | --- | --- |
| Live | every frame, full size | default |
| Half | every frame at half the width and height | the governor, when the mean frame is over 25 ms |
| Still | one frame per change (a tab, a turn, a new look), the camera cuts, the dead stand | the setting `video/menu_scene` set to still, or the governor when the mean frame is over 40 ms at Half, or over 120 ms at Live (a software renderer) |

The governor reads the page's own frame time over 1.5 s windows, ignores the first 12 frames, clamps one long frame,
never steps back up in a session and does not run under Movie Maker. A covered menu (another screen on the router)
draws nothing (`set_active(false)`). Reduced motion cuts the camera and stops the dead.

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
a few seconds to notice (`StageGovernor.is_software`).
