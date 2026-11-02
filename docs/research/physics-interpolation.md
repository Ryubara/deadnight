# Physics interpolation: the soldier seen from the side

The player's body moves on 60 Hz physics ticks. A screen that draws more often than that (120, 144, 165 Hz) shows the
body at its last tick for two or three frames, then jumps. Seen from the side while strafing, the jump is across the
view: the soldier looks doubled and blurry (issue #344). Godot 4.7.2, Compatibility renderer.

## What was wrong

`ThirdPersonCamera` already blended the last two ticks of the body by hand
(`Engine.get_physics_interpolation_fraction()`), so the camera moved smoothly while the body, drawn at its tick
position, did not. The picture is the difference of the two: the soldier swung by a whole tick of travel (0.08 m, 18
px at 1280x720) every two or three frames. At 60 Hz the frames and ticks coincide and nothing shows, which is why it
is only seen on a fast screen.

## Why the first fix did not reach the game (#353)

The fix of #352 turned the setting on and measured a test room: 16 px of unevenness before, 0.0 after. The maintainer
then played the live web build and saw the same judder. The cause was not the web: **the game's night hangs under a
screen, and a `Control` is not physics-interpolated.** `physics_interpolation_mode` is inherited down the tree, so the
`NightScreen` (and the `Stage` above it) switched it off for the whole lot, the soldier and the zombies. The test room
sits under a plain `Node`, so every measure passed while the game drew the body at its last tick. A probe in the
browser showed it (`player.is_physics_interpolated()` false, the chest's interpolated position equal to its tick
position), and `Night` in a `Control` on the desktop does the same. `Night` now sets its own mode to ON, which
overrides what the screen above it says; the camera rig stays OFF and `RemoteAvatars` (drawn from a track of their
own) is set OFF.

What to remember: a setting that a node inherits is only proved in the tree the game builds. The web smoke run now fails
when `window.deadnight.interpolated` is false in a night, and `tests/night/test_night_interpolation.gd` and the
`night_side_on_probe` cases do the same on the desktop.

## What we did

- `physics/common/physics_interpolation` is on (`project.godot`), and `Night` is ON itself (above). The renderer
  blends every node that moves in `_physics_process` between its last two ticks: the body, the weapon in its hand (the
  `BoneAttachment3D` under the skeleton), the zombies' views, which are placed in the tick that delivers a snapshot,
  the prize crane.
- The camera rig is **not** interpolated by the engine (`physics_interpolation_mode = OFF` in
  `ThirdPersonCamera.setup`). It is placed every drawn frame from the body's last two tick positions, and an engine
  blend on top of that is a second one: with the rig left on, the soldier still wandered 11 px on the screen
  (measured, below). Its own blend is not removed: it reads the same two tick positions and the same fraction as the
  engine's, so body and camera agree.
- Places that jump get `reset_physics_interpolation()`: `Player.teleport` and a `ZombieView`'s first placement.
- What is moved on the drawn frame by a tween or `_process` is set to `PHYSICS_INTERPOLATION_MODE_OFF` (`Barricade`'s
  boards and its pool of flying copies, `ShotEffects`, `BlastEffect`): the engine would blend them a tick late.
- Doors are not animated (their slabs are removed), lamps and signs change light, not place.

## What a frame shows: before and after

`tests/captures/side_on_smoothness.tscn` strafes the player across the test room, with a marker ball on the body and
one on the weapon mount, at a fixed frame rate (`--fixed-fps`, so 144 frames fall over 60 ticks the same way
everywhere), and reads the balls' centres out of each rendered frame. Frame-to-frame unevenness is the RMS of
`x[i + 1] - 2 x[i] + x[i - 1]` over about 350 frames in a steady stretch (pixels at 1280x720):

| Refresh rate | Body before | Body after | Weapon mount before | Weapon mount after |
| --- | --- | --- | --- | --- |
| 60 Hz | 0.0 | 0.0 | 0.07 | 0.07 |
| 120 Hz | 17.9 | 0.0 | 19.7 | 0.07 |
| 144 Hz | 16.4 | 0.0 | 18.0 | 0.06 |
| 165 Hz | 15.3 | 0.001 | 16.8 | 0.08 |

(The weapon mount's remaining 0.07 is the run clip's own motion, the same at 60 Hz.) A zombie view crossing a still
camera at 2.5 m/s at 144 Hz: 3.1 before, 0.16 after.

The test (`tests/player/test_side_on_smoothness.gd`) reads where the renderer draws the chest
(`get_global_transform_interpolated()`) against the camera, over 60 ticks of steady strafing. The soldier must stay
within 2 px of one place on a 1920x1080 view at 100, 144 and 165 frames a second. With the project setting off it
wanders 38 to 44 px; with the rig left interpolated, 10 to 11 px; now below 0.002.

## Why the test runs the game in a child process

The first version ran the frames in the test's own process and failed on a loaded machine (11.7 px on CI, 55 px on a
busy desktop) with nothing wrong in the blend. Two things come from the real clock there and a script cannot set
either: the length of each frame, and `Engine.get_physics_interpolation_fraction()`. The camera follows the body with a
spring that samples the body once per frame, so it trails by half a frame's length; uneven frames therefore move the
soldier on the screen by pixels (a 3 ms jitter in the loop was enough for 3 px). Waiting for a stretch of calm frames
only moved the failure to the machines that never had one.

`--fixed-fps N` fixes the length of every frame and so which fraction of a tick each one falls on, but it is a
command-line option. The test therefore starts a second Godot (`OS.execute(OS.get_executable_path(), ...)`) on
`tests/player/side_on_probe.tscn` with `--headless --fixed-fps N`, which prints one `WANDER` line, and reads it back.
The same frames come out on every machine (the second run prints the same number), and it needs no window: the screen
position is `Camera3D.unproject_position`. Two control cases run the probe with the body not interpolated and with the
rig interpolated twice, and must show more than 5 px, so the measure is known to see the faults on every run.
Reverting either part of #352 fails the main case at all three rates.

`tests/player/night_side_on_probe.tscn` is the same measure in the real night, put under a `Control` as `NightScreen`
does, and prints the RMS of the second difference of the soldier's screen x (`UNEVEN`, pixels of a 1920x1080 view):
0.19, 0.10, 0.07 at 100, 144, 165 fps as shipped; 42.7, 43.6, 40.7 when the night leaves the setting to its screen
(`--mode=inherit`). `test_side_on_smoothness.gd` runs both.

## The web build, measured (#353)

`tools/web_smoke/judder.py` opens the build in Chrome, starts a night, strafes left and right for 18 s and records, for
every frame the browser draws, where the soldier's chest is on the screen as the renderer draws it
(`game/core/judder_probe.gd` writes the rows into `window.deadnight.frames` when the page sets `record`). It then takes
the stretches of steady strafing (away from the turns, with the camera not pushed in by a wall) and reports the
unevenness: the RMS of how far each frame's screen x is from the straight line between its neighbours, drawn at the
frames' own times, so a slow frame does not count and a body that steps does. Chrome with the machine's GPU
(`--gpu`, RTX 5080, ANGLE D3D11, a 240 Hz display); `--unpaced` lifts the frame limit (`--disable-gpu-vsync
--disable-frame-rate-limit`, 400 to 500 frames a second). Local export of the same code, with and without the fix:

| Run | Frames a second | Unevenness before | Unevenness after |
| --- | --- | --- | --- |
| Paced by the display (240 Hz) | 240 | 9.06 px | 0.26 px |
| Unpaced | 430 to 510 | 6.23 px | 1.09 px |

Before, the chest moved in 60 Hz steps (a 24 px saw tooth of the 1920 view while the camera glided); after, it holds
one place. What is left unpaced is the real clock: frames of 2 ms with spikes to 5 to 14 ms, over a camera that samples
the body once per frame (the same reason the desktop test runs at a fixed frame rate). Pixels, not only the model:
the run can keep consecutive cropped frames (`--clip N`), and the hood's edge in them stepped by 8 to 10 px every
tick before and held within 1 to 2 px after.

The live site serves the build of `main` (the `.wasm` and `.js` match a local export of that commit byte for byte, the
`.pck` differs by a few editor-side script files), with `Cache-Control: no-cache` and an ETag on every file and no
service worker (`progressive_web_app/enabled=false`): a returning player is never held on an old build.

## Rules that came out of it

- A node that moves in `_process` or in a tween is not drawn right by physics interpolation. Either move it in the tick
  or set its `physics_interpolation_mode` to OFF.
- A node that is placed somewhere new needs `reset_physics_interpolation()` after the new transform is set.
- Physics interpolation is inherited down the tree and a `Control` switches it off: a 3D world under a screen needs its
  own root set to ON, and the proof is made in the tree the game builds, not in a test room.
- Hand blends and engine blends do not stack: a node that blends by hand is OFF in the engine.
- Skinned bones are not interpolated: the animation runs on the drawn frame (it is time-driven, so it is smooth).
- A client that gets snapshots from the network (not from the loopback tick) places its views off the physics tick:
  those views need a blend of their own (issue #105), not this setting.
- Measure with a frame rate that is not a multiple of the tick rate, and by the position on the screen, not the node's
  position: the node's `global_transform` never shows the blend.

The general findings (for every game) are written up for the kit's docs hub as `docs/godot/physics-interpolation.md`.
