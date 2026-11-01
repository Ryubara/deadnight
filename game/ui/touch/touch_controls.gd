class_name TouchControls
extends Control
## The touch controls of a night: a floating move stick on the left, a look area on the right,
## and buttons under the right thumb. They press the game's own input actions (`move_*`, `fire`,
## `aim`, `jump`, `reload`, `swap_weapon`, `throw_grenade`, `interact`, `sprint`, `pause`), so
## the player and the night read them like a key or a pad and nothing else forks.
##
## Every finger is tracked by its touch index and has one job until it lifts: the stick, the look,
## or one button. A finger that starts on Fire also looks while it drags, so one thumb can aim and
## shoot. Look goes out as mouse motion in mouse pixels (`TouchLook`), so the sensitivity setting,
## the ADS slow-down and invert Y apply as they do for a mouse.
##
## The layer shows when `TouchMode.wanted`, in landscape, and while the night is live (`live`).
## While it is up the engine's touch-to-mouse emulation is off, or every touch would also click
## Fire. The interact button shows only while the HUD has a prompt: what it does is its label.
##
## While it is up the HUD shows no key hints (`UIInputMode.touch`), and `TouchHints` labels the
## controls the first time each is met, until it is used.

## A look drag, in mouse pixels (also sent to the input system as mouse motion).
signal looked(mouse_relative: Vector2)
## The platform's safe-area insets changed (left, top, right, bottom, canvas units).
signal safe_insets_changed(insets: Vector4)
## The touch layout is flipped for a left hand, or stopped being (the HUD swaps its columns).
signal mirrored_changed(mirrored: bool)

const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const SPRINT := &"sprint"
const SPRINT_ON := 0.95
const SPRINT_OFF := 0.75
const STICK_DEADZONE := 0.1
## A press lasts at least this long, so a quick tap is still seen by the next physics tick.
const MIN_HOLD := 0.09
const INSET_PERIOD := 0.5
const HAPTIC_MS := 12
## Captions on the buttons, and what the interact button says for each kind of prompt.
const LABELS := {
	TouchLayout.FIRE: "FIRE",
	TouchLayout.AIM: "AIM",
	TouchLayout.JUMP: "JUMP",
	TouchLayout.RELOAD: "RELOAD",
	TouchLayout.SWAP: "SWAP",
	TouchLayout.GRENADE: "GRENADE",
	TouchLayout.SHOULDER: "SIDE",
}
const VERBS := {
	&"buy_door": "OPEN",
	&"buy_weapon": "BUY",
	&"buy_ammo": "AMMO",
	&"buy_crane": "PLAY",
	&"crane_take": "TAKE",
	&"fill_fuel": "FUEL",
	&"repair": "HOLD",
	&"circuit": "SWITCH",
	&"revive": "REVIVE",
}
const DEFAULT_VERB := "USE"

## The HUD state, for the interact button.
var state: HudState
## False while a menu or the result is up: the layer hides and lets go of everything.
var live := true:
	set(value):
		live = value
		_refresh_active()
## Set by a test or a debug view; otherwise read from the platform.
var insets_override: Variant = null
var touch_scale := 1.0
var opacity := 0.7
var insets := Vector4.ZERO
## The layout is flipped for a left hand (the setting `controls/left_handed`).
var left_handed := false
## Whether the first-run hints remember what was used in the settings. Tests turn it off.
var persist_hints := true
## The first-run labels, a child that draws over the buttons.
var hints: TouchHints

var _enabled := false
var _active := false
var _circles := {}
var _safe := Rect2()
var _touches := {}
var _pressed_at := {}
var _release_at := {}
var _clock := 0.0
var _inset_clock := INSET_PERIOD
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_vector := Vector2.ZERO
var _sprinting := false
var _interact_verb := ""
var _last_insets := Vector4.ZERO
var _was_mirrored := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_resized)
	get_viewport().size_changed.connect(_on_resized)
	var service := get_tree().root.get_node_or_null(TouchMode.SETTING_PATH)
	if service != null and service.has_signal(&"changed"):
		service.connect(&"changed", _on_setting_changed)
	hints = TouchHints.new()
	hints.controls = self
	hints.persist = persist_hints
	add_child(hints)
	refresh()


func _exit_tree() -> void:
	_release_everything()
	Input.emulate_mouse_from_touch = true


## Re-read the settings (mode, size, opacity) and the platform, and lay out again.
func refresh() -> void:
	touch_scale = _setting(&"controls/touch_scale", 1.0)
	opacity = _setting(&"controls/touch_opacity", 0.7)
	left_handed = _flag(SettingsService.LEFT_HANDED)
	_enabled = TouchMode.wanted(get_tree())
	_relayout()
	_refresh_active()


## True while the controls are on screen and taking touches.
func is_active() -> bool:
	return _active


## True while the touch controls are wanted and flipped for a left hand: the HUD's columns
## follow, and stay put under a pause menu (a layer that is down for a menu is still the layout).
func is_mirrored() -> bool:
	return _enabled and left_handed


func button_circle(id: StringName) -> Dictionary:
	return _circles.get(id, {})


## The caption the interact button shows now, "" when it is hidden.
func interact_verb() -> String:
	return _interact_verb


func is_stick_down() -> bool:
	return _stick_index >= 0


func stick_vector() -> Vector2:
	return _stick_vector


func is_sprinting() -> bool:
	return _sprinting


func is_pressed(id: StringName) -> bool:
	return _pressed_at.has(id) and not _release_at.has(id)


func safe_rect() -> Rect2:
	return _safe


## Portrait: the canvas is taller than wide. The rotate prompt covers it; the controls wait.
func is_portrait() -> bool:
	var canvas := _canvas()
	return canvas.y > canvas.x


## This node's size, or the viewport's when it sits under a CanvasLayer (no parent to fill).
func _canvas() -> Vector2:
	if size.x > 0.0 and size.y > 0.0:
		return size
	return get_viewport_rect().size


func _process(delta: float) -> void:
	_clock += delta
	for action: StringName in _release_at.keys():
		if _clock >= float(_release_at[action]):
			_release_at.erase(action)
			_pressed_at.erase(action)
			Input.action_release(action)
	_inset_clock += delta
	if _inset_clock >= INSET_PERIOD:
		_inset_clock = 0.0
		_relayout()
		_refresh_active()
	var verb := _verb_now()
	if verb != _interact_verb:
		_interact_verb = verb
		if verb == "":
			_drop_button(TouchLayout.INTERACT)
	if _active:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# This layer handles the touch before the HUD sees it: the input mode is told here.
		UIInputMode.track(event)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_down(touch.index, touch.position)
		else:
			_touch_up(touch.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touch_drag(drag.index, drag.position, drag.relative, drag.velocity)
		get_viewport().set_input_as_handled()


func _touch_down(index: int, point: Vector2) -> void:
	if _touches.has(index):
		_touch_up(index)
	var hidden: Array = [] if _interact_verb != "" else [TouchLayout.INTERACT]
	var button := TouchLayout.button_at(point, _circles, hidden)
	if button != &"":
		_touches[index] = {&"role": &"button", &"button": button}
		_press_button(button)
		if button == TouchLayout.INTERACT:
			hints.mark_used(TouchHints.INTERACT)
	elif _stick_index < 0 and TouchLayout.stick_zone(_safe, left_handed).has_point(point):
		hints.mark_used(TouchHints.MOVE)
		_stick_index = index
		_stick_origin = point
		_stick_pos = point
		_touches[index] = {&"role": &"stick"}
		_set_stick(Vector2.ZERO)
	elif not _has_role(&"look"):
		_touches[index] = {&"role": &"look"}


func _touch_up(index: int) -> void:
	var touch: Dictionary = _touches.get(index, {})
	_touches.erase(index)
	match touch.get(&"role", &""):
		&"stick":
			_stick_index = -1
			_set_stick(Vector2.ZERO)
		&"button":
			_release_button(touch[&"button"])


func _touch_drag(index: int, point: Vector2, relative: Vector2, velocity: Vector2) -> void:
	var touch: Dictionary = _touches.get(index, {})
	match touch.get(&"role", &""):
		&"stick":
			_stick_pos = point
			_follow_stick()
		&"look":
			_look(relative, velocity)
		&"button":
			if touch[&"button"] == TouchLayout.FIRE:
				_look(relative, velocity)


func _look(relative: Vector2, velocity: Vector2) -> void:
	var look := TouchLook.mouse_equivalent(relative, velocity.length(), _canvas().y)
	looked.emit(look)
	if relative != Vector2.ZERO:
		hints.mark_used(TouchHints.LOOK)
	# Injected events are in window pixels and the viewport maps them back to canvas units, so
	# the look is sent through the stretch in advance: the player receives exactly `look`.
	var motion := InputEventMouseMotion.new()
	motion.relative = get_viewport().get_final_transform().basis_xform(look)
	motion.position = get_viewport().get_final_transform() * get_viewport().get_mouse_position()
	Input.parse_input_event(motion)


## The stick follows the finger: a finger past the rim drags the base along, so the thumb never
## runs out of travel and the stick centre is always one thumb-length behind it.
func _follow_stick() -> void:
	var radius := TouchLayout.STICK_RADIUS * touch_scale
	var offset := _stick_pos - _stick_origin
	if offset.length() > radius:
		_stick_origin += offset.normalized() * (offset.length() - radius)
		offset = _stick_pos - _stick_origin
	var raw := offset / radius
	var length := raw.length()
	var vector := Vector2.ZERO
	if length > STICK_DEADZONE:
		vector = raw.normalized() * inverse_lerp(STICK_DEADZONE, 1.0, minf(length, 1.0))
	_set_stick(vector)


func _set_stick(vector: Vector2) -> void:
	_stick_vector = vector
	_axis(MOVE_RIGHT, maxf(vector.x, 0.0))
	_axis(MOVE_LEFT, maxf(-vector.x, 0.0))
	_axis(MOVE_BACK, maxf(vector.y, 0.0))
	_axis(MOVE_FORWARD, maxf(-vector.y, 0.0))
	var length := vector.length()
	if length >= SPRINT_ON:
		_sprinting = true
	elif length < SPRINT_OFF:
		_sprinting = false
	if _sprinting:
		Input.action_press(SPRINT)
	else:
		Input.action_release(SPRINT)


func _axis(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _press_button(id: StringName) -> void:
	_buzz()
	if id == TouchLayout.PAUSE:
		_send_action(id, true)
		_send_action.call_deferred(id, false)
		return
	_release_at.erase(id)
	_pressed_at[id] = _clock
	Input.action_press(id)


func _release_button(id: StringName) -> void:
	if id == TouchLayout.PAUSE or not _pressed_at.has(id):
		return
	var held_until: float = float(_pressed_at[id]) + MIN_HOLD
	if _clock >= held_until:
		_pressed_at.erase(id)
		Input.action_release(id)
	else:
		_release_at[id] = held_until


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


## A finger on a button that is gone (interact hid) lets go.
func _drop_button(id: StringName) -> void:
	for index: int in _touches.keys():
		if _touches[index].get(&"button", &"") == id:
			_touch_up(index)


func _has_role(role: StringName) -> bool:
	for touch: Dictionary in _touches.values():
		if touch[&"role"] == role:
			return true
	return false


func _buzz() -> void:
	var service := get_tree().root.get_node_or_null(TouchMode.SETTING_PATH)
	if service != null and service.has_method(&"get_value"):
		if service.call(&"get_value", &"controls/haptics") == false:
			return
	Input.vibrate_handheld(HAPTIC_MS)


func _verb_now() -> String:
	if state == null or state.prompt.is_empty():
		return ""
	return VERBS.get(state.prompt.get("kind", &""), DEFAULT_VERB)


func _setting(key: StringName, fallback: float) -> float:
	var service := get_tree().root.get_node_or_null(TouchMode.SETTING_PATH)
	if service == null or not service.has_method(&"get_value"):
		return fallback
	var value: Variant = service.call(&"get_value", key)
	return float(value) if value is float or value is int else fallback


func _flag(key: StringName) -> bool:
	var service := get_tree().root.get_node_or_null(TouchMode.SETTING_PATH)
	if service == null or not service.has_method(&"get_value"):
		return false
	return service.call(&"get_value", key) == true


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	# The hints' own bookkeeping is no reason to lay the buttons out again.
	if key != SettingsService.TOUCH_HINTS_SEEN:
		refresh()


func _on_resized() -> void:
	_relayout()
	_refresh_active()


func _refresh_active() -> void:
	var now := _enabled and live and not is_portrait() and is_inside_tree()
	if now != _active:
		_active = now
		if now:
			# Controls up and no other device used yet: the HUD shows a finger, not a keycap.
			UIInputMode.touch = true
			UIInputMode.gamepad = false
		if not now:
			_release_everything()
		queue_redraw()
	visible = _active
	if is_mirrored() != _was_mirrored:
		_was_mirrored = is_mirrored()
		mirrored_changed.emit(_was_mirrored)
	# Touch-to-mouse emulation would also click Fire (left mouse) and look twice.
	Input.emulate_mouse_from_touch = not _active


func _release_everything() -> void:
	_touches.clear()
	_stick_index = -1
	_set_stick(Vector2.ZERO)
	for action: StringName in _pressed_at.keys():
		Input.action_release(action)
	_pressed_at.clear()
	_release_at.clear()


func _relayout() -> void:
	insets = insets_override if insets_override != null else _platform_insets()
	_safe = TouchLayout.safe_rect(_canvas(), insets)
	_circles = TouchLayout.buttons(_safe, touch_scale, left_handed)
	if insets != _last_insets:
		_last_insets = insets
		safe_insets_changed.emit(insets)


## The notch, rounded corners and home bar, in canvas units. On the web the page's CSS insets
## (needs `viewport-fit=cover`, see `docs/research/mobile-controls.md`); on a phone build the
## display server's safe area; nowhere else.
func _platform_insets() -> Vector4:
	if OS.has_feature("web"):
		return _web_insets()
	if OS.has_feature("android") or OS.has_feature("ios"):
		return TouchLayout.insets_from(
			DisplayServer.get_display_safe_area(), DisplayServer.screen_get_size(), _canvas()
		)
	return Vector4.ZERO


func _web_insets() -> Vector4:
	var script := (
		"(function(){var d=document.createElement('div');"
		+ "d.style.cssText='position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;"
		+ "padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) "
		+ "env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';"
		+ "document.body.appendChild(d);var s=getComputedStyle(d);"
		+ "var r=[s.paddingLeft,s.paddingTop,s.paddingRight,s.paddingBottom,"
		+ "window.innerWidth].join(',');document.body.removeChild(d);return r;})()"
	)
	var answer: Variant = JavaScriptBridge.eval(script, true)
	if not answer is String:
		return Vector4.ZERO
	var parts := (answer as String).replace("px", "").split(",")
	if parts.size() < 5 or float(parts[4]) <= 0.0:
		return Vector4.ZERO
	var k := _canvas().x / float(parts[4])
	return Vector4(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])) * k


func _draw() -> void:
	if not _active:
		return
	var tokens := UITokens.active()
	var font := tokens.display_font(tokens.embolden_display * 0.3)
	_draw_stick(tokens)
	for id: StringName in _circles:
		if id == TouchLayout.INTERACT and _interact_verb == "":
			continue
		var label: String = _interact_verb if id == TouchLayout.INTERACT else LABELS.get(id, "")
		_draw_button(tokens, font, id, _circles[id], label)


## Colour at the resting opacity, or full while its control is held.
func _alpha(colour: Color, held: bool) -> Color:
	return Color(colour, colour.a * (1.0 if held else opacity))


func _is_held(id: StringName) -> bool:
	for touch: Dictionary in _touches.values():
		if touch.get(&"button", &"") == id:
			return true
	return false


func _draw_button(
	tokens: UITokens, font: Font, id: StringName, circle: Dictionary, label: String
) -> void:
	var centre: Vector2 = circle[&"centre"]
	var radius: float = circle[&"radius"]
	var held := _is_held(id)
	var primary := id == TouchLayout.FIRE or id == TouchLayout.INTERACT
	var fill := tokens.surface_raised
	if held:
		fill = tokens.accent_bright
	elif primary:
		fill = tokens.accent
	var ink := tokens.ink_on_accent if (held or primary) else tokens.ink
	draw_circle(centre + Vector2(3.0, 4.0), radius, _alpha(tokens.shadow, held))
	draw_circle(centre, radius, _alpha(fill, held))
	draw_arc(centre, radius, 0.0, TAU, 48, _alpha(tokens.outline.lightened(0.5), held), 3.0, true)
	if id == TouchLayout.PAUSE:
		var bar := Vector2(7.0, radius * 0.9)
		draw_rect(Rect2(centre + Vector2(-13.0, -bar.y * 0.5), bar), _alpha(ink, held))
		draw_rect(Rect2(centre + Vector2(6.0, -bar.y * 0.5), bar), _alpha(ink, held))
		return
	var px := int(radius * (0.34 if label.length() <= 4 else 0.27))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var at := centre + Vector2(-width * 0.5, px * 0.35)
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _alpha(ink, held))


func _draw_stick(tokens: UITokens) -> void:
	var radius := TouchLayout.STICK_RADIUS * touch_scale
	var held := _stick_index >= 0
	var origin := _stick_origin if held else TouchLayout.stick_rest(_safe, touch_scale, left_handed)
	var ring := tokens.accent_bright if _sprinting else tokens.ink
	draw_circle(origin, radius, _alpha(Color(tokens.shadow, 0.35), held))
	draw_arc(origin, radius, 0.0, TAU, 64, _alpha(ring, held), 4.0 if held else 3.0, true)
	if held:
		var knob := origin + (_stick_pos - origin).limit_length(radius)
		draw_circle(knob, radius * 0.45, _alpha(tokens.accent if _sprinting else tokens.ink, true))
