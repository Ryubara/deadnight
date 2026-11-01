class_name Reconciler
extends RefCounted
## Keeps a predicting client's own body honest. The client moves its body at once with the command
## it sends (so the controls answer without a round trip) and records where each command left it.
## The server says, in every frame, which command it had got to (`ack`) and where that left the
## player; the difference with what this client recorded for that command is the error, and
## `correction` gives how far to move the body toward the server's answer.
##
## Not a replay of the commands after `ack`: the body is moved by a share of the error each frame
## (`CATCH_UP`), which hides the small differences (a push from another player, a command the
## server used twice) and snaps over a big one.

## Errors shorter than this (metres) are not worth a correction.
const DEADZONE := 0.03
## The share of the error taken back each frame.
const CATCH_UP := 0.25
## Errors longer than this (metres) snap at once: the server moved the player (a respawn, a push).
const SNAP := 2.5
## How many commands are remembered.
const KEEP := 600

## The longest error seen, and how many frames needed a correction, for the numbers of a run.
var worst_error := 0.0
var corrections := 0
var frames := 0

var _history: Dictionary[int, Vector3] = {}


## Remembers where command `seq` left the body.
func record(seq: int, position: Vector3) -> void:
	_history[seq] = position
	if _history.size() > KEEP:
		_history.erase(_history.keys()[0])


## How far to move the body, given the server's position after command `ack`; zero when nothing is
## to be done (no such command, or an error within the deadzone).
func correction(ack: int, server_position: Vector3) -> Vector3:
	frames += 1
	if not _history.has(ack):
		return Vector3.ZERO
	var error := server_position - _history[ack]
	for seq in _history.keys():
		if seq <= ack:
			_history.erase(seq)
	worst_error = maxf(worst_error, error.length())
	if error.length() < DEADZONE:
		return Vector3.ZERO
	corrections += 1
	if error.length() > SNAP:
		return error
	return error * CATCH_UP
