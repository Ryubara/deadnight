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
| `ThirdPersonCamera` | `third_person_camera.gd` | Holds the view (mouse and stick look), follows the body with critically damped springs on the interpolated body position, eases aim, sprint and shoulder, keeps the lens out of walls and the head. Its yaw and pitch are sampled into the command. See [shoulder camera](shoulder-camera.md). |
| `PlayerAnimation` | `player_animation.gd` | Reads the state; never moves the body. |

Prediction, then, is: keep a ring of (command, resulting state); when the server's state for tick N arrives, set the
state with `copy_from`, `teleport`-style, and call `simulate` again for the commands after N. A test does this today
(`test_replaying_the_same_commands_from_the_same_state_gives_the_same_result`): record 150 commands as bytes, rewind,
replay, and the position matches within 1 mm.

Replaying is safe in **any callback**, physics frame or not (`tests/player/test_player_reconcile.gd`: 150 commands
re-simulated in one callback, from the air and from a slope, in a physics frame and in an idle frame, match within
1 mm). Two things made that false, and `PlayerSimulation._slide` fixes both:

- `CharacterBody3D.move_and_slide()` ignores the caller's delta: it steps by the physics delta in a physics frame and
  by the *frame* delta (wall time) anywhere else, which is where a `SceneMultiplayer` handler runs. The measured error
  was 5.7 m over 150 commands. `_slide` scales the velocity by `delta / engine_delta` before the call and back after,
  so the step is exactly `delta` in every frame (sliding only projects the velocity, so the scaling is exact). It
  also means `delta` is honoured: a double step moves twice as far.
- The body's own "was I on the floor last call" cache (what its floor snap reads) is not restored by `copy_from`, so
  the first replayed tick snapped to a slope or not depending on where the previous run had ended (3 mm, then more).
  `_slide` turns the body's snap off for the call and snaps afterwards from the carried `state.on_floor`, the engine's
  rule (`was_on_floor`, not moving up, no floor after the slide) on data a rewind does restore.

Still open for the net work: floats are not quantized for the wire yet; and `_slide` cannot scale when the engine has
no delta yet (the very first frame), where it reports an error.

## Stepping up

A ledge up to `step_height` (0.3 m) is climbed by walking into it, at any pace and from an angle, with no jump
(`tests/player/test_player_step_up.gd`). It is part of the simulation (`PlayerSimulation._step_up`), so a server and a
replay climb the same ledges; it uses physics queries only (`test_move`, one ray), never the body's contact cache.

- **What counts as a ledge:** the tick's walk is blocked by a *wall* (a contact steeper than `floor_max_angle`, so a
  slope stays the engine's), a ray down a hair inside the face finds a walkable top between `step_min_rise` and
  `step_height` above the feet, there is room to lift (nothing overhead) and the lifted body is not blocked going on.
  A taller ledge, a low beam over it and a wall with no top within reach stay walls.
- **Lift, then walk:** the body is lifted onto the top (plus two safe margins) and the same tick's slide carries it on.
  The rounded foot is still over the ledge's edge for about one body radius of walking, so the engine would report no
  floor, and the body would sag a few centimetres, play the fall and the landing, and bounce. `step_settle` keeps the
  carried floor flag for `step_settle_distance` (0.5 m) of walking and turns the floor snap off meanwhile (a snap would
  pull the foot back down beside the ledge); the engine's answer takes over as soon as the foot is on the top.
- **The view:** the body moves up in one tick, but `Player` draws the model `step_lag` metres lower and lets that decay
  (`exp(-step_view_frequency * delta)`, in the tick, so physics interpolation blends it and a replay does not care).
  The camera's vertical spring (10 rad/s) does the same for the view. Measured at 144 Hz over a climb
  (`test_the_view_is_smooth_at_144_hz_over_a_climb`): the model moves at most 27 mm a frame (a pop would be 126 mm), the
  camera pivot at most 8 mm; the control test with the easing off sees the pop.
- **Limits:** only on the ground and not while rising (a jump is a jump); a ledge too narrow to rest the whole capsule
  on is still climbed (the ray finds the top, not the footprint). Micro differences between a first run and a replay at
  the ledge's far edge (a body sliding off a corner) are about 10 micrometres, amplified to a millimetre by the slide;
  the replay test therefore ends on top of the ledge.

## Crouching

Held crouch lowers the capsule and the pose, slows the walk, and cannot be undone under a low ceiling
(`PlayerSimulation._next_stance`, `tests/player/test_player_crouch.gd`). It is carried in `PlayerCommand.crouch`
(a level) and `PlayerMotionState.crouching`, which the network wire already had.

- **Stance:** a crouch starts on the ground when the key is down (not in the air: one that began on the ground carries
  over a fall), and ends when the key is up *and* the standing body fits. The fit test is a shape query of the
  standing capsule, a `crouch_probe_skin` (2 cm) shorter at both ends and narrower, so the floor under the feet and a
  wall beside them never count, only what is overhead. Under a beam the crouch holds with the key up and the walk
  stays slow.
- **The shape follows the carried state:** every tick starts by setting the body's capsule to `state.crouching` (its
  feet stay where they are, the shape grows up from them), so a rewind to a crouched or a standing state restores the
  right shape, and a replay in any frame matches (`test_a_replay_crouches_and_stands_the_same`). A body with no
  capsule child is left alone.
- **Pace:** every pace (run, aim) is scaled by `crouch_speed / run_speed` (0.5): a crouched run is 2.4 m/s, a crouched
  aim walk 1.4. Sprint is ignored while crouched, and so is a jump (the buffer still holds it for 0.1 s, so a jump
  pressed as the key goes up fires if there is room).
- **Camera:** the pivot target drops to `crouch_pivot_height` (1.1 m) at once; the pivot's own vertical spring (10
  rad/s) eases it in about half a second, the same spring that eases a step up.
- **Pose:** the kit's `Duck` clip is a down-and-up cycle (1.67 s, the Body bone's lowest at its middle), not a held
  crouch. The body machine's `crouch` state loops 0.1 s of it around that lowest second
  (`AnimationNodeAnimation.use_custom_timeline`, found by scanning the Body track, not assumed) and lays the Walk over
  it at `crouch_walk_blend` (0.6) of its weight at the crouch speed, so the legs step under the held pose; the kit has
  no crouch walk. `PlayerAnimation` travels to `crouch` from `locomotion` while the state crouches on the floor, and
  back when it stands; a fall leaves it by its own transition.
- **Not done:** remote avatars in the night view draw the standing pose (that view is another change's); cover and
  zombie sight against a crouched player are not designed yet (`docs/design/map.md`).

## Settings

Sensitivity and invert Y come from the `Settings` autoload (`controls/mouse_sensitivity`, `controls/invert_y`, through
`get_value(key)`; the player refreshes on its `changed` signal). `PlayerSettings` falls back to 1.0 and off when the
autoload is missing or answers something odd, so the test room runs on its own.

## Tuning values

All in `player_tuning_default.tres` (a `PlayerTuning` resource); metres, seconds, degrees unless stated.

| Group | Value | Why |
| --- | --- | --- |
| Speed | run 4.8, sprint 7.0 (every direction), aim 2.6 m/s (0.75 of that backing away) | The default pace is a run; Walk plays only on the way up to it (and when aiming slows the player); aiming is a deliberate shuffle. |
| Acceleration | 38 m/s2 up to the run (0.13 s), 18 above it to the sprint (0.25 s in all), friction 44 from a run and 30 above it, 30 easing down to a lower pace, 6 in the air | Snappy but not instant; a sprint builds and carries on a little. [Character controller](character-controller.md) has the curves. |
| Facing | 14 rad/s toward the run direction, 9 while sprinting, 22 in a pivot (a turn wider than 100 degrees), 24 toward the aim direction | The body visibly turns instead of snapping, and the velocity turns with it; aiming catches up fast so shots go where the camera points. |
| Jump | 1.1 m height, gravity x1.7, coyote 0.1 s, buffer 0.1 s | Short, snappy arc; a late or early press still counts. |
| Step up | ledges up to 0.3 m, lifted onto in one tick; the model eases up at 14 /s (95 percent in about 0.2 s) | A walk into a curb, a plank or a low crate is not a wall. See [Stepping up](#stepping-up). |
| Crouch | capsule 1.2 m (feet fixed), walk 2.4 m/s (aim 1.4), no sprint, no jump; camera pivot 1.1 m | Half the run pace is a deliberate creep; the pivot follows the head (0.89 of the capsule). See [Crouching](#crouching). |
| Body | capsule 1.8 m by 0.35 m radius, model scaled x0.8 | `docs/design/style.md`: the kit's characters are 2.31 m, x0.8 gives 1.85 m. |
| Look | 0.0022 rad per mouse pixel (about 0.126 degrees), stick 170 degrees per second with a squared response, pitch -60 to +50 degrees, x0.7 while aiming | Settings multiply sensitivity; the squared stick curve gives fine control near the centre. |
| Camera | pivot 1.6 m up, shoulder 0.6 m, arm 2.3 m, FOV 70 | Over the shoulder, closer than the first draft (arm 2.8 m, FOV 75): [shoulder camera](shoulder-camera.md) has every number and the reasoning. |
| Aim zoom | arm 1.8 m, shoulder 0.65 m, FOV 60; critically damped spring at 24 rad/s | Settled in about 0.2 s; the screen centre stays 0.2 m clear of the body. |
| Shoulder swap | critically damped spring at 16 rad/s | About 0.3 s; the camera glides across, no cut. |
| Camera follow | spring at 22 rad/s (10 vertically, 16 while sprinting) on the body drawn between its last two physics ticks | Smooth at any frame rate; trails a runner by 2 v / w. |
| Camera collision | sphere sweeps (0.25 m) sideways to the shoulder, back along the view, then straight to the lens; pulled in at once, let out at 6 rad/s | The camera slides in or comes forward instead of entering a wall; the body hides when the lens is within 0.9 m of the head. |
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
  1, estimated from the foot bone's travel); Idle and Walk play at their own pace. Sprint plays Run 1.27x, in every
  direction: the body faces where it goes, so one clip serves them all
  ([character controller](character-controller.md)).
- Loops and event frames come from `clips.json` (glTF has no loop flag and no events); only Jump_Idle, a kit clip the
  spec does not list, is looped by name. Events are a frame check on the playing upper clip: `clip_event(clip,
  event)` fires for muzzle, can_fire_again, round_in, weapon_visible and the rest, and the weapon shows and hides on
  its own events. Footsteps stay distance based (one source); Walk's step events are not used.
- **Weapons:** `equip(id)` attaches the weapon id's own model (`holds/<id>.tres`); `equip(class)` the class's
  to a `BoneAttachment3D` on `Index1.R` with `HOLD_GUN` or `HOLD_MELEE`. The default is Rifle.
- `clips.json` is read with `FileAccess`: the web preset includes `*.json` in its filter ([web export](web-export.md)).
- **Moving while aiming** plays the aim gait: `Walk_Shoot`, `Walk_Back`, `Strafe_Left`, `Strafe_Right` in a
  `BlendSpace2D` on the velocity in the facing's frame, over the Idle/Walk/Run blend by an aim weight
  ([Animation](../design/animation.md#moving-while-aiming)). Before, aiming at 2.6 m/s played the full Run (past the
  1D blend's 2.2 m/s end) forward under the aim, whichever way the player went.
- The body's state machine enters `locomotion` on the player's first landing (Start has no automatic transition): a
  test that steps the tree with physics off starts the playback itself.

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
- The camera ease (`ThirdPersonCamera.step`, called from `_process`) and the animation (`PlayerAnimation._process`,
  the AnimationTree) run
  on the frame delta, which is wall time, while `await physics_frame` counts fixed ticks. On a loaded machine the two
  drift apart and tests that wait N ticks and then read the fov, the shoulder offset or the animation state failed
  once in a while. `test_player.gd` therefore turns both off and steps them by hand (the camera with `step(delta, 1.0)`),
  one tick per physics frame
  (`_ticks`); read the camera and animation only after `_ticks`/`_seconds`, never after a plain `process_frame` wait.
- `clips.json` rounds `seconds` (Fire_Rifle is 0.333 for 8 frames at 24 fps), shorter than its last event
  (`can_fire_again` at 8/24). A frame step ending in between ended the clip and skipped the event, so the rifle never
  fired again; it showed as a test that passed or failed with frame timing. `PlayerAnimation` now holds an action
  until its last event (`_clip_seconds`).
- Movie Maker's PNG encode is the slow part (about 0.25 s a frame at 1080p); 10 fps captures are enough to judge motion.

## Sources

- Godot docs:
  [SpringArm3D](https://docs.godotengine.org/en/stable/classes/class_springarm3d.html) (no longer used by the camera),
  [AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html),
  [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html).
- Model: [Character Soldier by Quaternius](https://poly.pizza/m/PpLF4rt4ah), CC0.
