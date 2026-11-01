class_name GrenadeThrower
extends RefCounted
## The player's side of a throw, one tick at a time: turns the grenade buttons of each
## `PlayerCommand` into `GrenadeAction`s for the server. Press a button to cook, hold to keep
## cooking, release to throw (the overarm button throws far, the underarm one tosses short).
##
## It reads only its arguments, so the same commands from the same state give the same actions
## whenever they are run: live on the client (which predicts the throw at once), on the server
## from the command stream, and again when the client replays its unacknowledged commands after a
## correction. `snapshot()` / `restore()` save its state beside the movement state for that replay.

## How far the hand may drift while cooking before the server is told where it is now.
const HAND_SYNC_DISTANCE := 0.5

var player_id: int = 0
var def: GrenadeDef

var _style: StringName = &""
var _held_ticks: int = 0
## After an abandoned cook the held button does nothing until it is let go.
var _blocked: bool = false
var _seq: int = 0
var _last_hand: Vector3 = Vector3.ZERO


func _init(p_player_id: int, p_def: GrenadeDef) -> void:
	player_id = p_player_id
	def = p_def


## Whether a grenade is in the hand right now.
func is_cooking() -> bool:
	return _style != &""


## Seconds the pin has been out, at the fixed step the commands are made at.
func cooked_for(delta: float) -> float:
	return _held_ticks * delta


## What the server should hear for this tick's command. `hand` is where the grenade would leave
## the hand, `aim` the camera direction and `velocity` the player's own, all of this tick.
func step(
	command: PlayerCommand, hand: Vector3, aim: Vector3, velocity: Vector3
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var wanted := _wanted(command)
	if _style == &"":
		if wanted == &"":
			_blocked = false
		elif not _blocked:
			_seq += 1
			_style = wanted
			_held_ticks = 0
			_last_hand = hand
			actions.append(GrenadeAction.cook(player_id, _seq, hand))
		return actions
	if wanted == _style:
		_held_ticks += 1
		if hand.distance_to(_last_hand) > HAND_SYNC_DISTANCE:
			_last_hand = hand
			actions.append(GrenadeAction.cook(player_id, _seq, hand))
		return actions
	actions.append(
		GrenadeAction.throw_grenade(player_id, _seq, hand, aim, velocity, _style == &"under")
	)
	_style = &""
	_held_ticks = 0
	return actions


## The server said the grenade went off in the hand (or the cook was refused): forget the hold,
## and ignore the button until it is released.
func abandon() -> void:
	_style = &""
	_held_ticks = 0
	_blocked = true


func snapshot() -> Dictionary:
	return {
		"style": _style,
		"held": _held_ticks,
		"seq": _seq,
		"hand": _last_hand,
		"blocked": _blocked,
	}


func restore(data: Dictionary) -> void:
	_style = data["style"]
	_held_ticks = data["held"]
	_seq = data["seq"]
	_last_hand = data["hand"]
	_blocked = data["blocked"]


func _wanted(command: PlayerCommand) -> StringName:
	if _style == &"over" and command.throw_over:
		return &"over"
	if _style == &"under" and command.throw_under:
		return &"under"
	if command.throw_over:
		return &"over"
	if command.throw_under:
		return &"under"
	return &""
