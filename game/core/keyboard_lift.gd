class_name KeyboardLift
extends Node
## Keeps the text field being typed in above whatever covers the bottom of a phone's screen: the
## system keyboard, or the game's own keypad (Deadnight #1183). A phone held sideways has a keyboard
## taller than half the page, and the Play together code field sits just below the middle.
##
## The screens' layer (the router's canvas layer) is moved up by as much as the field needs, never
## so far that the field leaves the top, and put back when the field loses the focus or nothing
## covers the page any more. Nothing in the layout changes: no screen is resized, so there is no
## shifted layout to come back from. Where nothing covers the page (a desktop) it does nothing.
##
## The input mode is no judge of it: the engine's own keyboard sends the keys it types and the arrow
## presses that place the caret as key events, so a phone that is being typed on reads as a
## keyboard.

## Units kept between the field and what covers it.
const MARGIN := 28.0
## Units kept above the field when the scene has to give way most.
const TOP_MARGIN := 24.0
## How fast the scene follows, as the share of the distance covered in a second (an exponential
## ease).
const RATE := 14.0
## Seconds between two questions to the page about the keyboard.
const ASK_EVERY := 0.1
## A shift under this is rest.
const REST := 0.5

## () -> float: units of the viewport's height the system keyboard hides. `WebKeyboard` by default.
var system_cover := Callable()
## () -> float: units the game's own keypad covers (0 with none up).
var keypad_cover := Callable()
## How far up the scene is now, in units.
var shift := 0.0

var _fingers := {}
## What the page said the system keyboard covers, and how long ago (a script call is not free).
var _system_cover := 0.0
var _system_age := INF


func _ready() -> void:
	if not system_cover.is_valid():
		system_cover = _web_cover
	if not keypad_cover.is_valid():
		keypad_cover = func() -> float: return CodeKeypad.covering


func _web_cover() -> float:
	var web := WebKeyboard.current
	return web.covered_units(get_viewport()) if web != null else 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_fingers[touch.index] = true
		else:
			_fingers.erase(touch.index)


## A finger is down. The press of a button takes the field's focus and so the keyboard away; if the
## scene followed at once it would slide from under the finger, and the lift of the finger would
## land beside the button. The scene waits for the finger.
func finger_down() -> bool:
	return not _fingers.is_empty() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _process(delta: float) -> void:
	_system_age += delta
	if finger_down():
		return
	var target := wanted()
	if is_equal_approx(shift, target):
		return
	if UIMotion.reduced or absf(target - shift) < REST:
		shift = target
	else:
		shift = lerpf(shift, target, 1.0 - exp(-RATE * delta))
	_apply()


## The shift the focused field needs now: 0 with no field being typed in, or nothing covering the
## page.
func wanted() -> float:
	var field := get_viewport().gui_get_focus_owner() as LineEdit
	if field == null or not field.editable or not field.is_visible_in_tree():
		return 0.0
	var covered := cover()
	if covered <= 0.0:
		return 0.0
	var rect := field.get_global_rect()
	var free_bottom := get_viewport().get_visible_rect().size.y - covered
	var need := rect.end.y + MARGIN - free_bottom
	return clampf(need, 0.0, maxf(rect.position.y - TOP_MARGIN, 0.0))


## Units of the page's height something covers: the larger of the system keyboard and the keypad.
func cover() -> float:
	var covered := 0.0
	if system_cover.is_valid():
		if _system_age >= ASK_EVERY:
			_system_cover = float(system_cover.call())
			_system_age = 0.0
		covered = maxf(covered, _system_cover)
	if keypad_cover.is_valid():
		covered = maxf(covered, float(keypad_cover.call()))
	return covered


func _apply() -> void:
	UIRouter.offset = Vector2(0.0, -shift)


func _exit_tree() -> void:
	UIRouter.offset = Vector2.ZERO
