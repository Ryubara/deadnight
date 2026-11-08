# Hip fire in third-person shooters

What third-person shooters do when the player fires without aiming down the sights, and what Deadnight does (#300,
maintainer feedback 2026-11-01: the shots landed where expected, but the character neither turned nor zoomed in as if
aiming, as other third-person controllers do).
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

- **Hip fire turns the body and raises the weapon, and never zooms** (the maintainer, #464, 2026-11-02, after testing
  the Discord Activity, decided to drop the zoom from hip fire entirely and keep it for aiming, open to revisiting
  later). The history: a first version
  gave hip fire its own half zoom and left the weapon on the aim button alone (a second, partial aim: the gun jumped
  into the aim pose when the button was pressed); #417 made it the aim held for a moment, one weight for the camera,
  the body and the hands (`aiming or fire_age < hold`), on the maintainer's point that the camera logic should be the
  same with or without aiming (#300); the zoom then showed up where it was not wanted, in aim, shoot, release (#428,
  #433: a shot fired while aiming no longer restarts the hold) and finally on every shot. Now the camera reads the aim
  button only (60 to 40 degrees and back, `test_hip_fire.gd`, `test_aim_release.gd`), and the body's turn, the legs'
  aim gait and the weapon's pose read the hold (`PlayerMotionState.holds_aim`). Revisiting a small hip-fire zoom later
  is one more input of `ThirdPersonCamera`; nothing else has to change.
- **Face the view while the aim is held** (not always, as the combat kit above does): walking should still turn the
  soldier to where he runs, because the dead come from every side and the player flees as much as fights. The hold
  (0.8 s) hides the swing back between single shots and keeps the camera from pulsing between the slowest weapon's
  shots.
- **Turn fast but not instantly**: 8 rad/s, 0.16 s for a view 75 degrees away. A snap makes the shoulders pop and the
  weapon jump; the finite rate is the documented option (the strafing system's turn rate). It is slower than the first
  version (22 and 24) because the weapon turns with the body *and* with the aim weight and the two add up.
- **The button does more than the zoom**: a slower walk (`aim_speed`) and a steadier look (`steady_amount()`), both
  for the real aim button only, because a burst from the hip should not slow the view.
- **The shot never moves**: the reticle sits on the camera ray whatever the body or the zoom does, as the Cinemachine
  note says it should; `AimResolver` already aimed the muzzle at that point.
- **The server turns the body**: facing is simulated state and the muzzle is rotated by it, so the trigger travels in
  the player's command and the server decides the turn (no client-only rotation that a replay would disagree with).
- **Firing is a strafe for the movement**: once the movement turned the body to its heading with pivot rules (#354),
  a body facing the view looked like one that must turn before it hurries, so a player backing away while shooting
  crawled. While the trigger is held (and for the hold after) the velocity goes straight to the input, as when aiming
  (`test_firing_while_backing_away_keeps_the_run_speed`).

## Turn first, then shoot (#477)

The maintainer, playing the Discord Activity (2026-11-02), found the hip-fire turn right but asked that the character
finish turning to the cursor before the gun fires: a player walking one way who hip-fires at a zombie behind expects
the shot once the body has come round to the centre of the screen, and a press made mid-turn holds the shot until
then. The turn was already
there (the hold above); the shot was not tied to it: the server shot on the trigger alone, from the camera ray, so a
soldier walking away fired through his own back on the press and turned afterwards.

**What is public, and what is not** (searched 2026-11-02; as with the zoom, the named games' own rules are not
published):

- No source found states a rule like "the shot waits for the body" for Gears, Uncharted, The Last of Us or Fortnite.
  Naughty Dog's GDC 2024 talk on The Last of Us Part II gunplay (Derek Mattson, "A Second Shot: Improving Ranged") lists
  "camera vs character perception, weapon feel, hit detection and input delay" as its problems, which is this one, but
  the abstract has no numbers: <https://www.gdcvault.com/play/1034215/A-Second-Shot-Improving-Ranged>.
- The mismatch itself is documented: the player sees the camera, the character has a body, and the shot has to join
  them. Forrest Smith (Monday Night Combat) traces from the camera through the crosshair first, then from the hand to
  the barrel tip, and notes shooting from the hip fails more often because the barrel is further from the crosshair on
  the screen: <https://www.forrestthewoods.com/blog/adventures_with_guns_in_a_third_person_shooter/>. Deadnight
  already does the first half (`AimResolver` aims the muzzle at what the camera ray hits); this change handles the
  second, a muzzle that is on the wrong side of the body.
- Engines that ship a third-person combat controller turn the body to the camera's yaw during weapon use rather than
  letting the weapon point anywhere: Opsive's Ultimate Character Controller "Third Person Combat" movement "requests
  character yaw from the attached look source", with a motor rotation speed for the alignment, and no dead zone or
  hold-the-shot setting documented:
  <https://opsive.com/support/documentation/ultimate-character-controller/character/movement-types/included-movement-types/third-person-combat/>.
  Unreal's usual answer is an aim offset (the upper body bends toward the aim, so the weapon follows the crosshair while
  the feet keep the walk) with turn-in-place clips past a yaw threshold (45, 90 and 180 degree turns appear in
  community write-ups): <https://dev.epicgames.com/documentation/unreal-engine/creating-an-aim-offset-in-unreal-engine>.
  Deadnight has no aim offset: the whole body turns, so it is the first, not the second.
- Buffering a press so an early input still counts when the action becomes available is the standard answer to "the
  button came a moment before the character could use it" (a stored press time, a window in seconds, a used flag; a
  100 ms window in the example): <https://www.wayline.io/blog/art-of-input-buffering>. The window there is for an
  action that is blocked for a frame or two; here the block is a turn, so the window is sized to the turn.

So the rule is the maintainer's, built from those parts: **a shot leaves when the body faces the view, within a
tolerance; a press before that is kept for a short buffer; a held trigger waits as long as it takes.**

**The math** (all in `PlayerSimulation._gate_shot`; `angle_difference(from, to)` in Godot is `to - from` wrapped to
[-pi, pi], so it is the shortest signed way round, and `rotate_toward` turns at a fixed rate without overshooting):

- Error: `e = abs(angle_difference(facing, view_yaw))`, 0 to pi. The body turns first (`_face`), then the gate reads the
  error after this tick's turn, so a view 17 degrees away is one tick of turn (7.6 degrees) from within the tolerance
  and is ready at once, and the same inputs give the same answer on the server and on a replaying client.
- Turn rate: `aim_turn_speed` = 8 rad/s = 458 degrees a second = 7.6 degrees a tick at 60 Hz.
- Time to align: `t = max(e - tol, 0) / 8 rad/s`. 45 degrees 0.08 s (5 ticks), 90 degrees 0.18 s (11 ticks), 180
  degrees 0.37 s (23 ticks). A hip shot at the soldier's back is held for at most about a third of a second, and the
  common side shot for a tenth.
- A view that moves at `w` rad/s while the body turns at `W` closes the gap at `W - w`: faster than 8 rad/s (a flick,
  not a drag) and the gap never closes, the shot waits and the body keeps turning. When the view stops it is within
  `e / W`. A view that laps the body (it passes 180 degrees away and comes back round) is the shortest-delta wrap at
  work, not a bug: `angle_difference` is the distance the body would turn.
- Buffer: `hip_fire_buffer` 0.6 s, longer than the 0.37 s worst turn, shorter than a second so a press from long ago
  does not fire out of nowhere. A tap is the rising edge of the trigger (`trigger_down` in the state, so a replay
  agrees); it arms `shot_buffer`, which runs down by the tick and is cleared the tick the shot is ready, so a tap fires
  exactly once. The body keeps turning after the tap for the 0.8 s `hip_fire_hold`, which is longer than the buffer.
- Tolerance: `hip_fire_align_degrees` 10. At least one tick of turn (7.6) so the body cannot step over the window and
  make the shot wait a whole extra tick. At most what the muzzle can tolerate: it sits 0.5 m from the body's centre
  (`muzzle_offset` 0.3 m right, 0.4 m forward), so a body 10 degrees off puts it `0.5 sin 10` = 0.09 m beside where it
  would be, which at the 12 m the weapon converges on is 0.41 degrees: less than the smallest spread any gun that has
  one (0.6, the others 2.2 and 5; three have none). The shot's direction is the camera ray's whatever the body does;
  the tolerance only bounds where it leaves from.

**What changed in the code.** `PlayerSimulation` computes `state.shot_ready` every tick (the trigger is held or a press
is buffered, and the body faces the view within the tolerance, or the aim button is down: the aim has always turned the
body and is unchanged). `NightServer._act` shoots when `shot_ready`, not when the trigger is down. A predicting client
runs the same simulation from the same commands, so it knows the tick a shot leaves and a replay from an older state
gets the same ticks (`test_a_replay_from_an_older_state_is_ready_on_the_same_ticks`). Effects stay driven by the
server's `shot_fired`, so nothing flashes or sounds before the shot exists.

**The bot had to look where it shoots.** Before #511 the Autopilot sent its walking direction as the view
(`motion.yaw`) and the target as the ray (`dir`), so the gate held its shots for every turn of its path, not of its aim:
it took 574 frames to make 14 kills where `main` took 464, and the kill-allocation test (`test_kill_allocations.gd`)
failed on the extra sounds of a slower fight (54 to 66 objects held against a slack of 48). With the gate opened wide
the run was `main`'s to the frame, so the gate was the cause, not a leak. #511 made the bot look along its aim
(`NightCommand.aim_along`, the walk turned into a stick push under that view) for its own shot-follows-view check, which
is what this gate needs too: a bot that looks where it walks while it shoots is held here and refused there. One piece
was left: it chose its target with the barrel placed along its walking heading, so the zombie it could "see" changed as
it walked, the view flipped between targets 60 degrees apart and the body chased each one (515 frames, 77 objects held).
The barrel is now placed along the heading to the target, where the body will turn to fire: 395 frames, 44 shots, 14
objects held, `main`'s numbers.

**Proof in the browser** (`tools/web_smoke/hip_fire.py`, scenario 4; software GL, 10 to 15 frames a second, 2026-11-02):
the view is turned about 167 degrees from the body with the page's own mouse events, then the trigger is tapped (150
ms) or held. Tap: the one shot is ready 0.28 s after the press, with the body within 10 degrees, on one drawn frame.
Held: the first shot is ready 0.345 s after the press (the 0.37 s of the maths above, less the tolerance), then stays
ready. Two traps the probe had to learn:

- **A one-tick flag sampled once a frame misses a tap.** `shot_ready` is true for one physics tick on a tap, and a slow
  browser draws a frame every 4 to 6 ticks, so reading it in `_process` saw the held trigger (many ticks) and lost the
  tap. `ViewWebProbe` now latches it in `_physics_process` and clears it when it writes the row.
- **A dead player measures nothing.** A night of zombies ends within a minute on the software renderer, and a run of
  seven scenarios outlasts it: the turn-first screenshot was the "You did not make it" panel. `scenario()` starts a
  fresh night when the old one is over (before the scenario, or under it) and runs it once more; `new_nights` in
  `result.json` counts them.

## Open

- Not measured: whether a very short click is lost. `Input.is_action_pressed("fire")` is read once per physics tick, so
  a press and release that both land between two reads would leave nothing (the probe's tap is 150 ms, a real click's
  length; its first try of 60 ms failed, but that was the sampling trap above, so it says nothing about the game).
  A latched press (`Input.is_action_just_pressed` in `_input`) would close it if a slow device shows it.
- Whether a sprinting player should lose the sprint when firing (many shooters do). Not changed here: the bots run and
  shoot together and the balance gate is tuned on it.
- Touch (#272, #286): a drag-to-look phone player fires with a button; the turn works the same, and an auto-fire
  would hold the trigger and so the body's turn and the weapon's pose (not the camera, #464). Revisit when #286 lands.
