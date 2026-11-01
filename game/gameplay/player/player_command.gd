class_name PlayerCommand
extends RefCounted
## One physics tick of player input, small and serializable.
##
## The controller samples the controls into one of these per tick; the simulation consumes it.
## Nothing else reaches the simulation, so a server (or a prediction replay) can run the same
## commands and get the same result. `jump` and `swap_shoulder` are "pressed this tick" edges,
## the rest are levels. View angles are absolute (radians), as the camera holds them.

## x: right is positive; y: backward is positive (the Input.get_vector convention). Length <= 1.
var move := Vector2.ZERO
var yaw := 0.0
var pitch := 0.0
var sprint := false
## Carried and recorded; the simulation does not act on it yet (crouch is a follow-up).
var crouch := false
var jump := false
var aim := false
var swap_shoulder := false
## The grenade buttons, as levels: holding one cooks the grenade, letting go throws it (overarm for
## `throw_over`, the short underarm toss for `throw_under`). `GrenadeThrower` makes actions of them.
var throw_over := false
var throw_under := false


func to_dict() -> Dictionary:
	return {
		&"move": move,
		&"yaw": yaw,
		&"pitch": pitch,
		&"sprint": sprint,
		&"crouch": crouch,
		&"jump": jump,
		&"aim": aim,
		&"swap_shoulder": swap_shoulder,
		&"throw_over": throw_over,
		&"throw_under": throw_under,
	}


static func from_dict(data: Dictionary) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = data.get(&"move", Vector2.ZERO)
	command.yaw = data.get(&"yaw", 0.0)
	command.pitch = data.get(&"pitch", 0.0)
	command.sprint = data.get(&"sprint", false)
	command.crouch = data.get(&"crouch", false)
	command.jump = data.get(&"jump", false)
	command.aim = data.get(&"aim", false)
	command.swap_shoulder = data.get(&"swap_shoulder", false)
	command.throw_over = data.get(&"throw_over", false)
	command.throw_under = data.get(&"throw_under", false)
	return command


func to_bytes() -> PackedByteArray:
	return var_to_bytes(to_dict())


static func from_bytes(bytes: PackedByteArray) -> PlayerCommand:
	var data: Variant = bytes_to_var(bytes)
	return from_dict(data if data is Dictionary else {})
