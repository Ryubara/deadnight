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
  `tools/ci_test_shards.py` from the file list, so a new test file
  moved suites between shards, and the leak moved with them.
- Before #1234, #1214, #1228, #1229 and #1223 leaked and after it they did not, but #1234 does not touch it: on `main`
  with #1234 the two suites leak the same 243 and 257 objects alone. Their shards changed, and `main`'s own shard 1
  could not show it: it fails in the late-round budget step, before the tests step runs.

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
| The 71 suites of #1214's shard | 996, 432 | none (595 cases, 0 failures) |

The warm-up costs 7 seconds a shard (621 scripts, on a loaded machine). The leak check in `ci.yml` is as it was.

- `tests/core/test_exit_leak_warmup.gd` runs the two suites that leaked alone in a child Godot through the tool and
  fails on any leak line. Pointed at the plain tool it fails on the same lines (`leaked at exit`, 243 + 257 objects).
- `tools/ci_test_shards.py --self-test` fails when the godot job runs the plain tool again or loses its leak check.
- A real leak (a lambda cycle, a held node, a sound at quit) is not hidden: those are in objects that are held, and the
  suites for them (`test_audio_quit.gd`, the lessons linked in the kit's `docs/godot/test-exit-leaks.md`) still fail.

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
