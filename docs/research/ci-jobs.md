# What a pull request starts on CI

Why a push starts the jobs it does, and why the number is small on purpose (#447: the maintainer, 2026-11-02: "We have
PRs that are backing us up", with 21 open pull requests, the account's 20 concurrent jobs all busy and 33 queued).

## What each workflow does

| Workflow | Jobs | Starts when |
| --- | --- | --- |
| `ci` | `conventions` (first, seconds, also decides the rest) | every push to a pull request |
| | `godot`, `web` (about 15 minutes each) | the change touches something they can see |
| | `mkdocs`, `markdownlint`, `actionlint` | their own files changed |
| | `build-ok` | always: the one required name for the build |
| `pr` (`pull_request_target`) | `pr-rules` (the title, description, docs and commits checks, as steps) | every push and every edit of the description |
| `pr-status` | `labels` | the push, and once when `ci` ends (not when it was cancelled) |
| `docs` | `mkdocs` (pages build), `deploy` | a push to `main` only |

## Which files start which job

`.github/scripts/ci_scope.py` reads the pull request's changed files (the API, no checkout) and the `conventions` job
passes four answers on: `godot`, `web`, `docs`, `markdown`, `workflows`.

- A **documentation-only** pull request (`docs/**`, any `*.md`, `.github/ISSUE_TEMPLATE/**`) skips `godot` and `web`.
- A pull request that **only adds tests** (`game/tests/**`) skips `web`: the export's `exclude_filter` drops `tests/*`.
- `deploy/`, `spikes/` and `tools/web_smoke/` are not seen by the game's import and tests.
- `mkdocs` runs for `docs/**`, `mkdocs.yml`, `requirements-docs.txt` and any `*.md`; `markdownlint` for any `*.md` and
  the markdownlint rules; `actionlint` for `.github/workflows/**`.
- A list of no files, or of 3000 (the API's limit), turns everything on; so does a push to `main` or a manual run.

A required check whose job is skipped by an `if` reports success, so every required name (`pr-rules`, `conventions`,
`build-ok`, `mkdocs`, `markdownlint`, `actionlint`) is still reported. A path filter on the
whole workflow would leave the check missing and block the merge, which is why the filtering is done with `if`.
`build-ok` fails when `conventions`, `godot` or `web` failed or was cancelled, so a skipped job after a failed
`conventions` does not pass.

## The web job's browser steps

After the export the `web` job opens the build three times: `smoke.py` (the menu to a running night, frame budget,
console errors), `skin_tour.py` (the menu, the transitions, the credits) and `startup_check.py` (#484). The last walks
every menu path the other probes in `tools/web_smoke/` use, once: the Loadout tab, Play together, settings, Solo, and
on a `?dev` page the server address button to the join screen. The probes reach those through the shared helpers of
`smoke.py` (`reach_menu`, `menu_item`, `open_together`, `open_settings`, `start_solo`, `back_to_menu`) and
`online.open_address`, so a menu change is one edit there, and a change that breaks a path fails this step with the name
of the step and a screenshot (`failure.png` in the `web-smoke` artifact) instead of the next probe run: the rework of
the menu (#466) had broken `pointer_lock.py` and `touch_look.py`, which kept key walks of their own. Probes that start
from the address (`kill_spike.py` with `?bench`, `menu_stage.py` with `?stage`) or from their own scene
(`audio_load.py`, `gun_levels_web.py`, `door_swap.py`, `touch_assist.py`) walk no menu. About two minutes on the
software renderer. Run locally it goes under `gds quiet` like every probe.

## Folding the four `pr` checks into `pr-rules`

The ruleset requires `title`, `body`, `docs` and `commits` by name, and one job is one name, so folding them into one
job would block every pull request until the ruleset is edited. Replacing the four names with one saves three more jobs
a push, in three steps, because `pr.yml` runs from the base branch (`pull_request_target`) and a new name only reports
after its workflow is on `main`:

1. **Done (#457):** `pr.yml` gained the `pr-rules` job (the four checks as steps of one job, a later step still runs
   after a failed one so a run lists every refusal) beside the four old jobs.
2. **Done:** the maintainer edited the ruleset once `pr-rules` had reported on `main`: it now requires `pr-rules`,
   `conventions`, `build-ok`, `mkdocs`, `markdownlint` and `actionlint`, and the names `title`, `body`, `docs` and
   `commits` are gone.
3. **Done:** the four old jobs are deleted from `pr.yml` and `merge.required_checks` in `.github/conventions.yml` names
   the ruleset's six checks (a manual path: a maintainer merges it by hand). Nothing else named the four jobs:
   `pr_status.py` and the ruleset sync read `required_checks`, and the `pr-status` and `ci-failure` workflows watch
   the `ci` and `docs` workflows, not any job of `pr`. Only `CONTRIBUTING.md`'s list of required checks was
   updated by hand.

A push to a pull request now starts one `pr` job (`pr-rules`) where it started four, then five.

## Measured

Jobs started (not skipped) per push to a pull request, from the runs of one pull request head before and after:

| Pull request | Before | After |
| --- | --- | --- |
| Code and docs | 16 | 12 |
| Code only | 16 | 10 |
| Tests only | 16 | 9 |
| Documentation only | 16 | 10 |

Before, every pull request started the same 16: `ci` (`godot`, `web`, `build-ok`), `conventions`, `docs` (`mkdocs`,
`markdownlint`, `actionlint`), `pr` (four) and `pr-status` (five runs: one for the push and one per workflow that
ended, cancelled ones included). Now: `ci` (`conventions` and the jobs above, `build-ok`), the four `pr` jobs, and two
`labels` runs (these numbers were taken before step 3, which took three of the four `pr` jobs away). A
documentation-only pull request starts `conventions`, `mkdocs`, `markdownlint` and `build-ok` besides the `pr` jobs
and `labels`; none runs more than half a minute, so it is green in about two minutes where it waited for
a 15-minute build before. The 15-minute jobs that remain are the ones that were cancelled and restarted on every push:
a push that fails `conventions` now stops them from starting.
