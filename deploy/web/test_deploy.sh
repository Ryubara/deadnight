#!/usr/bin/env bash
# Tests the branch guard and the message of deploy.sh without Railway (DEPLOY_DRY_RUN=1): only main may be deployed to
# the shared web service unless --force-branch is given, and the message names the real branch and short sha.
#
#   bash deploy/web/test_deploy.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
sha=0123456789abcdef0123456789abcdef01234567

# A throwaway repository holding a copy of the script, to read a real checkout's branch from.
repo=$work/repo
mkdir -p "$repo/deploy/web"
cp "$here/deploy.sh" "$repo/deploy/web/deploy.sh"
cp "$here/../railway_up.sh" "$repo/deploy/railway_up.sh"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m first

# run <expected exit> <expected stdout line, or "-" for none> <expected stderr part, or "-"> <env...> -- <args...>
check() {
    local want_code=$1 want_out=$2 want_err=$3
    shift 3
    local envs=()
    while [ "$1" != -- ]; do envs+=("$1"); shift; done
    shift
    local out err code
    out=$(env -u DEPLOY_BRANCH -u GITHUB_ACTIONS -u GITHUB_REF_NAME DEPLOY_DRY_RUN=1 "${envs[@]}" bash "$repo/deploy/web/deploy.sh" "$@" 2>"$work/err")
    code=$?
    err=$(cat "$work/err")
    local ok=1
    [ "$code" = "$want_code" ] || ok=0
    if [ "$want_out" = - ]; then [ -z "$out" ] || ok=0; else [ "$out" = "$want_out" ] || ok=0; fi
    if [ "$want_err" = - ]; then [ -z "$err" ] || ok=0; else [[ $err == *"$want_err"* ]] && [ "$(wc -l <<<"$err")" = 1 ] || ok=0; fi
    if [ $ok = 1 ]; then echo "ok   $CASE"; else echo "FAIL $CASE: code=$code out='$out' err='$err'"; failures=$((failures + 1)); fi
}

CASE="main goes through with its real name and short sha"
check 0 "message: main 0123456" - DEPLOY_BRANCH=main -- build "$sha"
CASE="another branch is refused with one line"
check 2 - "branch 'net-x'" DEPLOY_BRANCH=net-x -- build "$sha"
CASE="the refusal says how to force it"
check 2 - "--force-branch" DEPLOY_BRANCH=net-x -- build "$sha"
CASE="--force-branch deploys it and the message still names the branch"
check 0 "message: net-x 0123456" - DEPLOY_BRANCH=net-x -- --force-branch build "$sha"
CASE="--force-branch can come after the arguments"
check 0 "message: net-x 0123456" - DEPLOY_BRANCH=net-x -- build "$sha" /tmp/stage --force-branch
CASE="a branch whose name contains a slash"
check 0 "message: art/hands 0123456" - DEPLOY_BRANCH=art/hands -- build "$sha" --force-branch
CASE="CI on main uses GITHUB_REF_NAME and is unchanged"
check 0 "message: main 0123456" - GITHUB_ACTIONS=true GITHUB_REF_NAME=main -- build "$sha"
CASE="CI on another ref is refused"
check 2 - "branch 'feature'" GITHUB_ACTIONS=true GITHUB_REF_NAME=feature -- build "$sha"
CASE="a checkout of main goes through"
check 0 "message: main 0123456" - -- build "$sha"
git -C "$repo" checkout -q -b feature-y
CASE="a checkout of another branch is refused"
check 2 - "branch 'feature-y'" -- build "$sha"
CASE="a checkout of another branch forced says its branch"
check 0 "message: feature-y 0123456" - -- --force-branch build "$sha"
git -C "$repo" checkout -q --detach
CASE="a detached checkout is refused and named detached"
check 2 - "branch 'detached'" -- build "$sha"
CASE="a detached checkout forced says detached"
check 0 "message: detached 0123456" - -- --force-branch build "$sha"
CASE="missing arguments print the usage"
check 1 - "usage:" DEPLOY_BRANCH=main -- build

if [ $failures -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
