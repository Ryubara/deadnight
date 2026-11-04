class_name VoiceDirector
extends RefCounted
## Decides when the soldier speaks and which take, so lines never overlap, stack or repeat. Plain
## logic on a clock the owner moves (`advance`): no engine nodes, no wall clock, a seedable
## generator. `SoldierVoice` asks (`choose`), plays, and tells it what played (`commit`).
##
## - **One voice at a time.** A line owns the channel until it ends plus `GAP`; a request that
##   comes while it is busy is dropped (a bark is about the moment it was said in, not queued).
## - **Priority.** Only a request of `interrupt_priority` or more (hurt, downed) may cut any line
##   that is speaking, and only one it ranks above: downed over hurt over everything else. A
##   request that outranks the line speaking by `cut_margin` (a streak over a kill, a boss over a
##   mutter) cuts it too. A progression cheer (`SoldierVoiceCatalog.PROGRESS`) ranks above the
##   chatter and gives way to any line of `urgent_priority` or more (a boss, a teammate down).
## - **Cooldown** per moment and per speaker, and a `chance` that the moment is voiced at all.
## - **Variety.** A moment never repeats one of its last `remember_takes` takes (fewer when few).

## Lines started, in order, for tests and the capture's report:
## {"event", "speaker", "take", "at"}.
var history: Array[Dictionary] = []

var _t := NightSoundTuning.current()
var _rng := RandomNumberGenerator.new()
var _now := 0.0
## "event:speaker" -> when it last started.
var _last := {}
## event -> its last takes (numbers), newest last.
var _recent := {}
## The line that is speaking: {"event", "speaker", "take", "priority", "ends"}; empty when none.
var _line := {}
var _free_at := -INF
var _quiet_since := 0.0


func seed_random(value: int) -> void:
	_rng.seed = value


func advance(delta: float) -> void:
	_now += delta


func now() -> float:
	return _now


## Whether a line is speaking now.
func is_speaking() -> bool:
	return not _line.is_empty() and _now < float(_line["ends"])


## Seconds until the channel is free for an ordinary line (0 when it is).
func wait() -> float:
	return maxf(_free_at - _now, 0.0)


## Seconds since the last line ended (since the start when none has).
func quiet_for() -> float:
	return _now - (float(_line["ends"]) if not _line.is_empty() else _quiet_since)


## The take number to play for `event` said by `speaker`, or 0 when nothing should be said now: the
## moment is unknown, the channel is busy with something at least as important, the speaker said
## it too recently, or the chance roll said no. Changes nothing until `commit`.
func choose(event: StringName, speaker := 0) -> int:
	var info: Dictionary = SoldierVoiceCatalog.moments().get(event, {})
	if info.is_empty() or not may_start(int(info["priority"])):
		return 0
	if _now - float(_last.get("%s:%d" % [event, speaker], -INF)) < float(info["cooldown"]):
		return 0
	if _rng.randf() >= float(info["chance"]):
		return 0
	var count := int(info["takes"])
	var avoid: Array = _recent.get(event, [])
	var options: Array[int] = []
	for n in range(1, count + 1):
		if not avoid.has(n):
			options.append(n)
	return options[_rng.randi() % options.size()]


## Whether a line of this priority could start now.
func may_start(priority: int) -> bool:
	if _now >= _free_at:
		return true
	if not is_speaking():
		return priority >= _t.interrupt_priority
	return would_interrupt(priority)


## Whether a line of this priority would cut the one that is speaking.
func would_interrupt(priority: int) -> bool:
	if not is_speaking():
		return false
	var current := int(_line["priority"])
	var cheer := SoldierVoiceCatalog.is_progress(_line["event"])
	return (
		priority > current
		and (
			priority >= _t.interrupt_priority
			or priority - current >= _t.cut_margin
			or (cheer and priority >= _t.urgent_priority)
		)
	)


## Records that `take` of `event` started now and lasts `duration`; the channel is its until then.
func commit(event: StringName, speaker: int, take: int, duration: float) -> void:
	var info: Dictionary = SoldierVoiceCatalog.moments()[event]
	_last["%s:%d" % [event, speaker]] = _now
	var recent: Array = _recent.get(event, [])
	recent.append(take)
	var keep := mini(_t.remember_takes, int(info["takes"]) - 1)
	while recent.size() > keep:
		recent.pop_front()
	_recent[event] = recent
	_line = {
		"event": event,
		"speaker": speaker,
		"take": take,
		"priority": int(info["priority"]),
		"ends": _now + duration,
	}
	_free_at = _now + duration + _t.line_gap
	history.append({"event": event, "speaker": speaker, "take": take, "at": _now})


## Forgets the line that is speaking (it was cut, or the night ended).
func clear() -> void:
	_line = {}
	_free_at = -INF
	_quiet_since = _now
