#!/usr/bin/env bash
# Tests tools/ci/retry.sh with commands that fail on purpose: it repeats a failure a bounded number of times, stops at the
# first pass, stops a hung attempt, and a command that really fails still fails with its own exit code.
#
#   bash tools/ci/test_retry.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# A command that fails its first $1 runs, with exit code $2, then passes; every run adds a line to $work/runs.
flaky=$work/flaky.sh
cat >"$flaky" <<'EOF'
#!/usr/bin/env bash
echo run >>"$FLAKY_DIR/runs"
runs=$(wc -l <"$FLAKY_DIR/runs")
if [ "$runs" -le "$1" ]; then echo "flaky: failing run $runs"; exit "$2"; fi
echo "flaky: pass on run $runs"
EOF

# check <expected exit> <expected runs> <expected output part> <retry arguments...>
check() {
    local want_code=$1 want_runs=$2 want_out=$3 out code runs
    shift 3
    : >"$work/runs"
    out=$(FLAKY_DIR=$work bash "$here/retry.sh" "$@" 2>&1)
    code=$?
    runs=$(wc -l <"$work/runs")
    if [ "$code" = "$want_code" ] && [ "$runs" = "$want_runs" ] && [[ $out == *"$want_out"* ]]; then
        echo "ok   $CASE"
    else
        echo "FAIL $CASE: code=$code runs=$runs out='$out'"
        failures=$((failures + 1))
    fi
}

CASE="a command that passes runs once"
check 0 1 "pass on run 1" -p 0 -- bash "$flaky" 0 1
CASE="a failure that is gone on the second run passes, after one warning"
check 0 2 "Attempt 1 of 3 failed" -p 0 -- bash "$flaky" 1 1
CASE="a failure that is gone on the last attempt passes"
check 0 3 "pass on run 3" -p 0 -- bash "$flaky" 2 1
CASE="a failure that never goes stops after the attempts and keeps its exit code"
check 7 3 "Failed 3 times" -p 0 -- bash "$flaky" 99 7
CASE="-n sets the attempts"
check 1 5 "Failed 5 times" -n 5 -p 0 -- bash "$flaky" 99 1
CASE="-n 1 is no retry"
check 1 1 "Failed 1 times" -n 1 -p 0 -- bash "$flaky" 99 1

CASE="a hung attempt is stopped by -t and the next one runs"
hang=$work/hang.sh
cat >"$hang" <<'EOF'
#!/usr/bin/env bash
echo run >>"$FLAKY_DIR/runs"
[ "$(wc -l <"$FLAKY_DIR/runs")" -gt 1 ] || sleep 30
EOF
start=$SECONDS
check 0 2 "stopped after 1 s" -p 0 -t 1 -- bash "$hang"
[ $((SECONDS - start)) -lt 10 ] || { echo "FAIL $CASE: took $((SECONDS - start)) s"; failures=$((failures + 1)); }

CASE="the pause grows with the attempt (1 s then 2 s)"
start=$SECONDS
check 1 3 "Failed 3 times" -p 1 -- bash "$flaky" 99 1
[ $((SECONDS - start)) -ge 3 ] || { echo "FAIL $CASE: took $((SECONDS - start)) s"; failures=$((failures + 1)); }

CASE="no command is a usage error"
out=$(bash "$here/retry.sh" -n 2 2>&1); code=$?
if [ "$code" = 2 ] && [[ $out == *usage:* ]]; then echo "ok   $CASE"; else echo "FAIL $CASE: code=$code out='$out'"; failures=$((failures + 1)); fi
CASE="a count that is not a number is a usage error"
out=$(bash "$here/retry.sh" -n x -- true 2>&1); code=$?
if [ "$code" = 2 ] && [[ $out == *usage:* ]]; then echo "ok   $CASE"; else echo "FAIL $CASE: code=$code out='$out'"; failures=$((failures + 1)); fi

if [ $failures -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
