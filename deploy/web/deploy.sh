#!/usr/bin/env bash
# Deploys an exported web build to the Railway service `web` and waits until it is live.
#
#   RAILWAY_TOKEN=<project token> deploy/web/deploy.sh <build/web folder> <commit sha> [stage folder]
#
# With a project token the CLI needs no project or environment; locally, `railway link` the stage's parent or pass
# RAILWAY_TOKEN. Prints the deployment id; exits non-zero if the deploy fails or is not live after ten minutes.
set -euo pipefail

build=${1:?usage: deploy.sh <build/web> <commit sha> [stage]}
sha=${2:?usage: deploy.sh <build/web> <commit sha> [stage]}
stage=${3:-$(mktemp -d)}
here=$(cd "$(dirname "$0")" && pwd)

test -s "$build/index.html" && test -s "$build/index.wasm" && test -s "$build/index.pck"

rm -rf "$stage"
mkdir -p "$stage/build"
cp "$here/Dockerfile" "$here/Caddyfile" "$here/railway.toml" "$here/discord-bridge.js" "$stage/"
cp -r "$build" "$stage/build/web"

railway up "$stage" --path-as-root --service web --ci --message "main ${sha:0:7}"

# `up --ci` returns when the build is done; the deployment is live once Railway's health check (/healthz) passes.
for _ in $(seq 1 60); do
    # the list is newest first; its first top-level "status" is the deployment just made
    status=$(railway deployment list --service web --json | grep -m1 '^    "status"' | cut -d'"' -f4)
    echo "deployment: $status"
    case $status in
        SUCCESS) exit 0 ;;
        FAILED | CRASHED | REMOVED) exit 1 ;;
    esac
    sleep 10
done
echo "deployment did not become live in ten minutes" >&2
exit 1
