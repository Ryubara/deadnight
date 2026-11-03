#!/usr/bin/env bash
# Tests deploy/check_head.sh without GitHub or Railway: a build older than what the service runs is refused (#552), a
# build newer than it deploys even when main moved on while the run was going (#732).
#
#   bash deploy/test_check_head.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# A history like main's: c1 <- c2 <- c3 <- c4 (the head), and a commit off main (b, from c1: a branch deployed by hand).
repo=$work/repo
git init -q "$repo"
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
commit() { git -C "$repo" commit -q --allow-empty -m "$1" && git -C "$repo" rev-parse HEAD; }
c1=$(commit one)
c2=$(commit two)
c3=$(commit three)
c4=$(commit four)
git -C "$repo" checkout -q -b side "$c1"
b=$(commit side)
git -C "$repo" checkout -q -
unknown=3333333333333333333333333333333333333333

# check <expected exit> <expected output part> <commit> [VAR=value ...]: runs the check inside the repository
check() {
    local want_code=$1 want_out=$2 sha=$3 out code
    shift 3
    out=$(cd "$repo" && env "$@" bash "$here/check_head.sh" "$sha" web 2>&1)
    code=$?
    if [ "$code" = "$want_code" ] && [[ $out == *"$want_out"* ]]; then
        echo "ok   $CASE"
    else
        echo "FAIL $CASE: code=$code out='$out'"
        failures=$((failures + 1))
    fi
}

# The commit the service runs, as the check reads it from the CLI's JSON, for $PATH.
stub=$work/stub
mkdir -p "$stub"
deployments() { # <status:message>... newest first, in the layout of `railway deployment list --json`
    local first=1 item
    echo "["
    for item in "$@"; do
        [ $first = 1 ] || echo "  },"
        first=0
        echo "  {"
        echo "    \"id\": \"x\","
        echo "    \"status\": \"${item%%:*}\","
        echo "    \"createdAt\": \"2026-11-03T05:58:52.701Z\","
        echo "    \"meta\": {"
        echo "      \"buildOnly\": false,"
        if [ -n "${item#*:}" ]; then echo "      \"cliMessage\": \"${item#*:}\","; fi
        echo "      \"reason\": \"deploy\""
        echo "    },"
        echo "    \"serviceId\": \"y\""
    done
    echo "  }"
    echo "]"
}
railway_says() { # <deployments file> | fail
    if [ "$1" = fail ]; then
        printf '#!/bin/sh\nexit 1\n' >"$stub/railway"
    else
        printf '#!/bin/sh\n[ "$1 $2 $3" = "deployment list --service" ] && [ "$4" = web ] && cat "%s"\n' "$1" >"$stub/railway"
    fi
    chmod +x "$stub/railway"
}
with_stub=(PATH="$stub:$PATH")

CASE="behind the head of main but newer than the live commit: deployed (#732)"
check 0 "is ahead of ${c2:0:7}" "$c3" DEPLOY_LIVE_SHA="$c2" DEPLOY_MAIN_HEAD="$c4"
CASE="older than the live commit: refused, even when it is not the head (#552)"
check 3 "is older than ${c3:0:7}" "$c2" DEPLOY_LIVE_SHA="$c3" DEPLOY_MAIN_HEAD="$c4"
CASE="the refusal is a notice the run shows"
check 3 "::notice title=Not deployed::" "$c2" DEPLOY_LIVE_SHA="$c3" DEPLOY_MAIN_HEAD="$c4"
CASE="the head of main is deployed over an older live commit"
check 0 "is ahead of ${c1:0:7}" "$c4" DEPLOY_LIVE_SHA="$c1" DEPLOY_MAIN_HEAD="$c4"
CASE="the live commit again is a redeploy, so a re-run repairs a service"
check 0 "runs now: redeployed" "$c3" DEPLOY_LIVE_SHA="$c3" DEPLOY_MAIN_HEAD="$c4"
CASE="a short live sha (the deployment message holds seven characters) is read"
check 0 "is ahead of ${c2:0:7}" "$c3" DEPLOY_LIVE_SHA="${c2:0:7}" DEPLOY_MAIN_HEAD="$c4"
CASE="a short live sha newer than the commit refuses it"
check 3 "is older than ${c4:0:7}" "$c3" DEPLOY_LIVE_SHA="${c4:0:7}" DEPLOY_MAIN_HEAD="$c4"
CASE="a live commit off main (a branch deployed by hand) is replaced by a main build"
check 0 "not on main: deployed" "$c3" DEPLOY_LIVE_SHA="$b" DEPLOY_MAIN_HEAD="$c4"

CASE="the live commit comes from the newest SUCCESS deployment, not a newer failed one"
railway_says "$work/d1.json"
deployments "BUILDING:main ${c4:0:7}" "FAILED:main ${c3:0:7}" "SUCCESS:main ${c2:0:7}" "REMOVED:main ${c1:0:7}" >"$work/d1.json"
check 0 "is ahead of ${c2:0:7}" "$c3" "${with_stub[@]}"
CASE="an older run is refused against the live commit the CLI reports"
check 3 "is older than ${c2:0:7}" "$c1" "${with_stub[@]}"
CASE="the game server's message (game server <sha>) is read the same way"
deployments "SUCCESS:game server ${c3:0:7}" "REMOVED:game server ${c1:0:7}" >"$work/d1.json"
check 3 "is older than ${c3:0:7}" "$c2" "${with_stub[@]}"
CASE="a live deployment without a message is unknown, and the head of main decides: the head deploys"
deployments "SUCCESS:" "REMOVED:main ${c1:0:7}" >"$work/d1.json"
check 0 "is the head of main" "$c4" "${with_stub[@]}" DEPLOY_MAIN_HEAD="$c4"
CASE="a live deployment without a message is unknown, and the head of main decides: a build behind it is refused"
check 3 "not the head of main (${c4:0:7})" "$c3" "${with_stub[@]}" DEPLOY_MAIN_HEAD="$c4"
CASE="a CLI that fails leaves the live commit unknown: a build behind the head is refused, as #552 did"
railway_says fail
check 3 "not the head of main (${c4:0:7})" "$c3" "${with_stub[@]}" DEPLOY_MAIN_HEAD="$c4"
CASE="a live commit this checkout lacks leaves it unknown: the head of main is deployed"
check 0 "is the head of main" "$c4" DEPLOY_LIVE_SHA="$unknown" DEPLOY_MAIN_HEAD="$c4"
CASE="a main that was rewritten to another commit refuses a build when the live commit is unknown"
check 3 "not the head of main" "$c4" DEPLOY_LIVE_SHA="$unknown" DEPLOY_MAIN_HEAD="$c1"

CASE="missing arguments print the usage"
out=$(bash "$here/check_head.sh" "$c1" 2>&1); code=$?
if [ "$code" != 0 ] && [[ $out == *"usage:"* ]]; then echo "ok   $CASE"; else echo "FAIL $CASE: code=$code out='$out'"; failures=$((failures + 1)); fi
CASE="an unreadable live commit and head warn and deploy, as before the check"
out=$(cd "$repo" && env -u DEPLOY_MAIN_HEAD -u DEPLOY_LIVE_SHA PATH="$(mktemp -d)" GITHUB_REPOSITORY=x/y /bin/bash "$here/check_head.sh" "$c1" web 2>&1); code=$?
if [ "$code" = 0 ] && [[ $out == *"::warning title=Head of main unknown"* ]]; then echo "ok   $CASE"; else echo "FAIL $CASE: code=$code out='$out'"; failures=$((failures + 1)); fi

if [ $failures -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
