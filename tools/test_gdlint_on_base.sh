#!/usr/bin/env bash
# Tests tools/gdlint_on_base.sh without GitHub: a stand-in for the lint command fails on a script of more than 10 lines,
# the same shape as gdlint's `max-file-lines` (#1238).
#
#   bash tools/test_gdlint_on_base.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

cat > "$work/lint.sh" <<'LINT'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$LINT_LOG"
for file in "$@"; do
    [ "$(wc -l < "$file")" -le 10 ] || { echo "$file: over the limit"; exit 1; }
done
LINT

repo=$work/repo
git init -q "$repo"
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
git -C "$repo" config core.autocrlf false
save() { git -C "$repo" add -A && git -C "$repo" commit -q -m "$1" && git -C "$repo" rev-parse HEAD; }
lines() { for i in $(seq "$1" "$2"); do echo "line $i"; done; }

# Two sides that each stay under the limit and cross it together: a.gd of 4 lines, the base adds 4 at its start and the
# pull request adds 4 at its end. `gone.gd` is removed by the pull request, so it must never reach the lint.
lines 11 14 > "$repo/a.gd"
echo 'one' > "$repo/gone.gd"
echo 'text' > "$repo/note.txt"
start=$(save start)
branch=$(git -C "$repo" symbolic-ref --short HEAD)

git -C "$repo" checkout -q -b crossing "$start"
lines 15 18 >> "$repo/a.gd"
rm "$repo/gone.gd"
crossing=$(save crossing)

git -C "$repo" checkout -q -b words "$start"
echo 'more' >> "$repo/note.txt"
words=$(save words)

git -C "$repo" checkout -q -b clash "$start"
echo 'theirs' > "$repo/a.gd"
clash=$(save clash)

git -C "$repo" checkout -q "$branch"
{ lines 1 4; cat "$repo/a.gd"; } > "$repo/a.tmp" && mv "$repo/a.tmp" "$repo/a.gd"
moved=$(save moved)

check() { # name, base, head, expected exit code, expected lint argument ('-' for no call at all)
    git -C "$repo" checkout -q -f --detach "$3" || exit 2
    export LINT_LOG=$work/log
    : > "$LINT_LOG"
    (cd "$repo" && bash "$here/gdlint_on_base.sh" "$2" "$3" bash "$work/lint.sh") > "$work/out" 2>&1
    code=$?
    called=$(tr '\n' ' ' < "$LINT_LOG" | sed 's/ $//')
    if [ "$code" -ne "$4" ] || [ "${called:--}" != "$5" ]; then
        echo "FAIL $1: exit $code, lint called with '${called:--}' (wanted $4, '$5')"
        cat "$work/out"
        failures=$((failures + 1))
    else
        echo "ok   $1"
    fi
}

check "the pull request alone stays under the limit" "$start" "$crossing" 0 a.gd
check "the base moved and the two cross the limit" "$moved" "$crossing" 1 a.gd
check "the pull request changes no script" "$moved" "$words" 0 -
check "a conflict with the base is not this check's" "$moved" "$clash" 0 -

if [ "$(cd "$repo" && bash "$here/gdlint_on_base.sh" "$start" missing true 2>/dev/null; echo $?)" = 0 ]; then
    echo "FAIL a head git cannot read must not pass"
    failures=$((failures + 1))
else
    echo "ok   a head git cannot read does not pass"
fi

[ "$failures" -eq 0 ] && echo "gdlint_on_base: all passed"
exit "$failures"
