class_name TouchFixture
extends RefCounted
## Shared helpers for the touch suites: a canvas with the touch controls on it, and fingers.

const PHONE := Vector2(2340.0, 1080.0)
const ACTIONS: Array[StringName] = [
	&"fire",
	&"jump",
	&"aim",
	&"reload",
	&"interact",
	&"swap_weapon",
	&"throw_grenade",
	&"sprint",
	&"swap_shoulder"
]

var controls: TouchControls
var host: Control
var _suite: GdUnitTestSuite
var _hand_before: Variant = null
var _auto_fire_before: Variant = null
## False for a fixture over controls that belong to something else (`attach`).
var _owns_host := true


static func make(
	suite: GdUnitTestSuite, canvas := PHONE, state: HudState = null, persist_hints := false
) -> TouchFixture:
	var fixture := TouchFixture.new()
	fixture._suite = suite
	TouchMode.device_is_touch = true
	fixture.host = Control.new()
	fixture.host.size = canvas
	fixture.host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	suite.add_child(fixture.host)
	fixture.controls = TouchControls.new()
	fixture.controls.state = state
	# The hints would write what a test used into the player's own settings file.
	fixture.controls.persist_hints = persist_hints
	fixture.host.add_child(fixture.controls)
	fixture.controls.size = canvas
	fixture.controls.refresh()
	return fixture


## A fixture over touch controls that already exist (the night screen's own), instead of a new set.
static func attach(suite: GdUnitTestSuite, existing: TouchControls) -> TouchFixture:
	var fixture := TouchFixture.new()
	fixture._suite = suite
	fixture.controls = existing
	fixture.host = existing.get_parent() as Control
	fixture._owns_host = false
	return fixture


## The player's hand: true flips the layout (through the setting, as the Settings screen does).
func left_handed(on := true) -> void:
	var settings := _suite.get_tree().root.get_node("Settings")
	if _hand_before == null:
		_hand_before = settings.get_value(SettingsService.LEFT_HANDED)
	settings.set_value(SettingsService.LEFT_HANDED, on)


## The player's auto-fire choice (through the setting, as the Settings screen does): false makes Aim
## a toggle.
func auto_fire(on := true) -> void:
	var settings := _suite.get_tree().root.get_node("Settings")
	if _auto_fire_before == null:
		_auto_fire_before = settings.get_value(SettingsService.TOUCH_AUTO_FIRE)
	settings.set_value(SettingsService.TOUCH_AUTO_FIRE, 1 if on else 0)


func free_all() -> void:
	if _auto_fire_before != null:
		_suite.get_tree().root.get_node("Settings").set_value(
			SettingsService.TOUCH_AUTO_FIRE, _auto_fire_before
		)
		_auto_fire_before = null
	if _hand_before != null:
		_suite.get_tree().root.get_node("Settings").set_value(
			SettingsService.LEFT_HANDED, _hand_before
		)
		_hand_before = null
	TouchMode.device_is_touch = null
	if _owns_host and is_instance_valid(host):
		host.free()
	Input.emulate_mouse_from_touch = true
	UIInputMode.reset()
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


## What the browser's web runtime does for every finger: the page reports the finger as a pointer
## move, and the runtime turns it into a mouse motion in device pixels. `relative` is in canvas
## units here. A real device sends it besides the touch events (#470).
func stray_mouse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = _window().basis_xform(relative)
	event.position = _window() * Vector2(500.0, 500.0)
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
