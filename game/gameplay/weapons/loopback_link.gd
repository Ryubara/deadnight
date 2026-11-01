class_name LoopbackLink
extends RefCounted
## A stand-in transport between a client and a `CombatServer` in the same process: single-player
## runs through it, and so does the test range. Every action and every answer is serialised with
## `var_to_bytes` and read back, so the link proves they are plain data; when the real transport
## (#38) is chosen, only this class is replaced.
##
## `latency_ticks` delays each direction by that many fixed steps, to feel the lag compensation.

## Events the server answered with, after the round trip.
signal delivered(events: Array)

var latency_ticks: int = 0

## Anything with `apply(action: Dictionary) -> Array` (the combat server, the night server).
var _server: RefCounted
var _tick: int = 0
var _requests: Array[Dictionary] = []
var _answers: Array[Dictionary] = []


func _init(p_server: RefCounted, p_latency_ticks: int = 0) -> void:
	_server = p_server
	latency_ticks = p_latency_ticks


## The client's side: put an action on the wire.
func send(action: Dictionary) -> void:
	_requests.append({"due": _tick + latency_ticks, "bytes": var_to_bytes(action)})


## The server's side: events the server caused on its own (a projectile that burst, a reload that
## finished) go to the client the same way an answer does.
func broadcast(events: Array) -> void:
	if not events.is_empty():
		_answers.append({"due": _tick + latency_ticks, "bytes": var_to_bytes(events)})


## One fixed step: deliver what is due in each direction. Call once per tick, after the server's.
func pump() -> void:
	_tick += 1
	while not _requests.is_empty() and _requests[0]["due"] <= _tick:
		var action: Dictionary = bytes_to_var(_requests.pop_front()["bytes"])
		var events: Array = _server.apply(action)
		_answers.append({"due": _tick + latency_ticks, "bytes": var_to_bytes(events)})
	while not _answers.is_empty() and _answers[0]["due"] <= _tick:
		delivered.emit(bytes_to_var(_answers.pop_front()["bytes"]))
