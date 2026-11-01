# Player controller

The third-person, over-the-shoulder player (`game/gameplay/player/`), written while building it. The character is the
Quaternius Toon Shooter Soldier (CC0, `game/assets/characters/soldier/`).

## The network boundary

Deadnight is network-first: an authoritative server, client prediction, and single-player running the same code with
the server in-process. So movement is a function of data, and everything else only reads its result.

```text
controls --sample--> PlayerCommand --\
                                      >-- PlayerSimulation.simulate(body, state, command, tuning, delta) --> PlayerMotionState
network / replay ---> PlayerCommand --/                                                                       |
                                                              camera rig, animation tree, audio hooks <-- read-only
```

| Piece | File | Rule |
| --- | --- | --- |
| `PlayerCommand` | `player_command.gd` | One physics tick of input: move vector, view yaw and pitch, sprint, crouch, jump, aim, swap shoulder. Serializable (`to_bytes` / `from_bytes`). `jump` and `swap_shoulder` are edges (true on the tick the key goes down), the rest are levels. |
| `PlayerMotionState` | `player_motion_state.gd` | Everything carried between ticks: position, velocity, facing, floor flag, sprint and aim flags, shoulder side, coyote and jump-buffer timers, footstep distance. Plus what happened in the tick (`jumped`, `landed`, `footstep`). `copy_from` rewinds it. |
| `PlayerSimulation` | `player_simulation.gd` | `simulate()` reads only its arguments and the physics world, never `Input`, the camera, the animation tree or the clock. |
| `Player` | `player.gd` | The glue: `sample_command()` reads the controls, `tick(command)` runs the simulation and shows the result. `submit_command()` feeds a command from elsewhere. |
| `ThirdPersonCamera` | `third_person_camera.gd` | Holds the view (mouse and stick look), eases aim and shoulder, follows the body. Its yaw and pitch are sampled into the command. |
| `PlayerAnimation` | `player_animation.gd` | Reads the state; never moves the body. |

Prediction, then, is: keep a ring of (command, resulting state); when the server's state for tick N arrives, set the
state with `copy_from`, `teleport`-style, and call `simulate` again for the commands after N. A test does this today
(`test_replaying_the_same_commands_from_the_same_state_gives_the_same_result`): record 150 commands as bytes, rewind,
replay, and the position matches within 1 mm.

Known limits to settle when the net work lands: `move_and_slide` integrates with the engine's physics delta, so
`delta` must equal it (tests change `physics_ticks_per_second`, not the argument); the floor flag is carried in the
state but `move_and_slide` keeps its own contact cache, which a rewind does not restore; floats are not quantized for
the wire yet; crouch is carried in the command and state but nothing acts on it.

## Settings

Sensitivity and invert Y come from the `Settings` autoload (`controls/mouse_sensitivity`, `controls/invert_y`, through
`get_value(key)`; the player refreshes on its `changed` signal). `PlayerSettings` falls back to 1.0 and off when the
autoload is missing or answers something odd, so the test room runs on its own.

## Tuning values

All in `player_tuning_default.tres` (a `PlayerTuning` resource); metres, seconds, degrees unless stated.

| Group | Value | Why |
| --- | --- | --- |
| Speed | run 4.8, sprint 7.0, aim 2.6 m/s | The kit has no Walk clip, so the default pace is the Run clip; aiming is a deliberate shuffle. |
| Acceleration | 38 m/s2 on the ground (full run speed in 0.13 s), 44 friction, 6 in the air | Snappy but not instant; a reversal takes about a quarter second. |
| Facing | 14 rad/s toward the run direction, 24 rad/s toward the aim direction | The body visibly turns instead of snapping; aiming catches up fast so shots go where the camera points. |
| Jump | 1.1 m height, gravity x1.7, coyote 0.1 s, buffer 0.1 s | Short, snappy arc; a late or early press still counts. |
| Body | capsule 1.8 m by 0.35 m radius, model scaled x0.8 | `docs/design/style.md`: the kit's characters are 2.31 m, x0.8 gives 1.85 m. |
| Look | 0.0022 rad per mouse pixel (about 0.126 degrees), stick 170 degrees per second with a squared response, pitch -60 to +50 degrees, x0.7 while aiming | Settings multiply sensitivity; the squared stick curve gives fine control near the centre. |
| Camera | pivot 1.55 m up, shoulder offset 0.75 m, arm 2.8 m, FOV 75 | Over the shoulder, the character fills about a third of the screen height. |
| Aim zoom | arm 1.9 m, shoulder 0.6 m, FOV 62; exponential ease at 10 per second | A modest zoom, settled in about 0.3 s. |
| Shoulder swap | exponential ease at 9 per second | About 0.35 s; the camera glides across, no cut. |
| Camera collision | `SpringArm3D` with a 0.25 m sphere | The camera pulls in instead of entering a wall (tested with the player against the back wall). |
| Footsteps | one `footstep` signal per 1.9 m on the ground | Distance-based so it matches the animation at any speed; audio hooks onto the signal. |

## Animation

The tree is built in `player_animation.gd` from the Soldier's own clips (prefix `CharacterArmature|`):

- `locomotion`: Idle and Run blended by speed (complete at 2.2 m/s); in parallel an aiming pair, Idle_Shoot held on its
  first frame (time scale 0) and Run_Gun; the two pairs are mixed by how far the aim zoom has eased in.
- `jump` (Jump, then Jump_Idle looping) then `land` (Jump_Land), back to `locomotion` at the end of the landing clip.
- **No foot sliding:** Run and Run_Gun play at a time scale of ground speed / 5.5 (the Run clip's planted-foot speed at
  scale 1, estimated from the foot bone's travel; checked by eye in the captures). Sprint plays the same clip 1.27x.
- The imported clips do not loop; `LOOPED` in the script sets Idle, Run, Run_Gun, Jump_Idle and Idle_Shoot to loop.
- The soldier carries all fourteen weapons on its right-hand bone; the script shows only the AK.
- The kit has **no Walk, strafe or Walk_Shoot clips** (`style.md` lists Walk for the other characters only), so aiming
  while moving sideways plays Run_Gun forward. Strafe animation needs new clips (follow-up).

## Things found the hard way

- `AnimationNodeStateMachine.travel()` only works along transitions you added; add the ones you need both ways.
- `Input.is_action_just_pressed` can report one press on two consecutive physics frames when the press arrives between
  ticks; the player keeps its own per-tick edge (`_pressed_edge`).
- GdUnit4 in `--headless` does not transport input events: actions work (`simulate_action_press`), mouse motion does
  not. Call `_unhandled_input` with an event, or `PlayerCommand`s, instead. `push_unhandled_input` is deprecated and
  scaled the motion unpredictably.
- Two scripts both called `PlayerState` (this one and the round rules') broke the whole project at merge time as a
  global class clash; this one is `PlayerMotionState`. Check `grep -r "class_name X"` before naming a global class.
- A test room crate in the run lane made speed tests read zero; keep the lane clear.
- Movie Maker's PNG encode is the slow part (about 0.25 s a frame at 1080p); 10 fps captures are enough to judge motion.

## Sources

- Godot docs: [SpringArm3D](https://docs.godotengine.org/en/stable/classes/class_springarm3d.html),
  [AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html),
  [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html).
- Model: [Character Soldier by Quaternius](https://poly.pizza/m/PpLF4rt4ah), CC0.
