# Contributing to Deadnight

Thank you for helping. This page is short on purpose: the rules a program can check live in
[`.github/conventions.yml`](.github/conventions.yml), and the checks tell you what is wrong.

## The flow

1. Start from an issue (the forms ask for what is needed), or open one first for anything larger than a small fix.
2. Work on a branch. `main` takes no direct pushes; every change is a pull request.
3. Give the pull request a title, and its commits messages, that follow the commit rules below.
4. Fill in the pull request template. Every task you list is finished and ticked; work you do not finish goes in
   its own issue. If the pull request finishes an issue, add a line `Fixes #<number>`.
5. A change to the game's code (`game/` outside `assets/`, or `server/`) also changes `docs/` or `README.md`, or
   the description says `Docs: none`.
6. The pull request is squash-merged: the title becomes the one commit on `main`.

## Commit rules

Generated from `.github/conventions.yml` (`groundwork.py render`); what each area covers is listed there.

<!-- conventions:begin commit-rules -->
- Title `area: Verb the rest`, at most 72 characters, present tense, no trailing period. Verbs: Add, Fix, Update,
  Remove, Rebuild, Rework, Improve, Document. Areas: `core`, `gameplay`, `ui`, `net`, `world`, `art`, `audio`,
  `build`, `ci`, `agents`, `docs`, `tests`. A breaking change ends the title with `(BREAKING)`.
- An agent ends the message with `Co-Authored-By: <model name> <noreply address>` (one of: `noreply@anthropic.com`,
  `noreply@google.com`, `noreply@openai.com`) and no other trailer. No other e-mail address appears in a message.
<!-- conventions:end -->

## Checks

The required checks are `title`, `body`, `docs`, `commits`, `conventions`, `build-ok`, `mkdocs`,
`markdownlint` and `actionlint`. Before you push, `uvx pre-commit run --all-files` runs the local ones, and
`uv run --with pyyaml python .github/scripts/groundwork.py check --offline` shows whether the generated files
still match the conventions.

## Conduct

Be kind. See the [Code of Conduct](CODE_OF_CONDUCT.md).
