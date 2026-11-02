# Why the `godot` job took twenty minutes, and how a test stays fast

The `godot` job runs the whole GdUnit4 suite headless. On `main` it took 16.5 to 19.8 minutes against a 20-minute limit
(#524: pull requests that added tests were cancelled with no failed test; #400 was main's own run cancelled). The
limit was raised to 30 in the meantime (#501); this page is about the time itself.

## Measure first

The job log carries a timestamp per line. The time of a suite is the gap between its `Run Test Suite:` line and the next
one, which includes its `before()` and `after()`; sorting those gaps gives the list that matters. One run on `main`
(run 41395192208, 279 suites, 1,128 s of suites in a 19 min 46 s job):

| Suite | Seconds on CI | Cause |
| --- | --- | --- |
| `ui/test_settings_layout` | 107 | 40 real `create_timer(0.8)` settles, one per tab visit |
| `rules/test_balance_targets` | 91 | 5 cells of 60 seeded nights for the gate, then 60 more nights for a case that only needs to see a wall |
| `player/test_omni_movement` | 51 | a physics frame awaited per hand-stepped tick |
| `player/test_player` | 49 | the same |
| `world/test_drive_in_jump_reach`, `test_drive_in_opening_order`, `zombies/test_door_navigation` | 36, 29, 28 | navigation meshes and geometry: CPU, nothing to wait for |
| `player/test_player_crouch`, `test_reload_tilt`, `test_player_step_up`, `test_aim_weight`, `test_weapon_hold`, `test_omni_curves`, `test_hip_fire`, `test_aim_release` | 24 to 34 each | a physics frame awaited per hand-stepped tick |
| `net/*_online`, `test_client_freeze`, `test_netcode_scenario` | 21 to 43 each | real sockets and real freezes: the time is the test |

## What a fast test does

1. **Tick by hand, back to back.** A suite that steps the player itself switches its `_physics_process` off once and
   calls `PlayerHandStep.tick(player)` (or `player.tick(command)` with a command it built) for every tick. The
   simulation reads only its arguments and the world (`PlayerSimulation`), so the result is the same and the suite no
   longer runs at 60 ticks a second of wall time. 2,000 ticks cost about a tenth of a second. `OmniHarness._run` and
   the `_ticks` of the player suites do this.
2. **Wait one frame per measurement, not per tick.** The skeleton's modifiers and the layout run on the idle frame:
   `await get_tree().process_frame` after a run of ticks, not between them.
3. **A body added in the test is not in the physics world until the physics server has stepped once.** Hand ticks never
   step it, so the first tick after adding a ledge, a beam or a wall walks through it (`OmniHarness._flush_physics`,
   one real physics frame, once per setup). The same holds for the test room itself: the first tick of a suite follows
   one physics frame in `before_test`. Without it the player falls through the floor (the symptom was a body at
   `y = -0.9` with a vertical speed of -5.5 m/s, and sprint tests that never sprinted).
4. **Let a settle run at a faster clock, not a shorter wait.** `test_settings_layout` waits for a page's entrance to
   finish; it now sets `Engine.time_scale = 10` for the wait only (0.08 s of wall time) and puts it back to 1 before the
   next click, so the clicks and the frames where a page is caught mid-way run at the real pace. A suite that sets
   `time_scale` restores it in `after_test`.
5. **Run only as many nights as the case needs.** The balance gate keeps its 60 nights per cell; a case that proves the
   gate can fail (`inert` upgrades, health out of range) needs a wall, which 20 nights show with room to spare (median
   rounds one to six below range, a stampede killing two thirds).

## What was left alone, on purpose

- `player/test_player_reconcile` is about the engine's own physics callback; its harness runs `_by_clock = true`, one
  command per physics frame, and the suite stays at about 17 s.
- A recording made by hand in one frame and replayed in an idle frame landed 0.2 to 6 mm apart in one run of six
  (`test_a_replay_crouches_and_stands_the_same`): `move_and_slide` steps an idle frame by its wall-time delta and the
  simulation rescales the velocity to match. The two replay tests (crouch, step-up) record and replay in physics
  callbacks; the idle frame of a message handler is the reconcile suite's.
- `night/test_kill_allocations` takes six ticks per frame on purpose: at 30 it made nine more nodes (a frame with more
  kills asks the pools for more) and failed. A test about what one frame allocates is not made faster by packing frames.
- The `net` suites talk to a real server over a real socket and freeze the client for real seconds. Their time is
  their subject.

## Checking that a faster test still tests

Each sped-up suite was run with its behaviour broken once, locally, and failed: sprint speed and crouch speed in
`PlayerSimulation`, ledge stepping, the camera's aim weight, the reload tilt, the support hand's reach, the settings
page's row spacing (607 failures), the balance ranges widened so the `inert` case passes the gate.

## For a new test

If it steps something by hand, it does not await a clock frame per step. If it adds a collider, it awaits one physics
frame. If it needs a real clock (a socket, a freeze), it says so in its first comment and keeps its waits short. Look
at the job's slowest suites with the timestamps above before and after adding a suite that takes more than ten seconds.
