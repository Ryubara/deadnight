class_name DeadStats
extends RefCounted
## What the dead do to the bodies in a night (#914), read from outside: for every player up, how
## long  the body was held by a zombie it was pushing into (pinned), how often that went on for as
## long as a person would call being stuck (trapped), how many nudges the server made, and what the
## work cost (`PerfProbe`). `tick` runs once after every `SeatedNight.tick`; `report` is plain data.

## Seconds of unbroken hold that make an episode, and a trap.
const EPISODE := 0.5
const TRAPPED := 2.0
## A gap shorter than this in a hold does not end it.
const GAP := 0.25

var night: SeatedNight
## The seats counted (all when empty).
var only: Array[int] = []
var ticks := 0
var player_ticks := 0
var pinned_ticks := 0
var touching_ticks := 0
var dead_ticks := 0.0
var episodes := 0
var trapped := 0
var longest := 0.0
var _run: Dictionary[int, float] = {}
var _gap: Dictionary[int, float] = {}
var _counted: Dictionary[int, int] = {}
var _usec: Dictionary[StringName, int] = {}
var _near_sum := 0.0
var _near_ticks := 0


func _init(p_night: SeatedNight) -> void:
	night = p_night
	PerfProbe.enabled = true
	PerfProbe.take()


func tick() -> void:
	ticks += 1
	var taken := PerfProbe.take()
	for label: StringName in taken["usec"]:
		_usec[label] = _usec.get(label, 0) + int(taken["usec"][label])
	dead_ticks += float(night.server.sim.standing_count())
	for id: int in night.server.rules.players:
		if night.server.rules.players[id].downed or night.server.body_of(id) == null:
			continue
		if not only.is_empty() and not only.has(id):
			continue
		var field := night.server.dead_field_of(id)
		player_ticks += 1
		_near_sum += float(field.ids.size())
		_near_ticks += 1
		if not field.touch_ids.is_empty():
			touching_ticks += 1
		var pinned := field.blocked
		if pinned:
			pinned_ticks += 1
			_run[id] = _run.get(id, 0.0) + Night.STEP + _gap.get(id, 0.0)
			_gap[id] = 0.0
			if _run[id] >= EPISODE and _counted.get(id, 0) < 1:
				_counted[id] = 1
				episodes += 1
			if _run[id] >= TRAPPED and _counted.get(id, 0) < 2:
				_counted[id] = 2
				trapped += 1
			longest = maxf(longest, _run[id])
		elif _run.has(id):
			_gap[id] = _gap.get(id, 0.0) + Night.STEP
			if _gap[id] > GAP:
				_run.erase(id)
				_gap.erase(id)
				_counted.erase(id)


func report() -> Dictionary:
	PerfProbe.enabled = false
	var minutes := float(player_ticks) * Night.STEP / 60.0
	var per_tick := func(label: StringName) -> float:
		return snappedf(float(_usec.get(label, 0)) / maxf(float(ticks), 1.0), 0.01)
	var shove := night.server.shove()
	return {
		"ticks": ticks,
		"player_minutes": snappedf(minutes, 0.01),
		"pinned_share": snappedf(float(pinned_ticks) / maxf(float(player_ticks), 1.0), 0.0001),
		"touching_share": snappedf(float(touching_ticks) / maxf(float(player_ticks), 1.0), 0.0001),
		"episodes": episodes,
		"episodes_per_player_minute": snappedf(float(episodes) / maxf(minutes, 0.01), 0.01),
		"trapped": trapped,
		"trapped_per_player_hour": snappedf(float(trapped) / maxf(minutes / 60.0, 0.001), 0.1),
		"longest_hold": snappedf(longest, 0.01),
		"nudges": shove.nudges,
		"mean_dead": snappedf(dead_ticks / maxf(float(ticks), 1.0), 0.1),
		"mean_near": snappedf(_near_sum / maxf(float(_near_ticks), 1.0), 0.01),
		"us_per_tick":
		{
			"snapshot": per_tick.call(&"dead.snapshot"),
			"fill": per_tick.call(&"dead.fill"),
			"block": per_tick.call(&"dead.block"),
			"shove": per_tick.call(&"dead.shove"),
		},
	}
