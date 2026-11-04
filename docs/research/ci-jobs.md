# What a pull request starts on CI

Why a push starts the jobs it does, and why the number is small on purpose (#447: the maintainer, 2026-11-02: "We have
PRs that are backing us up", with 21 open pull requests, the account's 20 concurrent jobs all busy and 33 queued).

## What each workflow does

| Workflow | Jobs | Starts when |
| --- | --- | --- |
| `ci` | `conventions` (first, seconds, also decides the rest) | every push to a pull request |
| | `godot` (17 to 20 minutes on 2026-11-02, limit 30), `web` (about 15) | the change touches something they can see |
| | `backend` (about a minute) | `spikes/backend/**` (not its Markdown) or `ci.yml` changed; every push to `main` |
| | `deploy-backend` (a few minutes) | a green push to `main` only: publishes `spikes/backend` to the `backend` service and compares its `/health` settings keys with the game's ([#944](platform-backend.md#a-setting-is-never-dropped-944)) |
| | `mkdocs`, `markdownlint`, `actionlint` | their own files changed |
| | `build-ok` | always: the one required name for the build |
| `pr` (`pull_request_target`) | `pr-rules` (the title, description, docs and commits checks, as steps) | every push and every edit of the description |
| `pr-status` | `labels` | the push, and once when `ci` ends (not when it was cancelled) |
| `docs` | `mkdocs` (pages build), `deploy` | a push to `main` only |
| `bots-nightly` | `plan`, `soak` (a matrix job of ten nights for each cell), `report` | 03:17 UTC every day and by hand; never on a pull request ([the bot soak](bots.md#the-nightly-soak-and-the-parity-batch)) |

## Which files start which job

`.github/scripts/ci_scope.py` reads the pull request's changed files (the API, no checkout) and the `conventions` job
passes its answers on: `godot`, `web`, `docs`, `markdown`, `workflows`, `backend`.

- A **documentation-only** pull request (`docs/**`, any `*.md`, `.github/ISSUE_TEMPLATE/**`) skips `godot` and `web`.
- A pull request that **only adds tests** (`game/tests/**`) skips `web`: the export's `exclude_filter` drops `tests/*`.
- `deploy/`, `spikes/` and `tools/web_smoke/` are not seen by the game's import and tests.
- `backend` runs the platform backend's own tests (`npm run typecheck`, `npm test` of `spikes/backend`, Node 24, with a
  Postgres 17 service so the two store tests do not skip; a skipped test fails the step) when `spikes/backend/**` other
  than Markdown, or `ci.yml`, changed, and on every push to `main` (#558). It waits for `conventions` only, so it runs
  beside the six Godot shards and never lengthens the critical path (about a minute against 5 to 6 minutes for a
  shard), and `build-ok` waits for it. Before it, nothing ran `node --test`: `godot` only installs the packages so the
  lobby's real-socket test can start the backend, so a backend change that broke a lobby, presence or ticket rule
  merged green.
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

## The docs rules of `pr-rules` (#540)

The kit's rules that make docs ship with a change (its `docs/hooks.md#docs`) apply here through the same checker
(`.github/scripts/groundwork.py`, synced from the kit with `gds sync`) and this repository's `.github/conventions.yml`
(`pull_requests.lessons`, `read_first`, `kit_docs`). The description step runs `groundwork.py pr-history` first, which
asks GitHub (read-only: the `checks: read` and `issues: read` permissions of the job) which watched checks failed on an
earlier commit of the pull request and which issues it closes, with their labels; it falls back to the title alone when
GitHub cannot be asked.

- `Lessons:` in Summary: a pull request titled `Fix` or `Rework`, or after a failed `build-ok`, `conventions`, `mkdocs`,
  `markdownlint` or `actionlint` on an earlier commit, or closing a `bug` issue, links the kit's lesson
  (`docs/lessons/<yyyy-mm-dd>-<slug>.md`) or a row of its corrections page. `Lessons: none (reason)` is refused there and
  allowed elsewhere.
- `Kit docs:` in Summary: the same pull requests name the kit pull request that documents the process
  (`gdstudio#N` or its URL), or `Kit docs: none (reason)`.
- `Read first:` in Summary: a pull request that closes an issue names the areas whose checks the author read first
  (`gds lessons <area>`). The kit's `areas.toml` is not in this repository, so the line is required but not matched
  against the issue's labels.

A `none (reason)` line ends with the `)`. Changing the rules is a change to `.github/conventions.yml`, which a
maintainer merges by hand.

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

## When the `godot` job looks hung

A job cut at its `timeout-minutes` ends its log on whatever test was running, so the last `STARTED` line names an
innocent test (#488: `test_night_shot_authority.gd` "hung" 15 ms before GitHub cancelled the job at exactly 20
minutes; it passes alone and in its folder). Before suspecting the test, compare the cancel time with the job's start
plus its limit, and list the longest gaps between log timestamps: a real hang leaves a gap of minutes, a cut leaves
none. The test step has grown to 17 to 20 minutes, so #501 raised the limit to 30; a pull request that adds slow suites
(real physics frames, about 2 s each case) says so in its description.
