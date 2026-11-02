class_name MatchSettings
extends Resource
## The rules of one match that whoever starts it chooses before the night begins: how many
## zombies, how many at once, how long the breaks last and an optional time limit per round.
##
## The server owns them (`GameRules.settings`), they ride the rules' snapshot (so WELCOME and a
## late join carry them) and they are set only while the night has not started
## (`RulesAction.configure`). The defaults are today's game exactly: a count of 1x, the alive cap
## the round curve gives, the tuned break and no time limit. Pure data and pure functions; the
## reasoning is in docs/design/rounds.md#match-settings.

## The zombie counts the Play screen offers. The setting itself takes any value in
## `MIN_COUNT_MULTIPLIER..MAX_COUNT_MULTIPLIER`, so another choice is a line added here.
const COUNT_CHOICES: Array[float] = [1.0, 2.0, 3.0]
const MIN_COUNT_MULTIPLIER := 0.25
const MAX_COUNT_MULTIPLIER := 5.0
## `max_alive`, `break_seconds` and `round_time_limit` mean "not set" at this value.
const AUTO := 0
## The explicit values: a break of at least a second, a limit of at least half a minute.
const MIN_BREAK := 1.0
const MAX_BREAK := 120.0
const MIN_TIME_LIMIT := 30.0
const MAX_TIME_LIMIT := 3600.0
## The keys of `to_dict`, each with the type it must have (a whole number also fits a float).
const KEYS := {
	"count_multiplier": TYPE_FLOAT,
	"max_alive": TYPE_INT,
	"break_seconds": TYPE_FLOAT,
	"round_time_limit": TYPE_FLOAT,
}

## Round N's zombie count is the tuned count for N times this (rounded, at least one). A type's
## first round still brings its exact `intro_count`, and a boss round its own bosses.
@export_range(0.25, 5.0, 0.25) var count_multiplier: float = 1.0
## Most zombies alive at once; 0 is the tuned curve (`RoundTuning.alive_cap`). A number caps it,
## and never above `RoundTuning.alive_cap_ceiling`, the crowd the lot stands.
@export_range(0, 40, 1) var max_alive: int = AUTO
## Seconds of break between rounds; 0 is the tuned break (`RoundTuning.break_seconds`). The wait
## before round 1 and the longer break before a special round are unchanged.
@export_range(0.0, 120.0, 1.0) var break_seconds: float = 0.0
## Seconds a round may last before time is up; 0 is no limit. When it runs out the dead keep
## coming faster (`RoundTuning.overtime_spawn_rate`, and the tuned cap's ceiling); nobody loses.
@export_range(0.0, 3600.0, 5.0) var round_time_limit: float = 0.0


## The defaults: today's game.
func is_default() -> bool:
	return (
		is_equal_approx(count_multiplier, 1.0)
		and max_alive == AUTO
		and is_zero_approx(break_seconds)
		and is_zero_approx(round_time_limit)
	)


## Whether `other` holds the same four values.
func same_as(other: MatchSettings) -> bool:
	return other != null and to_dict() == other.to_dict()


## A round's zombie count after the multiplier: `normal` is the tuned count for the round and the
## players. At least one.
func scaled_count(normal: int) -> int:
	return maxi(1, roundi(float(normal) * count_multiplier))


## Zombies alive at once in `round_number` for `players`. `overtime` is a round whose time ran out:
## the tuned curve gives way to the ceiling, but a cap the host chose stays.
func alive_cap(rounds: RoundTuning, round_number: int, players: int, overtime: bool = false) -> int:
	if max_alive > AUTO:
		return mini(max_alive, rounds.alive_cap_ceiling)
	if overtime:
		return rounds.alive_cap_ceiling
	return rounds.alive_cap(round_number, players)


## Seconds of break after a round.
func break_for(rounds: RoundTuning) -> float:
	return break_seconds if break_seconds > 0.0 else rounds.break_seconds


## Seconds between spawns: the round's own, faster once its time is up.
func spawn_interval(
	rounds: RoundTuning, round_number: int, players: int, overtime: bool = false
) -> float:
	var interval := rounds.spawn_interval(round_number, players)
	return interval / rounds.overtime_spawn_rate if overtime else interval


## Whether a round that has run `elapsed` seconds is out of time (never when there is no limit).
func is_overtime(elapsed: float) -> bool:
	return round_time_limit > 0.0 and elapsed >= round_time_limit


## Plain data for the snapshot, an action or a command line.
func to_dict() -> Dictionary:
	return {
		"count_multiplier": count_multiplier,
		"max_alive": max_alive,
		"break_seconds": break_seconds,
		"round_time_limit": round_time_limit,
	}


## The name of the first field of `data` that is missing, of the wrong type or out of range, or
## `&""` when it is fine. Strict: a value outside the bounds is refused, not clamped.
static func problem(data: Dictionary) -> StringName:
	for key: String in KEYS:
		if not data.has(key) or not SnapshotCheck.fits_type(data[key], KEYS[key]):
			return StringName(key)
	if not _in_range(data["count_multiplier"], MIN_COUNT_MULTIPLIER, MAX_COUNT_MULTIPLIER):
		return &"count_multiplier"
	if data["max_alive"] < AUTO or data["max_alive"] > _alive_ceiling():
		return &"max_alive"
	if not _is_auto_or_in_range(data["break_seconds"], MIN_BREAK, MAX_BREAK):
		return &"break_seconds"
	if not _is_auto_or_in_range(data["round_time_limit"], MIN_TIME_LIMIT, MAX_TIME_LIMIT):
		return &"round_time_limit"
	return &""


## Settings from `to_dict`'s data (a snapshot, a WELCOME, an action), or null when `problem` finds
## fault with it.
static func from_dict(data: Dictionary) -> MatchSettings:
	if not problem(data).is_empty():
		return null
	var out := MatchSettings.new()
	out.count_multiplier = float(data["count_multiplier"])
	out.max_alive = data["max_alive"]
	out.break_seconds = float(data["break_seconds"])
	out.round_time_limit = float(data["round_time_limit"])
	return out


## The settings a rules snapshot (or WELCOME's) holds; the defaults for a snapshot without any.
static func from_snapshot(snapshot: Dictionary) -> MatchSettings:
	var held: Variant = snapshot.get("match_settings")
	var out: MatchSettings = from_dict(held) if typeof(held) == TYPE_DICTIONARY else null
	return out if out != null else MatchSettings.new()


## A copy with every value pulled into its bounds (a value just under an explicit minimum becomes
## the minimum), for what a person typed or dragged.
func clamped() -> MatchSettings:
	var out := MatchSettings.new()
	out.count_multiplier = clampf(count_multiplier, MIN_COUNT_MULTIPLIER, MAX_COUNT_MULTIPLIER)
	out.max_alive = clampi(max_alive, AUTO, _alive_ceiling())
	out.break_seconds = _clamp_optional(break_seconds, MIN_BREAK, MAX_BREAK)
	out.round_time_limit = _clamp_optional(round_time_limit, MIN_TIME_LIMIT, MAX_TIME_LIMIT)
	return out


## The most alive at once a host may ask for: the rules' ceiling (the crowd the lot stands).
static func _alive_ceiling() -> int:
	return RoundTuning.new().alive_cap_ceiling


static func _in_range(value: Variant, low: float, high: float) -> bool:
	var number := float(value)
	return is_finite(number) and number >= low and number <= high


static func _is_auto_or_in_range(value: Variant, low: float, high: float) -> bool:
	return is_finite(float(value)) and (is_zero_approx(float(value)) or _in_range(value, low, high))


static func _clamp_optional(value: float, low: float, high: float) -> float:
	if value <= 0.0:
		return 0.0
	return clampf(value, low, high)
