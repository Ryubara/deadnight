#!/usr/bin/env bash
# Lints a pull request's changed scripts as they would land on the base as it is now, not as it was when the run began.
#
#   bash tools/gdlint_on_base.sh <base commit> <pull request head> <lint command...>
#
# A `pull_request` run checks out the merge made when it started, and the ruleset does not ask for an up-to-date branch,
# so a pull request that lands while the run goes is in nobody's merged head: #1225's run began eight minutes before
# #1214 landed, and the two crossed `max-file-lines` (#1238). The `gdlint-late` job runs this last, just before
# `build-ok`. Only the files the pull request changes can differ from a base that its own `push` run judges, and
# `gdlint` reads one file at a time, so linting those is enough and takes seconds.
#
# Nothing is committed: `git merge-tree` makes the merge as a tree and the changed files are written from it. A pull
# request that conflicts with the base passes here, because GitHub will not merge it and the conflict has to go first.
set -euo pipefail

base=$1
head=$2
shift 2

if merged=$(git merge-tree --write-tree "$base" "$head"); then
    :
else
    status=$?
    if [ "$status" -eq 1 ]; then
        echo "The pull request conflicts with the base: nothing to lint until that is resolved."
        exit 0
    fi
    exit "$status"
fi

mapfile -d '' -t files < <(git diff -z --name-only --diff-filter=d "$base...$head" -- '*.gd')
if [ "${#files[@]}" -eq 0 ]; then
    echo "The pull request changes no script: nothing to lint."
    exit 0
fi

git restore --source="$merged" --worktree -- "${files[@]}"
echo "Linting ${#files[@]} changed script(s) on the base at $(git rev-parse --short "$base")."
"$@" "${files[@]}"
