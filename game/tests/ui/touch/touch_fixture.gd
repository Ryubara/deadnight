class_name TouchFixture
extends RefCounted
## Shared helpers for the touch suites: a canvas with the touch controls on it, and fingers.

const PHONE := Vector2(2340.0, 1080.0)
const ACTIONS: Array[StringName] = [
	&"fire", &"jump", &"aim", &"reload", &"interact", &"swap_weapon", &"throw_grenade", &"sprint"
]

var controls: TouchControls
var host: Control
var _suite: GdUnitTestSuite


static func make(suite: GdUnitTestSuite, canvas := PHONE, state: HudState = null) -> TouchFixture:
	var fixture := TouchFixture.new()
	fixture._suite = suite
	TouchMode.device_is_touch = true
	fixture.host = Control.new()
	fixture.host.size = canvas
	fixture.host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	suite.add_child(fixture.host)
	fixture.controls = TouchControls.new()
	fixture.controls.state = state
	fixture.host.add_child(fixture.controls)
	fixture.controls.size = canvas
	fixture.controls.refresh()
	return fixture


func free_all() -> void:
	TouchMode.device_is_touch = null
	if is_instance_valid(host):
		host.free()
	Input.emulate_mouse_from_touch = true
	for action in ACTIONS:
		Input.action_release(action)


## The centre of a button, in canvas units.
func at(id: StringName) -> Vector2:
	return controls.button_circle(id)[&"centre"]


func touch(index: int, position: Vector2, pressed := true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = _window() * position
	event.pressed = pressed
	Input.parse_input_event(event)
	await _suite.get_tree().process_frame


func drag(index: int, position: Vector2, relative: Vector2, speed := 0.0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = _window() * position
	event.relative = _window().basis_xform(relative)
	event.velocity = _window().basis_xform(relative.normalized() * speed)
	Input.parse_input_event(event)
	await _suite.get_tree().process_frame


## A press and a lift in the same frame: the quickest tap a thumb makes.
func tap(position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = _window() * position
		event.pressed = pressed
		Input.parse_input_event(event)
	await _suite.get_tree().process_frame


func lift(index: int, position := Vector2.ZERO) -> void:
	await touch(index, position, false)


## Events arrive in window pixels and the viewport maps them to canvas units: the headless window
## is tiny, so a test states canvas units and this converts.
func _window() -> Transform2D:
	return host.get_viewport().get_final_transform()
