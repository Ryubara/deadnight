# Hip fire in third-person shooters

What third-person shooters do when the player fires without aiming down the sights, and what Deadnight does (#300,
maintainer feedback 2026-11-01: "the hitscan lands where expected [...] but the character doesn't rotate
automatically, and also doesn't auto zoom in as if they were aiming, just like other third person controllers").
The numbers and the code are in [the shoulder camera](shoulder-camera.md#hip-fire).

## What is public, and what is not

No developer talk or manual that we could find states a hip-fire turn speed, hold time or zoom amount for a named
game, so **every number in Deadnight is a design choice, not a measurement**. What the engines and controller kits
document is the *mechanism*, and it is the same everywhere:

| Fact | Source |
| --- | --- |
| Unreal's third-person template turns the body to its movement direction (`Orient Rotation to Movement`); the common fix for a shooter is to switch that off and drive the body's yaw from the controller (`Use Controller Rotation Yaw`), usually only while aiming or firing, with a state switch rather than both on at once. | Epic forum answers: [make the player face where the camera looks](https://forums.unrealengine.com/t/how-do-make-player-face-forwards-where-the-follow-camera-is-looking-3rd-person-shooter/148825), [orient rotation to camera](https://forums.unrealengine.com/t/orient-rotation-to-camera/480253) |
| A hip-fire state that is not wired into the movement logic loses to the move-facing state: the body keeps its walking yaw, the symptom the maintainer described. | [Epic forum thread on facing the camera at zero velocity](https://forums.unrealengine.com/t/gasp-ue-5-5-cant-seem-to-get-player-to-face-along-the-camera-at-0-velocity/2484990) |
| A strafing system keeps the character facing the camera direction while the legs animate by movement direction, with a turn-rate setting where the default is an instant turn and a finite value gives a gradual one. | [Overdare TPS strafing system](https://docs.overdare.com/script-manual/tps-strafing-system) |
| A combat movement type requests the character's yaw from the camera's look direction rather than the travel direction, so the character strafes while facing the view; aim adds target-facing and optional zoom presets on top. | [Opsive Ultimate Character Controller, Third Person Combat](https://opsive.com/support/documentation/ultimate-character-controller/character/movement-types/included-movement-types/third-person-combat/) |
| Keeping the aim point locked to the screen centre while the camera blends to an aiming camera is the hard part; the usual answer is a ray from the camera through the centre. | [Cinemachine 3 third-person cameras](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/ThirdPersonCameras.html) |

## What Deadnight does, and why

- **Hip fire is the aim, held for a moment** (maintainer, playing, reopening #300: "The logic should be the same
  camera wise with or without aiming no matter when they're shooting, aiming is just a precheck that skips it if
  already aiming"). A first version gave hip fire its own half zoom with its own springs and left the weapon on the aim
  button alone, which showed as a second, partial aim: the gun jumped into the aim pose when the button was pressed, did
  not rise when shooting, and the zoom-out was three times slower. There is now one weight (`aiming or fire_age <
  hold`) for the camera, the body, the legs and the hands, and one set of springs.
- **Face the view while the aim is held** (not always, as the combat kit above does): walking should still turn the
  soldier to where he runs, because the dead come from every side and the player flees as much as fights. The hold
  (0.8 s) hides the swing back between single shots and keeps the camera from pulsing between the slowest weapon's
  shots.
- **Turn fast but not instantly**: 8 rad/s, 0.16 s for a view 75 degrees away. A snap makes the shoulders pop and the
  weapon jump; the finite rate is the documented option (the strafing system's turn rate). It is slower than the first
  version (22 and 24) because the weapon turns with the body *and* with the aim weight and the two add up.
- **Zoom all the way**, as the aim does. What stays different is what the button does on top of it: a slower walk
  (`aim_speed`) and a steadier look (`steady_amount()`, its own ease on the real button), because a burst from the hip
  should not slow the view.
- **The shot never moves**: the reticle sits on the camera ray whatever the body or the zoom does, as the Cinemachine
  note says it should; `AimResolver` already aimed the muzzle at that point.
- **The server turns the body**: facing is simulated state and the muzzle is rotated by it, so the trigger travels in
  the player's command and the server decides the turn (no client-only rotation that a replay would disagree with).
- **Firing is a strafe for the movement**: once the movement turned the body to its heading with pivot rules (#354),
  a body facing the view looked like one that must turn before it hurries, so a player backing away while shooting
  crawled. While the trigger is held (and for the hold after) the velocity goes straight to the input, as when aiming
  (`test_firing_while_backing_away_keeps_the_run_speed`).

## Open

- Whether a sprinting player should lose the sprint when firing (many shooters do). Not changed here: the bots run and
  shoot together and the balance gate is tuned on it.
- Touch (#272, #286): a drag-to-look phone player fires with a button; the turn works the same, and an auto-fire
  would hold the trigger and so the zoom. Revisit when #286 lands.
