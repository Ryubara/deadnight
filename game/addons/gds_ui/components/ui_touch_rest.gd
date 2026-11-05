@tool
class_name UITouchRest
extends RefCounted
## Takes the hover off a button a finger has lifted from. A finger that lifts sends no mouse exit,
## so the engine keeps the button it lifted over hovered, and drawn lit (pale and grown by the
## hover spring), until the next mouse motion; on a phone that is the next touch. The button is
## told the mouse left it, once its press feedback has run (`REST_DELAY_S`).
##
## It is decided from the event that lifted, never from the device: a touch (an
## `InputEventScreenTouch` release) takes the hover off, and a mouse release does not, so a desktop
## mouse keeps its hover and a laptop with a touch screen does whichever the last hand did. A real
## mouse that moves over the button before the delay ends keeps it too.

## How long after the lift the button is told, in seconds: the press spring (`UIButton`) is
## underdamped and settles in about this long, so the squash ends as designed before the look
## returns.
const REST_DELAY_S := 0.3

const _GENERATION := &"ui_touch_rest"


## Makes `button` go back to its resting look after a tap (once; a second call does nothing).
static func follow(button: BaseButton) -> void:
	if button.has_meta(_GENERATION):
		return
	button.set_meta(_GENERATION, 0)
	button.gui_input.connect(_on_gui_input.bind(button))


static func _on_gui_input(event: InputEvent, button: BaseButton) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		# A real mouse is over the button: it keeps what it has.
		_cancel(button)
		return
	var touch := event as InputEventScreenTouch
	if touch == null or not button.is_inside_tree():
		return
	var generation := _cancel(button)
	if touch.pressed:
		# A finger is down again: whatever was due to rest waits for its lift.
		return
	button.get_tree().create_timer(REST_DELAY_S).timeout.connect(
		_rest.bind(button.get_instance_id(), generation)
	)


## Calls off the rest that is due, and returns the number of the next one.
static func _cancel(button: BaseButton) -> int:
	var next := int(button.get_meta(_GENERATION, 0)) + 1
	button.set_meta(_GENERATION, next)
	return next


## Tells `button` the mouse left it, when it is still there, still hovered and nothing has touched
## or moved over it since. It may be gone by now (a press that opens a screen frees its own button).
static func _rest(id: int, generation: int) -> void:
	var button := instance_from_id(id) as BaseButton
	if button == null or not button.is_inside_tree():
		return
	if int(button.get_meta(_GENERATION, 0)) != generation:
		return
	if not button.is_hovered():
		return
	drop_hover(button)


## Takes the hover off `button` now: a button that stops being a pointer target for a moment is
## told the mouse left it (and nothing brings it back until the pointer moves).
static func drop_hover(button: BaseButton) -> void:
	var filter := button.mouse_filter
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.mouse_filter = filter
