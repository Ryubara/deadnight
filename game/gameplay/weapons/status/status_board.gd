class_name StatusBoard
extends RefCounted
## Who has which status effect and for how long: the server's one record of it (`CombatServer` owns
## it, the rules read it to know that a hit shatters, the night server tells the zombie simulation
## what it means). Pure data stepped by the combat clock: no node, no engine time, no random draw.
##
## A target holds any number of statuses at once (a status id to the seconds left); applying one it
## already has keeps the longer time. What a zombie under several of them does is the sum of their
## definitions: it halts if any halts, goes at the slowest speed, shatters if any shatters, and is
## drawn in the one with the highest priority (`wire_of`).

var _left: Dictionary[int, Dictionary] = {}
## The build-up of a status that takes several hits to put on: target id to {status id: [bolts
## so far, seconds the count is kept]}. A bolt short of the count only chills (the caller's rule);
## the count runs out with its time, silently.
var _bolts: Dictionary[int, Dictionary] = {}


## Puts `status` on `target_id` for `seconds` (a longer time already running is kept). The change as
## an event for the combat answer: `status_applied` with `target_id`, `status`, `seconds` (what is
## left now) and what the target is under now (`summary_of`).
func apply(target_id: int, status: StatusDef, seconds: float) -> Dictionary:
	var held: Dictionary = _left.get_or_add(target_id, {})
	held[status.id] = maxf(held.get(status.id, 0.0), seconds)
	var event := {
		"type": &"status_applied",
		"target_id": target_id,
		"status": status.id,
		"seconds": held[status.id],
	}
	event.merge(summary_of(target_id))
	return event


## One combat step: the time left of every status runs down, and each that ran out is gone. The
## events are `status_ended` (`target_id`, `status`, and what the target is under now).
func step(delta: float) -> Array[Dictionary]:
	var ended: Array[Dictionary] = []
	_step_bolts(delta)
	for target_id: int in _left.keys():
		var held := _left[target_id]
		var done: Array[StringName] = []
		for id: StringName in held:
			held[id] -= delta
			if held[id] <= 0.0:
				done.append(id)
		for id in done:
			held.erase(id)
		if held.is_empty():
			_left.erase(target_id)
		for id in done:
			var event := {"type": &"status_ended", "target_id": target_id, "status": id}
			event.merge(summary_of(target_id))
			ended.append(event)
	return ended


## The target is gone (killed or removed): its statuses go with it, silently.
func forget(target_id: int) -> void:
	_left.erase(target_id)
	_bolts.erase(target_id)


## One more bolt of a status that takes several on `target_id`: the count so far including this one.
## The count is kept for `seconds` from the last bolt.
func add_bolt(target_id: int, status_id: StringName, seconds: float) -> int:
	var held: Dictionary = _bolts.get_or_add(target_id, {})
	var entry: Array = held.get(status_id, [0, 0.0])
	entry[0] += 1
	entry[1] = seconds
	held[status_id] = entry
	return entry[0]


## The count of `status_id` on `target_id` is over (the status went on): start from none.
func clear_bolts(target_id: int, status_id: StringName) -> void:
	if _bolts.has(target_id):
		_bolts[target_id].erase(status_id)


func has(target_id: int, status_id: StringName) -> bool:
	return _left.get(target_id, {}).has(status_id)


## Seconds left of one status on a target, 0 when it has none.
func left(target_id: int, status_id: StringName) -> float:
	return _left.get(target_id, {}).get(status_id, 0.0)


## Whether the target is under any status at all.
func any(target_id: int) -> bool:
	return _left.has(target_id)


## Whether any hit on this target kills it and breaks it (a status that shatters is on it).
## `keeps` is a status this hit does not break (the freeze gun's own bolt on a frozen zombie).
func shatterable(target_id: int, keeps: StringName = &"") -> bool:
	for def in _defs_of(target_id):
		if def.shatters and def.id != keeps:
			return true
	return false


## What the zombie simulation needs and a snapshot carries, from all the statuses of a target:
## `wire` (the id of the one drawn, `StatusDef.NONE` for none), `halts` (it stands still and does
## not attack) and `speed_scale` (the share of its speed it keeps).
func summary_of(target_id: int) -> Dictionary:
	var wire := StatusDef.NONE
	var best := -INF
	var halts := false
	var scale := 1.0
	for def in _defs_of(target_id):
		if def.priority > best:
			best = def.priority
			wire = def.wire
		halts = halts or def.halts
		scale = minf(scale, def.speed_scale)
	return {"wire": wire, "halts": halts, "speed_scale": scale}


func _step_bolts(delta: float) -> void:
	for target_id: int in _bolts.keys():
		var held := _bolts[target_id]
		for id: StringName in held.keys():
			held[id][1] -= delta
			if held[id][1] <= 0.0:
				held.erase(id)
		if held.is_empty():
			_bolts.erase(target_id)


func _defs_of(target_id: int) -> Array[StatusDef]:
	var defs: Array[StatusDef] = []
	for id: StringName in _left.get(target_id, {}):
		defs.append(StatusCatalog.get_def(id))
	return defs
