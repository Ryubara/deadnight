class_name ChallengeClock
extends RefCounted
## What day it is for the player, and how long until the next one. A day is a whole number
## (days since 1970, in the player's own time), so the daily rotation is a function of that number
## and a test sets any day it likes. The day turns at the player's local midnight; where the
## platform cannot say the offset it is UTC's.

const DAY_SECONDS := 86400

## Seconds the player's clock is ahead of UTC.
var offset_seconds := 0

var _now: Callable


## The machine's clock and time zone.
static func system() -> ChallengeClock:
	var clock := ChallengeClock.new()
	clock._now = Time.get_unix_time_from_system
	var zone: Dictionary = Time.get_time_zone_from_system()
	clock.offset_seconds = int(zone.get("bias", 0)) * 60
	return clock


## A clock that stands still at `unix` seconds (a test's, or a capture's).
static func fixed(unix: float, p_offset_seconds: int = 0) -> ChallengeClock:
	var clock := ChallengeClock.new()
	clock._now = func() -> float: return unix
	clock.offset_seconds = p_offset_seconds
	return clock


## A clock reading `source` (a Callable returning unix seconds): a test moves time with it.
static func from_source(source: Callable, p_offset_seconds: int = 0) -> ChallengeClock:
	var clock := ChallengeClock.new()
	clock._now = source
	clock.offset_seconds = p_offset_seconds
	return clock


## The unix time of the start of day number `day`, in UTC terms (zero offset).
static func day_start(day: int) -> int:
	return day * DAY_SECONDS


## Day number `day` as `YYYY-MM-DD`.
static func date_text(day: int) -> String:
	return Time.get_date_string_from_unix_time(day_start(day))


func local_seconds() -> float:
	return float(_now.call()) + offset_seconds


## Today's number.
func day() -> int:
	return floori(local_seconds() / DAY_SECONDS)


## Whole seconds until the day turns (1 to 86400).
func seconds_to_refresh() -> int:
	return ceili((day() + 1) * DAY_SECONDS - local_seconds())
