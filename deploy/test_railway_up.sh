#!/usr/bin/env bash
# Tests the retry of `railway up` (deploy/railway_up.sh) through the three real deploy scripts with a fake `railway` first
# on the PATH that fails the way Railway did (`failed to fetch snapshot`, #1269) and in the other ways an attempt ends:
# a failure that left a finished deployment is repeated, one that left a deployment still going is not, the attempts and
# the seconds are bounded, a real failure still fails, and `up` never starts while a deployment of the service is going.
#
#   bash deploy/test_railway_up.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# The scripts in a tree of their own, with the files they copy, as a checkout that has a git history (they ask for the sha).
tree=$work/tree
mkdir -p "$tree/deploy/web" "$tree/deploy/server" "$tree/deploy/backend" "$tree/game" "$tree/spikes/backend/src" "$work/build"
cp "$here/railway_up.sh" "$tree/deploy/"
cp "$here/web/deploy.sh" "$here/web/Dockerfile" "$here/web/Caddyfile" "$here/web/railway.toml" "$here/web/discord-bridge.js" \
    "$here/web/discord-share.js" "$tree/deploy/web/"
cp "$here/server/deploy.sh" "$here/server/Dockerfile" "$here/server/railway.toml" "$tree/deploy/server/"
cp "$here/backend/deploy.sh" "$here/backend/railway.toml" "$tree/deploy/backend/"
echo 'exit 0' >"$tree/deploy/backend/check_keys.sh" # the settings comparison has its own test
echo x >"$tree/game/project.godot"
echo x >"$tree/spikes/backend/src/a.ts"
for f in Dockerfile package.json package-lock.json tsconfig.json; do echo x >"$tree/spikes/backend/$f"; done
for f in index.html index.wasm index.pck; do echo x >"$work/build/$f"; done
git -C "$tree" init -q -b main
git -C "$tree" add -A 2>/dev/null
git -C "$tree" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m first

# The fake CLI. State lives in $FAKE_STATE:
#   deployments    "id:status" lines, newest first (d0 is the live one before the deploy)
#   ups            one line per `railway up`
#   lists          one line per `deployment list`
#   overlap        written when `up` starts while the newest deployment is not over
# FAKE_UP: the way each `up` ends, a word per attempt (the last repeats):
#   ok         a SUCCESS deployment, exit 0
#   badbuild   a FAILED deployment, exit 0   (a build that failed after the CLI was told to go on: the wait loop judges it)
#   snapshot   a FAILED deployment, "failed to fetch snapshot", exit 1
#   net        no deployment, exit 1
#   ghost      a BUILDING deployment, exit 1 (the CLI's stream broke); it ends as FAKE_GHOST_END after FAKE_GHOST_POLLS lists
#   finished   a SUCCESS deployment, exit 1 (the stream broke after the build)
#   hang       no deployment, runs for 30 s (stopped by the attempt limit)
#   slow       a FAILED deployment after FAKE_SLOW seconds, exit 1
# FAKE_LIST_FAIL: numbers of the `deployment list` calls that fail ("2 3"); FAKE_LIST_BROKEN_AFTER_UP: from the first `up` on.
mkdir -p "$work/bin"
cat >"$work/bin/railway" <<'EOF'
#!/usr/bin/env bash
state=$FAKE_STATE
case $1 in
    up)
        echo up >>"$state/ups"
        n=$(wc -l <"$state/ups")
        read -r -a words <<<"$FAKE_UP"
        idx=$((n - 1)); [ "$idx" -lt "${#words[@]}" ] || idx=$((${#words[@]} - 1))
        kind=${words[$idx]}
        newest=$(head -1 "$state/deployments"); newest=${newest#*:}
        case $newest in SUCCESS | FAILED | CRASHED | REMOVED) ;; *) echo "up while $newest" >>"$state/overlap" ;; esac
        add() { { echo "d$n:$1"; cat "$state/deployments"; } >"$state/new" && mv "$state/new" "$state/deployments"; }
        echo "Indexing... Uploading... (attempt $n: $kind)"
        case $kind in
            ok) add SUCCESS ;;
            badbuild) add FAILED ;;
            snapshot) add FAILED; echo "failed to fetch snapshot" >&2; echo "Deploy failed: Failed to build an image." >&2; exit 1 ;;
            net) echo "error sending request" >&2; exit 1 ;;
            ghost) add BUILDING; echo "stream closed" >&2; exit 1 ;;
            finished) add SUCCESS; echo "stream closed" >&2; exit 1 ;;
            hang) sleep 30; exit 1 ;;
            slow) sleep "$FAKE_SLOW"; add FAILED; echo "failed to fetch snapshot" >&2; exit 1 ;;
        esac
        ;;
    deployment)
        echo list >>"$state/lists"
        n=$(wc -l <"$state/lists")
        [ ! -s "$state/ups" ] || [ -z "${FAKE_LIST_BROKEN_AFTER_UP:-}" ] || exit 1
        for k in ${FAKE_LIST_FAIL:-}; do [ "$k" != "$n" ] || exit 1; done
        top=$(head -1 "$state/deployments")
        if [ "${top#*:}" = BUILDING ]; then
            polls=$(( $(cat "$state/ghost" 2>/dev/null || echo 0) + 1 ))
            echo "$polls" >"$state/ghost"
            if [ "$polls" -gt "${FAKE_GHOST_POLLS:-1}" ]; then
                { echo "${top%%:*}:${FAKE_GHOST_END:-SUCCESS}"; tail -n +2 "$state/deployments"; } >"$state/new" && mv "$state/new" "$state/deployments"
            fi
        fi
        echo "["
        first=1
        while IFS=: read -r id status; do
            [ $first = 1 ] || echo "  },"
            first=0
            printf '  {\n    "id": "%s",\n    "status": "%s",\n    "createdAt": "2026-11-05T14:45:45.000Z",\n    "meta": {\n      "cliMessage": "main 0123456"\n    },\n' "$id" "$status"
            echo '    "url": "x"'
        done <"$state/deployments"
        echo "  }"
        echo "]"
        ;;
    domain) echo "https://backend.example.test" ;;
    status) [ -z "${FAKE_UNLINKED:-}" ] || { echo "No linked project found" >&2; exit 1; } ;;
    *) echo "fake railway: $*" >&2; exit 64 ;;
esac
EOF
chmod +x "$work/bin/railway"

# run <script: web|server|backend> <expected exit> <expected ups> <expected output part> [more] -- ENV=value...
run() {
    local script=$1 want_code=$2 want_ups=$3 want_out=$4 want_more=${5:-} out code ups started
    shift 6
    rm -rf "$work/state"
    mkdir -p "$work/state"
    echo "d0:SUCCESS" >"$work/state/deployments"
    local args=()
    case $script in
        web) args=("$tree/deploy/web/deploy.sh" "$work/build" 0123456789abcdef "$work/stage") ;;
        server) args=("$tree/deploy/server/deploy.sh" deadnight-server "$work/stage") ;;
        backend) args=("$tree/deploy/backend/deploy.sh" backend "$work/stage") ;;
    esac
    started=$SECONDS
    out=$(env PATH="$work/bin:$PATH" FAKE_STATE="$work/state" RAILWAY_TOKEN=token DEPLOY_BRANCH=main RAILWAY_UP_PAUSE=0 RAILWAY_POLL_SECONDS=0 \
        "$@" bash "${args[@]}" 2>&1)
    code=$?
    ups=0
    [ ! -f "$work/state/ups" ] || ups=$(wc -l <"$work/state/ups")
    local ok=1
    [ "$code" = "$want_code" ] || ok=0
    [ "${ups:-0}" = "$want_ups" ] || ok=0
    [[ $out == *"$want_out"* ]] || ok=0
    [[ $out == *"$want_more"* ]] || ok=0
    [ ! -e "$work/state/overlap" ] || ok=0
    if [ $ok = 1 ]; then
        echo "ok   $CASE"
    else
        echo "FAIL $CASE: code=$code (want $want_code) ups=$ups (want $want_ups) took $((SECONDS - started)) s overlap=$(cat "$work/state/overlap" 2>/dev/null)"
        echo "$out" | sed 's/^/     /'
        failures=$((failures + 1))
    fi
}

CASE="web: a deploy that goes through runs railway up once and is unchanged"
run web 0 1 "deployment: SUCCESS" "" -- FAKE_UP="ok"
CASE="web: failed to fetch snapshot (a FAILED deployment left) is repeated and the second upload passes"
run web 0 2 "failed to fetch snapshot" "which is over" -- FAKE_UP="snapshot ok"
CASE="web: the warning names the attempt"
run web 0 2 "railway up failed (attempt 1 of 3)" "deployment: SUCCESS" -- FAKE_UP="snapshot ok"
CASE="web: an upload that never reached Railway (no deployment) is repeated, twice"
run web 0 3 "the attempt left no deployment" "deployment: SUCCESS" -- FAKE_UP="net net ok"
CASE="web: three failures in a row fail the job after exactly three uploads"
run web 1 3 "railway up failed 3 times" "failed to fetch snapshot" -- FAKE_UP="snapshot"
CASE="web: RAILWAY_UP_ATTEMPTS sets the bound"
run web 1 2 "railway up failed 2 times" "" -- FAKE_UP="snapshot" RAILWAY_UP_ATTEMPTS=2
CASE="web: a build that ends FAILED after a good upload still fails the job, with no second upload"
run web 1 1 "deployment: FAILED" "" -- FAKE_UP="badbuild"
CASE="web: a failed attempt whose deployment is still BUILDING is not uploaded again; the wait sees it live"
run web 0 1 "not uploading again, waiting for it" "deployment: SUCCESS" -- FAKE_UP="ghost ok" FAKE_GHOST_POLLS=2
CASE="web: ...and when that deployment ends FAILED the job fails, still with one upload"
run web 1 1 "not uploading again, waiting for it" "deployment: FAILED" -- FAKE_UP="ghost ok" FAKE_GHOST_POLLS=2 FAKE_GHOST_END=FAILED
CASE="web: a failed attempt whose deployment is already SUCCESS is not uploaded again"
run web 0 1 "(SUCCESS): not uploading again" "" -- FAKE_UP="finished ok"
CASE="web: the CLI cannot list the deployments after the failure: nothing is repeated"
run web 1 1 "so it cannot be shown that none is alive" "" -- FAKE_UP="snapshot ok" FAKE_LIST_BROKEN_AFTER_UP=1
CASE="web: the CLI cannot list the deployments before the attempt: a failure is not repeated"
run web 1 1 "could not list the service's deployments before the attempt" "" -- FAKE_UP="snapshot ok" FAKE_LIST_FAIL="1"
CASE="web: a hung attempt is stopped at the attempt limit and the next one runs"
run web 0 2 "stopped after 1 s" "deployment: SUCCESS" -- FAKE_UP="hang ok" RAILWAY_UP_ATTEMPT_SECONDS=1 RAILWAY_UP_MIN_ATTEMPT_SECONDS=1 RAILWAY_UP_WAIT_RESERVE=0
CASE="web: a status read that fails in the wait is asked again"
run web 0 1 "deployment: unreadable" "deployment: SUCCESS" -- FAKE_UP="ok" FAKE_LIST_FAIL="2"

# The seconds: every attempt takes 2 s and fails; the budget is 12 s with 4 s kept for the wait and 5 s the least an attempt may get.
# Attempt 1 may take 8 s, attempt 2 gets 5 or 6 s, and attempt 3 would get 2 to 4 s: it is not started, and the script ends inside its budget.
CASE="web: the retry loop stays inside the budget (no third attempt, ends inside 12 s)"
started=$SECONDS
run web 1 2 "no time for attempt 3" "" -- FAKE_UP="slow" FAKE_SLOW=2 RAILWAY_DEPLOY_SECONDS=12 RAILWAY_UP_WAIT_RESERVE=4     RAILWAY_UP_MIN_ATTEMPT_SECONDS=5 RAILWAY_UP_ATTEMPTS=5
[ $((SECONDS - started)) -le 12 ] || { echo "FAIL $CASE: took $((SECONDS - started)) s"; failures=$((failures + 1)); }
CASE="web: the wait loop ends at the budget too, with its own message"
started=$SECONDS
run web 1 1 "deployment did not become live" "" -- FAKE_UP="ghost" FAKE_GHOST_POLLS=1000 RAILWAY_DEPLOY_SECONDS=3 RAILWAY_UP_WAIT_RESERVE=1 \
    RAILWAY_UP_MIN_ATTEMPT_SECONDS=1 RAILWAY_POLL_SECONDS=1
[ $((SECONDS - started)) -le 6 ] || { echo "FAIL $CASE: took $((SECONDS - started)) s"; failures=$((failures + 1)); }

CASE="web: no token and no linked project: refused before anything is uploaded"
run web 2 0 "neither RAILWAY_TOKEN is set nor a project linked" "" -- FAKE_UP="ok" RAILWAY_TOKEN= FAKE_UNLINKED=1
CASE="web: no token but a linked project (a person's shell) deploys"
run web 0 1 "deployment: SUCCESS" "" -- FAKE_UP="ok" RAILWAY_TOKEN=

CASE="server: failed to fetch snapshot is repeated and the second upload passes"
run server 0 2 "which is over" "deployment: SUCCESS" -- FAKE_UP="snapshot ok"
CASE="server: three failures fail the job"
run server 1 3 "railway up failed 3 times" "" -- FAKE_UP="snapshot"
CASE="server: a deployment still going is not uploaded over"
run server 0 1 "not uploading again" "deployment: SUCCESS" -- FAKE_UP="ghost ok" FAKE_GHOST_POLLS=2
CASE="backend: failed to fetch snapshot is repeated, the second upload passes and the settings check runs"
run backend 0 2 "which is over" "deployment: SUCCESS" -- FAKE_UP="snapshot ok"
CASE="backend: three failures fail the job"
run backend 1 3 "railway up failed 3 times" "" -- FAKE_UP="net"
CASE="backend: a deployment still going is not uploaded over"
run backend 0 1 "not uploading again" "deployment: SUCCESS" -- FAKE_UP="ghost ok" FAKE_GHOST_POLLS=2

if [ $failures -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
