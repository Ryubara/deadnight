class_name WindPlan
extends RefCounted
## The draws behind the drive-in's wind, from one seed and nothing else (no clock, no engine
## randomness), so a test or a capture can replay a night's wind exactly. A night rolls its own
## character once (`calm`: how long the lulls run; `breeze_db`: how strong the whole night's wind
## is), and then every gust is drawn on its own: how long the lull before it, how strong, from
## which side, how fast it drifts round, and sometimes a detail (a loose sign, a rattling sheet, a
## tarp) that rides on it. Which file a gust plays and its pitch are the audio service's own draw
## (`SoundDef.variants`, `pitch_semitones`), so length and colour vary there. The research and the
## shipped games it follows are `docs/research/wind.md`.

## The wait (seconds) before the first gust of a night, so the opening is a quiet one.
const FIRST_GUST_S := Vector2(4.0, 11.0)
## The lull (seconds) between one gust ending and the next beginning is drawn between these, skewed
## short (`LULL_SKEW`), and now and then (`LONG_LULL_CHANCE`) a long one: the empty minute.
const LULL_S := Vector2(1.5, 26.0)
const LULL_SKEW := 1.7
const LONG_LULL_CHANCE := 0.08
const LONG_LULL_S := Vector2(35.0, 60.0)
## How strong a gust is, in dB over the gust files' trim: mostly milder, now and then a strong one.
## The range is narrow on purpose: a gust weaker than the base layer would not be a gust.
const GUST_DB := Vector2(-4.0, 0.0)
const GUST_DB_SKEW := 1.6
## The night's character: the lulls are scaled by `calm` and every gust and the base moved by
## `breeze_db`.
const CALM := Vector2(0.7, 1.4)
const BREEZE_DB := Vector2(-2.5, 1.0)
## A gust is heard from this far (metres) from the listener, and its bearing drifts by up to this
## many radians a second while it plays.
const GUST_M := Vector2(10.0, 16.0)
const DRIFT_RAD_S := 0.12
## A detail rides on a gust at least this strong, no sooner than this many gusts after the last
## detail, and then with this chance; it comes in at this share of the gust's length and is heard
## from this far.
const DETAIL_MIN_DB := -3.0
const DETAIL_AFTER_GUSTS := 3
const DETAIL_CHANCE := 0.45
const DETAIL_AT := Vector2(0.25, 0.6)
const DETAIL_M := Vector2(14.0, 30.0)
const DETAIL_DB := Vector2(-4.0, 0.0)
const DETAILS: Array[StringName] = [&"wind_creak", &"wind_rattle", &"wind_flap"]
## The base layer's level (dB under its own) wanders by a step this size every time it is asked,
## between these.
const WALK_STEP_DB := 0.25
const WALK_DB := Vector2(-2.0, 1.0)

var calm := 1.0
var breeze_db := 0.0

var _rng := RandomNumberGenerator.new()
var _since_detail := 0
var _walk_db := 0.0


func _init(seed_value: int = 1) -> void:
	_rng.seed = seed_value
	calm = _rng.randf_range(CALM.x, CALM.y)
	breeze_db = _rng.randf_range(BREEZE_DB.x, BREEZE_DB.y)


## Seconds from the start of the night to its first gust.
func first_gust_delay() -> float:
	return _rng.randf_range(FIRST_GUST_S.x, FIRST_GUST_S.y)


## The next gust: `lull` (seconds of quiet before it, counted from the last one's end), `db` (over
## the gust files' trim), `bearing` and `drift` (radians and radians a second, where it blows from),
## `metres` (how far off), and `detail` (a sound id, or `&""`) with `detail_at` (its share of the
## gust's length), `detail_bearing`, `detail_metres` and `detail_db`.
func next_gust() -> Dictionary:
	var gust := {
		"lull": _lull(),
		"db": lerpf(GUST_DB.x, GUST_DB.y, pow(_rng.randf(), GUST_DB_SKEW)) + breeze_db,
		"bearing": _rng.randf() * TAU,
		"drift": _rng.randf_range(-DRIFT_RAD_S, DRIFT_RAD_S),
		"metres": _rng.randf_range(GUST_M.x, GUST_M.y),
		"detail": &"",
	}
	_since_detail += 1
	if (
		_since_detail > DETAIL_AFTER_GUSTS
		and gust["db"] >= DETAIL_MIN_DB + breeze_db
		and _rng.randf() < DETAIL_CHANCE
	):
		_since_detail = 0
		gust["detail"] = DETAILS[_rng.randi() % DETAILS.size()]
		gust["detail_at"] = _rng.randf_range(DETAIL_AT.x, DETAIL_AT.y)
		gust["detail_bearing"] = _rng.randf() * TAU
		gust["detail_metres"] = _rng.randf_range(DETAIL_M.x, DETAIL_M.y)
		gust["detail_db"] = _rng.randf_range(DETAIL_DB.x, DETAIL_DB.y)
	return gust


## The base layer's wander: its level (dB under its own, `WALK_DB`) after one more step.
func walk_base() -> float:
	_walk_db = clampf(
		_walk_db + _rng.randf_range(-WALK_STEP_DB, WALK_STEP_DB), WALK_DB.x, WALK_DB.y
	)
	return _walk_db


func _lull() -> float:
	if _rng.randf() < LONG_LULL_CHANCE:
		return _rng.randf_range(LONG_LULL_S.x, LONG_LULL_S.y) * calm
	return lerpf(LULL_S.x, LULL_S.y, pow(_rng.randf(), LULL_SKEW)) * calm
