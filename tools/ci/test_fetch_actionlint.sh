#!/usr/bin/env bash
# Tests tools/ci/fetch_actionlint.sh against a local server that answers the way the release server did when it failed
# (a 92 byte body in place of the archive, #1269), and the other ways a download goes wrong: it retries, says what it
# got, installs only a real archive with a binary of the version asked for, and still fails when it never gets one.
#
#   bash tools/ci/test_fetch_actionlint.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
failures=0
python=""
for candidate in python3 python; do
    # a Windows machine can have a `python3` that only opens the store, so the candidate has to run
    if "$candidate" -c 'import http.server' 2>/dev/null; then python=$candidate; break; fi
done
[ -n "$python" ] || { echo "no python that runs"; exit 1; }

# The server: the Nth request gets the Nth word of $SEQ (the last word repeats).
#   ok       the archive: a script that prints $VERSION, as `actionlint -version` does
#   wrong    an archive whose binary prints another version
#   limit    HTTP 429 with a 92 byte body and a retry-after header
#   html     HTTP 200 with a web page
#   cut      HTTP 200 with the first 100 bytes of the archive
#   empty    HTTP 200 with nothing in it
#   reset    the connection closed without an answer
#   noexe    a gzip archive with no actionlint in it
cat >"$work/server.py" <<'EOF'
import http.server, io, os, sys, tarfile

seq = os.environ["SEQ"].split(",")
version = os.environ["VERSION"]
count = {"n": 0}


def archive(printed, name="actionlint"):
    data = ("#!/bin/sh\necho " + printed + "\n").encode()
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w:gz") as tar:
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = 0o755
        tar.addfile(info, io.BytesIO(data))
    return out.getvalue()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        count["n"] += 1
        with open(os.environ["COUNT_FILE"], "w") as handle:
            handle.write(str(count["n"]))
        kind = seq[min(count["n"], len(seq)) - 1]
        status, headers, body = 200, {}, b""
        if kind == "ok":
            body = archive(version)
        elif kind == "wrong":
            body = archive("9.9.9")
        elif kind == "noexe":
            body = archive(version, name="README.md")
        elif kind == "limit":
            status, headers, body = 429, {"Retry-After": "7", "X-RateLimit-Remaining": "0"}, b"Too many requests. Slow down, then try again in a little while please. Thank you very much..."[:92]
        elif kind == "html":
            body = b"<html><body>Service unavailable</body></html>"
        elif kind == "cut":
            body = archive(version)[:100]
        elif kind == "reset":
            self.connection.close()
            return
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
EOF
server_pid=""
trap '[ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null; rm -rf "$work"' EXIT

# check <sequence> <expected exit> <expected requests> <expected output part> [more expected output part]
check() {
    local seq=$1 want_code=$2 want_requests=$3 want_out=$4 want_more=${5:-} out code requests
    mkdir -p "$work/bin-$CASE_ID"
    : >"$work/count"
    SEQ=$seq VERSION=1.7.12 COUNT_FILE=$work/count "$python" "$work/server.py" >"$work/port" &
    server_pid=$!
    for _ in $(seq 1 50); do [ -s "$work/port" ] && break; sleep 0.1; done
    port=$(head -1 "$work/port")
    out=$(ACTIONLINT_BASE_URL=http://127.0.0.1:$port ACTIONLINT_PLATFORM=linux_amd64 ACTIONLINT_PAUSE=0 \
        bash "$here/fetch_actionlint.sh" 1.7.12 "$work/bin-$CASE_ID" 2>&1)
    code=$?
    kill "$server_pid" 2>/dev/null
    wait "$server_pid" 2>/dev/null
    server_pid=""
    requests=$(cat "$work/count")
    installed=no
    [ -x "$work/bin-$CASE_ID/actionlint" ] && installed=yes
    local want_installed=no
    [ "$want_code" = 0 ] && want_installed=yes
    if [ "$code" = "$want_code" ] && [ "${requests:-0}" = "$want_requests" ] && [ "$installed" = "$want_installed" ] \
        && [[ $out == *"$want_out"* ]] && [[ $out == *"$want_more"* ]]; then
        echo "ok   $CASE"
    else
        echo "FAIL $CASE: code=$code requests=$requests installed=$installed"
        echo "$out" | sed 's/^/     /'
        failures=$((failures + 1))
    fi
}

CASE_ID=1 CASE="a good archive is installed on the first request"
check ok 0 1 "actionlint 1.7.12 downloaded"
CASE_ID=2 CASE="the 92 byte error body is retried, shown with its headers, and the next request installs"
check limit,ok 0 2 "HTTP status 429" "Retry-After: 7"
CASE_ID=3 CASE="the 92 byte body is shown (size and text)"
check limit,ok 0 2 "size: 92 bytes" "body: Too many requests"
CASE_ID=4 CASE="a web page with status 200 is not handed to tar"
check html,ok 0 2 "HTTP 200 but not a gzip archive" "body: <html>"
CASE_ID=5 CASE="a cut archive is retried"
check cut,ok 0 2 "not a gzip archive"
CASE_ID=6 CASE="an empty answer is retried"
check empty,ok 0 2 "not a gzip archive"
CASE_ID=7 CASE="a closed connection is retried and curl's exit code is shown"
check reset,ok 0 2 "curl exit code 52"
CASE_ID=8 CASE="an archive without the binary is retried"
check noexe,ok 0 2 "no actionlint in it"
CASE_ID=9 CASE="a binary of another version is not installed"
check wrong,ok 0 2 "the binary says '9.9.9', not '1.7.12'"
CASE_ID=10 CASE="three failures in a row and the fourth installs"
check limit,html,reset,ok 0 4 "attempt 3 of 4 failed"
CASE_ID=11 CASE="a download that never works fails the step after four attempts"
check limit 1 4 "actionlint was not downloaded" "4 attempts"

if [ $failures -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
