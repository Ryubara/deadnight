#!/usr/bin/env bash
# Deploys the platform backend (spikes/backend) to the Railway service `backend` and waits until it is live and takes
# the game's match settings.
#
#   RAILWAY_TOKEN=<project token> deploy/backend/deploy.sh [service name] [stage folder]
#
# Locally, `railway link` the project first. The service must exist (it keeps its Postgres reference and its secrets;
# only the code is replaced). The Railway message is `backend <short sha>`, which deploy/check_head.sh reads to tell
# whether a build is older than the live one. After the deployment is SUCCESS (its own health check passed), the live
# `/health` is compared with the game's keys (deploy/backend/check_keys.sh): a deploy of a backend that is behind the
# game fails the job, loudly (#944).
set -euo pipefail

service=${1:-backend}
stage=${2:-$(mktemp -d)}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

rm -rf "$stage"
mkdir -p "$stage"
cp "$here/railway.toml" "$stage/"
# The code and what builds it, without the packages and the tests.
tar -C "$root/spikes/backend" --exclude=node_modules --exclude=test --exclude=dist -cf - \
    Dockerfile package.json package-lock.json tsconfig.json src \
    | tar -C "$stage" -xf -

railway up "$stage" --path-as-root --service "$service" --ci --message "backend $(git -C "$root" rev-parse --short HEAD)"

for _ in $(seq 1 60); do
    # the list is newest first; its first top-level "status" is the deployment just made
    status=$(railway deployment list --service "$service" --json | grep -m1 '^    "status"' | cut -d'"' -f4)
    echo "deployment: $status"
    case $status in
        SUCCESS) break ;;
        FAILED | CRASHED | REMOVED) exit 1 ;;
    esac
    sleep 10
done
[ "${status:-}" = SUCCESS ] || { echo "deployment did not become live in ten minutes" >&2; exit 1; }

url=${BACKEND_URL:-$(railway domain --service "$service" 2>/dev/null | grep -oE 'https://[^ ]+' | head -1)}
if [ -z "$url" ]; then
    echo "::error title=No backend address::the service has no public domain to check the settings keys on" >&2
    exit 1
fi
bash "$here/check_keys.sh" "$url"
