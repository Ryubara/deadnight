class_name CommandCodec
extends RefCounted
## The numbers of a command on the wire, and the snapping both ends apply to them: a move is one
## signed byte a stick axis, an angle two bytes (a turn in 65536 steps, a look up or down in 32767
## steps either way over a quarter turn), a point two bytes a coordinate in centimetres.
##
## Every `snap_*` is the decoding of the encoding, so a client that snaps its command before it
## moves its own body (prediction) feeds its simulation exactly the numbers the server reads; they
## differ only by what the sim does with them, never by what the wire dropped.

## A stick axis is a signed byte over this many steps either way.
const MOVE_STEPS := 127
const TURN_STEPS := 65536
const LOOK_STEPS := 32767
const YAW_STEP := TAU / TURN_STEPS
const LOOK_STEP := (PI / 2.0) / LOOK_STEPS
## Centimetres; a coordinate is good for this far (about 327 m) from the origin either way.
const POINT_STEPS_PER_METRE := 100.0
const POINT_MAX := 32767

# --- Move ---


## The two bytes of a stick push: each axis rounded to a step of 1/127, then, if that lands outside
## the unit circle, the larger axis stepped back until it is inside (so what is sent is never a
## stronger push than the stick gave, and decoding it needs no scaling).
static func move_bytes(value: Vector2) -> Vector2i:
	if not value.is_finite():
		return Vector2i.ZERO
	var limited := value.limit_length(1.0)
	var bytes := Vector2i(roundi(limited.x * MOVE_STEPS), roundi(limited.y * MOVE_STEPS))
	while bytes.x * bytes.x + bytes.y * bytes.y > MOVE_STEPS * MOVE_STEPS:
		if absi(bytes.x) >= absi(bytes.y):
			bytes.x -= signi(bytes.x)
		else:
			bytes.y -= signi(bytes.y)
	return bytes


## The move a pair of bytes means: never longer than 1, so a hostile (127, 127) is a full push.
static func move_from_bytes(x: int, y: int) -> Vector2:
	var push := Vector2(clampi(x, -MOVE_STEPS, MOVE_STEPS), clampi(y, -MOVE_STEPS, MOVE_STEPS))
	if push.length_squared() > MOVE_STEPS * MOVE_STEPS:
		push = push.normalized() * MOVE_STEPS
	return push / MOVE_STEPS


static func snap_move(value: Vector2) -> Vector2:
	var bytes := move_bytes(value)
	return move_from_bytes(bytes.x, bytes.y)


# --- Angles ---


## A turn (radians, any number of full turns) as a step of the 65536 round a circle.
static func yaw_step(yaw: float) -> int:
	if not is_finite(yaw):
		return 0
	return posmod(roundi(yaw / YAW_STEP), TURN_STEPS)


## The turn a step means, in [-PI, PI).
static func yaw_from_step(step: int) -> float:
	return (step if step < TURN_STEPS / 2 else step - TURN_STEPS) * YAW_STEP


static func snap_yaw(yaw: float) -> float:
	return yaw_from_step(yaw_step(yaw))


## A look up or down (radians, held to a quarter turn either way) as a signed step.
static func look_step(pitch: float) -> int:
	if not is_finite(pitch):
		return 0
	return roundi(clampf(pitch, -PI / 2.0, PI / 2.0) / LOOK_STEP)


static func look_from_step(step: int) -> float:
	return clampi(step, -LOOK_STEPS, LOOK_STEPS) * LOOK_STEP


static func snap_pitch(pitch: float) -> float:
	return look_from_step(look_step(pitch))


# --- Points and directions ---


static func point_step(metres: float) -> int:
	if not is_finite(metres):
		return 0
	return clampi(roundi(metres * POINT_STEPS_PER_METRE), -POINT_MAX, POINT_MAX)


static func point_from_step(step: int) -> float:
	return clampi(step, -POINT_MAX, POINT_MAX) / POINT_STEPS_PER_METRE


static func snap_point(value: Vector3) -> Vector3:
	return Vector3(
		point_from_step(point_step(value.x)),
		point_from_step(point_step(value.y)),
		point_from_step(point_step(value.z))
	)


## The turn and look of a direction (0 and 0 face -Z, the way the camera's yaw and pitch do).
static func direction_angles(direction: Vector3) -> Vector2:
	if not direction.is_finite() or direction.length() < 0.001:
		return Vector2.ZERO
	var unit := direction.normalized()
	return Vector2(atan2(-unit.x, -unit.z), asin(clampf(unit.y, -1.0, 1.0)))


## The unit direction a turn and a look make.
static func direction_from_angles(yaw: float, pitch: float) -> Vector3:
	var flat := cos(pitch)
	return Vector3(-sin(yaw) * flat, sin(pitch), -cos(yaw) * flat)
