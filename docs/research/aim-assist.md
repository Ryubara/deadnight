# Touch aim assist and auto-fire

What helps a thumb aim at a moving zombie, what Deadnight does about it (#286), and how much it is worth, measured with
a bot and in the balance simulator. The controls themselves are in [Mobile controls](mobile-controls.md) and
[Touch controls](../design/touch-controls.md); this page answers their open questions 1 (auto-fire) and 2 (assist
strength).

## What the public guidance says

- "Aim assist and auto shoot reduce the burden of tracking and acquiring targets" on a touch screen, whose basic
  problems are the thumb covering what it aims at and a coarse finger
  ([Game Developer, 2016](https://www.gamedeveloper.com/game-platforms/ux-deep-dive-painful-reality-of-building-fps-experiences-on-mobile---part-1)).
- A shooter on phones that fires for the player when the crosshair is on an enemy ("simple" mode) is easy to start with
  and wastes ammunition; players are advised to move on to a fire button
  ([GGRecon](https://www.ggrecon.com/guides/best-call-of-duty-mobile-season-9-settings-guide/)). With limited
  ammunition, auto-fire was first an option the player turns on; the maintainer decided otherwise in #470 (see the
  answers below).
- *Common practice* (not tied to one primary source): **friction** slows the look speed while the crosshair is over a
  target, **magnetism** pulls the view a little toward it, both strongest on touch and with a strength the player can
  set. Both are tuned by play.

## What Deadnight does

All of it is for touch alone: the touch layer must be up **and** a finger must be the last input
(`UIInputMode.touch`), so a mouse or a pad on the same machine gets nothing. The code is `AimAssist` (pure functions on
plain data, `game/gameplay/player/`), `TouchAimAssist` (the night's driver, `game/gameplay/night/`) and the numbers in
`AimAssistTuning`.

| Help | What it does | When |
| --- | --- | --- |
| Friction | Multiplies the look drag by `1 - 0.6 * strength * closeness`, down to 0.4 on the middle of a zombie at full strength | Whenever a zombie is near the crosshair's ray |
| Magnetism | Closes part of the angle from the view to the zombie's chest each tick, at most 0.9 rad/s at full strength | Only while Aim or Fire is held, and not while the thumb turns the view quickly (it is gone at 2 rad/s, half gone at 1) |
| Auto-fire | Holds the trigger while the crosshair is on a hit zone within 25 m (the same ray test as a shot, `Hitbox.ray`) | Only with the setting on (the default) and while the player aims; with it off Aim is a toggle and the trigger is left alone |

- The target is the zombie whose chest the crosshair's ray passes nearest, as a share of the capture radius (1.1 m at
  full strength, 0.44 m at near zero, times the zombie's size). Zombies behind the view, farther than 30 m, dying or
  behind a wall (`WorldProbe`, the ray the shots use) are not helped.
- It reads only the client's picture of the night (`ClientState`: the zombie list of the last frame, the player's
  weapon, ammunition and reload flag), so it works the same on a local night and on a game server, and the server still
  decides every hit. The nudge goes into the camera rig's yaw and pitch like a hand would
  (`ThirdPersonCamera.nudge`); the command the server reads is the view as it is after it.
- Auto-fire does not fire an empty gun, a reloading one or a downed player's, and a melee weapon only within its arm.
- Settings (the Touch tab): **Touch aim assist** 0 to 1, default 0.5 (gentle: a mouse player and a touch
  player face the same zombies), and **Touch auto-fire** Off or On, default On (a saved "always" counts as On).

## Answers to the open questions

1. **Auto-fire** was off by default (ammunition is limited) with a "While aiming" and an "Always" choice. The
   maintainer decided in #470: **on by default**, firing only while the player aims with the crosshair on a zombie in
   reach (never beyond 25 m, whatever the gun reaches), and with it **off** the Aim button is a toggle, so the player
   aims and shoots by hand. The Fire button shoots wherever the player aims, in both. "Always" is gone.
2. **Assist strength**: friction plus magnetism, at 0.5 by default; the player sets 0 (off) to 1. The strength scales
   both the effect and the capture radius.

## How much it is worth

**The thumb bot** (`game/tests/player/thumb_bot.gd`, `test_aim_assist_bot.gd`): a modelled thumb with a held trigger
follows the nearest of seven zombies that walk in at 1.1 m/s. It follows with a lag of 0.3 s, turns with a noisy,
wandering drag, and every tick counts whether the crosshair is on a hit zone. Twelve seeds of 60 s each, the same
`AimAssist` calls as in the game:

| Strength | Ticks on a zombie | Of the misses, won back |
| --- | --- | --- |
| 0 (off) | 48.4 % | 0 |
| 0.25 | 50.0 % | 3 % |
| 0.5 (default) | 54.3 % | 11 % |
| 0.75 | 61.1 % | 25 % |
| 1.0 | 68.7 % | 39 % |

The curve is steep at the top on purpose: the default is a light help, and the top of the slider is the strong one.
Fitted, the win is `0.39 * strength^1.8` of the misses (`AimAssistTuning.accuracy_gain` and `accuracy_curve`); the test
fails when the assist moves away from that by more than four points.

**The balance simulator** (`SimSkill.with_touch_assist`, `balance_cli.gd --assist=0.5`, the test
`test_balance_touch_assist.gd`) adds that win to a modelled player's accuracy and changes nothing else. Mean round
reached in 60 seeded nights, one player:

| Player | No assist | Assist 0.5 | Assist 1.0 |
| --- | --- | --- | --- |
| Weak | 4.3 | 5.5 | 7.6 |
| Average | 9.1 | not run | 10.8 |
| Strong | 11.8 | not run | not run |

The assist is worth having (a weak player with it reaches the round 3 rounds further at full strength) and does not
break co-op: a weak player with the full assist stays behind an average one without it, and an average one with it
behind a strong one. The balance gate's own cells (`test_balance_targets.gd`) never use the assist, so the shipped
targets did not move.

## In a browser

`tools/web_smoke/touch_assist.py` exports a copy of the project that starts on `tests/captures/touch_assist_bench.tscn`
(the real export leaves `tests/` out): the game's own night screen with the touch layer forced on (`?touch=1`), one
zombie held beside the crosshair (`AssistRig`). In headless Chrome with touch emulation (844 x 390, a real GPU) it sends
real touches through the DevTools protocol: a finger on the look area that drags toward the zombie and stops 0.55 m
short, then a finger on Aim. Once with the assist off and once at 0.5 with auto-fire while aiming:

| Run | Crosshair from the chest | Shots | Kills | Longest frame after the first draw |
| --- | --- | --- | --- | --- |
| Off | 0.42 m (a miss) | 0 | 0 | 23 ms |
| Assist 0.5, auto-fire while aiming | on the zombie | 2 | 2 | 94 ms (the shot) |

No console error or page error in either run, and the game saw a finger as the last input
(`UIInputMode.touch`) through the browser's own touch events, which is what turns the assist on.

The run is repeatable (`--runs N` repeats both runs on one export; 10 of 10 pass, the view turns 0.143 rad in three
drag steps from 1.17 m to 0.46 m off the chest every time). Two things made it flaky before (#490): the bench set the
mouse visible but left the player's request for the lock standing, which the grip reads as a lock lost, so the night
paused itself (3 of 3 runs on a loaded machine) and the touch layer went dead; and the zombie was placed while the
shoulder camera still eased in, so the view often started 0.44 m off, under the 0.55 m stop, and the drag never ran (a
pass that proved nothing). The bench now withdraws the request (`grip.want(false)`), waits for the lens to be still
and places the zombie then; the probe fails on a paused night, on a start too near to need a drag, and on a yaw that
does not change, and prints the yaw and distance at each drag step.

Found while building the run:

- **The shoulder camera's lens orbits the pivot**, so a world-fixed zombie changes its angle from the lens when the view
  turns, and again when Aim zooms in: a drag that left the crosshair 0.4 m off the chest left it 1.15 m off after the
  aim zoom, outside the capture. The capture is in metres at the target for that reason; a thumb that holds Aim while it
  closes in is helped, one that taps Aim from far off is not.
- **`TouchAimAssist` re-reads the settings whenever one changes** (the first-run hints write one), so a bench or test
  that sets `assist.strength` directly is overwritten at the first touch; set the setting instead, as the player does.
- **The client's zombie list lags the server's** by the time a zombie spends coming out of the ground: a run that
  starts on the first zombie of the server has no target for the assist yet. Wait for `ClientState.zombies`.
- A truck parked against the camera hides a zombie behind it, and the assist rightly ignores it (a wall in the way,
  `WorldProbe`); `AssistRig` turns the view to open ground first.

## Not done, and not known

- The bot's thumb is a model, and its absolute numbers are not a player's. What the test holds fixed is the *assist*:
  its relative win over the same thumb, and that the simulator's constants are that measurement.
- Feel on a real phone (whether 0.5 is gentle enough, whether magnetism is noticed) has not been tried by a person; the
  strength is a setting for that reason. A device test in a Discord Activity is still open.
- The aim point is a walker's chest scaled by `ZombieModels.aim_scale`; a crawler's low body is helped like the rest.
- The weak spot of a boss is not aimed for: the assist helps with the body, and the headshot stays the player's.
