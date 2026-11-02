class_name ChallengePromptQueue
extends RefCounted
## What the challenge prompt shows and when: a queue of advances (`ChallengeProfile.apply`'s
## dictionaries), one on screen at a time. Plain data and a clock the caller moves with
## `advance(delta)`, so a test steps it by hand and a capture repeats frame for frame.
##
## The rules (docs/design/progression.md, "The progress prompt in the night"):
## - One prompt per challenge: a newer advance of the one showing, or waiting, replaces it.
## - The most important first: a finished challenge, then a milestone, then 75, 50, 25 percent.
## - Rare and short: it comes in over `IN_SECONDS`, holds, leaves over `OUT_SECONDS`. A
##   completion holds longer; with others waiting every hold shortens, so a burst never queues up
##   a long wait.
## - At most `MAX_WAITING` wait; the lowest quarter marks go first, a completion never does.
## - A prompt that waited past `STALE_SECONDS` is dropped: it would describe something long gone.
## - While blocked (the player is down) nothing starts and the showing one holds, but waiting ones
##   still age.

enum Phase { IDLE, IN, HOLD, OUT }

const IN_SECONDS := 0.25
const OUT_SECONDS := 0.4
const HOLD_SECONDS := 2.4
const HOLD_COMPLETE_SECONDS := 3.2
const HOLD_BUSY_SECONDS := 1.6
## Quiet between one prompt and the next.
const GAP_SECONDS := 0.3
const MAX_WAITING := 3
const STALE_SECONDS := 20.0

## The prompt showing now (empty when none).
var current: Dictionary = {}
var phase: Phase = Phase.IDLE

var _waiting: Array[Dictionary] = []
var _clock := 0.0
var _phase_time := 0.0
var _gap := 0.0
var _hold := HOLD_SECONDS


## How much a prompt matters: higher shows first and is dropped last.
static func priority(advance: Dictionary) -> int:
	if advance.get("completed", false):
		return 100
	if int(advance.get("rung", 0)) > 0:
		return 80
	return 20 + int(advance.get("checkpoint", 0)) / 2


## True for an advance worth a prompt at all: a quarter mark, a finish or a milestone step.
static func is_worth_showing(advance: Dictionary) -> bool:
	return (
		bool(advance.get("completed", false))
		or int(advance.get("rung", 0)) > 0
		or int(advance.get("checkpoint", 0)) > 0
	)


## True for the prompts a player who chose "completions only" still sees.
static func is_milestone_or_completion(advance: Dictionary) -> bool:
	return bool(advance.get("completed", false)) or int(advance.get("rung", 0)) > 0


## Adds an advance. One of the same challenge already showing is updated in place (its hold
## starts again); one waiting is replaced.
func push(advance: Dictionary) -> void:
	var entry := advance.duplicate()
	entry["_at"] = _clock
	if not current.is_empty() and current["id"] == advance["id"] and phase != Phase.OUT:
		if priority(advance) >= priority(current):
			current = entry
			if phase == Phase.HOLD:
				_phase_time = 0.0
		return
	for i in _waiting.size():
		if _waiting[i]["id"] == advance["id"]:
			if priority(advance) >= priority(_waiting[i]):
				_waiting[i] = entry
			return
	_waiting.append(entry)
	while _waiting.size() > MAX_WAITING:
		_drop_least()
	_waiting.sort_custom(_before)


## Moves time on. `blocked` holds a showing prompt and starts none (the player is down).
func advance(delta: float, blocked := false) -> void:
	_clock += delta
	_waiting = _waiting.filter(
		func(entry: Dictionary) -> bool: return _clock - float(entry["_at"]) <= STALE_SECONDS
	)
	if blocked:
		return
	_phase_time += delta
	match phase:
		Phase.IDLE:
			_gap = maxf(_gap - delta, 0.0)
			if _gap <= 0.0 and not _waiting.is_empty():
				_show(_waiting.pop_front())
		Phase.IN:
			if _phase_time >= IN_SECONDS:
				phase = Phase.HOLD
				_phase_time = 0.0
		Phase.HOLD:
			if _phase_time >= _hold:
				phase = Phase.OUT
				_phase_time = 0.0
		Phase.OUT:
			if _phase_time >= OUT_SECONDS:
				current = {}
				phase = Phase.IDLE
				_phase_time = 0.0
				_gap = GAP_SECONDS


## 0 to 1: how far the prompt is in (0 not there, 1 fully shown).
func shown() -> float:
	match phase:
		Phase.IN:
			return clampf(_phase_time / IN_SECONDS, 0.0, 1.0)
		Phase.HOLD:
			return 1.0
		Phase.OUT:
			return 1.0 - clampf(_phase_time / OUT_SECONDS, 0.0, 1.0)
	return 0.0


func waiting_count() -> int:
	return _waiting.size()


## Forgets everything waiting and showing (a new night).
func clear() -> void:
	current = {}
	phase = Phase.IDLE
	_waiting.clear()
	_phase_time = 0.0
	_gap = 0.0


func _show(entry: Dictionary) -> void:
	current = entry
	phase = Phase.IN
	_phase_time = 0.0
	var quick := not _waiting.is_empty()
	_hold = HOLD_COMPLETE_SECONDS if priority(entry) >= 100 else HOLD_SECONDS
	if quick:
		_hold = minf(_hold, HOLD_BUSY_SECONDS)


## Drops the least important waiting prompt that is not a completion.
func _drop_least() -> void:
	var worst := -1
	for i in _waiting.size():
		if priority(_waiting[i]) >= 100:
			continue
		if worst < 0 or priority(_waiting[i]) <= priority(_waiting[worst]):
			worst = i
	# Only completions waiting: they are all kept.
	if worst >= 0:
		_waiting.remove_at(worst)


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var pa := priority(a)
	var pb := priority(b)
	if pa != pb:
		return pa > pb
	return float(a["_at"]) < float(b["_at"])
