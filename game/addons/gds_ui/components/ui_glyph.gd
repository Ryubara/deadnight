@tool
class_name UIGlyph
extends Control
## The button to press, drawn: a keycap or a mouse button for the keyboard and mouse, or the gamepad
## button (a lettered disc, the four PlayStation shapes, a shoulder or trigger, a d-pad cross, a
## stick, start or back) by the last device used. It reads the action's binding from the InputMap,
## so a rebound key shows the new key, and follows `UIInputMode` live: pick up the pad and the
## keycaps become buttons. It sinks while its action is held. Nothing is an image: every shape is
## drawn from tokens, so there is no asset to license and a restyle reaches it.
##
## Set `action`, or set `event` to draw one binding whatever the action says (a sheet of every
## glyph does). `device` pins the device kind and `family` the gamepad's button set; the default
## follows the player.

## Which device's binding to show.
enum Device { FOLLOW, KEYBOARD, GAMEPAD }

## The names of the engine's joypad buttons that have a glyph, by the `JoyButton` number.
const SHOULDER_NAMES := {
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
}
const PLAYSTATION_SHOULDERS := {
	JOY_BUTTON_LEFT_SHOULDER: "L1",
	JOY_BUTTON_RIGHT_SHOULDER: "R1",
}
const STICK_NAMES := {JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3"}
## Key names shorter than the engine's, for keycaps.
const KEY_ALIASES := {
	"ESCAPE": "ESC",
	"BACKSPACE": "BKSP",
	"PAGEUP": "PGUP",
	"PAGEDOWN": "PGDN",
	"CTRL": "CTRL",
	"QUOTELEFT": "`",
}
## The face buttons, bottom, right, left, top, by `JoyButton` (A, B, X, Y) and their labels.
const FACE_LETTERS := {
	UIInputMode.Family.GENERIC: ["A", "B", "X", "Y"],
	UIInputMode.Family.NINTENDO: ["B", "A", "Y", "X"],
}
## How deep a pressed glyph sinks, in pixels.
const SINK := 4.0
const PAD := 14.0

@export var action := &"":
	set(value):
		action = value
		_refresh()
@export var device := Device.FOLLOW:
	set(value):
		device = value
		_refresh()
## The gamepad button set to draw; -1 follows the pad in use.
@export var family := -1:
	set(value):
		family = value
		_refresh()
## Draws as held, for sheets and captures; a real held action does the same.
@export var preview_pressed := false:
	set(value):
		preview_pressed = value
		queue_redraw()

## The binding the glyph draws now (see `binding`).
## One binding to draw instead of the action's.
var event: InputEvent:
	set(value):
		event = value
		_refresh()

var _tokens := UITokens.active()
var _face: Font
var _held := false
var _binding: InputEvent


## The text on a keycap or disc for `event` (the key name, the button letter), or "?" for a binding
## with no glyph. Pure: tests and tools use it without drawing.
static func caption_for(binding: InputEvent, pad_family := UIInputMode.Family.GENERIC) -> String:
	if binding is InputEventKey:
		var key := binding as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var name := OS.get_keycode_string(code).to_upper()
		return KEY_ALIASES.get(name, name)
	if binding is InputEventMouseButton:
		match (binding as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			MOUSE_BUTTON_WHEEL_UP:
				return "WHEEL UP"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "WHEEL DOWN"
		return "MOUSE"
	if binding is InputEventJoypadButton:
		return _button_caption((binding as InputEventJoypadButton).button_index, pad_family)
	if binding is InputEventJoypadMotion:
		return _axis_caption(binding as InputEventJoypadMotion, pad_family)
	return "?"


## The first binding of `action_name` for the keyboard and mouse, or for a gamepad; null when
## there is none.
static func binding_for(action_name: StringName, gamepad: bool) -> InputEvent:
	if not InputMap.has_action(action_name):
		return null
	for candidate in InputMap.action_get_events(action_name):
		var is_pad := candidate is InputEventJoypadButton or candidate is InputEventJoypadMotion
		if (
			is_pad == gamepad
			and (is_pad or candidate is InputEventKey or candidate is InputEventMouseButton)
		):
			return candidate
	return null


static func _button_caption(index: int, pad_family: int) -> String:
	if index >= JOY_BUTTON_A and index <= JOY_BUTTON_Y:
		return _face_letters(pad_family)[index]
	if SHOULDER_NAMES.has(index):
		return (
			PLAYSTATION_SHOULDERS[index]
			if pad_family == UIInputMode.Family.PLAYSTATION
			else SHOULDER_NAMES[index]
		)
	if STICK_NAMES.has(index):
		return STICK_NAMES[index]
	match index:
		JOY_BUTTON_START:
			return "START"
		JOY_BUTTON_BACK:
			return "BACK"
		JOY_BUTTON_DPAD_UP:
			return "UP"
		JOY_BUTTON_DPAD_DOWN:
			return "DOWN"
		JOY_BUTTON_DPAD_LEFT:
			return "LEFT"
		JOY_BUTTON_DPAD_RIGHT:
			return "RIGHT"
	return str(index)


static func _axis_caption(motion: InputEventJoypadMotion, pad_family: int) -> String:
	match motion.axis:
		JOY_AXIS_TRIGGER_LEFT:
			return "L2" if pad_family == UIInputMode.Family.PLAYSTATION else "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "R2" if pad_family == UIInputMode.Family.PLAYSTATION else "RT"
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
			return "L"
		JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
			return "R"
	return "?"


static func _face_letters(pad_family: int) -> Array:
	return FACE_LETTERS.get(pad_family, FACE_LETTERS[UIInputMode.Family.GENERIC])


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_tokens()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	UIInputMode.changed().connect(_refresh)
	UITokens.active_changed().connect(_on_tokens_changed)
	_refresh()


func _process(_delta: float) -> void:
	var held := preview_pressed or (is_visible_in_tree() and _action_held())
	if held != _held:
		_held = held
		queue_redraw()


## The device kind this glyph draws for now.
func shows_gamepad() -> bool:
	match device:
		Device.KEYBOARD:
			return false
		Device.GAMEPAD:
			return true
	return UIInputMode.gamepad


## The gamepad button set this glyph draws now.
func pad_family() -> int:
	return family if family >= 0 else UIInputMode.family


## The InputEvent this glyph draws: the one set, else the action's binding for the device.
func binding() -> InputEvent:
	return _binding


## The text on the glyph now.
func caption() -> String:
	return caption_for(_binding, pad_family()) if _binding != null else "?"


## Reads the binding again: call it after the InputMap changes (a rebinding screen does).
func refresh() -> void:
	_refresh()


func _refresh() -> void:
	_binding = event if event != null else binding_for(action, shows_gamepad())
	custom_minimum_size = _natural_size()
	queue_redraw()
	update_minimum_size()


func _on_tokens_changed(_next: UITokens) -> void:
	_apply_tokens()
	_refresh()


func _apply_tokens() -> void:
	_tokens = UITokens.active()
	_face = _tokens.display_font(_tokens.embolden_display * 0.3)


func _action_held() -> bool:
	return action != &"" and InputMap.has_action(action) and Input.is_action_pressed(action)


func _font() -> Font:
	return _face


func _text_size() -> int:
	return _tokens.size_caption


## The size of the glyph for its binding: a square or a disc is as tall as the controls, a keycap,
## a pill or a long key name widens to its text.
func _natural_size() -> Vector2:
	var height := float(_tokens.control_height) * 0.9
	var shape := _shape()
	if shape == &"keycap" or shape == &"pill":
		var text_width := (
			_font().get_string_size(caption(), HORIZONTAL_ALIGNMENT_LEFT, -1, _text_size()).x
		)
		return Vector2(maxf(height, text_width + PAD * 2.0), height)
	if shape == &"mouse":
		return Vector2(height * 0.8, height)
	return Vector2(height, height)


## Which drawing the binding takes.
func _shape() -> StringName:
	var shape := &"keycap"
	if _binding is InputEventMouseButton:
		var wheel := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		shape = &"pill" if (_binding as InputEventMouseButton).button_index in wheel else &"mouse"
	elif _binding is InputEventJoypadMotion:
		var triggers := [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
		shape = &"pill" if (_binding as InputEventJoypadMotion).axis in triggers else &"stick"
	elif _binding is InputEventJoypadButton:
		shape = _button_shape((_binding as InputEventJoypadButton).button_index)
	return shape


static func _button_shape(index: int) -> StringName:
	if index >= JOY_BUTTON_A and index <= JOY_BUTTON_Y:
		return &"face"
	if STICK_NAMES.has(index):
		return &"stick"
	var dpad := [
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT
	]
	return &"dpad" if index in dpad else &"pill"


func _draw() -> void:
	if _binding == null:
		_draw_unbound()
		return
	var sink := SINK if _held or preview_pressed else 0.0
	var rect := Rect2(Vector2(sink, sink), size - Vector2.ONE * SINK)
	var shadow_at := Vector2.ONE * (SINK - sink)
	match _shape():
		&"face":
			_draw_face(rect, shadow_at)
		&"stick":
			_draw_stick(rect, shadow_at)
		&"dpad":
			_draw_dpad(rect, shadow_at)
		&"mouse":
			_draw_mouse(rect, shadow_at)
		_:
			_draw_cap(rect, _shape() == &"pill")


func _draw_unbound() -> void:
	var rect := Rect2(Vector2.ZERO, size).grow(-2.0)
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(_tokens.border)
	box.border_color = _tokens.ink_disabled
	box.set_corner_radius_all(_tokens.radius_sm)
	draw_style_box(box, rect)
	_text(rect, "?", _tokens.ink_disabled)


func _cap_box(fill: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.anti_aliasing = true
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	return box


func _draw_cap(rect: Rect2, round_ends: bool) -> void:
	var radius := int(rect.size.y * 0.5) if round_ends else _tokens.radius_sm
	draw_style_box(_cap_box(_tokens.shadow, radius), Rect2(Vector2.ONE * SINK, rect.size))
	draw_style_box(_cap_box(_tokens.accent_bright, radius), rect)
	_text(rect, caption(), _tokens.ink_on_accent)


func _draw_face(rect: Rect2, shadow_at: Vector2) -> void:
	var centre := rect.get_center()
	var radius := minf(rect.size.x, rect.size.y) * 0.5
	draw_circle(centre + shadow_at, radius, _tokens.shadow)
	draw_circle(centre, radius, _tokens.accent_bright)
	var index := (_binding as InputEventJoypadButton).button_index
	if pad_family() == UIInputMode.Family.PLAYSTATION:
		_draw_shape(centre, radius * 0.5, index)
	else:
		_text(rect, caption(), _tokens.ink_on_accent)


## The PlayStation face shapes: cross, circle, square and triangle, in line.
func _draw_shape(centre: Vector2, reach: float, index: int) -> void:
	var colour := _tokens.ink_on_accent
	var width := maxf(float(_tokens.border) + 1.0, 3.0)
	match index:
		JOY_BUTTON_A:
			draw_line(
				centre + Vector2(-reach, -reach),
				centre + Vector2(reach, reach),
				colour,
				width,
				true
			)
			draw_line(
				centre + Vector2(-reach, reach),
				centre + Vector2(reach, -reach),
				colour,
				width,
				true
			)
		JOY_BUTTON_B:
			draw_arc(centre, reach, 0.0, TAU, 32, colour, width, true)
		JOY_BUTTON_X:
			draw_rect(
				Rect2(centre - Vector2.ONE * reach, Vector2.ONE * reach * 2.0), colour, false, width
			)
		JOY_BUTTON_Y:
			var top := centre + Vector2(0.0, -reach * 1.1)
			var left := centre + Vector2(-reach * 1.05, reach * 0.8)
			var right := centre + Vector2(reach * 1.05, reach * 0.8)
			draw_polyline(PackedVector2Array([top, left, right, top]), colour, width, true)


func _draw_stick(rect: Rect2, shadow_at: Vector2) -> void:
	var centre := rect.get_center()
	var radius := minf(rect.size.x, rect.size.y) * 0.5
	draw_circle(centre + shadow_at, radius, _tokens.shadow)
	draw_circle(centre, radius, _tokens.accent_bright)
	draw_arc(centre, radius * 0.72, 0.0, TAU, 32, Color(_tokens.ink_on_accent, 0.55), 2.0, true)
	_text(rect, caption(), _tokens.ink_on_accent)


func _draw_dpad(rect: Rect2, shadow_at: Vector2) -> void:
	var centre := rect.get_center()
	var arm := minf(rect.size.x, rect.size.y) * 0.5
	var thick := arm * 0.62
	var index := (_binding as InputEventJoypadButton).button_index
	for pass_colour in [_tokens.shadow, _tokens.ink_muted]:
		var at := shadow_at if pass_colour == _tokens.shadow else Vector2.ZERO
		draw_rect(
			Rect2(centre + at - Vector2(arm, thick * 0.5), Vector2(arm * 2.0, thick)), pass_colour
		)
		draw_rect(
			Rect2(centre + at - Vector2(thick * 0.5, arm), Vector2(thick, arm * 2.0)), pass_colour
		)
	var lit := Rect2()
	match index:
		JOY_BUTTON_DPAD_UP:
			lit = Rect2(centre - Vector2(thick * 0.5, arm), Vector2(thick, arm - thick * 0.25))
		JOY_BUTTON_DPAD_DOWN:
			lit = Rect2(
				centre + Vector2(-thick * 0.5, thick * 0.25), Vector2(thick, arm - thick * 0.25)
			)
		JOY_BUTTON_DPAD_LEFT:
			lit = Rect2(centre - Vector2(arm, thick * 0.5), Vector2(arm - thick * 0.25, thick))
		_:
			lit = Rect2(
				centre + Vector2(thick * 0.25, -thick * 0.5), Vector2(arm - thick * 0.25, thick)
			)
	draw_rect(lit, _tokens.accent_bright)


func _draw_mouse(rect: Rect2, shadow_at: Vector2) -> void:
	var radius := int(rect.size.x * 0.45)
	draw_style_box(_cap_box(_tokens.shadow, radius), Rect2(shadow_at, rect.size))
	draw_style_box(_cap_box(_tokens.ink_muted, radius), rect)
	var button := (_binding as InputEventMouseButton).button_index
	var half := rect.size.x * 0.5
	var top := rect.size.y * 0.5
	var lit := _tokens.accent_bright
	if button == MOUSE_BUTTON_LEFT:
		draw_style_box(_cap_box(lit, radius), Rect2(rect.position, Vector2(half, top)))
	elif button == MOUSE_BUTTON_RIGHT:
		draw_style_box(
			_cap_box(lit, radius), Rect2(rect.position + Vector2(half, 0.0), Vector2(half, top))
		)
	else:
		draw_rect(Rect2(rect.position + Vector2(half - 2.0, 3.0), Vector2(4.0, top - 6.0)), lit)
	draw_line(
		rect.position + Vector2(0.0, top),
		rect.position + Vector2(rect.size.x, top),
		_tokens.shadow,
		2.0
	)
	draw_line(
		rect.position + Vector2(half, 0.0), rect.position + Vector2(half, top), _tokens.shadow, 2.0
	)


## Centres `text` in `rect`, shrunk to fit if it is wider than the glyph.
func _text(rect: Rect2, text: String, colour: Color) -> void:
	var font := _font()
	var px := _text_size()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	if width > rect.size.x - 4.0:
		px = maxi(int(float(px) * (rect.size.x - 4.0) / width), 8)
		width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var ascent := font.get_ascent(px)
	var descent := font.get_descent(px)
	var baseline := rect.get_center().y + (ascent - descent) * 0.5
	draw_string(
		font,
		Vector2(rect.get_center().x - width * 0.5, baseline),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		px,
		colour
	)
