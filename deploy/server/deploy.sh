#!/usr/bin/env bash
# Deploys the game server to a Railway service from the `game/` project of this checkout.
#
#   deploy/server/deploy.sh <service name> [stage folder]
#
# Locally, `railway link` the project first (the test project is gdstudio-net-test). The service must exist; make it
# with `railway add --service <name>`, and give it a public domain with `railway domain --service <name>`.
set -euo pipefail

service=${1:?usage: deploy.sh <service name> [stage]}
stage=${2:-$(mktemp -d)}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

rm -rf "$stage"
mkdir -p "$stage/game"
cp "$here/Dockerfile" "$here/railway.toml" "$stage/"
# The project without the import cache, the reports and the test tooling the server never loads.
tar -C "$root" --exclude='game/.godot' --exclude='game/reports' --exclude='game/addons/gdUnit4' -cf - game \
    | tar -C "$stage" -xf -

railway up "$stage" --path-as-root --service "$service" --ci --message "game server $(git -C "$root" rev-parse --short HEAD)"

# `up --ci` returns when the build is done; the server is live once the deployment is SUCCESS (the server speaks
# WebSocket only, so there is no HTTP health check to wait for).
for _ in $(seq 1 60); do
    # the list is newest first; its first top-level "status" is the deployment just made
    status=$(railway deployment list --service "$service" --json | grep -m1 '^    "status"' | cut -d'"' -f4)
    echo "deployment: $status"
    case $status in
        SUCCESS) exit 0 ;;
        FAILED | CRASHED | REMOVED) exit 1 ;;
    esac
    sleep 10
done
echo "deployment did not become live in ten minutes" >&2
exit 1
