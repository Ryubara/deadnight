class_name UIInputMode
extends RefCounted
## Which kind of input was used last. The focus ring shows only for keyboard and gamepad:
## a mouse user sees hover, not a ring. A finger is a third kind: it is a pointer too, and it
## hides the key hints (a keycap on a phone points at nothing).

static var pointer := true
## Whether the last input was a finger (or the touch controls are up and nothing else was used).
static var touch := false
## Whether the last non-pointer input came from a gamepad (button glyphs follow it).
static var gamepad := false


## Feed every input event through this (the router does).
static func track(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		pointer = true
		gamepad = false
		touch = true
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		pointer = true
		gamepad = false
		# Mouse motion does not end touch: the touch layer sends its look as motion, and a finger
		# on a menu is a mouse as far as the engine says. A click that is not the engine's copy of
		# a touch is a real mouse, which takes over.
		var is_motion := event is InputEventMouseMotion
		touch = touch and (is_motion or event.device == InputEvent.DEVICE_ID_EMULATION)
	elif event is InputEventAction:
		# The touch layer sends `pause` as an action: that is not a key being pressed.
		if not touch:
			pointer = false
	elif event is InputEventKey or event is InputEventJoypadButton:
		pointer = false
		touch = false
		gamepad = event is InputEventJoypadButton
	elif (
		event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5
	):
		pointer = false
		touch = false
		gamepad = true


## Forget what was used (a test, or a new session).
static func reset() -> void:
	pointer = true
	gamepad = false
	touch = false
