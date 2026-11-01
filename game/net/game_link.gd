class_name GameLink
extends RefCounted
## The client's end of a night's connection: what `Night` talks to, whatever carries the bytes.
## `LoopbackLink` (single-player, tests) and `WebSocketLink` (a game server) both are one.
##
## The client `send`s plain-data actions (a `NightCommand.to_dict()`), calls `pump` once per fixed
## tick, and hears the server through `delivered`: the events of the ticks that arrived, the
## frame of each last.

## Events the server sent, in order, after the trip.
signal delivered(events: Array)


## Puts one action on the wire.
func send(_action: Dictionary) -> void:
	pass


## Once per fixed tick: moves what is due in each direction.
func pump() -> void:
	pass


func is_open() -> bool:
	return true


func close() -> void:
	pass
