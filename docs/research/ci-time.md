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

## Jobs by test folder (three), six (#775), eight by script seconds (#1015), nine (#1151), ten (#1265)

`godot` is a matrix of parallel shards (`godot (1)` to `godot (10)`), each running its own test scripts. The history:
three shards by folder (#524, then single scripts moved by hand, #676), six (#775), and each time the heaviest shard was
back at the 15-minute limit within a day or two, because the suite grows with every merge (28 new scripts in one
afternoon, #1015) and the shards were balanced by hand from a table that went stale. A shard that is over its limit is
cancelled with no failing test.

**Dealt by measured seconds (#1015; eight shards then, nine since #1151, ten since #1265).** `tools/ci_test_shards.py`
no longer names folders. Every `tests/**/test_*.gd` is one item, weighed by its seconds in `tools/ci_test_times.json`,
and the items are dealt out heaviest first to the shard with the least so far; a script that is not in the file counts
`default_seconds` (10), so a new script lands in the lightest shard and is never left out. The self-test (run in every
shard) fails when a script is in no shard or two, or when the workflow's matrix is not the same shards or the job's
limit is not the one the check assumes. Shard 1 starts with 240 s already counted (60 until #1265, 100 then), for the
main scene, the night run and the two budget runs it alone does: the four-player late-round case (54 to 112 s alone)
and, since #1193, the worst room of 8 people and 7 bots (85 s of night, 137 s on the runner: the crowd takes a minute to
reach 90 percent of its cap, and 15 bodies run at a third of the speed of 4).
The 140 s more take each of the ten shards' expected time from 436 s to 450 s, 10 s over the 440 s of `--report`
(advice only; a job is still about 8.5 minutes with its setup, against a limit of 15); an eleventh shard is next.

Measured on six complete CI runs (five of `main`, one of the late-round budget pull request, #968). The seconds of a
suite are the duration on its `Statistics:` line (`tools/ci_shard_time.py`, `suite_times`; the same as the gap between
its `Run Test Suite:` lines). The runner's speed varies by a factor of 1.5 from job to job (`test_balance_targets` 110 to
207 s, `test_bot_bands` 86 to 149 s), except the `net` suites, whose time is real (`test_room_eight` 61 s every time):

| Shard | Before: suites, s | Before: job, min | After: suites, s | After: job, min (suites + 50 s, shard 1 + 120 s) |
| --- | --- | --- | --- | --- |
| 1 | 811 | 14.7 | 338 | 7.6 |
| 2 | 251 | 5.0 | 408 | 7.6 |
| 3 | 479 | 9.0 | 383 | 7.2 |
| 4 | 488 | 9.0 | 458 | 8.5 |
| 5 | 554 | 10.2 | 427 | 8.0 |
| 6 | 766 | 13.9 | 450 | 8.3 |
| 7 | | | 433 | 8.1 |
| 8 | | | 446 | 8.3 |

Run A is the slowest `main` run with the "after" column the same suite times summed under the new split (job minutes
are the suites plus the setup seen in the logs). Shard 1 of run A had no late-round budget step yet, which adds 50 s:
its job would have been 15.5 minutes. Over all six runs the heaviest shard before was 653 to 816 s of suites (shard 1
or 6; shard 1 was cancelled at the limit on one `main` run, and #968 had shard 6 at 14 min 50 s); after it is 364 to
458 s. The expected job is 6.9 to 8.5 minutes on the slowest runners seen, and the spread inside a run is 100 to 120 s
(it was 430 to 590 s).

## Keeping the shards balanced (#1015)

- **The check in every shard.** The last step of a `godot` shard (`tools/ci_shard_time.py check`) reads the shard's
  `tests.log`, puts the slowest suites in the job summary, and compares the job's elapsed time (from a clock started
  by the first step, checkout included) with the 15-minute limit: an annotation past 60 % (9 min), a failed job past
  80 % (12 min). A balanced shard takes 6 to 9 minutes on the slowest runners seen, so the failure means real drift, and
  it shows on the pull request that pushed it, minutes before the limit cancels a job with nothing wrong in the log.
- **When it warns or fails,** or when the suite has grown by a few dozen scripts: download `tests.log` from the
  `gdunit4-report-N` artifacts of two or three recent runs of `main`, run `python3 tools/ci_shard_time.py update <logs>`
  (it averages the logs and rewrites the times file), commit it, and run `python3 tools/ci_test_shards.py --root game
  --report`: each shard's expected seconds. If the heaviest is over `REPORT_SHARD_BUDGET` (440 s), add a shard (`SHARDS`
  there and the matrix in the workflow; the self-test fails until both agree). The size rule from before still holds:
  total suite seconds / 480, rounded up, plus a margin for a slow runner and growth (3,250 s / 480 = 6.8, so eight;
  3,880 s / 480 = 8.1, so nine).
- **Refreshed on 2026-11-04 (#1091).** The report on the old times said 3,569 s and 454 s a shard against the 440 s
  budget, every shard flagged, with 28 scripts at the default. The mean of three green `main` runs (24 logs from
  artifacts of about 2 MB each, reduced to the times file and deleted) gave 3,254 s and 414 s a shard, none flagged,
  two scripts (merged after those runs) still at the default: stale times, not growth, had asked for a ninth shard.
  The same runs took 380 to 559 s a shard with setup. The budget was not raised.
- **Refreshed again on 2026-11-04 (#1151), and a ninth shard added.** `godot (1)` failed the time check on a green
  suite (12.2 minutes against the 12-minute fail line), about ten merges after #1091, several with new suites. The report
  on the file as it stood said 3,991 s and 506 s a shard (53 scripts at the default, every shard flagged). The mean of
  four green `main` runs (#1136, #1128, #1142 and #1144, 32 logs of about 25 MB each, reduced to the times file and
  deleted; the runs after them were still going or had a red shard) gave 3,877 s of suites and 492 s a shard on eight
  shards, **still every shard over the 440 s budget with one script at the default**, so this time the refresh did not
  make the ninth shard unnecessary: the suite grew (3,254 s on the 24 logs of #1091, 3,709 to 4,019 s a run now, +19 %
  in a day: the ladder's clip suites, the challenge and menu suites). Nine shards deal 437 s each, 8.1 total / 480
  rounded up. The real shard suites in those four runs, under the stale split, were 356 to 574 s and the jobs 405 to 647
  s (6.8 to 10.8 minutes); under the refreshed split the expected job is 437 s plus about 50 s of setup.
- **Refreshed again on 2026-11-05 (#1265), a tenth shard, and shard 1's head start raised.** `godot (1)` failed the time
  check on a green suite (12.4 minutes against the 12-minute line; 643 cases, 0 failures) in run 42037762096. Drift or a
  slow runner? Both, and a constant that was too small. Shard 1 ran the same 74 scripts in four `main` runs: the tests
  step took 375, 441, 476 and 546 s (jobs 8.3, 9.8, 10.8 and 12.4 minutes), a 1.46 spread on identical suites. The
  failing job was the slow end: its suites took 1.18 times their mean in the other runs (shards 2, 3 and 8 of the same
  run: 0.92, 1.04 and 1.14), `Hold the late-round worst case` took 112 s (54 s in the run before it, 73 to 108
  elsewhere), `test_soldier_ladder_clips` 97 s (54 and 60 s on two faster runners, 96 to 99 s on three others). The
  times file was also stale: 29 scripts counted at the 10 s default (`rules/test_crane` was 4.2 s in the file and took
  49 to 79 s; `ui/test_end_board_fit` 3.1 against 10 to 18), so shard 1's suites were expected at 417 s and took 460 s
  on average. And shard 1's head start was 60 s while its once-per-run steps took 100 s (the budget run averaged 91 s in
  six runs, plus the night and the main scene), so shard 1's job ran 619 s on average against the other shards' 535: 100
  s under the fail line before any slow runner. The mean of four green `main` runs (42023432725, 42026421751,
  42036953273 and 42040292920: 36 logs, reduced to the times file and deleted) gave 4,200 s of suites (4,117 to 4,341 a
  run, 3,880 in #1151) and, on nine shards, 473 s a shard against the 440 budget with no script at the default: the
  suite grew 8 % in a day (the server browser, the hidden challenges, the phone-page suites). Ten shards deal 430 s each
  with shard 1 at 100 s of head start. The limits are as they were. A slow runner can still add 30 % to a shard; the
  fail line is for that.
- **Do not hand-edit** a shard's list; there is none. A script that is slow on purpose gets its time from the file.

The slowest suites on the runner (mean seconds of four runs, 2026-11-04): `world/test_midway_fence_reach` 128,
`rules/test_balance_targets` 113 (60 seeded nights per cell, the gate), `night/test_bot_bands` 101,
`character/test_soldier_clip_fit` 99, `ui/test_menu_grips` 89, `net/test_challenges_online` 88,
`night/test_bot_orders_night` 86, `world/smallmap/test_smallmap_bot_night` 85, `character/test_soldier_ladder_clips` 82,
`rules/test_crane_pool` 72. Together they are a quarter of the suite's time (942 of 3,867 s). Most are seeded bot nights,
a walk of the whole map, real sockets, or the soldier clip sweeps. `test_soldier_clip_fit` is the one that swings: 85
to 92 s in three runs and 130 to 131 s in two, on whichever runner it got (its change in #1146 added a few lines to the
shared sampler and is not what moved it: 131 s ran before it merged). Speed-up candidates are issues of their own
(#1017 lists them).

## The web job (#1111)

The `web` job exports the game and runs eight browser probes (Playwright, headless Chromium). It takes 1,077 to 1,704 s
on a runner, nearly all of it the probes (each 100 to 300 s; "Open the build in a browser" alone 190 to 307 s). It was
limited to 30 minutes, and run 41887654023 was cancelled at the limit in its last probe because "Install the browser" had
taken 471 s (the Azure Ubuntu mirror served font packages with 60 to 160 s gaps) against 13 to 153 s on `main`.

- **The install is cached.** `playwright install-deps` fetches nine `.deb` files (fonts and libraries, 21 MB) and
  `playwright install` the headless shell (108 MB). Both folders are restored by `actions/cache`: the browser under a key
  of the Playwright version (`PLAYWRIGHT_VERSION`, a job variable that the install, the keys and every probe read, so a
  cached browser is always the one the library asks for), the packages under a key of the runner image and the version,
  with a restore key of any image: the images rotate every few days and even between two runs minutes apart (runs of
  this pull request got `20261026.354.1` and `20261101.360.1`), and apt fetches again any package whose version it
  wants and the cache lacks, so a stale entry costs time, never correctness. The restored files are copied into
  `/var/cache/apt/archives` before `install-deps`; afterwards the files fetched now (found by change time: apt gives a
  download the server's modification time, so `-newermt` misses them) and only the versions installed are kept, so an
  entry does not collect old versions.
- **Each install step has a limit of its own** (10 minutes), so a mirror that stalls ends red on "Install the browser's
  system packages" or "Install the browser", not as a cancelled job at the end.
- **The job has 40 minutes** and its last step (`tools/ci_shard_time.py web`, kept equal to the workflow's limit by
  `ci_test_shards.py --self-test`) annotates past 30 minutes (the old limit), fails past 38, and names an install step
  past 180 s in the annotation and the job summary. The slowest `main` run plus the 471 s install is 36 minutes:
  annotated, still green.
- **Measured on this pull request** (the mirror was fast on all three, 21 MB in 1 s, so the install itself gained
  little; what changed is that the downloads that stalled once are gone):

    | Run | Cache | Install-deps | Install browser | Job |
    | --- | --- | --- | --- | --- |
    | 41895393215 | cold (both) | 14 s, 21.1 MB fetched | 4 s, downloaded | 1,542 s |
    | 41899862660 | browser warm, packages missed (image rotated) | 11 s | 0 s | 1,077 s |
    | 41903192638 | both warm | 11 s, "Need to get 0 B/21.1 MB", 9 restored, 0 fetched | 0 s | 1,208 s |

  The job's total moved by 465 s between runs while the install moved by 7 s: the probes ran at different speeds on
  different runners, so the install is no longer what decides the limit, and none of the three needed more than 26 minutes.
  `apt-get update` (12.7 MB of indexes) still goes to the mirror on every run; the 10-minute step limit covers it.
- **A cache is saved by a run that ends green** and restored by the pull requests of the same repository from
  `main`'s entries: the first `main` run after this merge saves them, every run after that starts warm.
- **Left alone:** the probes themselves (about 1,100 s of the job) are not sped up here.

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

## The ten slowest suites (#1017)

Ten scripts took a third of the suite's seconds on the runner. Seconds of the suite on one machine (16 threads, run
alone, before and after in the same session; a runner is 1.5 to 3 times slower per thread, so read the ratio):

| Script | Before | After | What changed, and what it still proves |
| --- | --- | --- | --- |
| `rules/test_balance_targets` | 97.5 | 58.5 | the three "the gate can fail" tests run two small cells, not six; the climb test runs two cells, not three (below) |
| `night/test_bot_bands` | 110.4 | 74.2 | the seated night's bodies are indexed (below); every seed and second kept |
| `night/test_bot_grenade_soak` | 90.2 | 39.0 | the same; 3 seeds of 120 s kept |
| `world/test_midway_fence_reach` | 93.5 | 81.6 | a hop stops settling once the state is a fixed point; the same 21,423 hops |
| `world/smallmap/test_smallmap_bot_night` | 79.0 | 42.7 | a night stops when it has shown what its test asks for |
| `night/test_bot_orders_night` | 68.2 | 64.2 | waits for the map's answer after a door, not 12 or 60 frames; the indexed bodies |
| `night/test_bot_soak` | 53.6 | 25.5 | the indexed bodies |
| `night/test_bot_combat` | 55.8 | 44.1 | the indexed bodies |
| `night/test_bot_own_ammo` | 47.0 | 30.6 | the indexed bodies; waits for the map's answer after the door |
| Total | 694.2 | 460.8 | 233 s (34 %) |

`net/test_room_eight` (real sockets) was left alone, as the issue said.

**Most of it was one missing physics step.** A seated night awaited one `physics_frame` after adding the players' bodies,
but the signal fires before that iteration's step, so the bodies were still outside the physics index and
`move_and_slide` cost 0.24 ms for a body standing still instead of 0.02 ms: a tick of four players 3.7 ms, 1.6 ms with a
second await (`SeatedNight.start`). The bands' counts of shots, hits and blows are the same either way. The 917 tests of
the `night` folder and the 1,518 of `bots`, `zombies`, `world` and `rules` pass with it.

**The grenade soak showed a bot hazard with the bodies indexed, and #1021 fixed it.** On the first CI run of this change
the shard that runs the soak failed: on seed 11 a bot's grenade took 25.5 % of the bot's health (the limit is 10 %).
Locally 2 of 20 seeds read 23 % and 5 % with the bodies indexed and none above 4.7 % without; after #1021 (bots throwing
into posts at their own feet) merged, 0 of 20 read above 1 % with them indexed. The soak's hand-ticked bodies had passed
through each other and through every cast, so a night that is not bit-identical from run to run (it depends on what ran
before it in the process) can hold a hazard that the unindexed bodies hid.

**The statistics keep their counts.** No seed, second or night count of a statistic was cut. What was cut:

- *Balance gate.* The three tests that prove the gate can fail (drifted tuning, an easy game, ammunition out of reach)
  read the cells that show the miss (a solo cell or two, 0.3 to 2 s at 20 nights; the 8 player cell is half of a batch at
  9 s) and drop the checker's `no cell X` lines, so that an absent cell is not read as a miss. Each still fails when the
  ranges are widened (checked). The climb test read three cells at 60 nights; it reads the 4 player night (the upgrade
  carries 0.53 rounds of the climb, 0.3 asked) and the strong solo night (0.80), and no longer the 8 player night
  (1.70, and the cell that costs the most).
- *Smallmap.* An event is true once it has happened: the solo bot has shown round 4, the first link, four torn windows
  and a weapon by 130 s of the 330 on all four seeds, so the night stops 30 s after (the cap on the dead alive is read
  to the end); the team's three links by 60 s of 210, so it stops when the third is bought. A test that reads where a bot
  is after a wait (the orders suites' "back at its order" after a ping's mark runs out) is true early for a trivial
  reason, and its wait stays.
- *Midway sweep.* A settling body whose tick changes nothing under an unchanged command leaves every later tick
  unchanged: 19,667 of the sweep's 21,423 hops settled early, 299,114 of 1,670,994 ticks skipped, and none of the 19,667
  ended in a different state than the full 24 ticks (0 mismatches). The grid and the hops are the same, and on the map
  before the fix (#876) both tests fail as they did. Giving the sweep's body the extra physics frame saved a further
  15 s but landed the hops at other floats, so its calibration (the 1 m grid, the recorded chain) would have to be
  redone, and it was not taken.

The method and the numbers (a tick's cost, the seed spread for sizing a statistic) are in the kit's
`docs/godot/test-speed.md`.

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
