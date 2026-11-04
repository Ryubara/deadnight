#!/usr/bin/env bash
# Says whether the platform backend at a URL takes exactly the match settings the game has, so a backend that is
# behind the game (or ahead of it) is found by a script, not by a host whose lobby choices vanish (#944: the live backend
# had not been deployed since before the rules, so it answered 404 to every change and ignored the rules a start
# carried, and every night was the usual one on the drive-in with no bots).
#
#   deploy/backend/check_keys.sh <backend url> [match_settings.gd]
#
# The backend publishes its keys on `/health` (`settingsKeys`); the game's are the keys of `KEYS` in
# `game/gameplay/rules/match_settings.gd`. `$CHECK_KEYS_HEALTH` replaces the answer (for deploy/backend/test_check_keys.sh).
# Exit 0 when the lists are the same, 1 when they differ (both sides are printed), 2 when the answer cannot be read.
set -uo pipefail

url=${1:?usage: check_keys.sh <backend url> [match_settings.gd]}
here=$(cd "$(dirname "$0")" && pwd)
source_file=${2:-$here/../../game/gameplay/rules/match_settings.gd}

# The game's keys: the quoted names that start a line of the KEYS dictionary.
game=$(sed -n '/^const KEYS := {/,/^}/p' "$source_file" | grep -oE '^[[:space:]]+"[a-z_]+"' | tr -d ' \t"' | sort)
if [ -z "$game" ]; then
    echo "could not read the game's settings keys from $source_file" >&2
    exit 2
fi

health=${CHECK_KEYS_HEALTH:-}
if [ -z "$health" ]; then
    for _ in 1 2 3 4 5; do
        health=$(curl -fsS --max-time 15 "${url%/}/health" 2>/dev/null) && break
        health=""
        sleep 5
    done
fi
if [ -z "$health" ]; then
    echo "could not read ${url%/}/health" >&2
    exit 2
fi
live=$(printf '%s' "$health" | node -e '
let text = "";
process.stdin.on("data", (chunk) => (text += chunk)).on("end", () => {
  try {
    const keys = JSON.parse(text).settingsKeys;
    if (!Array.isArray(keys)) process.exit(3);
    console.log(keys.slice().sort().join("\n"));
  } catch {
    process.exit(3);
  }
});')
status=$?
if [ "$status" = 3 ] || [ -z "$live" ]; then
    echo "::error title=Backend behind the game::${url%/}/health lists no settingsKeys: this backend is from before the keys were published, so it is behind the game" >&2
    echo "the backend lists no settingsKeys (a build from before them)" >&2
    exit 1
fi
if [ "$game" = "$live" ]; then
    echo "the backend takes the game's settings: $(printf '%s' "$game" | tr '\n' ' ')"
    exit 0
fi
echo "::error title=Backend and game disagree::the backend and the game do not take the same match settings" >&2
echo "game:    $(printf '%s' "$game" | tr '\n' ' ')" >&2
echo "backend: $(printf '%s' "$live" | tr '\n' ' ')" >&2
exit 1
