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
	&"quick_melee",
	&"sprint",
	&"crouch",
	&"swap_shoulder",
	&"bot_wheel",
	&"bot_order_next",
	&"ping"
]

var controls: TouchControls
## The HUD under the controls, wired to them as the night screen does (`make` with `with_hud`).
var hud: Hud
var host: Control
## Whether a dead is within reach of the quick melee (what `controls.strike_ready` says).
var strike_up := false
var _suite: GdUnitTestSuite
var _hand_before: Variant = null
var _auto_fire_before: Variant = null
## False for a fixture over controls that belong to something else (`attach`).
var _owns_host := true


static func make(
	suite: GdUnitTestSuite,
	canvas := PHONE,
	state: HudState = null,
	persist_hints := false,
	with_hud := false
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
	fixture.controls.strike_ready = func() -> bool: return fixture.strike_up
	if with_hud:
		fixture._add_hud()
	# The hints would write what a test used into the player's own settings file.
	fixture.controls.persist_hints = persist_hints
	fixture.host.add_child(fixture.controls)
	fixture.controls.size = canvas
	fixture.controls.refresh()
	return fixture


## The HUD under the controls, wired to them as `NightScreen` does (#1280): the controls ask the
## HUD's weapon places where they are, the HUD takes the touch layout and the hand from them.
func _add_hud() -> void:
	hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	host.add_child(hud)
	controls.state = hud.state
	controls.zones = hud.slots.touch_zones
	controls.finger_units = func() -> float: return MenuScale.tap_units(host.get_window(), true)
	controls.active_changed.connect(func(active: bool) -> void: hud.touch_layout = active)
	controls.mirrored_changed.connect(func(on: bool) -> void: hud.mirrored = on)
	controls.safe_insets_changed.connect(func(insets: Vector4) -> void: hud.set_safe_insets(insets))


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
	# A finger still down made the engine's emulated left mouse button: the Input singleton holds it
	# for every suite after this one (the night's trigger reads it), until something lets it go.
	_release_mouse()


static func _release_mouse() -> void:
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if Input.is_mouse_button_pressed(button):
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = false
			Input.parse_input_event(event)
	Input.flush_buffered_events()


## The centre of a button, in canvas units.
func at(id: StringName) -> Vector2:
	return controls.button_circle(id)[&"centre"]


## The centre of the HUD's place that presses `action` (a weapon's slot, the grenade or the bots'
## tag), in canvas units; `Vector2.INF` where there is none.
func zone_centre(action: StringName) -> Vector2:
	for zone in controls.zones.call() if controls.zones.is_valid() else []:
		if zone[&"action"] == action:
			return (zone[&"rect"] as Rect2).get_center()
	return Vector2.INF


func touch(index: int, position: Vector2, pressed := true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = _window() * position
	event.pressed = pressed
	Input.parse_input_event(event)
	await _suite.get_tree().process_frame


func drag(index: int, position: Vector2, relative: Vector2, speed := 0.0) -> void:
	Input.parse_input_event(_drag_event(index, position, relative, speed))
	await _suite.get_tree().process_frame


## A drag the layer has read when this returns, with no frame passing (a test that keeps its own
## clock steps the frames itself).
func send_drag(index: int, position: Vector2, relative: Vector2, speed := 0.0) -> void:
	Input.parse_input_event(_drag_event(index, position, relative, speed))
	Input.flush_buffered_events()


func _drag_event(
	index: int, position: Vector2, relative: Vector2, speed: float
) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = _window() * position
	event.relative = _window().basis_xform(relative)
	event.velocity = _window().basis_xform(relative.normalized() * speed)
	return event


## What the browser's web runtime does for every finger: the page reports the finger as a pointer
## move, and the runtime turns it into a mouse motion in device pixels. `relative` is in canvas
## units here. A real device sends it besides the touch events (#470).
func stray_mouse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = _window().basis_xform(relative)
	event.screen_relative = relative  # the player turns by these pixels, whatever the window
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


## The look the fingers made and the view has not turned yet goes out now (the layer lets it out a
## share each frame, `LookSmoother`), and the player reads it: the turn is whole.
func settle_look() -> void:
	controls.flush_look()
	await _suite.get_tree().process_frame
	await _suite.get_tree().process_frame


func lift(index: int, position := Vector2.ZERO) -> void:
	await touch(index, position, false)


## Events arrive in window pixels and the viewport maps them to canvas units: the headless window
## is tiny, so a test states canvas units and this converts.
func _window() -> Transform2D:
	return host.get_viewport().get_final_transform()
