class_name BotTurn
extends RefCounted
## Whose turn it is to go on an errand (bots plan, phase 5): one bot at a time, the maintainer
## (`docs/research/bots.md#team-roles-and-communication`). A bot asks before it goes (`may_go`) and
## says it went (`took`) every think while the errand lasts; a turn lapses `LEASE` seconds after the
## last time it was taken, so a bot that finished, was called to a fight or left gives it up at
## once. A bot keeps the turn at most `SLICE` seconds while another waits, and then rests `REST`
## seconds before it may take it back, so the one with points to spend does not hold the others
## back for a whole night. Plain data and the clock the callers give it.

## Seconds a turn stands without being taken again.
const LEASE := 1.0
## Seconds a bot may keep the turn while another waits, and the rest it takes after.
const SLICE := 30.0
const REST := 10.0
## Seconds a bot that was told to wait counts as still waiting.
const WAITING := 3.0

## The bot whose turn it is (0 for nobody), since when, and until when.
var holder := 0
var _since := 0.0
var _until := 0.0
var _waiting: Dictionary[int, float] = {}
var _rest_until: Dictionary[int, float] = {}


## Whether `bot` may go on an errand now. A bot told no is noted as waiting.
func may_go(bot: int, now: float) -> bool:
	if holder != 0 and _until <= now:
		holder = 0
	if holder == bot:
		if now - _since > SLICE and _someone_waits(bot, now):
			holder = 0
			_rest_until[bot] = now + REST
			_waiting[bot] = now
			return false
		return true
	if holder != 0:
		_waiting[bot] = now
		return false
	if _rest_until.get(bot, -INF) > now and _someone_waits(bot, now):
		_waiting[bot] = now
		return false
	return true


## `bot` is on an errand now: the turn is its, and runs on for `LEASE` more seconds.
func took(bot: int, now: float) -> void:
	if holder != bot:
		holder = bot
		_since = now
	_until = now + LEASE
	_waiting.erase(bot)


## The bot left or was taken out.
func release(bot: int) -> void:
	if holder == bot:
		holder = 0
	_waiting.erase(bot)
	_rest_until.erase(bot)


func _someone_waits(except: int, now: float) -> bool:
	for bot: int in _waiting:
		if bot != except and now - _waiting[bot] <= WAITING:
			return true
	return false
