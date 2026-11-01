class_name HudReelDigit
extends Control
## One digit of a drum counter, like the number reels on a projector or a marquee board: a dark
## tile with a split line. When the digit changes the old one rolls out downward and the new one
## rolls in from above; with reduced motion it just changes.

const TILE := Vector2(52.0, 72.0)
const FONT_SIZE := 60
const ROLL_SECONDS := 0.35

var digit := "0"
var colour := Color("ff3d4d")

var _previous := "0"
## 0 at the start of a roll, 1 when settled.
var _roll := 1.0


func _init() -> void:
	custom_minimum_size = TILE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_digit(value: String) -> void:
	if value == digit:
		return
	_previous = digit
	digit = value
	if UIMotion.reduced or not is_inside_tree():
		_roll = 1.0
		queue_redraw()
		return
	_roll = 0.0
	var tween := create_tween()
	UIMotion.apply_ease(tween, UITokens.Ease.OVERSHOOT)
	tween.tween_method(_set_roll, 0.0, 1.0, ROLL_SECONDS)


func _set_roll(value: float) -> void:
	_roll = value
	queue_redraw()


func _draw() -> void:
	var tokens := UITokens.active()
	draw_rect(Rect2(Vector2.ZERO, size), tokens.bg)
	draw_rect(Rect2(Vector2.ZERO, size), tokens.outline, false, float(tokens.border))
	if _roll < 1.0:
		_draw_digit(_previous, _roll * size.y)
	_draw_digit(digit, (_roll - 1.0) * size.y)
	draw_line(Vector2(0.0, size.y * 0.5), Vector2(size.x, size.y * 0.5), tokens.bg, 3.0)


func _draw_digit(text: String, offset: float) -> void:
	var tokens := UITokens.active()
	var font := tokens.display_font(tokens.embolden_display * 0.5)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var baseline := (size.y + FONT_SIZE * 0.7) * 0.5 + offset
	draw_string(
		font,
		Vector2((size.x - width) * 0.5, baseline),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		colour
	)
