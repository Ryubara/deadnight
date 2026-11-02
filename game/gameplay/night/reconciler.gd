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
##
## A correction moves the body, so it moves the answer the commands still unanswered will be judged
## against too: the remembered positions after `ack` are shifted by the same amount. Without that
## the next frames (the server's answers are a round trip behind) measure the same error again and
## correct it again, and a round trip of a few frames turns each correction into a bigger one, until
## the body is thrown across the map (#483).

## Errors shorter than this (metres) are not worth a correction.
const DEADZONE := 0.03
## The share of the error taken back each frame.
const CATCH_UP := 0.25
## Errors longer than this (metres) snap at once: the server moved the player (a respawn, a push).
const SNAP := 2.5
## How many commands are remembered.
const KEEP := 600
## A body farther than this (metres) from the server's position, with no answer to judge it by (a
## freeze that outlasted the commands remembered, a seat taken back), is put where the server says.
const LOST := 6.0

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


## Forgets every command: the next answers are not about any of them (a freeze put the body where
## the server says).
func reset() -> void:
	_history.clear()


## How far to move the body, given the server's position after command `ack` (and, when it is
## given, where the body is now); zero when nothing is to be done (no such command, or an error
## within the deadzone). The body must be moved by the result.
func correction(ack: int, server_position: Vector3, body_position := Vector3.INF) -> Vector3:
	frames += 1
	if not _history.has(ack):
		if body_position != Vector3.INF and body_position.distance_to(server_position) > LOST:
			corrections += 1
			worst_error = maxf(worst_error, body_position.distance_to(server_position))
			_history.clear()
			return server_position - body_position
		return Vector3.ZERO
	var error := server_position - _history[ack]
	for seq in _history.keys():
		if seq <= ack:
			_history.erase(seq)
	worst_error = maxf(worst_error, error.length())
	if error.length() < DEADZONE:
		return Vector3.ZERO
	corrections += 1
	var shift := error if error.length() > SNAP else error * CATCH_UP
	for seq in _history:
		_history[seq] += shift
	return shift
