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
| Speed | run 4.8, sprint 7.0, aim 2.6 m/s | The default pace is a run; Walk plays only on the way up to it (and when aiming slows the player); aiming is a deliberate shuffle. |
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

The Soldier is the build of `tools/blender/build_soldier.py` (35 clips, bare names, no weapons in the file); the spec is
[Animation](../design/animation.md). The tree is built in `player_animation.gd`:

- `body`: `locomotion` blends Idle, Walk (at 0.45) and Run (complete at 2.2 m/s) by speed in a synced BlendSpace1D;
  `jump` (Jump, then Jump_Idle looping) then `land` (Jump_Land), back to `locomotion` at the end of the landing clip.
- `upper`: the class's `Aim_<Class>` loop with a OneShot for `<Action>_<Class>` (`play_action(&"Fire")`, Reload,
  Swing, Equip, Unequip), laid over `body` by a Blend2 filtered to the 32 `upper_bones` of `clips.json`. The filter
  paths take the skeleton path from the clips' own tracks, so a rebuild that moves the skeleton does not break them.
- `full`: a OneShot over both for HitReact and Death (`play_full_body`).
- **No foot sliding:** the Run end of the blend plays at ground speed / 5.5 (the Run clip's planted-foot speed at scale
  1, estimated from the foot bone's travel); Idle and Walk play at their own pace. Sprint plays Run 1.27x.
- Loops and event frames come from `clips.json` (glTF has no loop flag and no events); only Jump_Idle, a kit clip the
  spec does not list, is looped by name. Events are a frame check on the playing upper clip: `clip_event(clip,
  event)` fires for muzzle, can_fire_again, round_in, weapon_visible and the rest, and the weapon shows and hides on
  its own events. Footsteps stay distance based (one source); Walk's step events are not used.
- **Weapons:** `equip(class)` attaches the class's weapon scene (lever rifle, double shotgun, bat; Pistol has none yet)
  to a `BoneAttachment3D` on `Index1.R` with `HOLD_GUN` or `HOLD_MELEE`. The default is Rifle.
- `clips.json` is read with `FileAccess`: the web preset includes `*.json` in its filter ([web export](web-export.md)).
- No strafe or Walk_Shoot clips yet: moving sideways plays Walk or Run forward under the aim (#74).

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
- `clips.json` rounds `seconds` (Fire_Rifle is 0.333 for 8 frames at 24 fps), shorter than its last event
  (`can_fire_again` at 8/24). A frame step ending in between ended the clip and skipped the event, so the rifle never
  fired again; it showed as a test that passed or failed with frame timing. `PlayerAnimation` now holds an action
  until its last event (`_clip_seconds`).
- Movie Maker's PNG encode is the slow part (about 0.25 s a frame at 1080p); 10 fps captures are enough to judge motion.

## Sources

- Godot docs: [SpringArm3D](https://docs.godotengine.org/en/stable/classes/class_springarm3d.html),
  [AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html),
  [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html).
- Model: [Character Soldier by Quaternius](https://poly.pizza/m/PpLF4rt4ah), CC0.
