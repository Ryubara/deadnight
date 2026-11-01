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
## Seconds between the button coming up and the grenade leaving the hand, for each style: the
## time the throw clip takes to reach its release frame. Zero (the default) throws at once.
var release_over: float = 0.0
var release_under: float = 0.0

var _style: StringName = &""
var _held_ticks: int = 0
## After an abandoned cook the held button does nothing until it is let go.
var _blocked: bool = false
var _seq: int = 0
var _last_hand: Vector3 = Vector3.ZERO
## While the arm swings (the button is up, the grenade has not left): the style and the seconds
## left to the release. The fuse goes on burning meanwhile.
var _winding: StringName = &""
var _wind_left: float = 0.0
## The style whose swing began in the latest `step`, else empty.
var _swing_began: StringName = &""


func _init(p_player_id: int, p_def: GrenadeDef) -> void:
	player_id = p_player_id
	def = p_def


## Where a grenade leaves a player standing at `position` facing `facing` (radians) who looks along
## `dir`, and along which line: `{"hand": Vector3, "aim": Vector3}`. The hand is `reach` metres out
## along the aim on the ground and `GrenadeDef.hand_height` up. A look that is not a direction
## (zero, not finite) is the way the player faces. The server throws from this and the client
## previews the same throw from it.
static func launch(
	p_def: GrenadeDef, reach: float, position: Vector3, facing: float, dir: Vector3
) -> Dictionary:
	var aim := dir
	if not aim.is_finite() or aim.length_squared() < 0.5:
		aim = Basis(Vector3.UP, facing) * Vector3.FORWARD
	aim = aim.normalized()
	var flat := Vector3(aim.x, 0.0, aim.z).normalized()
	return {"hand": position + Vector3.UP * p_def.hand_height + flat * reach, "aim": aim}


## Whether a grenade is in the hand right now (cooking, or on its way out of the hand).
func is_cooking() -> bool:
	return _style != &"" or _winding != &""


## Whether the arm is swinging: the button is up and the grenade has not left the hand yet.
func is_winding_up() -> bool:
	return _winding != &""


## The style (`over` or `under`) of the swing that began in the latest `step`, else empty: the
## moment the throw clip should start.
func swing_began() -> StringName:
	return _swing_began


## Seconds the pin has been out, at the fixed step the commands are made at.
func cooked_for(delta: float) -> float:
	return _held_ticks * delta


## What the server should hear for this tick's command. `hand` is where the grenade would leave
## the hand, `aim` the camera direction and `velocity` the player's own, all of this tick.
func step(
	command: PlayerCommand,
	hand: Vector3,
	aim: Vector3,
	velocity: Vector3,
	delta: float = 1.0 / 60.0
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	_swing_began = &""
	if _winding != &"":
		_wind_left -= delta
		if _wind_left <= 0.0:
			actions.append(
				GrenadeAction.throw_grenade(
					player_id, _seq, hand, aim, velocity, _winding == &"under"
				)
			)
			_winding = &""
		return actions
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
	var release := release_under if _style == &"under" else release_over
	if release > 0.0:
		_swing_began = _style
		_winding = _style
		_wind_left = release
	else:
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
	_winding = &""
	_blocked = true


func snapshot() -> Dictionary:
	return {
		"style": _style,
		"held": _held_ticks,
		"seq": _seq,
		"hand": _last_hand,
		"blocked": _blocked,
		"winding": _winding,
		"wind_left": _wind_left,
	}


func restore(data: Dictionary) -> void:
	_style = data["style"]
	_held_ticks = data["held"]
	_seq = data["seq"]
	_last_hand = data["hand"]
	_blocked = data["blocked"]
	_winding = data["winding"]
	_wind_left = data["wind_left"]


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
