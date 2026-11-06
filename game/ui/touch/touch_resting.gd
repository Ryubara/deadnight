class_name TouchResting
extends RefCounted
## The fingers that are on the screen while the touch layer is down (the helicopter drop, a menu),
## and where each one is. The layer does not read them, and so cannot tell when it comes back up
## which are still there: a thumb that rests on the screen through the drop would have no look
## and no stick until it lifted (#1329). The layer notes them here while it is down, and takes
## them in when it is up again (`TouchControls._adopt_resting`).

## Finger index -> where it last was, in canvas units.
var _fingers := {}


## Follows a touch event the layer did not read: a finger lands, moves or lifts.
func note(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_fingers[touch.index] = touch.position
		else:
			_fingers.erase(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_fingers[drag.index] = drag.position


## A finger the layer was reading when it went down, still on the screen.
func rest(index: int, point: Vector2) -> void:
	_fingers[index] = point


## The fingers still down, by index, and none after.
func take() -> Dictionary:
	var taken := _fingers
	_fingers = {}
	return taken
