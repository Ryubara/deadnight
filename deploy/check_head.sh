#!/usr/bin/env bash
# Says whether a commit is the head of main, so a deploy job can skip a build that is behind it.
#
#   deploy/check_head.sh <commit sha>
#
# The `deploy` and `deploy-server` jobs of ci.yml run it first. The service is shared and shows the head of main, but
# the runs of two quick merges finish in any order, so the run of the older merge can reach its deploy after the newer
# run deployed (#552: `main 7c12a41` replaced `main 85325be` on Railway). Exit codes:
#
#   0  the commit is the head of main (or the head could not be read: that warns and deploys, as before this check)
#   3  the head of main is another commit (a newer merge, or a rewritten history): skip the deploy; the run of the
#      head deploys it, or Actions, ci, Run workflow does
#
# The head is `$DEPLOY_MAIN_HEAD` (for deploy/test_check_head.sh), else read from the GitHub API with `gh` and
# $GH_TOKEN, `$GITHUB_REPOSITORY`'s `main`, read at this moment, after the job waited for its turn in the concurrency group.
set -uo pipefail

sha=${1:?usage: check_head.sh <commit sha>}

head=${DEPLOY_MAIN_HEAD:-}
if [ -z "$head" ]; then
    for _ in 1 2 3; do
        head=$(gh api "repos/${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}/commits/main" --jq .sha 2>/dev/null) && break
        head=
        sleep 5
    done
fi
if [ -z "$head" ]; then
    echo "::warning title=Head of main unknown::could not read main from the GitHub API; deploying $sha without the check"
    exit 0
fi

if [ "$head" = "$sha" ]; then
    echo "$sha is the head of main"
    exit 0
fi
echo "::notice title=Not deployed::${sha:0:7} is not the head of main (${head:0:7}); a newer run deploys the head"
echo "${sha:0:7} is not the head of main (${head:0:7}): skipped" >&2
exit 3
