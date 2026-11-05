#!/usr/bin/env bash
# Downloads one release of actionlint into a folder, and says what it got when it did not get an archive.
#
#   bash tools/ci/fetch_actionlint.sh <version, like 1.7.12> [target folder, default .]
#
# This replaces rhysd's download-actionlint.bash, which runs `curl -L <url> | tar xz`: curl without -f, so an error
# page goes to tar and the job says only "gzip: stdin: not in gzip format" (run 42045608111, a 92 byte body; #1269).
# Here every download goes to a file first, and an attempt counts only when all of this holds:
#
#   - curl itself finished (a connect timeout, a reset or a stall is a failed attempt, not a hang: --max-time)
#   - the HTTP status is 200
#   - the file is a gzip archive that holds `actionlint`
#   - the binary runs and reports the version asked for
#
# A failed attempt prints the status line, the size, the headers that explain a limit (retry-after, x-ratelimit-*,
# server) and the first 200 characters of the body, then waits and tries again: up to $ACTIONLINT_ATTEMPTS (4) times,
# a pause of $ACTIONLINT_PAUSE (10) seconds times the attempt number, each download stopped after 60 s. Worst case about
# 4 * 60 + 10 + 20 + 30 = 300 s; the job has `timeout-minutes: 10`. Only linux (x86_64 and arm64) is supported, as in CI.
#
# $ACTIONLINT_BASE_URL replaces the release server and $ACTIONLINT_PLATFORM (linux_amd64) the machine's, for
# tools/ci/test_fetch_actionlint.sh.
set -uo pipefail

version=${1:?usage: fetch_actionlint.sh <version> [target folder]}
target=${2:-.}
attempts=${ACTIONLINT_ATTEMPTS:-4}
pause=${ACTIONLINT_PAUSE:-10}
base=${ACTIONLINT_BASE_URL:-https://github.com/rhysd/actionlint/releases/download}

platform=${ACTIONLINT_PLATFORM:-}
if [ -z "$platform" ]; then
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64) platform=linux_amd64 ;;
        Linux/aarch64 | Linux/arm64) platform=linux_arm64 ;;
        *) echo "::error title=actionlint::no download for $(uname -s)/$(uname -m) here" >&2; exit 1 ;;
    esac
fi
url="$base/v$version/actionlint_${version}_${platform}.tar.gz"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$target"

# what <file>: the first 200 characters of a body, anything not printable made a "?", after a prefix so that no body
# can start a line that Actions reads as a workflow command.
what() {
    printf '  body: %s\n' "$(head -c 200 "$1" | tr -c '[:print:]' '?')"
}

reason=""
for n in $(seq 1 "$attempts"); do
    rm -f "$work/archive" "$work/headers"
    status=$(curl -sS -L --connect-timeout 15 --max-time 60 -D "$work/headers" -o "$work/archive" -w '%{http_code}' "$url")
    rc=$?
    if [ $rc != 0 ]; then
        reason="curl exit code $rc (status '${status:-none}')"
    elif [ "$status" != 200 ]; then
        reason="HTTP status $status"
    elif ! gzip -t "$work/archive" 2>/dev/null; then
        reason="HTTP 200 but not a gzip archive"
    elif ! tar -xzf "$work/archive" -C "$work" actionlint 2>/dev/null; then
        reason="the archive has no actionlint in it"
    else
        got=$("$work/actionlint" -version 2>&1 | head -1) || got=""
        if [ "$got" = "$version" ]; then
            cp "$work/actionlint" "$target/actionlint"
            chmod +x "$target/actionlint"
            echo "actionlint $got downloaded to $target/actionlint (attempt $n of $attempts)"
            exit 0
        fi
        reason="the binary says '$got', not '$version'"
    fi
    echo "::warning title=actionlint download, attempt $n of $attempts failed::$reason"
    echo "  url: $url"
    size=0
    [ ! -f "$work/archive" ] || size=$(wc -c <"$work/archive")
    echo "  size: $size bytes"
    if [ -s "$work/headers" ]; then
        # the last response's headers (curl -L writes one block per redirect): the status line and the ones that explain a limit
        tr -d '\r' <"$work/headers" | awk '/^HTTP/ { block = "" } { block = block "\n" $0 } END { print block }' \
            | grep -i -E '^(HTTP|retry-after|x-ratelimit|server|content-type|content-length)' | sed 's/^/  header: /'
    fi
    if [ -s "$work/archive" ]; then what "$work/archive"; fi
    [ "$n" -lt "$attempts" ] || break
    sleep $((pause * n))
done
echo "::error title=actionlint was not downloaded::$attempts attempts, the last: $reason ($url)" >&2
exit 1
