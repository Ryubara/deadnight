# Camera shake

A shot gives the view a small kick: "very subtle, but there". It is the player's own view only, per weapon, trauma
style, and it never moves the aim. The code is `game/gameplay/player/camera_shake.gd` and `third_person_camera.gd`;
`game/tests/player/test_camera_shake.gd` pins the behaviour. Why trauma and how others do it:
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
for the two frames the picture is off by up to 0.6 degrees the reticle sits that far from where the shot goes; that is
the price of a shake you can see, and it is under the spread of the weapons that shake most.

## The numbers

All are exports on `PlayerTuning` (group Shake) or `WeaponDef` (group Feel), editable in the Godot editor.

| Number | Value | Why |
| --- | --- | --- |
| `shake_max_degrees` | 1.5 | the turn at trauma 1: the ceiling, reached only by stacking |
| `shake_decay` | 2.6 per second | a shotgun blast (0.65) is over in 0.25 s, a pistol shot (0.30) in 0.12 s |
| `shake_exponent` | 2 | the classic trauma curve |
| `shake_frequency` | 14 per second | a quick tremor, not a sway |
| `shake_roll_fraction` | 0.4 | |

| Weapon | `shake_trauma` | Peak turn (degrees) |
| --- | ---: | ---: |
| Pistol | 0.30 | 0.14 |
| SMG | 0.20 | 0.06 (a whole magazine stacks to about 0.2) |
| Rifle | 0.45 | 0.30 |
| Shotgun | 0.65 | 0.63 |
| Flare gun | 0.40 | 0.24 |
| Crowbar | 0 | none |

A test keeps every weapon under one degree and orders the guns (shotgun above rifle above pistol above SMG).

## The player's setting

Settings, Accessibility, **Camera shake**: 0 to 100 percent in steps of 10, default 100 (`accessibility/camera_shake`).
`PlayerSettings.camera_shake` scales the shake (`CameraShake.scale`); 0 turns it off and trauma is not even kept. It is
also **off while Reduced motion is on**, so one switch quiets the screens and the camera. The player re-reads it when
any setting changes.
