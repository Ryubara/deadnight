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
| `pr` (`pull_request_target`) | `title`, `body`, `docs`, `commits` | every push and every edit of the description |
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

A required check whose job is skipped by an `if` reports success, so every required name (`title`, `body`, `docs`,
`commits`, `conventions`, `build-ok`, `mkdocs`, `markdownlint`, `actionlint`) is still reported. A path filter on the
whole workflow would leave the check missing and block the merge, which is why the filtering is done with `if`.
`build-ok` fails when `conventions`, `godot` or `web` failed or was cancelled, so a skipped job after a failed
`conventions` does not pass.

## Why `pr` still has four jobs

The ruleset requires `title`, `body`, `docs` and `commits` by name, and one job is one name, so folding them into one
job would block every pull request until the ruleset is edited. The change that would save three more jobs a push is
to replace the four names with one (for example `pr-rules`, one job with the four steps), in three steps because
`pr.yml` runs from the base branch (`pull_request_target`) and a new name only reports after its workflow is on `main`:
(1) merge a pull request that adds the `pr-rules` job next to the four old ones; (2) the maintainer edits the ruleset,
adding `pr-rules` and removing `title`, `body`, `docs` and `commits` in one edit; (3) merge a pull request that deletes
the four old jobs. Until then the four jobs stay.

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
`labels` runs. A documentation-only pull request starts `conventions`, `mkdocs`, `markdownlint` and `build-ok` besides
the `pr` jobs and `labels`; none runs more than half a minute, so it is green in about two minutes where it waited for
a 15-minute build before. The 15-minute jobs that remain are the ones that were cancelled and restarted on every push:
a push that fails `conventions` now stops them from starting.

Test line for the CI scope check; this branch is never merged.
