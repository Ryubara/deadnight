# Camera shake

A shot gives the view a small kick, and a sprint a gentle sway: "very subtle, but there". Both are the player's own
view only and neither moves the aim. The code is `game/gameplay/player/camera_shake.gd` (the shot),
`sprint_sway.gd` (the sprint) and `third_person_camera.gd`; `game/tests/player/test_camera_shake.gd` and
`test_sprint_sway.gd` pin the behaviour. Why trauma and how others do it:
[Shot feedback research](../research/shot-feedback.md).

## How it works

- A shot adds **trauma** (0 to 1) to the shooter's `CameraShake`: the weapon's `WeaponDef.shake_trauma`, summed and
  capped at 1. `NightView` does it on `shot_fired` when the shooter is the local player (`ClientState.player_id`), so a
  remote player's shot shakes nobody's view.
- Trauma drains at `shake_decay` a second, linearly, and the shake is `max_degrees x trauma^exponent x noise`. The
  square means a light shot is barely felt and shots that come close together add up and are felt more.
- The **noise** is `FastNoiseLite` (smooth simplex) read at `time x shake_frequency` on its own line for pitch, yaw and
  roll; time is the sum of the steps it was given, never the clock, so tests and captures see the same shake.
- **Rotation only**, about the lens: no translation, so nothing slides against the walls and the camera's wall sweep
  is untouched. Roll is a fraction of pitch and yaw (roll reads as sickness).

## The aim stays true

The lens node (`Camera3D`) turns by the shake; the rig keeps the unshaken view as `aim_transform()`, and everything that
aims reads that: `HumanController` (the ray sent with each shot), the weapon's converge point in `PlayerAnimation`.
A test shakes with trauma 1 for half a second and checks the aim origin and direction do not change in the fifth
decimal while the lens is off by more than a tenth of a degree. The crosshair is the middle of the *shaken* picture, so
for the two frames the picture is off by up to 0.5 degrees the reticle sits that far from where the shot goes; that is
the price of a shake you can see, and it is under the spread of the weapons that shake most.

## The numbers

All are exports on `PlayerTuning` (group Shake) or `WeaponDef` (group Feel), editable in the Godot editor.

| Number | Value | Why |
| --- | --- | --- |
| `shake_max_degrees` | 1.5 | the turn at trauma 1: the ceiling, reached only by stacking |
| `shake_decay` | 2.6 per second | a shotgun blast (0.55) is over in 0.21 s, a pistol shot (0.30) in 0.12 s |
| `shake_exponent` | 2 | the classic trauma curve |
| `shake_frequency` | 14 per second | a quick tremor, not a sway |
| `shake_roll_fraction` | 0.4 | |

| Weapon | `shake_trauma` | Peak turn (degrees) |
| --- | ---: | ---: |
| Pistol | 0.30 | 0.14 |
| SMG | 0.20 | 0.06 (a whole magazine stacks to about 0.2) |
| Rifle | 0.45 | 0.30 |
| Shotgun | 0.55 | 0.45 |
| Flare gun | 0.40 | 0.24 |
| Crowbar | 0 | none |

A test keeps every weapon under half a degree (the shotgun was 0.63 and was brought down to 0.45) and
orders the guns (shotgun above rifle above pistol above SMG).

## The player's setting

Settings, Accessibility, **Camera shake**: 0 to 100 percent in steps of 10, default 100 (`accessibility/camera_shake`).
`PlayerSettings.camera_shake` scales the shake (`CameraShake.scale`); 0 turns it off and trauma is not even kept. It is
also **off while Reduced motion is on**, so one switch quiets the screens and the camera. The player re-reads it when
any setting changes.

## The sprint sway

While the body sprints the lens bobs and rolls a hair, in step with the feet. It is rotation only about the lens, like
the shot shake, so the aim ray, the walls sweep and the weapon's aim never see it. `ThirdPersonCamera.sway`
(`SprintSway`) is stepped by the rig each frame from `sprinting` and `ground_speed`, which the player sets after
every tick.

- **Locked to the feet.** The phase counts footfalls: ground speed times the step over `step_distance` (1.9 m, the
  metres per footstep event, and half the 3.9 m the Run clip covers in one cycle at its planted speed of 5.5 m/s).
  So a faster run sways faster (3.7 footfalls a second at 7 m/s), the same stride the animation and the footstep audio
  keep, and a body held against a wall stands still in the picture. No wall time is read.
- **Bob and sway.** Pitch goes through one cycle per footfall (`sprint_sway_bob_steps` 1), roll and yaw through one per
  two footfalls (`sprint_sway_sway_steps` 2), yaw a quarter of a cycle behind roll. `sprint_sway_phase_degrees` slides
  where in the stride a foot lands.
- **Only while sprinting.** `sprinting` and not aiming, and ground speed at least `sprint_sway_min_speed` (3 m/s): none
  while walking, aiming, standing, in the air, or downed (a downed body is ticked with an empty command, so it does not
  sprint). It eases in over `sprint_sway_ease_in` (0.4 s) and out over `sprint_sway_ease_out` (0.3 s), a linear ramp
  through a smoothstep, so the turn never jumps; the phase restarts at zero when the sway is fully out.
- **None in the air.** The feet make the sway, so it belongs to the ground: `ThirdPersonCamera.grounded` (the body's
  `on_floor`, set by the player after each tick) goes into `SprintSway.step`, and on the first tick the body is in the
  air (a jump, a step off a ledge, a fall) the sway is gone **at once**, level and phase to zero, with no ease-out, even
  with the sprint key still held and the body still fast. After landing, with the sprint still held, it comes back with
  the normal ease-in (0.4 s) from nothing. The maintainer saw it keep swaying through a sprint-jump with Shift held
  (issue #405).
- **With the shot shake.** The two turns multiply into one lens turn (the shake first). While trauma is up the sway
  gives way by up to `sprint_sway_fire_duck` (0.5) of itself, so a kick is not buried in the bob and the two never add
  to more than their bounds.
- **The setting.** The same Camera shake slider scales it, and Reduced motion turns it off: the sway reads
  `CameraShake.scale`.

| `PlayerTuning` (group Sprint sway) | Value |
| --- | --- |
| `sprint_sway_pitch_degrees` | 0.2 (was 0.4, and 0.3 before that) |
| `sprint_sway_yaw_degrees` | 0.1 (was 0.2) |
| `sprint_sway_roll_degrees` | 0.14 (was 0.28) |
| `sprint_sway_bob_steps` / `sprint_sway_sway_steps` | 1 / 2 footfalls to a cycle |
| `sprint_sway_phase_degrees` | 0 |
| `sprint_sway_ease_in` / `_ease_out` | 0.4 s / 0.3 s |
| `sprint_sway_min_speed` | 3 m/s |
| `sprint_sway_fire_duck` | 0.5 |

Why so small: Godot's field of view is the vertical one, so 60 degrees over 1080 pixels is about 18 pixels a degree:
0.2 degrees of bob moves the picture about 3 pixels up and down, and 0.14 degrees of roll about 2 pixels at the edge
of the screen. That is felt as a little life in the picture and not read as a wobble. The sway has been halved twice
as the maintainer played: first "very subtle, a bit more than a shot" (0.45 degrees at the largest, level with the
shotgun), then "too intensive, lower this down by 50%" (issue #405): the largest turn of the look direction is now
0.22 degrees (pitch and yaw together), under the quarter degree the test keeps every amplitude below. Measured on the
same run (a sprint, a sprint-jump with Shift held, the landing, in `tests/captures/sprint_camera_tune.tscn`): the
largest turn on the ground was 0.425 degrees before and 0.2125 after, and in the air 0.425 before (it carried on) and
0 after, from the first airborne tick.

## The sprint's other view changes

The sprint also widens the view and lets the camera out (`ThirdPersonCamera`, not shake): `sprint_fov_kick` is 3
degrees (it was 6; the maintainer asked for half, issue #405) and `sprint_arm_extra` 0.15 m (already halved from 0.3).
The default FOV is 60 degrees (it was 70: the maintainer found the view too far outward and wanted it closer to the
character), so a full sprint is 63 and the aim is 40 (`fov_aim`, it was 60). The one aim weight (#417) blends `fov` to
`fov_aim` for the aim button and for a shot from the hip alike, so a hip shot zooms 60 to 40 too (and back after the
0.8 s hold). `arm_length` is unchanged. The
follow lag of the sprint (16 rad/s) is not a shake and stays. No other sprint-driven motion exists: footsteps make no
trauma, and the only caller of `add_shake` is a local player's shot. Test: `test_sprint_camera.gd`. Captures: the pull
request.
