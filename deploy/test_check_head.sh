#!/usr/bin/env bash
# Tests deploy/check_head.sh without GitHub: a deploy of a commit that is not the head of main is refused (#552).
#
#   bash deploy/test_check_head.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
failures=0
older=1111111111111111111111111111111111111111
newer=2222222222222222222222222222222222222222

# check <expected exit> <expected output part> <head of main> <commit>
check() {
    local want_code=$1 want_out=$2 head=$3 sha=$4 out code
    out=$(DEPLOY_MAIN_HEAD=$head bash "$here/check_head.sh" "$sha" 2>&1)
    code=$?
    if [ "$code" = "$want_code" ] && [[ $out == *"$want_out"* ]]; then
        echo "ok   $CASE"
    else
        echo "FAIL $CASE: code=$code out='$out'"
        failures=$((failures + 1))
    fi
}

CASE="the head of main is deployed"
check 0 "is the head of main" "$newer" "$newer"
CASE="an older commit is refused when main moved on"
check 3 "not the head of main (2222222)" "$newer" "$older"
CASE="the refusal is a notice the run shows"
check 3 "::notice title=Not deployed::" "$newer" "$older"
CASE="a commit is refused when main was rewritten to another one"
check 3 "not the head of main" "$older" "$newer"
CASE="missing arguments print the usage"
out=$(bash "$here/check_head.sh" 2>&1); code=$?
if [ "$code" != 0 ] && [[ $out == *"usage:"* ]]; then echo "ok   $CASE"; else echo "FAIL $CASE: code=$code out='$out'"; failures=$((failures + 1)); fi
CASE="an unreadable head warns and deploys, as before the check"
out=$(env -u DEPLOY_MAIN_HEAD PATH="$(mktemp -d)" GITHUB_REPOSITORY=x/y /bin/bash "$here/check_head.sh" "$older" 2>&1); code=$?
if [ "$code" = 0 ] && [[ $out == *"::warning title=Head of main unknown"* ]]; then echo "ok   $CASE"; else echo "FAIL $CASE: code=$code out='$out'"; failures=$((failures + 1)); fi

if [ $failures -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
