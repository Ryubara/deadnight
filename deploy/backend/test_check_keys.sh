#!/usr/bin/env bash
# Tests deploy/backend/check_keys.sh without a backend: the same keys pass; a missing key, an extra key and a backend
# that publishes none (one from before them) fail (#944).
#
#   bash deploy/backend/test_check_keys.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

cat > "$work/match_settings.gd" <<'GD'
class_name MatchSettings
const KEYS := {
	"count_multiplier": TYPE_FLOAT,
	"map": TYPE_STRING,
	"bots": TYPE_INT,
}
const OPTIONAL_KEYS: Array[String] = ["map", "bots"]
GD

# check <name> <expected exit> <health answer>
check() {
    local name=$1 want=$2 health=$3 code
    CHECK_KEYS_HEALTH=$health bash "$here/check_keys.sh" https://backend.example "$work/match_settings.gd" >/dev/null 2>&1
    code=$?
    if [ "$code" = "$want" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name: exit $code, wanted $want"
        failures=$((failures + 1))
    fi
}

check "the same keys, in any order" 0 '{"status":"ok","settingsKeys":["map","bots","count_multiplier"]}'
check "a key the backend lacks" 1 '{"status":"ok","settingsKeys":["bots","count_multiplier"]}'
check "a key the game lacks" 1 '{"status":"ok","settingsKeys":["bots","count_multiplier","map","perk_limit"]}'
check "a backend from before the keys were published" 1 '{"status":"ok"}'
check "an answer that is not JSON" 1 'not json'

if [ "$failures" != 0 ]; then
    echo "$failures failed"
    exit 1
fi
