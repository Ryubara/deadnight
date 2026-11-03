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

After the speed-ups below the same job took 15 min 10 s (suites 853 s, down about 420 s on the suites both runs had; `main`
had grown by 26 suites and 150 s meanwhile). The rest is compute and real time, so the job is also split.

## Jobs by test folder (three, six since #775)

`godot` is a matrix of three shards (`godot (1)` to `godot (3)`), each running its own test folders
(`tools/ci_test_shards.py`: `night` and `rules`; `net`, `world` and `zombies`; everything else). A folder that is not
named goes to shard 3, so a new folder is never left out, and the script's self-test (run in every shard) fails if a
folder is in no shard or in two. Each shard repeats the checkout, the fetch of the pinned Godot (cached) and the import,
about a minute; the main-scene run and the night run happen in shard 1 only. `build-ok` still waits for the whole
`godot` job and is the one required name, so the ruleset needs no change. The timing per folder to balance by is in the
job log: re-balance when one shard drifts past the others by more than a few minutes.

**The night folder is split by script (#676).** Shard 1 (`night` and `rules`) ran 14 min 15 s on `main` already, against
a limit of 15, so the bot orders suites tipped it over and the job was cancelled with no test failing. The `night`
folder is 13 minutes of it, almost all in a few bot suites (`test_bot_bands` 185 s, `test_bot_soak` 78 s,
`test_bot_orders_night` 70 s), so `MOVED` in `tools/ci_test_shards.py` names those scripts and sends them to the shards
with room: after the move the three shards' suites take about 530, 560 and 580 s. A script of a split folder that is not
named stays with the folder's shard, so a new bot suite is still run. Check the shard times in the job log before a PR
adds minutes of suites; the step takes a minute of setup on top.

**Six shards, by measured seconds (#775).** The three shards grew back to 12 to 15 minutes (shard 1 reached the 15-minute
limit and was cancelled with no test failing, five times in one day). The suites alone were 655, 708 and 655 s in a
fast run of `main` and 814, 838 and 673 s in a run 15 % slower, 2,018 and 2,325 s in all: 3 shards cannot meet "no
shard over about 9 minutes" (a shard's job is its suites plus about 50 s of checkout, fetch and import), 4 could not
survive a slow runner (10.5 min), so there are six, about 6 minutes of suites and 7 in all, and the limit stays 15.
The seconds per script are the gaps between the `Run Test Suite:` lines of the job log (`gh api
repos/<repo>/actions/jobs/<id>/logs --allow-escape-sequences`); the table is the mean of two runs.

| Shard | Runs | Suites, s (fast / slow run) |
| --- | --- | --- |
| 1 | the rest of `night` (about 96 scripts), the main scene and a night run | 332 / 414 |
| 2 | `night/test_bot_bands`, `player` | 349 / 356 |
| 3 | `zombies`; `night/test_bot_soak`, `_orders_night`, `_combat`, `_team`, `_errand_buys` | 304 / 404 |
| 4 | `net` | 358 / 377 |
| 5 | `ui` and the small folders; `night/test_bot_own_ammo` | 343 / 362 |
| 6 | `rules`, `world`; `night/test_bot_train` | 332 / 413 |

The slowest suites on the runner (mean seconds): `night/test_bot_bands` 206 (eight seeds for each band),
`rules/test_balance_targets` 109 to 127 (60 seeded nights per cell, the gate), `night/test_bot_soak` 80,
`night/test_bot_orders_night` 68, `net/test_room_eight` 59, `night/test_bot_combat` 51, `night/test_bot_errands` 45,
`net/test_night_scoreboard_online` 43, `night/test_bot_team` 43, `world/smallmap/test_smallmap_bot_night` 40,
`night/test_bot_own_ammo` 40. All are seeded bot nights or real sockets: the time is the test. I read the scripts of
the 25 to 35 s suites outside
`net` (`player/test_aim_press_order`, `ui/test_hud_prompt_fit`, `night/test_shot_on_crosshair`, ...): none has a
`create_timer`, they load a night and step it, so none grew because of a bug and none got its own issue. They are also
the next place to look when a shard drifts: `test_bot_bands` alone is a third of a shard (`BOTS_BANDS_SEEDS` shortens it
by hand).

**The world shard grew the body sweeps (#848).** By 2026-11-03 shard 6 ran 663 s of suites (12.2 min of job) on a fast
run of `main`: `rules/test_balance_targets` 189, `world/test_midway_fence_reach` 132, `world/smallmap/test_smallmap_bot_night`
90. #848 adds two sweeps of the real player body at the walls, `world/test_drive_in_escape_sweep` (about 60 s) and
`world/smallmap/test_smallmap_escape_sweep` (about 37 s), which would have put the job near 14 minutes, so the lot's
sweep and the midway's go to shard 2 (`player`, 4.6 min of job). `MOVED` now splits `world`: its scripts are listed one
by one and its subfolders (`world/smallmap`) whole, with the folder's shard; the self-test checks every one is run.

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
