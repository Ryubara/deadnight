#!/usr/bin/env bash
# Says whether a build may replace what a Railway service runs now, so a deploy job skips a build that is older than
# the live one and deploys every build that is newer.
#
#   deploy/check_head.sh <commit sha> <railway service>
#
# The `deploy` and `deploy-server` jobs of ci.yml run it first, when they start (after the wait in their concurrency
# group, so nothing else is deploying), from a checkout with the whole history. The service is shared and shows main,
# but the runs of two quick merges finish in any order, so the run of the older merge can reach its deploy after the
# newer run deployed (#552: `main 7c12a41` replaced `main 85325be` on Railway). #552 first skipped every build that was
# not the head of main; a run takes 10 to 25 minutes and merges land every few minutes, so no run was ever the head and
# nothing deployed for hours (#732). What matters is the build the service runs now, so the question is asked of it.
# Exit codes:
#
#   0  deploy: the commit is the live one (a redeploy), is ahead of it (the live commit is its ancestor), or the live
#      commit is not on main (a branch deploy by hand, or a rewritten history), or neither commit could be read
#      (that warns and deploys, as before this check)
#   3  skip: the commit is an ancestor of the live one, so it would put an older build over a newer one; or, when the
#      live commit cannot be read, the head of main is another commit (the run of the head deploys, or Actions, ci, Run
#      workflow, does)
#
# The live commit is the last word of the `cliMessage` of the newest SUCCESS deployment of the service (`main 1a2b3c4`,
# `game server 1a2b3c4`, which deploy/web/deploy.sh and deploy/server/deploy.sh set), read with the `railway` CLI and
# the project token, or `$DEPLOY_LIVE_SHA` (for deploy/test_check_head.sh). When it cannot be read or is not in this
# checkout, the head of main decides, as #552 did: `$DEPLOY_MAIN_HEAD`, else the GitHub API with `gh` and $GH_TOKEN,
# `$GITHUB_REPOSITORY`'s `main`.
set -uo pipefail

sha=${1:?usage: check_head.sh <commit sha> <railway service>}
service=${2:?usage: check_head.sh <commit sha> <railway service>}

# The commit the service runs now, or nothing.
live=${DEPLOY_LIVE_SHA:-}
if [ -z "$live" ] && command -v railway >/dev/null 2>&1; then
    for _ in 1 2 3; do
        if list=$(railway deployment list --service "$service" --json 2>/dev/null); then
            # newest first; the first deployment that is SUCCESS is the live one (older ones are REMOVED)
            live=$(printf '%s\n' "$list" | awk '
                /^  \{/ { st = ""; msg = "" }
                /^    "status"/ { split($0, p, "\""); st = p[4] }
                /^      "cliMessage"/ { split($0, p, "\""); n = split(p[4], w, " "); msg = w[n] }
                /^  \}/ { if (st == "SUCCESS") { print msg; exit } }')
            break
        fi
        sleep 5
    done
fi
case $live in
    *[!0-9a-f]* | "") live="" ;;
esac
[ "${#live}" -ge 7 ] || live=""

# live_commit is the full sha of the live commit, when this checkout has it (a shallow one cannot say).
live_commit=""
if [ -n "$live" ] && [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = false ]; then
    live_commit=$(git rev-parse --verify -q "$live^{commit}" 2>/dev/null) || live_commit=""
fi
this_commit=$(git rev-parse --verify -q "$sha^{commit}" 2>/dev/null) || this_commit=$sha

if [ -n "$live_commit" ]; then
    if [ "$live_commit" = "$this_commit" ]; then
        echo "${sha:0:7} is what $service runs now: redeployed"
        exit 0
    elif git merge-base --is-ancestor "$live_commit" "$this_commit" 2>/dev/null; then
        echo "${sha:0:7} is ahead of ${live:0:7}, which $service runs now: deployed"
        exit 0
    elif git merge-base --is-ancestor "$this_commit" "$live_commit" 2>/dev/null; then
        echo "::notice title=Not deployed::${sha:0:7} is older than ${live:0:7}, which $service runs now; the newer build stays"
        echo "${sha:0:7} is older than ${live:0:7}, which $service runs now: skipped" >&2
        exit 3
    fi
    echo "${sha:0:7} and ${live:0:7} (which $service runs now) are not on one line of history; the live one is not on main: deployed"
    exit 0
fi

# The live commit is unknown: fall back to the head of main (#552).
echo "::notice title=Live commit unknown::could not tell which commit $service runs (${live:-unreadable}); comparing with the head of main"
head=${DEPLOY_MAIN_HEAD:-}
if [ -z "$head" ]; then
    for _ in 1 2 3; do
        head=$(gh api "repos/${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}/commits/main" --jq .sha 2>/dev/null) && break
        head=
        sleep 5
    done
fi
if [ -z "$head" ]; then
    echo "::warning title=Head of main unknown::could not read the live commit or main; deploying $sha without the check"
    exit 0
fi

if [ "$head" = "$sha" ]; then
    echo "$sha is the head of main"
    exit 0
fi
echo "::notice title=Not deployed::${sha:0:7} is not the head of main (${head:0:7}) and the live commit is unknown; a newer run deploys the head"
echo "${sha:0:7} is not the head of main (${head:0:7}): skipped" >&2
exit 3
