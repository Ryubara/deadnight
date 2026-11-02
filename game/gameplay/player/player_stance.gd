class_name PlayerStance
extends RefCounted
## What a body is doing with its whole self, in four bits: sprinting, crouching, off the floor, and
## rising (a jump on its way up; off the floor and not rising is a fall). The server puts it in each
## player of the frame as one small integer (`NightServer._frame`), delta-coded like the rest of the
## frame so it travels only on a change, and a client's puppet `Player` takes it from there
## (`Player.puppet_to`) so the other players' sprint carry, crouch, jump and fall are drawn by the
## same `PlayerAnimation` as a played body's (#549).

const SPRINT := 1
const CROUCH := 2
const AIR := 4
const RISING := 8
## The bits of a stance that exist; a number with any other bit is not a stance.
const MASK := SPRINT | CROUCH | AIR | RISING


## The stance of a simulated body's state.
static func pack(state: PlayerMotionState) -> int:
	var bits := 0
	if state.sprinting:
		bits |= SPRINT
	if state.crouching:
		bits |= CROUCH
	if not state.on_floor:
		bits |= AIR
		if state.velocity.y > 0.0:
			bits |= RISING
	return bits


## A stance read from the wire: anything outside `MASK` is dropped, a non-number is no stance.
static func clean(value: Variant) -> int:
	return (value & MASK) if value is int else 0
