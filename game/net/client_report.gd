class_name ClientReport
extends Node
## `--report [seconds]` on a client: prints one JSON line every few seconds with what the joined
## night looks like from here, for a headless run that has no window to look at (and for the
## numbers of #52): the player, who else is in the frame, the zombies and the round, the round trip
## and the gaps between ticks. The game does not read it; it only prints.

const DEFAULT_EVERY := 5.0

var every := DEFAULT_EVERY
var _since := 0.0


func _process(delta: float) -> void:
	_since += delta
	if _since < every:
		return
	_since = 0.0
	print(JSON.stringify(report(UIRouter.top())))


## What the top screen shows of an online night, as plain values; `{"event": "client", "night":
## false}` when there is none yet.
static func report(top: Control) -> Dictionary:
	var out := {"event": "client", "t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01)}
	var screen := top as NightScreen
	if screen == null or screen.night == null or screen.night.state == null:
		out["night"] = false
		return out
	var state := screen.night.state
	out["night"] = true
	out["player_id"] = state.player_id
	if state.has_frame():
		out["players"] = state.frame["players"].keys()
		out["round"] = state.round_number()
		out["zombies"] = state.zombies.size()
		out["points"] = state.points()
		out["position"] = state.position()
	var link := screen.night.link as WebSocketLink
	if link != null:
		out["bytes_in"] = link.bytes_in
		out["bytes_out"] = link.bytes_out
		out.merge(link.take_stats())
	return out
