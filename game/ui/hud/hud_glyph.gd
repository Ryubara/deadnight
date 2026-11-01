class_name HudGlyph
extends Control
## The button to press, drawn: a square keycap for the keyboard, a round button for a gamepad or a
## round tap mark (rings round a dot, no letter) for a finger, chosen by the last device used. It
## sinks when its action is held. The key name comes from the InputMap, so a rebound key shows the
## new key.

const SIZE := Vector2(48.0, 48.0)
const SINK := 4.0
const BUTTON_NAMES := ["A", "B", "X", "Y"]

@export var action := &"interact"
var pressed := false:
	set(value):
		if value != pressed:
			pressed = value
			queue_redraw()
var gamepad := false:
	set(value):
		if value != gamepad:
			gamepad = value
			queue_redraw()
## A finger was the last input: no keycap, a tap mark.
var touch := false:
	set(value):
		if value != touch:
			touch = value
			queue_redraw()


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	gamepad = UIInputMode.gamepad
	touch = UIInputMode.touch
	pressed = is_visible_in_tree() and Input.is_action_pressed(action)


## The text on the glyph for the current device: none for a finger.
func caption() -> String:
	return "" if touch else caption_for(action, gamepad)


static func caption_for(action_name: StringName, use_gamepad: bool) -> String:
	if not InputMap.has_action(action_name):
		return "?"
	for event in InputMap.action_get_events(action_name):
		if use_gamepad and event is InputEventJoypadButton:
			var index := (event as InputEventJoypadButton).button_index
			return BUTTON_NAMES[index] if index < BUTTON_NAMES.size() else str(index)
		if not use_gamepad and event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code).to_upper()
	return "?"


func _draw() -> void:
	var tokens := UITokens.active()
	var sink := SINK if pressed else 0.0
	var top := Rect2(Vector2(sink, sink), size - Vector2.ONE * SINK)
	var font := tokens.display_font(tokens.embolden_display * 0.3)
	var text := caption()
	var px := HudStyle.MEDIUM
	if touch:
		_draw_tap_mark(tokens, top)
		return
	if gamepad:
		var centre := top.get_center()
		var radius := top.size.x * 0.5
		draw_circle(centre + Vector2.ONE * (SINK - sink), radius, tokens.shadow)
		draw_circle(centre, radius, tokens.accent_bright)
	else:
		draw_rect(Rect2(Vector2.ONE * SINK, top.size), tokens.shadow)
		draw_rect(top, tokens.accent_bright)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(
		font,
		top.get_center() + Vector2(-width * 0.5, px * 0.35),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		px,
		tokens.ink_on_accent
	)


## Two rings round a dot, as a finger landing: the same round plate as a gamepad button.
func _draw_tap_mark(tokens: UITokens, top: Rect2) -> void:
	var centre := top.get_center()
	var radius := top.size.x * 0.5
	draw_circle(centre + Vector2.ONE * (SINK - (SINK if pressed else 0.0)), radius, tokens.shadow)
	draw_circle(centre, radius, tokens.accent_bright)
	var ink := tokens.ink_on_accent
	draw_circle(centre, radius * 0.2, ink)
	draw_arc(centre, radius * 0.5, 0.0, TAU, 32, ink, 3.0, true)
	draw_arc(centre, radius * 0.78, 0.0, TAU, 32, Color(ink, 0.55), 2.0, true)
