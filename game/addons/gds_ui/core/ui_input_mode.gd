class_name UIInputMode
extends RefCounted
## Which kind of input was used last. The focus ring shows only for keyboard and gamepad:
## a mouse user sees hover, not a ring. A finger is a third kind: it is a pointer too, and it
## hides the key hints (a keycap on a phone points at nothing).

## Which button set a gamepad's glyphs use: letters on a round button (a generic or Xbox-style
## pad), the four PlayStation shapes, or the letters of a Nintendo pad (whose A and B, and X and
## Y, sit the other way round from the engine's names).
enum Family { GENERIC, PLAYSTATION, NINTENDO }

## A mouse that moves less than this (screen pixels) in one event is a bumped desk, not a player
## taking the mouse: it leaves a gamepad player's glyphs alone.
const MOUSE_NOISE_PIXELS := 3.0


## Carries the `changed` signal: a static variable cannot declare one itself.
class Bus:
	extends RefCounted
	signal changed


static var pointer := true
## Whether the last input was a finger (or the touch controls are up and nothing else was used).
static var touch := false:
	set(value):
		if value != touch:
			touch = value
			_bus.changed.emit()
## Whether the last non-pointer input came from a gamepad (button glyphs follow it).
static var gamepad := false:
	set(value):
		if value != gamepad:
			gamepad = value
			_bus.changed.emit()
## The button set of the gamepad used last, from its name (`family_for`).
static var family := Family.GENERIC:
	set(value):
		if value != family:
			family = value
			_bus.changed.emit()

static var _bus := Bus.new()


## Emitted when what a glyph shows could change: `gamepad`, `touch` or `family` took a new value.
## A glyph connects to it in `_ready`; a freed listener is disconnected on its own.
static func changed() -> Signal:
	return _bus.changed


## The button set a gamepad of this name takes. Names are as the OS reports them ("PS5 Controller",
## "Xbox Series Controller", "Nintendo Switch Pro Controller"); anything unknown is generic.
static func family_for(joy_name: String) -> Family:
	var lowered := joy_name.to_lower()
	for word in ["ps3", "ps4", "ps5", "playstation", "dualshock", "dualsense", "sony"]:
		if lowered.contains(word):
			return Family.PLAYSTATION
	for word in ["nintendo", "switch", "joy-con", "pro controller"]:
		if lowered.contains(word):
			return Family.NINTENDO
	return Family.GENERIC


## Feed every input event through this (the router does).
static func track(event: InputEvent) -> void:
	_apply(event)
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and gamepad:
		family = family_for(Input.get_joy_name(event.device))


static func _apply(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		pointer = true
		gamepad = false
		touch = true
	elif (
		event is InputEventMouseButton
		or (
			event is InputEventMouseMotion
			and (event as InputEventMouseMotion).screen_relative.length() >= MOUSE_NOISE_PIXELS
		)
	):
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
	family = Family.GENERIC
