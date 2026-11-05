#!/usr/bin/env bash
# Deploys an exported web build to the Railway service `web` and waits until it is live.
#
#   RAILWAY_TOKEN=<project token> deploy/web/deploy.sh [--force-branch] <build/web folder> <commit sha> [stage folder]
#
# With a project token the CLI needs no project or environment; locally, `railway link` the stage's parent or pass
# RAILWAY_TOKEN. Prints the deployment id; exits non-zero if the deploy fails or is not live after ten minutes.
# A failed upload or build is repeated up to three times when the service holds no live deployment of it, and never
# while one is going (deploy/railway_up.sh, #1269); $RAILWAY_DEPLOY_SECONDS caps the whole script (CI: below the job's limit).
#
# The service is shared and serves the head of main, so only main may be deployed to it: any other branch (or a
# detached checkout) is refused with one line unless `--force-branch` is given. The Railway message names the real
# branch and short sha ("main 1a2b3c4", "net-x 1a2b3c4", "detached 1a2b3c4"), so the deployment list says what is live.
# The branch is, in this order: $DEPLOY_BRANCH, the CI run's $GITHUB_REF_NAME, the branch the checkout holding this
# script is on. DEPLOY_DRY_RUN=1 checks the branch, prints the message and stops (for deploy/web/test_deploy.sh).
set -euo pipefail

usage="usage: deploy.sh [--force-branch] <build/web> <commit sha> [stage]"
force=0
args=()
for arg in "$@"; do
    case $arg in
        --force-branch) force=1 ;;
        *) args+=("$arg") ;;
    esac
done
build=${args[0]:?$usage}
sha=${args[1]:?$usage}
stage=${args[2]:-$(mktemp -d)}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=deploy/railway_up.sh
. "$here/../railway_up.sh"

branch=${DEPLOY_BRANCH:-}
if [ -z "$branch" ] && [ "${GITHUB_ACTIONS:-}" = true ]; then
    branch=${GITHUB_REF_NAME:-}
fi
if [ -z "$branch" ]; then
    branch=$(git -C "$here" symbolic-ref --short -q HEAD 2>/dev/null || true)
fi
branch=${branch:-detached}
message="$branch ${sha:0:7}"

if [ "$branch" != main ] && [ "$force" != 1 ]; then
    echo "refusing to deploy branch '$branch' to the shared web service (main only); pass --force-branch to do it anyway" >&2
    exit 2
fi
if [ "${DEPLOY_DRY_RUN:-}" = 1 ]; then
    echo "message: $message"
    exit 0
fi

test -s "$build/index.html" && test -s "$build/index.wasm" && test -s "$build/index.pck"

rm -rf "$stage"
mkdir -p "$stage/build"
cp "$here/Dockerfile" "$here/Caddyfile" "$here/railway.toml" "$here/discord-bridge.js" "$here/discord-share.js" "$stage/"
cp -r "$build" "$stage/build/web"

railway_up_retry web "$message" "$stage" || exit $?

# `up --ci` returns when the build is done; the deployment is live once Railway's health check (/healthz) passes.
for _ in $(seq 1 60); do
    [ "$(railway_time_left)" -gt 0 ] || break
    # the list is newest first; its first top-level "status" is the deployment just made (nothing: the CLI did not answer)
    status=$(railway_status web)
    echo "deployment: ${status:-unreadable}"
    case $status in
        SUCCESS) exit 0 ;;
        FAILED | CRASHED | REMOVED) exit 1 ;;
    esac
    sleep "${RAILWAY_POLL_SECONDS:-10}"
done
echo "deployment did not become live in ten minutes (or the time the job had left)" >&2
exit 1
