# The UI suites in a window, on a schedule (#1196)

CI runs every GdUnit suite headless, where the game's own switches that a window turns the other way are off, so a
suite can rot unseen ([windowed against headless](windowed-vs-headless-tests.md): #1187, #1195). The `ui-windowed`
workflow runs `game/tests/ui` in a window on a schedule and reports what fails there. It is never part of a pull
request and never a required check, so it cannot block a merge.

## What was proved (2026-11-05)

Windowed GdUnit4 runs on a stock `ubuntu-24.04` runner under `xvfb-run` with Mesa's software GL and the Compatibility
renderer: Godot 4.7.2 and GdUnit4 6.2.2 as pinned, no change to `tools.toml`. Godot reports
`OpenGL API 4.5 (Core Profile) Mesa 25.2.8 ... llvmpipe`. The recipe is the kit's
[Windowed GdUnit on a Linux runner](https://github.com/Ryubara/gdstudio/blob/main/docs/godot/windowed-gdunit-on-linux.md).

| Step | Seconds |
| --- | --- |
| Two checkouts (LFS included) | 24 |
| `apt` packages (xvfb, Mesa, X libraries) | 9 |
| Workspace, pinned Godot and GdUnit4 | 2 (cached) |
| Import | 14 |
| All 114 suites, one process each (the first full run, two of them timing out at 300 s) | 2,605 (43 min 25 s) |
| The 110 suites the schedule runs (the last full run, 997 cases, none skipped) | 2,376 (39 min 36 s) |
| A failed suite run again headless | 186 for all of them |

The whole job takes about 41 minutes (setup 50 s). The same folder on a real window (Windows, a GPU) took 23.2 min.

- **Skips.** 1,002 test cases ran on the runner with 0 skipped (the real window: 1,007, 0 skipped). Headless,
  as CI runs it, `test_level_ink` and `test_poster_art_pixels` skip 14 of their 15 cases; on the runner they run,
  and pass, on real pixels. The job reports a pixel suite that skips there, or runs no case, as "did not run",
  not as a pass.
- **The hang does not appear.** The kit's
  [hang](https://github.com/Ryubara/gdstudio/blob/main/docs/lessons/2026-11-04-a-windowed-gdunit-run-hung-the-night-suites-after-a-ui-suite.md)
  (a UI suite that pushes mouse events, then `test_night_crosshair`, in one process) finished in 57 s on the runner.
  Deadnight #1207 finds `test_night_screen` hanging after `test_night_crosshair` in one windowed session on a real
  machine: running one process per suite, each with its own timeout, keeps both out of the schedule.

## Which suites the runner can judge

Compared suite by suite with the real window (on the `main` of that morning):

- **Same answer: 107 of the 113 suites both runs had.** Every suite that reads pixels, measures layout or drives
  input agreed, including the failures #1194 and #1195 fixed (`test_hover_room`, `test_night_crosshair`, `test_bot_wheel_input`,
  `test_night_menu`, `test_night_mouse_look`, `test_night_screen`): the runner found the same cases that fail in a window.
- **Not judged by llvmpipe (4 suites, in the known list with a reason).** They pass on a real window and headless:
    - `test_hud_prompt_fit` did not finish in 900 s (39 s on a GPU) and `test_menu_hero_arms` took 9 min 40 s (17 s):
      they draw a great deal in real time and a CPU rasteriser is 20 to 40 times slower.
    - `test_menu_stage` (a stage that must draw every frame, 4 against 1 counted) and `test_reduced_motion_skin` (a
      state read inside a timed fade) fail on the runner and pass in a real window: fewer frames per second.
  They are run and shown, never a reason to open an issue. A regression in these four is seen only on a GPU.
- **Fail in a real window and pass on the runner (2 suites, fixed since by #1203).** `test_hud_idle_redraws` and
  `test_ui_check_box` read a value after a count of frames, and a real window has no frame cap. A virtual display is a
  window, but not every window: the runner does not see a frame-rate dependence of this kind.
- **Not caught by the guard's source scan but caught by the window.** `test_night_screen_end` failed in both windows
  (#1201, fixed by #1208); it reaches the night through the Play screen. The known list is down to the four unjudged
  suites: every failure listed with an issue was fixed (#1194, #1198, #1203, #1208) before this landed.

## The job (`.github/workflows/ui-windowed.yml`)

- **When.** 04:47 UTC every day, and by hand (`workflow_dispatch` takes a comma-separated list of suites and a timeout).
  A run of a subset says so in its summary and neither opens nor closes the issue.
- **How.** `tools/ui_windowed.py run`: one Godot per suite under `xvfb-run`, its own process group, a 300 s limit
  (killed as a group). A suite that does not pass is run again headless, to say whether the window is what differs.
  It writes `result.json` after every suite, marked incomplete until the last.
- **What it reports** (`tools/ui_windowed.py report`, from the result files and the run job's own result):
    - *failing*: a suite fails in the window and passes headless; fails in both (main is red, or the runner); a
      pixel suite did not run; or a known failure passes now (remove it from `tools/ui_windowed_known.json`).
    - *could-not-run*: the run job failed, was cancelled, left no result or stopped part way (its step limit is below
      the job's). Never read as clean.
    - *known-only* and *clean*: nothing to do; a listed failure stays listed with its issue.
- **How it reaches us.** The `report` job runs `if: always()`. On *failing* or *could-not-run* it opens one issue
  ("Windowed UI suites need a look", `task`, `A-tests`, `S-needs-triage`, the task form's sections and a `From:` line),
  rewrites its text on every run, comments only when the kind changes, closes it on the first clean or known-only run, and
  fails the run, so the run list is red as well. The workflow is the actor; no agent posts. A *could-not-run* shown by
  trial (a suite name that does not exist) and a *failing* one (a real suite) both opened their issue and failed the job.
- **The known list** (`tools/ui_windowed_known.json`): a suite that fails in the window on purpose-for-now, with the issue
  that fixes it, or with `llvmpipe:` and why the runner cannot judge it. The first kind goes stale when it passes and then
  fails the report, so the list only shrinks.

## The headless guard

`tests/ui/test_ui_suites_start_a_night_with_no_drop_due.gd` lists the suites that push the night screen (`push`,
`reset`, `replace` or a `_push` helper, of `NIGHT` or of the scene's path) and fails one that never writes
`NightScreen.arrival_enabled = false` (or `true`, for a suite about the drop): restoring the old value does not count.
Its allowlist (`NOT_YET`) named #1195's three suites when this was written; they have landed, so it is empty, and an entry
that sets the switch fails the scan. `main.tscn` is not scanned: it opens the menu, and a night starts only where a suite
pushes the night. Four suites set the switch in this change (`test_night_mouse_grip`, `test_night_pad_pause`,
`test_night_scale`, `test_menu_ambience`); they passed both ways before and after.

## Not proved

- A schedule that never starts (GitHub disables scheduled workflows of a repository with no activity for 60 days) raises
  nothing; the run list is where it shows.
- The runner's four unjudged suites, and any suite whose answer depends on a GPU's frame time.
- The first scheduled run: every trial ran by push on the branch, not by the schedule.
