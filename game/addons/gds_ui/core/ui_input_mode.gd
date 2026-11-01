class_name UIInputMode
extends RefCounted
## Which kind of input was used last. The focus ring shows only for keyboard and gamepad:
## a mouse user sees hover, not a ring.

static var pointer := true


## Feed every input event through this (the router does).
static func track(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		or event is InputEventMouseMotion
		or event is InputEventScreenTouch
	):
		pointer = true
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction:
		pointer = false
	elif (
		event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5
	):
		pointer = false
