class_name UIInputMode
extends RefCounted
## Which kind of input was used last. The focus ring shows only for keyboard and gamepad:
## a mouse user sees hover, not a ring.

## A mouse that moves less than this (screen pixels) in one event is a bumped desk, not a player
## taking the mouse: it leaves a gamepad player's glyphs alone.
const MOUSE_NOISE_PIXELS := 3.0

static var pointer := true
## Whether the last non-pointer input came from a gamepad (button glyphs follow it).
static var gamepad := false


## Feed every input event through this (the router does).
static func track(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		or (
			event is InputEventMouseMotion
			and (event as InputEventMouseMotion).screen_relative.length() >= MOUSE_NOISE_PIXELS
		)
		or event is InputEventScreenTouch
	):
		pointer = true
		gamepad = false
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction:
		pointer = false
		if not event is InputEventAction:
			gamepad = event is InputEventJoypadButton
	elif (
		event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5
	):
		pointer = false
		gamepad = true
