# Physics interpolation: the soldier seen from the side

The player's body moves on 60 Hz physics ticks. A screen that draws more often than that (120, 144, 165 Hz) shows the
body at its last tick for two or three frames, then jumps. Seen from the side while strafing, the jump is across the
view: the soldier looks doubled and blurry (issue #344). Godot 4.7.2, Compatibility renderer.

## What was wrong

`ThirdPersonCamera` already blended the last two ticks of the body by hand (`Engine.get_physics_interpolation_fraction()`),
so the camera moved smoothly while the body, drawn at its tick position, did not. The picture is the difference of the
two: the soldier swung by a whole tick of travel (0.08 m, 18 px at 1280x720) every two or three frames. At 60 Hz the
frames and ticks coincide and nothing shows, which is why it is only seen on a fast screen.

## What we did

- `physics/common/physics_interpolation` is on (`project.godot`). The renderer blends every node that moves in
  `_physics_process` between its last two ticks: the body, the weapon in its hand (the `BoneAttachment3D` under the
  skeleton), the zombies' views, which are placed in the tick that delivers a snapshot, the prize crane.
- The camera rig is **not** interpolated by the engine (`physics_interpolation_mode = OFF` in `ThirdPersonCamera.setup`).
  It is placed every drawn frame from the body's last two tick positions, and an engine blend on top of that is a second
  one: with the rig left on, the soldier still wandered 11 px on the screen (measured, below). Its own blend is not
  removed: it reads the same two tick positions and the same fraction as the engine's, so body and camera agree.
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
(`get_global_transform_interpolated()`) against the camera, in frames that run many to a tick. The soldier must stay
within 2 px of one place on a 1920x1080 view while strafing at a steady pace. On `main` it wanders 47 px; with the
rig left interpolated, 11 px; now below 0.6. It skips frames around a long one (a loaded machine), where the body and
camera really do move together and the camera's spring takes half a second to follow.

## Rules that came out of it

- A node that moves in `_process` or in a tween is not drawn right by physics interpolation. Either move it in the tick
  or set its `physics_interpolation_mode` to OFF.
- A node that is placed somewhere new needs `reset_physics_interpolation()` after the new transform is set.
- Hand blends and engine blends do not stack: a node that blends by hand is OFF in the engine.
- Skinned bones are not interpolated: the animation runs on the drawn frame (it is time-driven, so it is smooth).
- A client that gets snapshots from the network (not from the loopback tick) places its views off the physics tick:
  those views need a blend of their own (issue #105), not this setting.
- Measure with a frame rate that is not a multiple of the tick rate, and by the position on the screen, not the node's
  position: the node's `global_transform` never shows the blend.

The general findings (for every game) are written up for the kit's docs hub as `docs/godot/physics-interpolation.md`.
