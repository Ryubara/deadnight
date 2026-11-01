class_name FrameDelta
extends RefCounted
## A frame is the whole picture of a step (`NightServer`); most of it does not change from one step
## to the next. Over a connection that never reorders or loses (TCP, so WebSocket), the server sends
## each client only what differs from the frame it sent that client before, and the client puts the
## frame back together. There is no baseline to agree on: the previous frame is the baseline.
##
## A delta is the frame's changed top-level fields, flagged `delta: true`. Of `players` it carries,
## for each player, only the fields that changed (all of them for a new player), and `gone`, the ids
## of players that left.


## `next` against `previous` (empty for the first frame, which is sent whole).
static func diff(previous: Dictionary, next: Dictionary) -> Dictionary:
	if previous.is_empty():
		return next
	var out := {"type": &"frame", "delta": true}
	for key: Variant in next:
		if key == "players":
			continue
		if not previous.has(key) or previous[key] != next[key]:
			out[key] = next[key]
	var before: Dictionary = previous.get("players", {})
	var now: Dictionary = next["players"]
	var players := {}
	for id: Variant in now:
		if not before.has(id):
			players[id] = now[id]
			continue
		var changed := {}
		for field: Variant in now[id]:
			if not before[id].has(field) or before[id][field] != now[id][field]:
				changed[field] = now[id][field]
		if not changed.is_empty():
			players[id] = changed
	out["players"] = players
	var gone := []
	for id: Variant in before:
		if not now.has(id):
			gone.append(id)
	if not gone.is_empty():
		out["gone"] = gone
	return out


## The whole frame that `delta` makes of `base` (the frame the client had). A whole frame (no
## `delta` flag) is returned as it is.
static func apply(base: Dictionary, delta: Dictionary) -> Dictionary:
	if not delta.get("delta", false):
		return delta
	var out := base.duplicate()
	for key: Variant in delta:
		if key == "players" or key == "gone" or key == "delta":
			continue
		out[key] = delta[key]
	var players: Dictionary = base.get("players", {}).duplicate()
	for id: Variant in delta.get("gone", []):
		players.erase(id)
	var changes: Dictionary = delta.get("players", {})
	for id: Variant in changes:
		var merged: Dictionary = players.get(id, {}).duplicate()
		merged.merge(changes[id], true)
		players[id] = merged
	out["players"] = players
	return out
