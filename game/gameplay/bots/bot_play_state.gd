class_name BotPlayState
extends RefCounted
## How boldly a bot plays, driven by its health and the danger about it
## (`docs/research/bots.md#play-states-693`).
## The maintainer: "aggressive if they're high on health, but more safe e.g. keeping their distance
## when they're low health."
##
## - `AGGRESSIVE` (healthy): the bot as it always was: it takes kills, may walk up to a zombie that
##   is not coming (`may_push`), and keeps only the profile's own retreat margin.
## - `CAREFUL` (hurt): it holds its range, keeps a wider margin (`margin`) and does not push.
## - `SAFE` (low): it keeps its distance (a wide margin, a retreat that prefers open ground and
##   heads for its teammates), does not go wandering (`may_wander`), gives a revive up while the
##   dead are near unless it is the last one up (`gives_up_revive`), and keeps to the near side of
##   the person it follows (`follow_band`) or a few metres behind the spot it holds (`hold_back`).
##
## The state is read from the share of full health less what danger nearby costs (each zombie
## beyond the first inside `pressure_range`). Every switch has two numbers (the profile's
## `careful_below` and `aggressive_above`, `safe_below` and `safe_above`), so a bot at the edge does
## not flicker, and a bot becomes bolder only after `play_state_dwell` seconds in its state (more
## careful at once). Plain data and the clock the brain gives it. With `enabled` off the state is
## still read (the soak counts it) but every question answers as an aggressive bot would: the
## before of the measurement.

enum State { AGGRESSIVE, CAREFUL, SAFE }

## False: the state is tracked and reported, nothing follows from it.
var enabled := true
var state := State.AGGRESSIVE
## How many times the state has changed.
var changes := 0
## The share the last `update` judged by (health less the danger's cost).
var share := 1.0

var _profile: BotProfile
var _since := -INF


func _init(profile: BotProfile) -> void:
	_profile = profile


## The state's name, for the reports and the notes.
static func name_of(of: State) -> StringName:
	match of:
		State.CAREFUL:
			return &"careful"
		State.SAFE:
			return &"safe"
	return &"aggressive"


func state_name() -> StringName:
	return name_of(state)


## Reads the bot's health (`me`: `health`, `max_health`) and the zombies it believes within
## `pressure_range` (`pressure`: how many), at `now`. Returns the state.
func update(me: Dictionary, pressure: int, now: float) -> State:
	var full := maxf(float(me.get("max_health", 100.0)), 1.0)
	var health := clampf(float(me.get("health", full)) / full, 0.0, 1.0)
	var cost := minf(
		float(maxi(pressure - 1, 0)) * _profile.pressure_penalty, _profile.pressure_cap
	)
	share = clampf(health - cost, 0.0, 1.0)
	var next := state
	match state:
		State.AGGRESSIVE:
			if share < _profile.safe_below:
				next = State.SAFE
			elif share < _profile.careful_below:
				next = State.CAREFUL
		State.CAREFUL:
			if share < _profile.safe_below:
				next = State.SAFE
			elif share >= _profile.aggressive_above:
				next = State.AGGRESSIVE
		State.SAFE:
			if share >= _profile.aggressive_above:
				next = State.AGGRESSIVE
			elif share >= _profile.safe_above:
				next = State.CAREFUL
	if next != state:
		var bolder := int(next) < int(state)
		if not bolder or now - _since >= _profile.play_state_dwell:
			state = next
			_since = now
			changes += 1
	return state


## Back to a healthy start (the bot went down, or the night began again).
func reset() -> void:
	state = State.AGGRESSIVE
	share = 1.0
	_since = -INF


## Whether the bot may walk up to a zombie (the crowbar's chase): only when it is healthy.
func may_push() -> bool:
	return not enabled or state == State.AGGRESSIVE


## Whether the bot may go off on its own (roam to another place, an errand): not when it is low.
func may_wander() -> bool:
	return not enabled or state != State.SAFE


## The retreat margin (metres) the bot keeps from the dead: the profile's, or the state's if wider.
func margin(base: float) -> float:
	if not enabled:
		return base
	match state:
		State.CAREFUL:
			return maxf(base, _profile.careful_margin)
		State.SAFE:
			return maxf(base, _profile.safe_margin)
	return base


## Whether a retreat should take open ground over a close place (a dead end is the end of a bot).
func prefers_open_ground() -> bool:
	return enabled and state == State.SAFE


## Whether a Safe bot under a Hold order may back away from the spot it holds, standing `apart`
## metres from it.
func may_back_off_hold(apart: float) -> bool:
	return enabled and state == State.SAFE and apart < _profile.hold_back


## The metres from the held spot beyond which a Safe holder walks back toward it.
func hold_back() -> float:
	return _profile.hold_back


## Whether a Safe holder is off the spot on purpose: it does not walk back until it is healthy.
func stays_off_hold(apart: float) -> bool:
	return enabled and state == State.SAFE and apart <= _profile.hold_back + 1.0


## The band (metres from the person) a follower keeps, or `Vector2.ZERO` for the usual one.
func follow_band() -> Vector2:
	if enabled and state == State.SAFE:
		return _profile.safe_follow_band
	return Vector2.ZERO


## Whether the bot gives up (or does not start) a revive: Safe, a zombie within
## `safe_revive_range`, and somebody else is up to do it (`last` is the last one up).
func gives_up_revive(nearest_threat: float, last: bool) -> bool:
	return (
		enabled and state == State.SAFE and not last and nearest_threat < _profile.safe_revive_range
	)
