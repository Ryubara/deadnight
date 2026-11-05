#!/usr/bin/env bash
# Runs a command again when it fails, a bounded number of times, for a CI step whose failure can come from outside
# (a package registry, a release download): `npm install --global ...`, `gds workspace init --fetch ...`.
#
#   bash tools/ci/retry.sh [-n attempts] [-p seconds] [-t seconds] -- <command> [args...]
#
#   -n  how many times the command runs in all (default 3)
#   -p  the pause before the next attempt, times the number of attempts made so far (default 10)
#   -t  the most one attempt may take, in seconds (default 300); a hung download is stopped, not waited for
#
# The worst case is n * t + p * n * (n - 1) / 2 seconds: pick the three so that it fits inside the step's and the job's
# `timeout-minutes` (every use in ci.yml says its own sum). The command's own output is shown as it comes; each failed
# attempt adds one line saying which attempt it was and the exit code (124 is the -t limit). The exit code is the last
# attempt's, so a command that really fails still fails the step, after n attempts and a line that says so.
#
# Only a command that is safe to run twice belongs here: an install or a download is; a deploy is not (see
# deploy/railway_up.sh, which looks at what the failed attempt left behind before it repeats anything).
set -uo pipefail

attempts=3
pause=10
limit=300
usage="usage: retry.sh [-n attempts] [-p seconds] [-t seconds] -- <command> [args...]"
while [ $# -gt 0 ]; do
    case $1 in
        -n) attempts=${2:?$usage}; shift 2 ;;
        -p) pause=${2:?$usage}; shift 2 ;;
        -t) limit=${2:?$usage}; shift 2 ;;
        --) shift; break ;;
        *) echo "$usage" >&2; exit 2 ;;
    esac
done
[ $# -gt 0 ] || { echo "$usage" >&2; exit 2; }
case $attempts$pause$limit in *[!0-9]* | "") echo "$usage (numbers only)" >&2; exit 2 ;; esac

code=0
for n in $(seq 1 "$attempts"); do
    code=0
    timeout "$limit" "$@" || code=$?
    [ "$code" != 0 ] || exit 0
    reason="exit code $code"
    [ "$code" != 124 ] || reason="stopped after $limit s"
    echo "::warning title=Attempt $n of $attempts failed::$1 ... ($reason)"
    [ "$n" -lt "$attempts" ] || break
    sleep $((pause * n))
done
echo "::error title=Failed $attempts times::$* ($reason)" >&2
exit "$code"
