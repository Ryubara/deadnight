# Why a shard leaked at exit with every test green, and what stops it (#1231)

`godot (1)` failed pull requests that had nothing to do with each other (#1214, #1223, #1226, #1228, #1229): every test
passed, GdUnit printed `Exit code: 0`, and the log ended with 996 to 1,042 `ObjectDB instances were leaked at exit` and
432 `resources still in use at exit` (GDScript 210, Resource 513, Image 155, TextLine 39, ...). The job's last line,
`! grep -E "leaked at exit|still in use" tests.log`, failed it. Main's shards were clean, and a pull request that added
a test file could turn a clean shard into a leaking one and a later merge of main turn it back.

## What it is

The leak is not a test that forgot an object, and it is not in a pull request's change. It is a script that only another
script names:

- A suite that names a class (`HeldWeapon`, `RecutSkin`, the lot's silhouettes) makes Godot read that class's scripts
  as the suite's dependencies. A script that is read that way and never loaded as a script of its own is still in use
  when the process quits, and so are the scripts, statics, fonts, textures and audio banks it reaches: hundreds of
  objects, none of them a node, all of them held by one script.
- Two suites leak **alone**, on Windows, on `main` before and after #1234: `weapons/test_recut_skin.gd` (243 objects,
  174 resources) and `world/test_drive_in_greybox.gd` (257, 181). Every single test case of the first leaks the same 243
  (a file with one test that reads a string from a shader does too), so it is the suite's script and what it names, not
  what a test does. Loading `HeldWeapon` from a ten-line script leaks 13 objects; loading `WeaponHandsIK` leaks 2.
- Whether a shard leaks depends on which suites it holds, because another suite that names the same classes loads them
  first. In the mix of #1214 it leaked 996 objects, run here on Windows with the same list and `--verbose` (996, 432
  resources). Thirteen suites run first with `test_recut_skin.gd` make it clean (player, character, lobby and menu
  ones: `test_sprint_sway`, `test_lobby_screen`, `test_ui_router_robustness`, ...); others (`test_audio_mix`,
  `test_hud_shapes`, `test_poster_set_view`) make it leak 740 to 905. The split of the suites is dealt by
  `tools/ci_test_shards.py` from the file list, so a new test file moved suites between shards, and the leak moved
  with them.
- Why `main` stayed clean: its runs 42011482212 (61a990d) and 42016360272 (98283f8) dealt both leaking suites to shard
  3, with 72 others (74 suites), and shard 3 passed the leak check in both (`Run the tests` success, 620 cases, no leak
  line). Shard 1 of those runs held 115 suites, neither of the two, and passed too. It is the mix again: the same two
  suites leak alone and not in that shard's mix. The red `main` runs 42004177635 (d47bfae) and 42004654168 (5c42a57)
  failed shard 1 in `Hold the late-round worst case to its budget` and skipped its tests step, so they say nothing
  about leaks in shard 1; they are not evidence that `main` was clean.
- #1234 does not touch the leak: on `main` with #1234 the two suites leak the same 243 and 257 objects alone. A pull
  request's shard leaks when its deal puts the leaking suites with a mix that does not cure them, and the deal moves
  with every test file added.

The same family as the kit's lesson on dev scripts in a scanned folder (a script loaded first leaves others in use,
`docs/godot/test-exit-leaks.md` in the kit), by a different road: the suites are handed by path here, so it is the
suite's own dependencies.

## The fix

`tools/ci/warm_GdUnitCmdTool.gd` is GdUnit4's command line tool after `ScriptWarmup.load_all()` has loaded every script
of `addons/gds_ui`, `core`, `gameplay`, `net`, `ui` and `world` as itself, in name order. CI runs the tests through it
(`.github/workflows/ci.yml`). Loaded first, as themselves, the scripts leave nothing in use:

| Run | Plain GdUnit tool | Through `warm_GdUnitCmdTool.gd` |
| --- | --- | --- |
| `test_recut_skin.gd` alone | 243 objects, 174 resources | none |
| `test_drive_in_greybox.gd` alone | 257, 181 | none |
| Five suites that leak together (listed below) | 911, 451 | none |
| Shard 8 of this branch's deal (75 suites, holds `test_recut_skin.gd`) | none (this mix cures it) | none |

The five suites are `test_audio_mix`, `test_hud_shapes`, `test_poster_set_view`, `test_recut_skin` and
`test_drive_in_greybox`, in that order. That list and shard 8 each ran through both tools, one after the other, with
the same arguments; the two runs of each ran the same cases (compared by suite and case name from each run's
`results.xml`): 55 cases and 55, 565 cases and 565 (34 skipped in both), no case in one and not the other, 0 failures,
0 orphans. The 71-suite shard of #1214, which gave 996 objects and 432 resources through the plain tool, was run
earlier in this task; its list and logs were deleted, and its case counts (596 plain, 595 through the wrapper) were
never reconciled, so nothing here rests on that pair. The warm-up costs 4 to 14 seconds a run (625 scripts, on a
loaded machine). The leak check in `ci.yml` is as it was.

- `tests/core/test_exit_leak_warmup.gd` runs the two suites that leaked alone in a child Godot through the tool and
  fails on any leak line. Pointed at the plain tool it fails on the same lines (`leaked at exit`, 243 + 257 objects).
- `tools/ci_test_shards.py --self-test` fails when the godot job runs the plain tool again or loses its leak check.
- A real leak is not hidden, shown by running it through `warm_GdUnitCmdTool.gd` (three throwaway suites, not
  committed): one suite that leaves a cycle of two `RefCounted` objects and a `Node` held by a static variable printed
  `WARNING: 3 ObjectDB instances were leaked at exit` and exited 101, so CI's `! grep -E "leaked at exit|still in use"`
  would fail on it; a suite with `assert_int(1).is_equal(2)` exited 100; a clean suite exited 0 with no leak line.

## What holds it, and what this does not do

The issue asks for the fix at the object that holds the graph. This is not that. As far as I found, what holds it is
engine-side, in how a script read only as another script's dependency is kept until the process quits: it is not a
node, a timer, a signal or a cycle in the game's code. Evidence: the held objects are GDScript, Resource, Image and
TextLine instances; one test case alone leaks the same count as the whole suite; loading the same script as itself
first leaves nothing; and breaking a type cycle between two classes (`ReloadPose` and `ReloadMotion`) in the game's
scripts changed neither count, so it was reverted. I did not find the engine's holder, and I did not fix the game at
one. The runner is the place because the set of scripts that leak is every script a suite names and nothing loads, it
changes with every suite and class added, and the load order is what decides it: a fixed load of every script in
name order makes the result independent of the deal. That choice, rather than a fix at the holder, is the
maintainer's to accept.

## Not yet proved by CI

That `godot (1)` of #1214 and #1226 no longer fails this way is not shown by a CI run of this branch: it is shown by
local runs of the leaking lists above. #1214's latest run on its own branch (9662a53) passed after main with #1234 was
merged into it; that is the deal moving, not this change. This page is to be read with the first CI run of the
branch.

Why the name: GdUnit4 finds its own arguments after the argument that contains `GdUnitCmdTool.gd`, so the wrapper's
file name ends with it (a wrapper called `gdunit_run.gd` printed the usage and ran nothing).

## How it was found (for the next one)

1. Run the shard's exact list on the machine you have, with the engine's `--verbose`: it printed the same 996 objects on
   Windows, so no Linux was needed. Pass the suites as `-a` paths, in the shard's order.
2. Bisect the list by running chunks in parallel (four at most): quarters, then halves, then each suite alone. Two
   suites leaked alone.
3. Split a suite into one file per test case (header, one test, the helpers): every case leaked the same count, so it
   is the suite's script.
4. Probe scripts: `extends SceneTree`, `load(PROBE_PATH)` in `_init`, `quit()`, a one-second run per script; sweeping
   the 582 game scripts found six that leak alone (the weapon hands, the silhouettes, the warm-up manifest, a screen).
   Loading all 582 in name order leaves 4 objects.
5. Compare with a clean list's suites to see which of them heal a leaking one (pairs of the healer first and the
   leaking suite: thirteen of thirty-four).

A long run that goes quiet on a loaded machine is not a hang: two parallel full-shard runs here stopped answering for
25 minutes (the net suites take ports); run one at a time, and write the log to a file, not through a pipe that waits.
