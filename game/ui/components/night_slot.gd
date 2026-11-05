class_name NightSlot
extends Control
## The place a night will be in the Server Browser's list while there is none to show: a dashed
## outline the size of a row with a line in it (`NO NIGHTS RIGHT NOW`, `LOOKING FOR NIGHTS...`,
## `COULD NOT LOAD THE LIST`). The sentence that says why and what to do is the screen's status line
## above it; this is the list's own part of it.

const DASH := 14.0
const GAP := 10.0
const WIDTH := 3.0
const TEXT_SIZE := 30
const TEXT_SIZE_COMPACT := 24

var text := "":
	set(value):
		text = value
		accessibility_name = value
		queue_redraw()
var compact := false:
	set(value):
		compact = value
		_fit()
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit()
	resized.connect(queue_redraw)


func _fit() -> void:
	custom_minimum_size = Vector2(0.0, NightRow.COMPACT_HEIGHT if compact else NightRow.HEIGHT)


func _draw() -> void:
	var edge := Rect2(Vector2.ZERO, size).grow(-WIDTH * 0.5)
	var colour := Color(MenuLook.INK, 0.45)
	draw_dashed_line(edge.position, Vector2(edge.end.x, edge.position.y), colour, WIDTH, DASH)
	draw_dashed_line(Vector2(edge.end.x, edge.position.y), edge.end, colour, WIDTH, DASH)
	draw_dashed_line(edge.end, Vector2(edge.position.x, edge.end.y), colour, WIDTH, DASH)
	draw_dashed_line(Vector2(edge.position.x, edge.end.y), edge.position, colour, WIDTH, DASH)
	var font := UITokens.active().font_display
	var size_now := TEXT_SIZE_COMPACT if compact else TEXT_SIZE
	var line := text.to_upper()
	var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now).x
	draw_string(
		font,
		Vector2((size.x - width) * 0.5, size.y * 0.5 + size_now * 0.35),
		line,
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 2.0 * GAP,
		size_now,
		Color(MenuLook.INK, 0.8)
	)
